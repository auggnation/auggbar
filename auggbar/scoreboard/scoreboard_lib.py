"""Core logic for the Auggment Scoreboard Waybar port.

This is the QML/Model logic from the original Omarchy plugin ported to plain
Python. It loads config + cached scores, builds the rotating tile list, decides
colours and formats bar text. No GUI here so it is easy to unit test.

Config:  ~/.config/auggment/scoreboard.json
Cache:   ~/.cache/auggment/scoreboard-cache.json
State:   ~/.config/auggment/scoreboard.state.json
"""

import json
import math
import os
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
CONFIG_DIR = os.path.expanduser("~/.config/auggment")
CONFIG_PATH = os.path.join(CONFIG_DIR, "scoreboard.json")
CACHE_DIR = os.path.expanduser("~/.cache/auggment")
CACHE_PATH = os.path.join(CACHE_DIR, "scoreboard-cache.json")
STATE_PATH = os.path.join(CONFIG_DIR, "scoreboard.state.json")
FETCH_SCRIPT = os.path.join(HERE, "fetch-scores.py")

DEFAULT_STATE_COLORS = {
    "live": "#22C55E",
    "today": "#F59E0B",
    "this_week": "#60A5FA",
    "final": "#9CA3AF",
}

STATE_RANK = {"in": 0, "pre": 1, "post": 2}
MOTORSPORTS = {"racing/nascar-cup", "racing/irl", "racing/f1"}
GOLF = {"golf/pga"}


def default_config():
    return {
        "timezone": "America/Chicago",
        "leagues": ["football/nfl"],
        "teams": [],
        "racing": {},
        "golf": [],
        "team_colors": {},
        "days_ahead_teams": {},
        "days_back": 1,
        "days_ahead": 7,
        "refresh_seconds": 60,
        "rotate_seconds": 6,
        "max_games": 40,
        "state_colors": {},
        "bar_logos": True,
        "league_in_cycle": False,
        "position": "right",
        "positioned": False,
    }


def load_config():
    cfg = default_config()
    try:
        with open(CONFIG_PATH, "r") as fh:
            loaded = json.load(fh)
        if isinstance(loaded, dict):
            cfg.update(loaded)
    except FileNotFoundError:
        pass
    except Exception:
        pass
    return cfg


def save_config(cfg):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=CONFIG_DIR, prefix=".scoreboard.", suffix=".tmp")
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, "w") as fh:
            json.dump(cfg, fh, indent=2)
            fh.write("\n")
        os.replace(tmp, CONFIG_PATH)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def _read_state():
    try:
        with open(STATE_PATH, "r") as fh:
            return json.load(fh)
    except Exception:
        return {}


def _write_state(state):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    try:
        with open(STATE_PATH, "w") as fh:
            json.dump(state, fh)
    except Exception:
        pass


def get_rotate_index():
    return int(_read_state().get("rotate_index", 0) or 0)


def set_rotate_index(value):
    state = _read_state()
    state["rotate_index"] = int(value)
    _write_state(state)


def _cache_age():
    try:
        return time.time() - os.path.getmtime(CACHE_PATH)
    except OSError:
        return None


def get_scores(config, force=False):
    """Return the scores document, refetching through fetch-scores.py when the
    cache is older than refresh_seconds (or when force is set)."""
    refresh = max(15, int(config.get("refresh_seconds", 60) or 60))
    age = _cache_age()
    if not force and age is not None and age < refresh:
        try:
            with open(CACHE_PATH, "r") as fh:
                return json.load(fh)
        except Exception:
            pass
    try:
        out = subprocess.run(
            [sys.executable, FETCH_SCRIPT],
            capture_output=True, text=True, timeout=30,
        )
        data = json.loads(out.stdout)
        if isinstance(data, dict):
            os.makedirs(CACHE_DIR, exist_ok=True)
            fd, tmp = tempfile.mkstemp(dir=CACHE_DIR, prefix=".scores.", suffix=".tmp")
            with os.fdopen(fd, "w") as fh:
                json.dump(data, fh)
            os.replace(tmp, CACHE_PATH)
            return data
    except Exception:
        pass
    # Fall back to whatever cache we have, even if stale.
    if age is not None:
        try:
            with open(CACHE_PATH, "r") as fh:
                return json.load(fh)
        except Exception:
            pass
    return {"games": [], "races": [], "golf": [], "counts": {}}


