"""Team lists for the settings pickers, cached on disk.

A league's team list changes a few times a year, so it is fetched at most once a week
(``~/.cache/auggment/scoreboard-misc.json``) and served from disk - stale if need be - when
ESPN cannot be reached. The settings panel therefore opens instantly and works offline.
Standard library only.
"""

import json
import os
import sys
from urllib import request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import smartcache  # noqa: E402

TTL = 7 * 86400
RETRY_AFTER_FAILURE = 300

# Slugs where the league path segment differs from ESPN's sport/league slugs.
SLUG_OVERRIDES = {
    "softball/college-softball": ("baseball", "college-softball"),
}
WEB_API_LEAGUES = {"softball/college-softball", "baseball/college-baseball"}

_cache = smartcache.KeyValueCache(os.path.expanduser("~/.cache/auggment/scoreboard-misc.json"))
_meter = smartcache.RequestMeter(os.path.expanduser("~/.cache/auggment/api_usage.json"),
                                 limit=lambda: 0)      # counted; a manual picker is never capped


def _http_json(url, timeout=8):
    req = request.Request(url, headers={
        "User-Agent": "AuggmentScoreboard/1.0",
        "Accept": "application/json",
    })
    with request.urlopen(req, timeout=timeout) as resp:
        return json.loads(resp.read().decode("utf-8", "replace"))


def teams_for(path):
    """[{abbr, name, logo, color}] for an ESPN league (color is '#RRGGBB' or '')."""
    key = f"teams:{path}"
    fresh = _cache.get(key, TTL)
    if fresh is not None:
        return fresh
    if _cache.get(key + ":fail", RETRY_AFTER_FAILURE) is not None:
        return _cache.get(key) or []
    sport, league = SLUG_OVERRIDES.get(path, (path.split("/")[0], path.split("/")[-1]))
    host = "site.web.api.espn.com" if path in WEB_API_LEAGUES else "site.api.espn.com"
    if not _meter.acquire("teams"):
        return _cache.get(key) or []
    try:
        res = _http_json(f"https://{host}/apis/site/v2/sports/{sport}/{league}/teams?limit=500")
        raw = res["sports"][0]["leagues"][0]["teams"]
    except Exception:
        _cache.put(key + ":fail", True)
        return _cache.get(key) or []
    out = []
    for t in raw:
        team = t.get("team", {})
        abbr, name = team.get("abbreviation"), team.get("displayName")
        if not abbr or not name:
            continue
        logos = team.get("logos") or []
        color = team.get("color", "")
        out.append({
            "abbr": abbr,
            "name": name,
            "logo": logos[0].get("href", "") if logos and isinstance(logos[0], dict) else "",
            "color": f"#{color}" if color else "",
        })
    out.sort(key=lambda x: x["name"].lower())
    if out:
        _cache.put(key, out)
    return out
