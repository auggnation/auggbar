"""Small iCalendar (RFC 5545) reader for auggment-calendar.

    iter_events(text, win_start, win_end) -> list of event dicts in the window
    calendar_info(text)                   -> {"name": ..., "color": ...}

Each event dict has: uid, title, location, url, allday (bool), and start/end,
which are `date`s for all-day events and timezone-aware `datetime`s otherwise.
DTEND is exclusive, as in iCalendar. Repeating events (RRULE/RDATE) are
expanded with python-dateutil; EXDATE removes occurrences and RECURRENCE-ID
overrides replace them. Cancelled events are skipped.
"""

from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

from dateutil.rrule import rrulestr

__all__ = ["iter_events", "calendar_info"]


# ----------------------------------------------------------------- parsing

def _unfold(text):
    """Join folded lines (a line starting with space/tab continues the last)."""
    out = []
    for raw in text.replace("\r\n", "\n").replace("\r", "\n").split("\n"):
        if raw[:1] in (" ", "\t") and out:
            out[-1] += raw[1:]
        elif raw:
            out.append(raw)
    return out


def _split(line):
    """'DTSTART;TZID=Europe/Paris:20260101T090000' -> (name, params, value)."""
    head, _, value = line.partition(":")
    parts = head.split(";")
    params = {}
    for p in parts[1:]:
        k, _, v = p.partition("=")
        params[k.upper()] = v.strip('"')
    return parts[0].upper(), params, value


def _unescape(v):
    return (v.replace("\\n", "\n").replace("\\N", "\n").replace("\\,", ",")
             .replace("\\;", ";").replace("\\\\", "\\"))


def _components(lines):
    """Yield (name, [(prop, params, value), ...]) for VCALENDAR-level blocks."""
    stack = []
    for line in lines:
        name, params, value = _split(line)
        if name == "BEGIN":
            stack.append((value.upper(), []))
        elif name == "END":
            if stack:
                yield stack.pop()
        elif stack:
            stack[-1][1].append((name, params, value))


def _tz(params, default_tz):
    tzid = params.get("TZID")
    if tzid:
        try:
            return ZoneInfo(tzid)
        except Exception:  # unknown/Windows-style TZID: fall back to local
            return default_tz
    return default_tz


def _value(params, value, default_tz):
    """One DATE / DATE-TIME value -> date or aware datetime."""
    value = value.strip()
    if params.get("VALUE", "").upper() == "DATE" or (len(value) == 8 and value.isdigit()):
        return date(int(value[0:4]), int(value[4:6]), int(value[6:8]))
    utc = value.endswith("Z")
    dt = datetime.strptime(value.rstrip("Z")[:15], "%Y%m%dT%H%M%S")
    return dt.replace(tzinfo=timezone.utc if utc else _tz(params, default_tz))


def _values(params, value, default_tz):
    return [_value(params, v, default_tz) for v in value.split(",") if v.strip()]


def _duration(v):
    """ISO 8601 duration as used by iCalendar, e.g. -P1DT2H30M, PT45M, P2W."""
    sign = -1 if v.startswith("-") else 1
    v = v.lstrip("+-").lstrip("P")
    total, num, in_time = timedelta(), "", False
    for ch in v:
        if ch == "T":
            in_time = True
        elif ch.isdigit():
            num += ch
        else:
            n = int(num or 0)
            num = ""
            total += {"W": timedelta(weeks=n), "D": timedelta(days=n),
                      "H": timedelta(hours=n), "S": timedelta(seconds=n)}.get(
                ch, timedelta(minutes=n) if in_time else timedelta(days=30 * n))
    return sign * total


# ----------------------------------------------------------------- events

def _as_dt(v):
    """date -> local midnight (aware), for comparisons; datetimes unchanged.
    Local, not UTC: a window "up to Nov 20" must include 6 PM on Nov 19 here."""
    if isinstance(v, datetime):
        return v
    return datetime.combine(v, time.min).astimezone()


def _key(v):
    """Comparable key for matching RECURRENCE-ID / EXDATE to occurrences."""
    return v.isoformat() if not isinstance(v, datetime) else v.astimezone(timezone.utc).isoformat()


