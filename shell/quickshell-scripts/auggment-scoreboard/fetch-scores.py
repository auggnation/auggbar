#!/usr/bin/env python3
"""Fetch live/upcoming/final scores from ESPN for the Auggment Scoreboard bar widget.

Reads ~/.config/auggment/scoreboard.json (or --config PATH) and prints a single
JSON document to stdout. Uses only the Python standard library so it runs on a
stock Arch/Omarchy box without pip packages.

Config shape (all keys optional):

    {
      "timezone": "America/Chicago",
      "leagues": ["football/nfl", "basketball/nba"],
      "teams": ["football/nfl:KC", "basketball/nba:BOS"],
      "racing": {"racing/nascar-cup": ["Larson"], "racing/f1": ["Verstappen"]},
      "golf": ["Scheffler"],
      "team_colors": {"football/nfl:KC": "#E31837"},
      "days_back": 1,
      "days_ahead": 7,
      "max_games": 40
    }

Favorite teams use "<league/path>:<ABBREVIATION>" (abbreviations are those ESPN
returns for the team, e.g. KC, BOS, LAD).
"""

import argparse
import hashlib
import json
import os
import sys
import time
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timedelta, timezone
from urllib import request, error

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leagues  # noqa: E402  (shared source metadata; see bin/leagues.py)
import smartcache  # noqa: E402  (polling rules + offline cache; synced with the Auggment-Scoreboard app)

try:
    from zoneinfo import ZoneInfo
except Exception:  # pragma: no cover
    ZoneInfo = None

CONFIG_PATH = os.path.expanduser("~/.config/auggment/scoreboard.json")

# path -> (sport, league) for the ESPN scoreboard endpoint. Ported from the
# Auggment-Scoreboard Flask app so both use identical ESPN slugs.
ESPN_API_PATHS = {
    "football/nfl": ("football", "nfl"),
    "football/cfl": ("football", "cfl"),
    "football/xfl": ("football", "xfl"),
    "football/college-football": ("football", "college-football"),
    "baseball/mlb": ("baseball", "mlb"),
    "baseball/college-baseball": ("baseball", "college-baseball"),
    "baseball/milb": ("baseball", "milb"),
    "basketball/nba": ("basketball", "nba"),
    "basketball/wnba": ("basketball", "wnba"),
    "basketball/euroleague": ("basketball", "euroleague"),
    "basketball/mens-college-basketball": ("basketball", "mens-college-basketball"),
    "basketball/womens-college-basketball": ("basketball", "womens-college-basketball"),
    "hockey/nhl": ("hockey", "nhl"),
    "hockey/mens-college-hockey": ("hockey", "mens-college-hockey"),
    "soccer/usa.1": ("soccer", "usa.1"),
    "soccer/usa.nwsl": ("soccer", "usa.nwsl"),
    "soccer/usa.usl.1": ("soccer", "usa.usl.1"),
    "soccer/usa.usl.l1": ("soccer", "usa.usl.l1"),
    "soccer/eng.1": ("soccer", "eng.1"),
    "soccer/eng.2": ("soccer", "eng.2"),
    "soccer/esp.1": ("soccer", "esp.1"),
    "soccer/ger.1": ("soccer", "ger.1"),
    "soccer/ita.1": ("soccer", "ita.1"),
    "soccer/fra.1": ("soccer", "fra.1"),
    "soccer/ned.1": ("soccer", "ned.1"),
    "soccer/por.1": ("soccer", "por.1"),
    "soccer/mex.1": ("soccer", "mex.1"),
    "soccer/bra.1": ("soccer", "bra.1"),
    "soccer/arg.1": ("soccer", "arg.1"),
    "soccer/uefa.champions": ("soccer", "uefa.champions"),
    "soccer/uefa.europa": ("soccer", "uefa.europa"),
    "soccer/fifa.world": ("soccer", "fifa.world"),
    "volleyball/womens-college-volleyball": ("volleyball", "womens-college-volleyball"),
    "volleyball/mens-college-volleyball": ("volleyball", "mens-college-volleyball"),
    "lacrosse/mens-college-lacrosse": ("lacrosse", "mens-college-lacrosse"),
    "lacrosse/womens-college-lacrosse": ("lacrosse", "womens-college-lacrosse"),
    "lacrosse/pll": ("lacrosse", "pll"),
    "lacrosse/nll": ("lacrosse", "nll"),
    "racing/nascar-cup": ("racing", "nascar-cup"),
    "racing/irl": ("racing", "irl"),
    "racing/f1": ("racing", "f1"),
    "golf/pga": ("golf", "pga"),
}

