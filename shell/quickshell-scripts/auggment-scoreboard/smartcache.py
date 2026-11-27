"""Smart polling + offline cache helpers for Auggmented Scoreboard.

Nothing in here touches Flask or the network except the logo downloader, so the
scheduling rules can be unit-tested on their own. The same file is used by the auggbar
desktop bar; keep the two copies identical.

When ESPN is asked for anything (``plan_league``)
------------------------------------------------
1. **Nightly** - just after local midnight (and the first time a league is seen, or when
   its window/conference filter changes) the whole date window is read, as one request
   per calendar month where ESPN supports it. If nothing is happening that is the only
   traffic for the next 24 hours.
2. **Game day** - a tracked game later today is re-checked every few hours
   (GAMEDAY_INTERVAL) in case it moved or already started.
3. **Live** - from just before the scheduled start until it is final, the day that game
   is on is re-read every LIVE_INTERVAL (one request covers every game that day).
4. **Update interval** - optional user setting (1 minute - 24 hours). Below 24 hours,
   today's unfinished games are also re-checked that often.

Everything fetched is persisted to ``cache/`` so a restart (or a dead network) still
shows the last known schedule, team list and logos.
"""

import hashlib
import json
import os
import re
import tempfile
import threading
import time
from collections import namedtuple
from datetime import date, datetime, timedelta, timezone

try:                       # optional: only used for timestamp formats fromisoformat rejects
    from dateutil import parser as _dtparser
except Exception:
    _dtparser = None

try:                       # ESPN buckets its "dates=" parameter by US Eastern time
    from zoneinfo import ZoneInfo
    FEED_TZ = ZoneInfo("America/New_York")
except Exception:          # pragma: no cover - very old Python / no tz database
    FEED_TZ = timezone(timedelta(hours=-5))

NIGHTLY = (0, 1)                      # local (hour, minute) of the nightly grab
LIVE_INTERVAL = 60                    # seconds between polls while a tracked game is live
GAMEDAY_INTERVAL = 3 * 3600           # re-check a tracked game that is later today
DELAYED_INTERVAL = 15 * 60            # a start that is very late: stop asking every minute
PRE_LEAD = timedelta(minutes=1)       # begin live polling this long before the start
PROMPT_START = timedelta(hours=1)     # a "pre" game this far past its start is still polled live
PRE_GRACE = timedelta(hours=8)        # give up on a delayed start after this
LIVE_MAX_AGE = timedelta(hours=8)     # ignore "in progress" games older than this (stuck feeds)

# User-selectable update interval, in minutes.
UPDATE_MIN_MINUTES = 1
UPDATE_MAX_MINUTES = 24 * 60

# Multi-day events do not need a one-minute heartbeat: path -> (poll seconds, max age)
SLOW_LEAGUES = {
    "golf/pga": (600, timedelta(days=5)),
    "cricket/current": (300, timedelta(days=6)),
}

# Leagues where one "dates=YYYYMM" request returns every game of the month. High-volume
# college sports are truncated by ESPN there, so they are read day by day instead.
MONTH_QUERY_PREFIXES = ("football/", "baseball/mlb", "basketball/nba", "basketball/wnba",
                        "hockey/nhl", "soccer/", "racing/", "golf/")
MONTH_LIMIT = 500                     # larger values make ESPN fall back to 25 results

MAX_BACKOFF = 60 * 60                 # cap for failure backoff while idle (seconds)
MAX_LIVE_BACKOFF = 5 * 60             # ... and while a tracked game is on
DISK_WRITE_MIN_GAP = 300              # live polls persist at most this often (SD-card friendly)


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


def feed_date(start):
    """The date ESPN files an event under."""
    return start.astimezone(FEED_TZ).date()


