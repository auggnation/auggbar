#!/usr/bin/env python3
"""The "scores board" that opens on left-click of the Scoreboard Waybar module.

Renders every favourite / league / racing / golf line into a rofi|wofi dmenu.
Selecting a game opens its ESPN page (http/https only). A refresh entry at the
top forces a refetch.
"""

import os
import shutil
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dmenu  # noqa: E402
import scoreboard_lib as lib  # noqa: E402

REFRESH = "⟳  Refresh now"
CLOSE = "✕  Close"


def safe_link(url):
    s = str(url or "").strip().lower()
    return s.startswith("http://") or s.startswith("https://")


def game_line(game):
    away = game.get("away") or {}
    home = game.get("home") or {}
    label = str(game.get("league_label", "")).ljust(7)
    if game.get("state") == "pre":
        mid = "%s @ %s" % (away.get("abbr", "?"), home.get("abbr", "?"))
    else:
        mid = "%s %s – %s %s" % (away.get("abbr", "?"), away.get("score", ""),
                                 home.get("score", ""), home.get("abbr", "?"))
    return "%s %s   %s" % (label, mid.ljust(22), lib.game_detail(game))


def build():
    config = lib.load_config()
    scores = lib.get_scores(config)
    games = scores.get("games") or []
    lines = [REFRESH, CLOSE, "──────────────────────────────"]
    actions = {REFRESH: ("refresh", None), CLOSE: ("close", None)}

    def section(title, items):
        if not items:
            return
        lines.append(title)
        for g in items[:12]:
            line = game_line(g)
            # De-dupe identical lines with a zero-width suffix if needed.
            key = line
            n = 1
            while key in actions:
                n += 1
                key = line + "\u200b" * n
            lines.append(key)
            actions[key] = ("open", g.get("link") if safe_link(g.get("link")) else None)

    fav = [g for g in games if lib.game_visible(g, config)]
    live = [g for g in games if not g.get("is_fav") and g.get("state") == "in"]
    pre = [g for g in games if not g.get("is_fav") and g.get("state") == "pre"]
    post = [g for g in games if not g.get("is_fav") and g.get("state") == "post"]

    section("— YOUR TEAMS —", fav)
    section("— LEAGUE · LIVE —", live)
    section("— LEAGUE · UPCOMING —", pre)
    section("— LEAGUE · FINAL —", post)

    for kind, title in (("races", "— RACING —"), ("golf", "— GOLF —")):
        items = scores.get(kind) or []
        if not items:
            continue
        lines.append(title)
        for item in items:
            name = item.get("name", "Event")
            key = "%s   %s" % (name, item.get("detail", ""))
            while key in actions:
                key += "\u200b"
            lines.append(key)
            actions[key] = ("info", None)
            for row in (item.get("drivers") or item.get("golfers") or [])[:10]:
                star = " ★" if row.get("fav") else ""
                extra = ""
                if row.get("car"):
                    extra = "  #%s" % row["car"]
                elif row.get("strokes") is not None:
                    extra = "  (%s)" % row["strokes"]
                sub = "    %s  %s%s%s" % (row.get("pos", "?"), row.get("name", ""), extra, star)
                while sub in actions:
                    sub += "\u200b"
                lines.append(sub)
                actions[sub] = ("info", None)
    return lines, actions


def main():
    lines, actions = build()
    choice = dmenu.choose("Scores", lines)
    if not choice:
        return
    kind, payload = actions.get(choice, ("info", None))
    if kind == "refresh":
        config = lib.load_config()
        lib.get_scores(config, force=True)
        os.execv(sys.executable, [sys.executable, os.path.abspath(__file__)])
    elif kind == "open" and payload:
        # Only ever hand an http(s) URL to the opener; never an arbitrary string.
        if isinstance(payload, str) and payload.startswith(("http://", "https://")):
            opener = shutil.which("xdg-open")
            if opener:
                subprocess.Popen([opener, payload])


if __name__ == "__main__":
    main()