# Leagues that live on the site.web.api host rather than site.api.
ESPN_WEB_API_LEAGUES = {"softball/college-softball", "baseball/college-baseball"}

# Leagues where a single request (no ?dates=) returns the current slate.
ESPN_NO_DATE_LEAGUES = {
    "baseball/college-baseball", "softball/college-softball",
    "volleyball/mens-college-volleyball", "hockey/mens-college-hockey",
    "lacrosse/mens-college-lacrosse", "lacrosse/womens-college-lacrosse",
}

MOTORSPORTS_LEAGUES = {"racing/nascar-cup", "racing/irl", "racing/f1"}
GOLF_LEAGUES = {"golf/pga"}

LEAGUE_LABELS = {
    "football/nfl": "NFL", "football/cfl": "CFL", "football/xfl": "XFL",
    "football/college-football": "NCAAF",
    "baseball/mlb": "MLB", "baseball/college-baseball": "NCAABB", "baseball/milb": "MiLB",
    "basketball/nba": "NBA", "basketball/wnba": "WNBA", "basketball/euroleague": "EuroLeague",
    "basketball/mens-college-basketball": "NCAAM",
    "basketball/womens-college-basketball": "NCAAW",
    "hockey/nhl": "NHL", "hockey/mens-college-hockey": "NCAACH",
    "soccer/usa.1": "MLS", "soccer/usa.nwsl": "NWSL", "soccer/usa.usl.1": "USL",
    "soccer/usa.usl.l1": "USL1", "soccer/eng.1": "EPL", "soccer/eng.2": "Championship",
    "soccer/esp.1": "La Liga", "soccer/ger.1": "Bundesliga", "soccer/ita.1": "Serie A",
    "soccer/fra.1": "Ligue 1", "soccer/ned.1": "Eredivisie", "soccer/por.1": "Primeira",
    "soccer/mex.1": "Liga MX", "soccer/bra.1": "Brasileirão", "soccer/arg.1": "Primera",
    "soccer/uefa.champions": "UCL", "soccer/uefa.europa": "UEL", "soccer/fifa.world": "World Cup",
    "volleyball/womens-college-volleyball": "NCAAVB", "volleyball/mens-college-volleyball": "NCAAvbM",
    "lacrosse/mens-college-lacrosse": "NCAALAX", "lacrosse/womens-college-lacrosse": "NCAAwlax",
    "lacrosse/pll": "PLL", "lacrosse/nll": "NLL",
    "racing/nascar-cup": "NASCAR", "racing/irl": "IndyCar", "racing/f1": "F1",
    "golf/pga": "PGA",
}

USER_AGENT = "AuggmentScoreboard/1.0 (+https://github.com/auggnation/auggment-scoreboard)"

# TheSportsDB free v1 API (the "3" key is their documented free test key).
TSDB_BASE = "https://www.thesportsdb.com/api/v1/json/3"


FETCH_ERRORS = 0   # network/HTTP failures this run; a run with errors and no data must not replace the cache


def _is_failure(exc):
    """A real outage (offline, timeout, 5xx, rate limit). A 4xx means the server answered and
    simply has nothing for us (e.g. an off-season series) - that is "no data", not an error,
    and must not trigger retries."""
    if isinstance(exc, error.HTTPError):
        return exc.code >= 500 or exc.code == 429
    return True


def http_json(url, timeout=8):
    global FETCH_ERRORS
    req = request.Request(url, headers={"User-Agent": USER_AGENT, "Accept": "application/json"})
    try:
        with request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8", "replace"))
    except Exception as exc:
        if _is_failure(exc):
            FETCH_ERRORS += 1
        raise


def load_config(path):
    cfg = {
        "timezone": "America/Chicago",
        "leagues": [],
        "teams": [],
        "racing": {},
        "golf": [],
        "team_colors": {},
        "days_back": 1,
        "days_ahead": 7,
        "max_games": 40,
    }
    try:
        with open(path, "r") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            cfg.update(loaded)
    except FileNotFoundError:
        pass
    except Exception as exc:  # pragma: no cover
        print(json.dumps({"error": f"config: {exc}"}))
        sys.exit(0)
    return cfg


def tzinfo(name):
    if ZoneInfo is None:
        return timezone.utc
    try:
        return ZoneInfo(name)
    except Exception:
        return timezone.utc


def _is_network_down(exc):
    """True for connection-level failures (offline, DNS, timeout) as opposed to an HTTP error."""
    return not isinstance(exc, error.HTTPError)