def next_nightly(ts, tz):
    """First nightly grab strictly after epoch ``ts``, in the user's local time."""
    base = datetime.fromtimestamp(ts, tz)
    for day_offset in (0, 1, 2):
        day = (base + timedelta(days=day_offset)).date()
        naive = datetime(day.year, day.month, day.day, *NIGHTLY)
        cand = tz.localize(naive) if hasattr(tz, "localize") else naive.replace(tzinfo=tz)
        if cand.timestamp() > ts:
            return cand.timestamp()
    return ts + 86400  # pragma: no cover


def clamp_interval(minutes):
    """The user's update interval in seconds, limited to 1 minute .. 24 hours."""
    try:
        minutes = float(minutes)
    except (TypeError, ValueError):
        minutes = UPDATE_MAX_MINUTES
    return int(max(UPDATE_MIN_MINUTES, min(UPDATE_MAX_MINUTES, minutes)) * 60)


# ─── polling decisions ───

# mode     'full' (whole window), 'update' (only ``dates``) or None (leave ESPN alone)
# dates    feed dates an 'update' must read
# next_due epoch time something next becomes due
# reason   'full' | 'live' | 'gameday' | 'interval' | 'idle' | 'backoff'
Plan = namedtuple("Plan", "mode dates next_due reason")

_RANK = {"live": 0, "gameday": 1, "interval": 2}


def backoff_seconds(fails, cap=MAX_BACKOFF):
    """Retry delay after ``fails`` consecutive failures (>=1): 1, 2, 4 ... minutes."""
    return min(cap, 60 * (2 ** (min(fails, 10) - 1)))


def plan_league(path, events, meta, now_ts, tz, sig, interval_s, relevant=None):
    """Decide what (if anything) to ask ESPN for one league right now.

    ``meta``      stored bookkeeping: full_at, seen {iso date: epoch}, sig, fails, attempt_at
    ``sig``       identifies the window/filter; a change forces a new full read
    ``interval_s`` the user's update interval (see clamp_interval)
    ``relevant``  predicate limiting which games count as "tracked" (None = all)
    """
    now = datetime.fromtimestamp(now_ts, timezone.utc)
    today = datetime.fromtimestamp(now_ts, tz).date()
    live_every, max_age = SLOW_LEAGUES.get(path, (LIVE_INTERVAL, LIVE_MAX_AGE))
    targets = {}                       # feed date -> (period, reason)
    wake = []

    def want(day, period, reason):
        old = targets.get(day)
        if old is None:
            targets[day] = (period, reason)
        else:
            targets[day] = (min(old[0], period),
                            reason if _RANK[reason] < _RANK[old[1]] else old[1])

    for ev in events or ():
        start = parse_utc(ev.get("date"))
        if start is None:
            continue
        state = event_state(ev)
        day = feed_date(start)
        is_today = start.astimezone(tz).date() == today
        if relevant is None or relevant(ev):
            if state == "in":
                if now - start <= max_age:
                    want(day, live_every, "live")
            elif state == "pre":
                begin = start - PRE_LEAD
                if begin <= now <= start + PRE_GRACE:
                    late = now > start + PROMPT_START
                    want(day, max(DELAYED_INTERVAL, live_every) if late else live_every, "live")
                elif now < begin:
                    wake.append(begin.timestamp())
                    if is_today:
                        want(day, min(GAMEDAY_INTERVAL, interval_s), "gameday")
        if interval_s < UPDATE_MAX_MINUTES * 60 and is_today and state != "post":
            want(day, interval_s, "interval")

    live = any(r == "live" for _, r in targets.values())
    full_at = meta.get("full_at")
    nightly = next_nightly(full_at, tz) if full_at else 0
    need_full = not full_at or meta.get("sig") != sig or now_ts >= nightly

    fails = int(meta.get("fails") or 0)
    if fails:
        retry = meta.get("attempt_at", 0) + backoff_seconds(
            fails, MAX_LIVE_BACKOFF if live else MAX_BACKOFF)
        if now_ts < retry:
            return Plan(None, [], retry, "backoff")
    if need_full:
        return Plan("full", [], now_ts, "full")

    seen = meta.get("seen") or {}
    due, due_reason, upcoming = [], None, [nightly] + wake
    for day, (period, reason) in sorted(targets.items()):
        at = seen.get(day.isoformat(), full_at) + period
        if now_ts >= at:
            due.append(day)
            if due_reason is None or _RANK[reason] < _RANK[due_reason]:
                due_reason = reason
        else:
            upcoming.append(at)
    if due:
        return Plan("update", due, now_ts, due_reason)
    state = min((r for _, r in targets.values()), key=_RANK.get, default="idle")
    return Plan(None, [], min(upcoming), state)