# ---------------------------------------------------------------------------
# Key helpers
# ---------------------------------------------------------------------------

def norm_key(key):
    s = str(key or "")
    i = s.rfind(":")
    if i < 0:
        return s.lower()
    return s[:i].lower() + ":" + s[i + 1:].upper()


def state_rank(state):
    return STATE_RANK.get(state, 3)


def days_until(iso):
    if not iso:
        return 0
    try:
        import datetime
        t = datetime.datetime.fromisoformat(str(iso).replace("Z", "+00:00")).timestamp()
    except Exception:
        return 0
    return math.ceil((t - time.time()) / 86400.0)


def team_ahead(config, key):
    overrides = config.get("days_ahead_teams") or {}
    v = overrides.get(key)
    if v is None or v == "":
        return int(config.get("days_ahead", 7) or 7)
    try:
        return int(v)
    except Exception:
        return int(config.get("days_ahead", 7) or 7)


def game_involves(game, key):
    for side in (game.get("away"), game.get("home")):
        if side and side.get("fav"):
            full = str(game.get("league_path", "")).lower() + ":" + str(side.get("abbr", "")).upper()
            if full == key:
                return True
    return False


def game_visible(game, config):
    if not game or not game.get("is_fav"):
        return False
    if game.get("state") != "pre":
        return True
    du = days_until(game.get("start"))
    for side in (game.get("away"), game.get("home")):
        if side and side.get("fav"):
            key = str(game.get("league_path", "")).lower() + ":" + str(side.get("abbr", "")).upper()
            if du <= team_ahead(config, key):
                return True
    return False


def better_game(a, b):
    ra, rb = state_rank(a.get("state")), state_rank(b.get("state"))
    if ra != rb:
        return ra < rb
    ta, tb = str(a.get("start") or ""), str(b.get("start") or "")
    if a.get("state") == "post":
        return ta > tb
    return ta < tb


def favorite_game_tiles(scores, config):
    games = (scores or {}).get("games") or []
    out, seen = [], set()
    for team in config.get("teams") or []:
        key = norm_key(team)
        best = None
        for g in games:
            if not game_visible(g, config) or not game_involves(g, key):
                continue
            if best is None or better_game(g, best):
                best = g
        if best is not None:
            ident = best.get("league_path", "") + "|" + str(best.get("name", "")) + "|" + str(best.get("start", ""))
            if ident not in seen:
                seen.add(ident)
                out.append(best)
    return out


def league_tiles(scores, config):
    if not config.get("league_in_cycle"):
        return []
    games = (scores or {}).get("games") or []
    out = []
    for path in config.get("leagues") or []:
        if path in MOTORSPORTS or path in GOLF:
            continue
        lst = [g for g in games if g.get("league_path") == path]
        if not lst:
            continue
        lst.sort(key=lambda g: (state_rank(g.get("state")), str(g.get("start") or "")))
        live = sum(1 for g in lst if g.get("state") == "in")
        out.append({
            "kind": "league",
            "league_path": path,
            "league_label": lst[0].get("league_label") or path.split("/")[-1].upper(),
            "games": lst,
            "live": live,
            "state": "in" if live > 0 else "pre",
        })
    return out


def tiles(scores, config):
    out = favorite_game_tiles(scores, config)
    for race in (scores or {}).get("races") or []:
        if race.get("is_fav"):
            out.append(race)
    for golfer in (scores or {}).get("golf") or []:
        if golfer.get("is_fav"):
            out.append(golfer)
    out.extend(league_tiles(scores, config))
    return out


def safe_index(tiles_list, rotate_index):
    n = len(tiles_list)
    if n == 0:
        return 0
    return ((rotate_index % n) + n) % n