def fetch_league(path, days_back, days_ahead, dates=None):
    """Fetch one ESPN league. Returns (events, error_count).

    ``dates`` (list of date objects) restricts the fetch to those days - a live poll is one
    request instead of one per day of the window. A connection failure aborts the rest
    of the fetch instead of burning a timeout per remaining day.
    """
    sport, league = ESPN_API_PATHS.get(path, (path.split("/")[0], path.split("/")[-1]))
    host = "site.web.api.espn.com" if path in ESPN_WEB_API_LEAGUES else "site.api.espn.com"
    base = f"https://{host}/apis/site/v2/sports/{sport}/{league}/scoreboard"

    events, seen, errors = [], set(), 0

    def collect(url):
        nonlocal errors
        try:
            for e in http_json(url).get("events", []):
                if e.get("id") and e["id"] not in seen:
                    seen.add(e["id"])
                    events.append(e)
            return True
        except Exception as exc:
            if not _is_failure(exc):
                return True
            errors += 1
            return not _is_network_down(exc)

    if path in ESPN_NO_DATE_LEAGUES:
        collect(base)
        return events, errors

    if dates is None:
        now = datetime.now(timezone.utc)
        day = (now - timedelta(days=days_back)).date()
        end = (now + timedelta(days=max(days_ahead, 1))).date()
        dates = []
        while day <= end:
            dates.append(day)
            day += timedelta(days=1)
    for day in dates:
        if not collect(f"{base}?dates={day.strftime('%Y%m%d')}"):
            break

    events.sort(key=lambda e: e.get("date", ""))
    return events, errors


def fetch_tsdb(path, days_back, days_ahead):
    """Fetch a league from TheSportsDB (used for leagues ESPN does not carry).

    Combines the next and previous fixtures for the league and keeps only the
    ones inside the look-back / look-ahead window. Returns (events, error_count).
    """
    lid = leagues.TSDB_LEAGUE_IDS.get(path)
    if not lid:
        return [], 0
    events, errors = {}, 0
    for endpoint in ("eventsnextleague.php", "eventspastleague.php"):
        try:
            data = http_json(f"{TSDB_BASE}/{endpoint}?id={lid}")
        except Exception as exc:
            if not _is_failure(exc):
                continue
            errors += 1
            if _is_network_down(exc):
                break
            continue
        for e in data.get("events") or []:
            eid = e.get("idEvent")
            if eid and eid not in events:
                events[eid] = e

    now = datetime.now(timezone.utc)
    lo = (now - timedelta(days=days_back)).date()
    hi = (now + timedelta(days=max(days_ahead, 1))).date()
    out = []
    for e in events.values():
        ts = e.get("strTimestamp") or ""
        try:
            d = datetime.fromisoformat(ts.replace("Z", "+00:00")).date()
        except Exception:
            out.append(e)
            continue
        if lo <= d <= hi:
            out.append(e)
    out.sort(key=lambda e: e.get("strTimestamp") or "")
    return out, errors


def safe_external_url(value):
    """Return the URL only when it is an http(s) link.

    Feed data is untrusted: a file: URL or a custom scheme would otherwise be
    handed to the desktop's MIME/protocol handlers (e.g. via xdg-open), so drop
    everything that is not http/https.
    """
    url = str(value or "").strip()
    lowered = url.lower()
    if lowered.startswith("http://") or lowered.startswith("https://"):
        return url
    return ""


def team_logo(team):
    if not isinstance(team, dict):
        return ""
    logos = team.get("logos") or []
    if logos and isinstance(logos[0], dict):
        return safe_external_url(logos[0].get("href", ""))
    return safe_external_url(team.get("logo", ""))


def _hex(c):
    c = (c or "").strip().lstrip("#")
    return c.lower() if len(c) == 6 and all(ch in "0123456789abcdefABCDEF" for ch in c) else ""