def _event(props, default_tz):
    ev = {"uid": "", "title": "", "location": "", "url": "", "status": "",
          "start": None, "end": None, "duration": None, "rrule": [], "rdate": [],
          "exdate": [], "recurrence_id": None}
    for name, params, value in props:
        if name == "UID":
            ev["uid"] = value.strip()
        elif name == "SUMMARY":
            ev["title"] = _unescape(value).strip()
        elif name == "LOCATION":
            ev["location"] = _unescape(value).strip()
        elif name == "URL":
            ev["url"] = value.strip()
        elif name == "STATUS":
            ev["status"] = value.strip().upper()
        elif name == "DTSTART":
            ev["start"] = _value(params, value, default_tz)
        elif name == "DTEND":
            ev["end"] = _value(params, value, default_tz)
        elif name == "DURATION":
            ev["duration"] = _duration(value.strip())
        elif name == "RRULE":
            ev["rrule"].append(value.strip())
        elif name == "RDATE":
            ev["rdate"] += _values(params, value, default_tz)
        elif name == "EXDATE":
            ev["exdate"] += _values(params, value, default_tz)
        elif name == "RECURRENCE-ID":
            ev["recurrence_id"] = _value(params, value, default_tz)
    if ev["start"] is None:
        return None
    allday = not isinstance(ev["start"], datetime)
    if ev["end"] is None:
        ev["end"] = ev["start"] + (ev["duration"] if ev["duration"] is not None
                                   else timedelta(days=1) if allday else timedelta())
    ev["allday"] = allday
    return ev


def _occurrences(ev, win_start, win_end):
    """Start times of `ev` that can overlap [win_start, win_end)."""
    length = ev["end"] - ev["start"]
    lo = _as_dt(win_start) - max(length, timedelta())
    hi = _as_dt(win_end)
    if not ev["rrule"] and not ev["rdate"]:
        return [ev["start"]]
    dtstart = _as_dt(ev["start"])
    starts = []
    for rule in ev["rrule"]:
        # dateutil wants UNTIL to match DTSTART's (naive/aware) kind; all-day
        # rules are expanded in UTC and turned back into dates below.
        rr = rrulestr(rule, dtstart=dtstart, ignoretz=False)
        starts += rr.between(lo, hi, inc=True)
    starts += [_as_dt(r) for r in ev["rdate"] if lo <= _as_dt(r) <= hi]
    if ev["allday"]:
        starts = [s.date() for s in starts]
    excluded = {_key(x if not ev["allday"] else _as_dt(x).date()) for x in ev["exdate"]}
    seen, out = set(), []
    for s in starts:
        k = _key(s)
        if k not in excluded and k not in seen:
            seen.add(k)
            out.append(s)
    return out


def iter_events(text, win_start, win_end):
    """Events (expanded occurrences) overlapping [win_start, win_end)."""
    default_tz = datetime.now().astimezone().tzinfo
    masters, overrides = [], {}
    for name, props in _components(_unfold(text)):
        if name != "VEVENT":
            continue
        ev = _event(props, default_tz)
        if ev is None:
            continue
        if ev["recurrence_id"] is not None:
            overrides[(ev["uid"], _key(ev["recurrence_id"]))] = ev
        else:
            masters.append(ev)

    lo, hi = _as_dt(win_start), _as_dt(win_end)
    out = []

    def emit(e, start, end):
        if e["status"] == "CANCELLED":
            return
        if _as_dt(end) > lo and _as_dt(start) < hi or (start == end and lo <= _as_dt(start) < hi):
            out.append({"uid": e["uid"], "title": e["title"], "location": e["location"],
                        "url": e["url"], "allday": e["allday"], "start": start, "end": end})

    for ev in masters:
        length = ev["end"] - ev["start"]
        for start in _occurrences(ev, win_start, win_end):
            override = overrides.pop((ev["uid"], _key(start)), None)
            if override is not None:
                emit(override, override["start"], override["end"])
            else:
                emit(ev, start, start + length)
    # Overrides whose original slot fell outside the window can still move into it.
    for ov in overrides.values():
        emit(ov, ov["start"], ov["end"])
    out.sort(key=lambda e: _as_dt(e["start"]))
    return out


def calendar_info(text):
    """The feed's display name and colour, if it declares them."""
    info = {"name": "", "color": ""}
    for line in _unfold(text):
        name, _params, value = _split(line)
        if name == "BEGIN" and value.upper() == "VEVENT":
            break
        if name in ("X-WR-CALNAME", "NAME") and not info["name"]:
            info["name"] = _unescape(value).strip()
        elif name in ("X-APPLE-CALENDAR-COLOR", "COLOR") and not info["color"]:
            info["color"] = value.strip()
    return info
