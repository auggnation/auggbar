"""Smart polling + offline cache helpers for Auggmented Scoreboard.

Nothing in here touches Flask or the network except the logo downloader, so the
scheduling rules can be unit-tested on their own.

Polling model
-------------
Each league is polled in one of two ways:

* **full**  - the whole date window (days_back .. days_ahead).  Needed to learn
  about new games and changed start times.  Runs at a few fixed local times
  each day (SCHEDULE_SLOTS - the first one is just after midnight), whenever the
  league is first seen, and whenever its window/conference filter changes.
* **live**  - only today's slate.  Runs ONLY while a game is in progress or is
  about to start (see ``live_plan``).  Between games nothing is fetched.

Everything fetched is persisted to ``cache/`` so a restart (or a dead network)
still shows the last known schedule, team list and logos.
"""

import hashlib
import json
import os
import re
import tempfile
import threading
import time
from datetime import datetime, timedelta, timezone

try:                       # optional: only used for timestamp formats fromisoformat rejects
    from dateutil import parser as _dtparser
except Exception:
    _dtparser = None

# Local wall-clock times (hour, minute) for the "does the schedule still look the
# same?" check.  00:05 is the nightly check; the others catch same-day time changes.
SCHEDULE_SLOTS = ((0, 5), (6, 5), (12, 5), (17, 5))
# When nothing we care about starts within QUIET_HOURS, only the nightly check and
# one midday check run - the bare minimum to notice a rescheduled game.
QUIET_SLOTS = ((0, 5), (12, 5))
QUIET_HOURS = 24

LIVE_INTERVAL = 30            # seconds between polls while a game is in progress
PRE_INTERVAL = 60             # seconds between polls in the lead-up to a start
PRE_LEAD = timedelta(minutes=5)     # start polling this long before first pitch
PRE_GRACE = timedelta(hours=3)      # keep polling a delayed start this long
LIVE_MAX_AGE = timedelta(hours=14)  # ignore "in progress" games older than this (stuck feeds)

# Slow sports: multi-day events do not need a 30 s heartbeat.
# path -> (poll seconds, max event age)
SLOW_LEAGUES = {
    "golf/pga": (300, timedelta(days=5)),
    "cricket/current": (120, timedelta(days=6)),
}

MAX_BACKOFF = 15 * 60         # cap for failure backoff (seconds)
DISK_WRITE_MIN_GAP = 300      # live polls persist at most this often (SD-card friendly)


# ─── time helpers ───

def parse_utc(value):
    """Parse an ESPN ISO timestamp into an aware UTC datetime (None if unusable)."""
    if not value or not isinstance(value, str):
        return None
    dt = None
    try:
        dt = datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
    except ValueError:
        if _dtparser is not None:       # older Pythons / odd formats
            try:
                dt = _dtparser.parse(value)
            except Exception:
                dt = None
    if dt is None:
        return None
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


def event_state(event):
    try:
        return event["status"]["type"]["state"]
    except Exception:
        return ""


def next_slot_after(ts, tz, slots=SCHEDULE_SLOTS):
    """First scheduled full-check time strictly after epoch ``ts`` (epoch seconds)."""
    base = datetime.fromtimestamp(ts, tz)
    for day_offset in (0, 1):
        day = (base + timedelta(days=day_offset)).date()
        for hour, minute in slots:
            cand = tz.localize(datetime(day.year, day.month, day.day, hour, minute)) \
                if hasattr(tz, "localize") else \
                datetime(day.year, day.month, day.day, hour, minute, tzinfo=tz)
            if cand.timestamp() > ts:
                return cand.timestamp()
    return ts + 6 * 3600  # unreachable with a non-empty slot list


# ─── polling decisions ───

def full_due_at(full_at, tz, slots=SCHEDULE_SLOTS):
    """Epoch time the next full refresh is due (0 = immediately)."""
    if not full_at:
        return 0
    return next_slot_after(full_at, tz, slots)


def slots_for(events, now_ts, relevant=None):
    """Full-check slots to use: all of them when a relevant game is close (or one is
    already in progress), otherwise the reduced quiet set."""
    horizon = now_ts + QUIET_HOURS * 3600
    for ev in events or ():
        if relevant is not None and not relevant(ev):
            continue
        if event_state(ev) == "in":
            return SCHEDULE_SLOTS
        start = parse_utc(ev.get("date"))
        if start is not None and now_ts - 6 * 3600 <= start.timestamp() <= horizon:
            return SCHEDULE_SLOTS
    return QUIET_SLOTS


def live_plan(path, events, now_ts, relevant=None):
    """Decide whether this league needs live polling right now.

    ``relevant`` (optional) is a predicate on a raw event; games it rejects (e.g.
    non-favourite teams when only favourites are shown) never trigger polling.

    Returns ``(interval, wake_ts)``:
      * ``interval`` - seconds between polls if a game is live/about to start,
        else ``None`` (nothing to poll for).
      * ``wake_ts``  - when polling should begin for the next upcoming game
        (epoch seconds) or ``None``.  Informational / used for status.
    """
    now = datetime.fromtimestamp(now_ts, timezone.utc)
    live_every, max_age = SLOW_LEAGUES.get(path, (LIVE_INTERVAL, LIVE_MAX_AGE))
    interval = None
    wake = None
    for ev in events or ():
        if relevant is not None and not relevant(ev):
            continue
        start = parse_utc(ev.get("date"))
        if start is None:
            continue
        state = event_state(ev)
        if state == "in":
            if now - start <= max_age:
                interval = live_every if interval is None else min(interval, live_every)
        elif state == "pre":
            begin = start - PRE_LEAD
            if begin <= now <= start + PRE_GRACE:
                pre_every = max(PRE_INTERVAL, live_every) if path in SLOW_LEAGUES else PRE_INTERVAL
                interval = pre_every if interval is None else min(interval, pre_every)
            elif begin > now:
                ts = begin.timestamp()
                wake = ts if wake is None else min(wake, ts)
    return interval, wake