def _luminance(c):
    """Relative luminance (0 = black, 1 = white) of a 6-digit hex colour."""
    def ch(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * ch(r) + 0.7152 * ch(g) + 0.0722 * ch(b)


# Below this the colour disappears on the dark bar (black, near-black navy).
MIN_LUMINANCE = 0.06


def _lighten(c, amount=0.55):
    r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
    return "".join(f"{round(v + (255 - v) * amount):02x}" for v in (r, g, b))


def team_color(team, override):
    """Bar colour for a team: the user's override, else ESPN's primary colour.
    A primary too dark to read (e.g. Pittsburgh's black) is swapped for the
    team's alternate colour (Pittsburgh gold); if that is dark too, the
    primary is lightened."""
    if override:
        return override if override.startswith("#") else f"#{override}"
    if not isinstance(team, dict):
        return ""
    primary, alt = _hex(team.get("color")), _hex(team.get("alternateColor"))
    if not primary:
        return f"#{alt}" if alt else ""
    if _luminance(primary) >= MIN_LUMINANCE:
        return f"#{primary}"
    if alt and _luminance(alt) >= MIN_LUMINANCE:
        return f"#{alt}"
    return f"#{_lighten(primary)}"


def team_color2(team, chosen):
    """The team's other colour (whichever of primary/alternate was not chosen)."""
    if not isinstance(team, dict):
        return ""
    for k in ("color", "alternateColor"):
        h = _hex(team.get(k))
        if h and f"#{h}" != (chosen or "").lower():
            return f"#{h}"
    return ""


def parse_team_game(path, event, cfg_favs, cfg_colors, tz):
    comp_list = event.get("competitions") or []
    if not comp_list or not comp_list[0].get("competitors"):
        return None
    comp = comp_list[0]
    competitors = comp["competitors"]
    home = next((c for c in competitors if c.get("homeAway") == "home"), competitors[0])
    away = next((c for c in competitors if c.get("homeAway") == "away"), competitors[-1])

    status = event.get("status", {})
    stype = status.get("type", {})

    def side(c, homeAway):
        team = c.get("team", {})
        abbr = (team.get("abbreviation") or team.get("shortDisplayName")
                or team.get("displayName") or "?")
        key = f"{path.lower()}:{abbr.upper()}"
        try:
            score = int(c.get("score") or 0)
        except Exception:
            score = c.get("score", "")
        return {
            "abbr": abbr,
            "name": team.get("displayName") or abbr,
            "short_name": team.get("shortDisplayName") or abbr,
            "score": score,
            "logo": team_logo(team),
            "color": team_color(team, cfg_colors.get(key)),
            "color2": team_color2(team, team_color(team, cfg_colors.get(key))),
            "fav": key in cfg_favs,
            "winner": c.get("winner", False),
            "home_away": homeAway,
        }

    a = side(away, "away")
    h = side(home, "home")
    state = stype.get("state", "pre")
    winner = None
    if state in ("in", "post") and isinstance(a["score"], int) and isinstance(h["score"], int):
        winner = "away" if a["score"] > h["score"] else ("home" if h["score"] > a["score"] else "tie")

    start = event.get("date", "")
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00")).astimezone(tz)
        start_local = dt.strftime("%a %-I:%M %p")
        start_full = dt.strftime("%a %b %-d, %-I:%M %p")
    except Exception:
        start_local = ""
        start_full = ""

    return {
        "kind": "game",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, path.split("/")[-1].upper()),
        "state": state,
        "detail": stype.get("shortDetail", "") or stype.get("detail", ""),
        "clock": status.get("displayClock", ""),
        "period": status.get("period", 0),
        "start": start,
        "start_local": start_local,
        "start_full": start_full,
        "name": event.get("shortName") or event.get("name", ""),
        "link": safe_external_url((event.get("links") or [{}])[0].get("href", "")),
        "away": a,
        "home": h,
        "is_fav": a["fav"] or h["fav"],
        "winner": winner,
    }