def full_queries(path, days_back, days_ahead, now_ts):
    """Query strings that cover the window: ``[(query, fallback_days)]``.

    One month query replaces up to ~30 daily ones; ``fallback_days`` are what to ask for
    individually if a month answer looks truncated (empty list for daily queries).
    """
    today = datetime.fromtimestamp(now_ts, FEED_TZ).date()
    first = today - timedelta(days=days_back)
    days = [first + timedelta(days=i) for i in range((days_back + max(days_ahead, 1)) + 1)]
    if path.startswith(MONTH_QUERY_PREFIXES):
        months = {}
        for d in days:
            months.setdefault((d.year, d.month), []).append(d)
        if len(months) < len(days):
            return [(f"dates={y}{m:02d}&limit={MONTH_LIMIT}", ds) for (y, m), ds in sorted(months.items())]
    return [(day_query(d), []) for d in days]


def day_query(day):
    return f"dates={day.strftime('%Y%m%d')}"


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


# ─── request meter ───

class RequestMeter:
    """Counts every request sent to ESPN, per local day, and enforces a daily ceiling.

    The ceiling is a safety net against a bug or an over-eager setting getting the
    address blocked. ``limit`` is a callable returning the ceiling (0 = no limit).
    """

    KEEP_DAYS = 14
    REFUSED_PAUSE = 30 * 60      # silence after ESPN answers 429 / 403

    def __init__(self, path, limit, today=None):
        self.path = path
        self._limit = limit
        self._today = today or (lambda: date.today().isoformat())
        self._lock = threading.Lock()
        self._days = None
        self._paused = 0

    def _load(self):
        if self._days is None:
            raw = load_json(self.path, {})
            raw = raw if isinstance(raw, dict) else {}
            days = raw.get("days")
            self._days = days if isinstance(days, dict) else {}
            self._paused = raw.get("paused_until") or 0

    def _save(self):
        save_json(self.path, {"days": self._days, "paused_until": self._paused})

    def pause(self, now=None):
        """ESPN refused a request: send nothing for a while (survives restarts)."""
        with self._lock:
            self._load()
            self._paused = (now or time.time()) + self.REFUSED_PAUSE
            self._save()

    def paused_until(self, now=None):
        with self._lock:
            self._load()
            return self._paused if self._paused > (now or time.time()) else None

    def acquire(self, kind):
        """Count one request of ``kind``; False (and not counted) if over today's ceiling
        or paused after a refusal."""
        if self.paused_until():
            return False
        with self._lock:
            self._load()
            counts = self._days.setdefault(self._today(), {})
            limit = int(self._limit() or 0)
            sent = sum(v for k, v in counts.items() if k != "blocked")
            allowed = not limit or sent < limit
            key = kind if allowed else "blocked"
            counts[key] = counts.get(key, 0) + 1
            for old in sorted(self._days)[:-self.KEEP_DAYS]:
                del self._days[old]
            # Blocked attempts can come in bursts; no need to write each of them.
            if allowed or counts[key] % 50 == 1:
                self._save()
            return allowed

    def snapshot(self):
        with self._lock:
            self._load()
            today = self._today()
            counts = dict(self._days.get(today, {}))
            blocked = counts.pop("blocked", 0)
            history = {d: sum(v for k, v in c.items() if k != "blocked")
                       for d, c in sorted(self._days.items())}
        return {"date": today, "total": sum(counts.values()), "by_kind": counts,
                "blocked": blocked, "limit": int(self._limit() or 0), "history": history}


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