def backoff_seconds(fails, base):
    """Retry delay after ``fails`` consecutive failures (>=1)."""
    return min(MAX_BACKOFF, base * (2 ** min(fails, 6)))


def merge_events(old, fresh):
    """Merge freshly fetched events into the cached list by event id.

    Fresh data wins; cached events that were not part of this fetch are kept
    (a live poll only covers today).  Result is sorted by start time.
    """
    by_id = {}
    for ev in old or ():
        if isinstance(ev, dict) and ev.get("id") is not None:
            by_id[ev["id"]] = ev
    for ev in fresh or ():
        if isinstance(ev, dict) and ev.get("id") is not None:
            by_id[ev["id"]] = ev
    return sorted(by_id.values(), key=lambda e: e.get("date", ""))


def prune_events(events, now_ts, keep_days_back, keep_days_ahead):
    """Drop events far outside the window (keeps the disk cache from growing)."""
    lo = now_ts - (keep_days_back + 2) * 86400
    hi = now_ts + (keep_days_ahead + 2) * 86400
    out = []
    for ev in events:
        start = parse_utc(ev.get("date"))
        if start is None or lo <= start.timestamp() <= hi:
            out.append(ev)
    return out


# ─── persistence ───

def _atomic_write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), prefix=".tmp-", suffix=".json")
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(text)
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default


def save_json(path, data):
    try:
        _atomic_write(path, json.dumps(data, separators=(",", ":"), default=str))
        return True
    except Exception as exc:
        print(f"[cache] could not write {path}: {exc}")
        return False


class KeyValueCache:
    """Small persistent {key: {"at": epoch, "data": ...}} store with TTL lookups.

    Used for team lists, local-feed schedules, weather and discovered series so
    they survive restarts and can be served stale while offline.
    """

    def __init__(self, path):
        self.path = path
        self._lock = threading.Lock()
        self._data = None
        self._dirty = False
        self._last_write = 0

    def _load(self):
        if self._data is None:
            raw = load_json(self.path, {})
            self._data = raw if isinstance(raw, dict) else {}

    def get(self, key, max_age=None):
        """Return cached data, or None.  ``max_age=None`` returns it however old."""
        with self._lock:
            self._load()
            entry = self._data.get(key)
        if not isinstance(entry, dict) or "data" not in entry:
            return None
        if max_age is not None and time.time() - entry.get("at", 0) > max_age:
            return None
        return entry["data"]

    def age(self, key):
        with self._lock:
            self._load()
            entry = self._data.get(key)
        return None if not isinstance(entry, dict) else time.time() - entry.get("at", 0)

    def put(self, key, data):
        with self._lock:
            self._load()
            self._data[key] = {"at": time.time(), "data": data}
            snapshot = json.dumps(self._data, separators=(",", ":"), default=str)
        try:
            _atomic_write(self.path, snapshot)
        except Exception as exc:
            print(f"[cache] could not write {self.path}: {exc}")


# ─── logo cache ───

_LOGO_NAME = re.compile(r"^[0-9a-f]{40}\.(png|jpg|jpeg|gif|svg|webp)$")


class LogoCache:
    """Downloads favourite-team logos once and serves them from disk.

    ``url_for(url, cache=True)`` returns a local ``/cache/logo/<name>`` URL when
    the file is on disk; otherwise it queues a background download and returns
    the original URL so the first display still works online.
    """

    ROUTE = "/cache/logo/"

    def __init__(self, directory, fetch):
        self.dir = directory
        self._fetch = fetch          # callable(url) -> bytes | None
        self._pending = set()
        self._failed = {}            # url -> epoch of last failure
        self._lock = threading.Lock()

    @staticmethod
    def _name(url):
        ext = os.path.splitext(url.split("?")[0])[1].lower().lstrip(".")
        if ext not in ("png", "jpg", "jpeg", "gif", "svg", "webp"):
            ext = "png"
        return hashlib.sha1(url.encode("utf-8")).hexdigest() + "." + ext

    @staticmethod
    def valid_name(name):
        return bool(_LOGO_NAME.match(name or ""))

    def url_for(self, url, cache=False):
        if not url or not isinstance(url, str) or not url.startswith(("http://", "https://")):
            return url or ""
        name = self._name(url)
        if os.path.exists(os.path.join(self.dir, name)):
            return self.ROUTE + name
        if cache:
            self._queue(url, name)
        return url

    def _queue(self, url, name):
        with self._lock:
            if url in self._pending or time.time() - self._failed.get(url, 0) < 3600:
                return
            self._pending.add(url)
        threading.Thread(target=self._download, args=(url, name), daemon=True).start()

    def _download(self, url, name):
        try:
            blob = self._fetch(url)
            if blob:
                os.makedirs(self.dir, exist_ok=True)
                tmp = os.path.join(self.dir, f".{name}.part")
                with open(tmp, "wb") as fh:
                    fh.write(blob)
                os.replace(tmp, os.path.join(self.dir, name))
            else:
                self._failed[url] = time.time()
        except Exception:
            self._failed[url] = time.time()
        finally:
            with self._lock:
                self._pending.discard(url)