def parse_tsdb_game(path, event, cfg_favs, cfg_colors, tz):
    """Map a TheSportsDB event to the same shape as parse_team_game."""
    def side(home_away):
        if home_away == "home":
            name = event.get("strHomeTeam") or "?"
            tid = event.get("idHomeTeam")
            raw_score = event.get("intHomeScore")
            logo = event.get("strHomeTeamBadge") or ""
        else:
            name = event.get("strAwayTeam") or "?"
            tid = event.get("idAwayTeam")
            raw_score = event.get("intAwayScore")
            logo = event.get("strAwayTeamBadge") or ""
        abbr = leagues.tsdb_abbr(tid, name)
        key = f"{path.lower()}:{abbr.upper()}"
        try:
            score = int(raw_score)
        except Exception:
            score = 0
        return {
            "abbr": abbr,
            "name": name,
            "short_name": abbr,
            "score": score,
            "logo": logo,
            "color": team_color(None, cfg_colors.get(key)),
            "fav": key in cfg_favs,
            "winner": False,
            "home_away": home_away,
        }

    a = side("away")
    h = side("home")

    status = (event.get("strStatus") or "NS").upper()
    if status in ("FT", "AET", "PEN", "FINAL", "AFTER EXTRA TIME"):
        state = "post"
    elif status in ("NS", "TBD", "POSTPONED", "POSTP", "CANCELED", "CANC", "PST", "SUSP"):
        state = "pre"
    else:
        state = "in"

    winner = None
    if state == "post":
        if a["score"] > h["score"]:
            winner = "away"
            a["winner"] = True
        elif h["score"] > a["score"]:
            winner = "home"
            h["winner"] = True
        else:
            winner = "tie"

    start = event.get("strTimestamp") or ""
    start_local = start_full = ""
    try:
        dt = datetime.fromisoformat(start.replace("Z", "+00:00"))
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        dt = dt.astimezone(tz)
        start_local = dt.strftime("%a %-I:%M %p")
        start_full = dt.strftime("%a %b %-d, %-I:%M %p")
    except Exception:
        pass

    if state == "in":
        detail = event.get("strProgress") or "LIVE"
    elif state == "post":
        detail = "Final"
    else:
        detail = start_full or (event.get("strTime") or "")

    return {
        "kind": "game",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, path.split("/")[-1].upper()),
        "state": state,
        "detail": detail,
        "clock": "",
        "period": int(event.get("intRound") or 0) if str(event.get("intRound") or "").isdigit() else 0,
        "start": start,
        "start_local": start_local,
        "start_full": start_full,
        "name": event.get("strEvent") or "",
        "link": "",
        "away": a,
        "home": h,
        "is_fav": a["fav"] or h["fav"],
        "winner": winner,
    }


def parse_race(path, event, fav_names, allowed):
    status = event.get("status", {})
    stype = status.get("type", {})
    comp_list = event.get("competitions") or []
    competitors = comp_list[0].get("competitors", []) if comp_list else []

    def order_key(c):
        try:
            return int(c.get("order", 999))
        except Exception:
            return 999

    ordered = [c for c in competitors if c.get("order") is not None] or competitors
    ordered = sorted(ordered, key=order_key)

    def is_fav(athlete, car):
        full = (athlete.get("displayName", "") or "").lower()
        return any(f in full or f == (car or "").lower() for f in fav_names)

    drivers = []
    for c in ordered[:10]:
        athlete = c.get("athlete", {})
        name = athlete.get("shortName") or athlete.get("displayName") or "—"
        car = athlete.get("jersey", "")
        drivers.append({
            "pos": c.get("order") or c.get("score", "?"),
            "name": name,
            "car": car,
            "fav": is_fav(athlete, car),
        })
    if fav_names:
        for c in ordered[10:]:
            athlete = c.get("athlete", {})
            car = athlete.get("jersey", "")
            if is_fav(athlete, car):
                name = athlete.get("shortName") or athlete.get("displayName") or "—"
                drivers.append({"pos": c.get("order") or c.get("score", "?"), "name": name,
                                "car": car, "fav": True})

    return {
        "kind": "race",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, path.split("/")[-1].upper()),
        "name": event.get("shortName") or event.get("name", "Race"),
        "state": stype.get("state", "pre"),
        "detail": stype.get("shortDetail", "") or stype.get("detail", ""),
        "is_fav": any(d.get("fav") for d in drivers),
        "drivers": drivers,
    }


def parse_golf(path, event, fav_names):
    status = event.get("status", {})
    stype = status.get("type", {})
    comp_list = event.get("competitions") or []
    competitors = comp_list[0].get("competitors", []) if comp_list else []

    def pos_key(c):
        pos = (c.get("status", {}).get("position", {}) or {}).get("id", "")
        try:
            return int(pos)
        except Exception:
            return 999

    active = [c for c in competitors
              if (c.get("status", {}).get("type", {}) or {}).get("state") not in ("cut", "wd", "dq")]
    ordered = sorted(active or competitors, key=pos_key)

    def is_fav(name):
        full = (name or "").lower()
        return any(f in full for f in fav_names)

    golfers = []
    for c in ordered[:10]:
        athlete = c.get("athlete", {})
        full_name = athlete.get("displayName", "")
        golfers.append({
            "pos": (c.get("status", {}).get("position", {}) or {}).get("displayName", "?"),
            "name": athlete.get("shortName") or full_name or "—",
            "strokes": c.get("score", "—"),
            "fav": is_fav(full_name),
        })
    if fav_names:
        for c in ordered[10:]:
            athlete = c.get("athlete", {})
            if is_fav(athlete.get("displayName", "")):
                golfers.append({
                    "pos": (c.get("status", {}).get("position", {}) or {}).get("displayName", "?"),
                    "name": athlete.get("shortName") or athlete.get("displayName", "—"),
                    "strokes": c.get("score", "—"),
                    "fav": True,
                })

    return {
        "kind": "golf",
        "league_path": path,
        "league_label": LEAGUE_LABELS.get(path, "PGA"),
        "name": event.get("shortName") or event.get("name", "Tournament"),
        "state": stype.get("state", "pre"),
        "detail": stype.get("shortDetail", "") or stype.get("detail", ""),
        "is_fav": any(g.get("fav") for g in golfers),
        "golfers": golfers,
    }