# ---------------------------------------------------------------------------
# Categories and colours
# ---------------------------------------------------------------------------

def game_category(game):
    if not game:
        return "this_week"
    if game.get("state") == "in":
        return "live"
    if game.get("state") == "post":
        return "final"
    try:
        import datetime
        d = datetime.datetime.fromisoformat(str(game.get("start", "")).replace("Z", "+00:00")).astimezone()
        n = datetime.datetime.now(d.astimezone().tzinfo)
        if (d.year, d.month, d.day) == (n.year, n.month, n.day):
            return "today"
    except Exception:
        pass
    return "this_week"


def tile_category(tile):
    if not tile:
        return "this_week"
    kind = tile.get("kind")
    if kind == "game":
        return game_category(tile)
    if kind == "league":
        return "live" if tile.get("live", 0) > 0 else "this_week"
    if tile.get("state") == "in":
        return "live"
    if tile.get("state") == "post":
        return "final"
    return "this_week"


def category_label(cat):
    return {"live": "LIVE", "today": "TODAY", "final": "FINAL"}.get(cat, "UPCOMING")


def state_color(config, cat):
    override = (config.get("state_colors") or {}).get(cat)
    return override or DEFAULT_STATE_COLORS.get(cat, "#9CA3AF")


def team_color(side, fallback):
    if side and side.get("fav") and side.get("color"):
        return side["color"]
    return fallback


# ---------------------------------------------------------------------------
# Text formatting
# ---------------------------------------------------------------------------

def tile_title(tile):
    if not tile:
        return ""
    if tile.get("kind") == "league":
        return str(tile.get("league_label", "")) + " scoreboard"
    if tile.get("kind") == "game":
        for side in (tile.get("away"), tile.get("home")):
            if side and side.get("fav"):
                return side.get("name") or side.get("abbr", "")
        a = tile.get("away") or {}
        h = tile.get("home") or {}
        return a.get("abbr", "?") + " @ " + h.get("abbr", "?")
    return tile.get("name", "")


def game_detail(game):
    if not game:
        return ""
    if game.get("state") == "in":
        if game.get("detail"):
            return game["detail"]
        if game.get("clock"):
            return game["clock"] + (" · P" + str(game["period"]) if game.get("period") else "")
        return "LIVE"
    if game.get("state") == "post":
        return "Final"
    return game.get("start_full") or game.get("start_local") or ""


def bar_label(config, scores, tile, loading=False):
    if not tile:
        if loading:
            return "…"
        if not (config.get("teams") or []):
            return "Pick teams"
        return "—"
    if tile.get("kind") == "league":
        label = tile.get("league_label", "")
        if tile.get("live", 0) > 0:
            return label + " · " + str(tile["live"]) + " live"
        return label + " · " + str(len(tile.get("games") or [])) + " games"
    if tile.get("kind") in ("race", "golf"):
        detail = str(tile.get("detail") or "")
        if len(detail) > 14:
            detail = detail[:14]
        return (tile.get("league_label") or "") + (" " + detail if detail else "")
    away = tile.get("away") or {}
    home = tile.get("home") or {}
    if tile.get("state") == "pre":
        return away.get("abbr", "?") + "@" + home.get("abbr", "?")
    return away.get("abbr", "?") + " " + str(away.get("score", "")) + "–" + str(home.get("score", "")) + " " + home.get("abbr", "?")


def summary(config, scores, loading=False):
    counts = (scores or {}).get("counts") or {}
    n = int(counts.get("games", 0)) + int(counts.get("races", 0)) + int(counts.get("golf", 0))
    if not n:
        return "Loading…" if loading else "No games in the look-ahead window"
    return str(n) + " games · looking " + str(config.get("days_ahead", 0)) + " days ahead"


def updated_text(scores):
    up = (scores or {}).get("updated")
    if not up:
        return ""
    try:
        import datetime
        dt = datetime.datetime.fromisoformat(str(up).replace("Z", "+00:00")).astimezone()
        return dt.strftime("%-I:%M %p")
    except Exception:
        return ""


def pango_escape(text):
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))