# ---------------------------------------------------------------------------
# Smart polling: what is fetched, and when
# ---------------------------------------------------------------------------
# Raw events are kept per league in ~/.cache/auggment/scoreboard-events/ so a run
# that has nothing due makes ZERO network requests and still produces a full document
# (the bar also works offline from the last known schedule). See smartcache.py for the
# rules; in short: the whole window is re-read a few times a day (midnight first), and a
# league is polled live only while one of its relevant games is on or about to start.

CACHE_DIR = os.path.expanduser("~/.cache/auggment")
EVENTS_DIR = os.path.join(CACHE_DIR, "scoreboard-events")
LOGO_DIR = os.path.join(CACHE_DIR, "scoreboard-logos")

# TheSportsDB is cached upstream; don't ask for it every 30 s while a game is on.
for _p in leagues.TSDB_LEAGUE_IDS:
    smartcache.SLOW_LEAGUES.setdefault(_p, (120, smartcache.LIVE_MAX_AGE))


def _store_file(path):
    return os.path.join(EVENTS_DIR, path.replace("/", "__") + ".json")


def _tsdb_state(event):
    status = (event.get("strStatus") or "NS").upper()
    if status in ("FT", "AET", "PEN", "FINAL", "AFTER EXTRA TIME"):
        return "post"
    if status in ("NS", "TBD", "POSTPONED", "POSTP", "CANCELED", "CANC", "PST", "SUSP"):
        return "pre"
    return "in"


def plan_view(path, events):
    """Events in the ESPN-ish shape the planner understands (TheSportsDB is adapted)."""
    if leagues.source_for(path) != "tsdb":
        return events
    return [{
        "id": e.get("idEvent"),
        "date": e.get("strTimestamp") or "",
        "status": {"type": {"state": _tsdb_state(e)}},
        "_abbrs": [leagues.tsdb_abbr(e.get("idHomeTeam"), e.get("strHomeTeam")).upper(),
                   leagues.tsdb_abbr(e.get("idAwayTeam"), e.get("strAwayTeam")).upper()],
    } for e in events]


def fav_abbrs(path, fav_set):
    prefix = path.lower() + ":"
    return {k[len(prefix):] for k in fav_set if k.startswith(prefix)}


def relevance(path, cfg, fav_set):
    """Predicate for games that may wake the live poller, or None for 'every game'.

    Only favourite teams are shown unless league_in_cycle is on, so a game between two
    other teams must never cause a poll."""
    if cfg.get("league_in_cycle") or path in MOTORSPORTS_LEAGUES or path in GOLF_LEAGUES:
        return None
    favs = fav_abbrs(path, fav_set)
    if not favs:
        return None

    def _rel(ev):
        if "_abbrs" in ev:
            return any(a in favs for a in ev["_abbrs"])
        try:
            for c in ev["competitions"][0]["competitors"]:
                team = c.get("team", {})
                abbr = (team.get("abbreviation") or team.get("shortDisplayName")
                        or team.get("displayName") or "?").upper()
                if abbr in favs:
                    return True
            return False
        except Exception:
            return True
    return _rel


def league_needed(path, cfg, fav_set, golf_favs):
    """A league nobody follows (no favourite team/driver, not shown as a league tile)
    costs nothing: it is never fetched."""
    if path in MOTORSPORTS_LEAGUES:
        return bool((cfg.get("racing") or {}).get(path))
    if path in GOLF_LEAGUES:
        return bool(golf_favs)
    return bool(cfg.get("league_in_cycle")) or bool(fav_abbrs(path, fav_set))


def _live_dates(events, tz):
    """Today, plus yesterday just after midnight or while a game that began yesterday runs."""
    now_local = datetime.now(tz)
    today = now_local.date()
    late = False
    for ev in events:
        if smartcache.event_state(ev) == "in":
            start = smartcache.parse_utc(ev.get("date"))
            if start and start.astimezone(tz).date() < today:
                late = True
    return [today - timedelta(days=1), today] if (late or now_local.hour < 6) else [today]


def refresh_league(path, back, ahead, tz, rel, force, now):
    """Bring one league's stored events up to date if (and only if) something is due.

    Returns (events, next_due_epoch, errors). Never raises; on any failure the last
    stored events are returned so the bar keeps working offline.
    """
    doc = smartcache.load_json(_store_file(path), None)
    have = isinstance(doc, dict) and isinstance(doc.get("events"), list)
    events = doc["events"] if have else None
    meta = dict(doc.get("meta") or {}) if have else {}
    sig = f"{back}:{ahead}"
    fails = int(meta.get("fails", 0))
    backoff_until = meta.get("attempt_at", 0) + smartcache.backoff_seconds(fails, 30) if fails else 0

    view = plan_view(path, events or [])
    mode = None
    if events is None or meta.get("sig") != sig:
        mode = "full"
    elif now >= smartcache.full_due_at(meta.get("full_at"), tz, smartcache.slots_for(view, now, rel)):
        mode = "full"
    else:
        interval, _ = smartcache.live_plan(path, view, now, rel)
        if interval and now >= meta.get("live_at", 0) + interval:
            mode = "live"
        elif force and smartcache.slots_for(view, now, rel) is smartcache.SCHEDULE_SLOTS:
            mode = "live"                     # manual refresh: re-read games happening around now
    if mode and fails and now < backoff_until and not (force and events is None):
        mode = None                           # recently failed (offline?): wait out the backoff

    errors = 0
    if mode:
        meta["attempt_at"] = now
        tsdb = leagues.source_for(path) == "tsdb"
        if tsdb:
            fresh, errors = fetch_tsdb(path, back, ahead)
        elif mode == "live":
            fresh, errors = fetch_league(path, back, ahead, dates=_live_dates(events or [], tz))
        else:
            fresh, errors = fetch_league(path, back, ahead)
        if errors and not fresh:
            meta["fails"] = fails + 1         # keep what we have
        else:
            if tsdb:
                events = fresh if not errors else (events if events is not None else fresh)
            elif mode == "full" and not errors:
                events = smartcache.prune_events(fresh, now, back, ahead)
            else:
                events = smartcache.merge_events(events, fresh)
            if mode == "full" and not errors:
                meta["full_at"] = now
                meta["sig"] = sig
            meta["live_at"] = now
            meta["fails"] = fails + 1 if errors else 0
        # Each run is a fresh process, so the store must always hold the latest poll.
        smartcache.save_json(_store_file(path), {"events": events or [], "meta": meta})

    events = events or []
    view = plan_view(path, events)
    if meta.get("fails"):
        next_due = meta.get("attempt_at", now) + smartcache.backoff_seconds(meta["fails"], 30)
    else:
        cands = [smartcache.full_due_at(meta.get("full_at"), tz, smartcache.slots_for(view, now, rel))]
        interval, wake = smartcache.live_plan(path, view, now, rel)
        if interval:
            cands.append(meta.get("live_at", now) + interval)
        elif wake:
            cands.append(wake)
        next_due = min(cands)
    return events, next_due, errors or meta.get("fails", 0)


def _local_logo(url):
    """Favourite-team logos are downloaded once and then served from disk (offline-safe)."""
    ext = os.path.splitext(url.split("?")[0])[1].lower().lstrip(".")
    name = hashlib.sha1(url.encode("utf-8")).hexdigest() + "." + (ext if ext in ("png", "jpg", "jpeg", "gif", "svg", "webp") else "png")
    dest = os.path.join(LOGO_DIR, name)
    if os.path.exists(dest):
        return "file://" + dest
    marker = os.path.join(LOGO_DIR, "." + name + ".failed")
    try:
        if FETCH_ERRORS or time.time() - os.path.getmtime(marker) < 3600:
            return url
    except OSError:
        pass
    try:
        os.makedirs(LOGO_DIR, exist_ok=True)
        req = request.Request(url, headers={"User-Agent": USER_AGENT})
        with request.urlopen(req, timeout=6) as resp:
            blob = resp.read(2_000_001)
            if not resp.headers.get("Content-Type", "").startswith("image/") or len(blob) > 2_000_000:
                raise ValueError("not a small image")
        tmp = dest + ".part"
        with open(tmp, "wb") as fh:
            fh.write(blob)
        os.replace(tmp, dest)
        return "file://" + dest
    except Exception:
        try:
            open(marker, "w").close()
        except OSError:
            pass
        return url


def localize_logos(games):
    """Cache both logos of every favourite game (the opponent shows on the tile too)."""
    for g in games:
        for side in (g.get("away"), g.get("home")):
            if side and str(side.get("logo", "")).startswith("http"):
                side["logo"] = _local_logo(side["logo"])


def build(cfg, force=False):
    tz = tzinfo(cfg.get("timezone", "America/Chicago"))
    days_back = int(cfg.get("days_back", 1))
    days_ahead = int(cfg.get("days_ahead", 7))
    team_windows = cfg.get("days_ahead_teams", {}) or {}

    def window_for(path):
        """A league must be fetched far enough for its longest per-team window."""
        eff = days_ahead
        prefix = path.lower() + ":"
        for k, v in team_windows.items():
            if isinstance(k, str) and k.lower().startswith(prefix):
                try:
                    eff = max(eff, int(v))
                except Exception:
                    pass
        return eff

    fav_set = set()
    for entry in cfg.get("teams", []):
        if isinstance(entry, str) and ":" in entry:
            lp, abbr = entry.rsplit(":", 1)
            fav_set.add(f"{lp.lower()}:{abbr.upper()}")
    colors = cfg.get("team_colors", {}) or {}
    racing = cfg.get("racing", {}) or {}
    golf_favs = [str(n).strip().lower() for n in cfg.get("golf", []) if str(n).strip()]

    games, races, golf = [], [], []
    now = time.time()
    # "Refresh every N s" in the settings now means: while a favourite game is live, poll
    # this often. (Nothing is polled when no favourite game is on.)
    try:
        smartcache.LIVE_INTERVAL = max(15, int(cfg.get("refresh_seconds", smartcache.LIVE_INTERVAL)))
    except Exception:
        pass
    league_paths = [p for p in cfg.get("leagues", []) if isinstance(p, str)
                    and league_needed(p, cfg, fav_set, golf_favs)]
    next_due, failing = [], 0
    if league_paths:
        with ThreadPoolExecutor(max_workers=min(8, len(league_paths))) as pool:
            fetched = list(pool.map(
                lambda p: (p,) + refresh_league(p, days_back, window_for(p), tz,
                                                relevance(p, cfg, fav_set), force, now),
                league_paths))
    else:
        fetched = []
    for path, events, due, errs in fetched:
        next_due.append(due)
        failing += 1 if errs else 0
        for event in events:
            try:
                if path in MOTORSPORTS_LEAGUES:
                    favs = [str(n).strip().lower() for n in racing.get(path, []) if str(n).strip()]
                    races.append(parse_race(path, event, favs, MOTORSPORTS_LEAGUES))
                elif path in GOLF_LEAGUES:
                    golf.append(parse_golf(path, event, golf_favs))
                elif leagues.source_for(path) == "tsdb":
                    g = parse_tsdb_game(path, event, fav_set, colors, tz)
                    if g:
                        games.append(g)
                else:
                    g = parse_team_game(path, event, fav_set, colors, tz)
                    if g:
                        games.append(g)
            except Exception:
                continue

    def sort_key(g):
        return (0 if g["is_fav"] else 1, {"in": 0, "pre": 1, "post": 2}.get(g["state"], 3),
                g.get("start", ""))

    games.sort(key=sort_key)
    max_games = int(cfg.get("max_games", 40))
    games = games[:max_games]
    localize_logos([g for g in games if g.get("is_fav")])
    return {
        "updated": datetime.now(tz).isoformat(),
        # Epoch seconds when something next needs the network. Until then the cached
        # document is exactly what a fresh run would produce (see scoreboard_lib.get_scores).
        "next_poll_at": min(next_due) if next_due else now + 6 * 3600,
        "offline": bool(failing),
        "timezone": cfg.get("timezone"),
        "counts": {"games": len(games), "races": len(races), "golf": len(golf)},
        "games": games,
        "races": races,
        "golf": golf,
        "fetch_errors": FETCH_ERRORS,
        "has_favorites": bool(fav_set) or bool(racing) or bool(golf_favs),
    }


def main():
    ap = argparse.ArgumentParser(description="Fetch ESPN scores for Auggment Scoreboard")
    ap.add_argument("--config", default=CONFIG_PATH)
    ap.add_argument("--pretty", action="store_true")
    ap.add_argument("--force", action="store_true", help="manual refresh: re-read games happening now")
    args = ap.parse_args()
    cfg = load_config(args.config)
    try:
        result = build(cfg, force=args.force)
    except Exception as exc:  # pragma: no cover
        result = {"error": str(exc), "games": [], "races": [], "golf": []}
    print(json.dumps(result, indent=2 if args.pretty else None))


if __name__ == "__main__":
    main()
