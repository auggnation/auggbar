#!/usr/bin/env python3
"""Terminal (rofi/wofi) settings menu for the Auggment Scoreboard.

A rofi|wofi dmenu loop that edits ~/.config/auggment/scoreboard.json in place.
Every change is saved immediately. Reused for the same fields the Omarchy QML
panel exposed: position, leagues, teams, look-ahead, racing/golf names, colours
and bar options.
"""

import json
import os
import re
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import dmenu  # noqa: E402
import scoreboard_lib as lib  # noqa: E402
import scoreboard_model as model  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
PALETTE = ["#E31837", "#F97316", "#F59E0B", "#22C55E", "#14B8A6", "#3B82F6",
           "#6366F1", "#A855F7", "#EC4899", "#FFFFFF", "#9CA3AF", "#111827"]


def _save(cfg):
    lib.save_config(cfg)


def toggle_menu(title, entries, selected, on_toggle):
    """entries: list of (key, label). selected: set. Repeats until Done."""
    while True:
        lines = []
        index = {}
        for key, label in entries:
            mark = "[x]" if key in selected else "[ ]"
            line = "%s %s" % (mark, label)
            while line in index:
                line += "\u200b"
            index[line] = key
            lines.append(line)
        lines.insert(0, "✔  Done")
        choice = dmenu.choose(title, lines)
        if choice is None or choice.startswith("✔"):
            return
        key = index.get(choice)
        if key is None:
            continue
        on_toggle(key)


def pick_number(label, current, lo, hi, step=1):
    raw = dmenu.ask(label, str(current))
    if raw is None:
        return current
    try:
        value = int(float(raw))
    except Exception:
        return current
    return max(lo, min(hi, value))


def pick_hex(label, current):
    raw = dmenu.ask(label + " (#RRGGBB, blank = default)", current or "")
    if raw is None:
        return current
    raw = raw.strip()
    if raw == "":
        return ""
    if not raw.startswith("#"):
        raw = "#" + raw
    if re.fullmatch(r"#[0-9a-fA-F]{6}", raw):
        return raw.upper()
    dmenu.notify("Colours must look like #RRGGBB", "Auggment Scoreboard", "critical")
    return current


def pick_choice(label, options, current):
    """options: list of (value, label). Returns chosen value."""
    lines = []
    index = {}
    for value, text in options:
        mark = "●" if value == current else "○"
        line = "%s %s" % (mark, text)
        while line in index:
            line += "\u200b"
        index[line] = value
        lines.append(line)
    choice = dmenu.choose(label, lines)
    if choice is None:
        return current
    return index.get(choice, current)


# ---------------------------------------------------------------------------
# Menus
# ---------------------------------------------------------------------------

def menu_leagues(cfg):
    selected = set(cfg.get("leagues") or [])

    def toggle(path):
        if path in selected:
            selected.discard(path)
        else:
            selected.add(path)
        order = [l["path"] for l in model.LEAGUES]
        cfg["leagues"] = [p for p in order if p in selected]
        cfg["teams"] = [t for t in (cfg.get("teams") or []) if t.split(":")[0] in selected]
        _save(cfg)

    entries = []
    for group in model.GROUP_ORDER:
        entries.append((None, "── %s ──" % group))
        for league in model.LEAGUES:
            if league["group"] == group:
                entries.append((league["path"], league["label"]))
    # Headers select nothing.
    entries = [(k, v) for k, v in entries if k is not None]
    toggle_menu("Leagues", entries, selected, toggle)


def _team_options(cfg):
    leagues = cfg.get("leagues") or []
    if not leagues:
        return []
    try:
        out = subprocess.run([sys.executable, os.path.join(HERE, "list-all-teams.py")] + leagues,
                             capture_output=True, text=True, timeout=30)
        return json.loads(out.stdout or "[]")
    except Exception:
        return []


def menu_teams(cfg):
    options = _team_options(cfg)
    if not options:
        dmenu.notify("Pick leagues first", "Auggment Scoreboard", "low")
        return
    by_value = {o["value"]: o for o in options}
    selected = set(cfg.get("teams") or [])

    def toggle(value):
        if value in selected:
            selected.discard(value)
        else:
            selected.add(value)
        cfg["teams"] = sorted(selected)
        _save(cfg)

    entries = [(o["value"], "%s · %s" % (o["label"], o["description"])) for o in options]
    toggle_menu("Favourite teams", entries, selected, toggle)


def menu_racing(cfg):
    current = ", ".join(_racing_names(cfg))
    raw = dmenu.ask("Racing drivers (comma-separated)", current)
    if raw is None:
        return
    names = [s.strip() for s in raw.split(",") if s.strip()]
    racing = {}
    for league in model.LEAGUES:
        if model.is_racing(league["path"]):
            racing[league["path"]] = names
    cfg["racing"] = racing
    _save(cfg)


def _racing_names(cfg):
    seen, out = set(), []
    for names in (cfg.get("racing") or {}).values():
        for name in names:
            n = str(name).strip()
            if n and n.lower() not in seen:
                seen.add(n.lower())
                out.append(n)
    return out


def menu_golf(cfg):
    current = ", ".join(cfg.get("golf") or [])
    raw = dmenu.ask("Golf players (comma-separated)", current)
    if raw is None:
        return
    cfg["golf"] = [s.strip() for s in raw.split(",") if s.strip()]
    _save(cfg)


def menu_state_colors(cfg):
    colors = dict(cfg.get("state_colors") or {})
    for key in ("live", "today", "this_week", "final"):
        current = colors.get(key, lib.DEFAULT_STATE_COLORS.get(key, ""))
        value = pick_hex("Colour: " + key, current)
        if value == "":
            colors.pop(key, None)
        else:
            colors[key] = value
    cfg["state_colors"] = colors
    _save(cfg)


def menu_team_colors(cfg):
    teams = cfg.get("teams") or []
    if not teams:
        dmenu.notify("Add favourite teams first", "Auggment Scoreboard", "low")
        return
    colors = dict(cfg.get("team_colors") or {})
    for team in teams:
        value = pick_hex("Colour: " + team, colors.get(team, ""))
        if value == "":
            colors.pop(team, None)
        else:
            colors[team] = value
    cfg["team_colors"] = colors
    _save(cfg)


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    if not dmenu.available():
        dmenu.notify("Install rofi or wofi to use the Scoreboard settings")
        return
    cfg = lib.load_config()
    while True:
        teams_n = len(cfg.get("teams") or [])
        leagues_n = len(cfg.get("leagues") or [])
        menu = [
            "Leagues (%d selected)" % leagues_n,
            "Favourite teams (%d)" % teams_n,
            "Racing drivers",
            "Golf players",
            "Days ahead: %s" % cfg.get("days_ahead", 7),
            "Days back: %s" % cfg.get("days_back", 1),
            "Rotate: %ss" % cfg.get("rotate_seconds", 6),
            "Refresh: %ss" % cfg.get("refresh_seconds", 60),
            "Bar logos: %s" % ("On" if cfg.get("bar_logos", True) else "Off"),
            "League last in cycle: %s" % ("On" if cfg.get("league_in_cycle") else "Off"),
            "Game state colours",
            "Team colours",
            "Clear all favourites",
            "Refresh scores now",
            "Quit",
        ]
        choice = dmenu.choose("Auggment Scoreboard", menu)
        if choice is None or choice == "Quit":
            break
        if choice.startswith("Leagues"):
            menu_leagues(cfg)
        elif choice.startswith("Favourite teams"):
            menu_teams(cfg)
        elif choice.startswith("Racing drivers"):
            menu_racing(cfg)
        elif choice.startswith("Golf players"):
            menu_golf(cfg)
        elif choice.startswith("Days ahead"):
            cfg["days_ahead"] = pick_number("Days ahead (0-30)", cfg.get("days_ahead", 7), 0, 30)
            _save(cfg)
        elif choice.startswith("Days back"):
            cfg["days_back"] = pick_number("Days back (0-14)", cfg.get("days_back", 1), 0, 14)
            _save(cfg)
        elif choice.startswith("Rotate"):
            cfg["rotate_seconds"] = pick_number("Rotate seconds (2-60)", cfg.get("rotate_seconds", 6), 2, 60)
            _save(cfg)
        elif choice.startswith("Refresh:"):
            cfg["refresh_seconds"] = pick_number("Refresh seconds (15-600)", cfg.get("refresh_seconds", 60), 15, 600, 5)
            _save(cfg)
        elif choice.startswith("Bar logos"):
            cfg["bar_logos"] = not cfg.get("bar_logos", True)
            _save(cfg)
        elif choice.startswith("League last"):
            cfg["league_in_cycle"] = not cfg.get("league_in_cycle", False)
            _save(cfg)
        elif choice.startswith("Game state colours"):
            menu_state_colors(cfg)
        elif choice.startswith("Team colours"):
            menu_team_colors(cfg)
        elif choice.startswith("Clear all"):
            cfg["teams"] = []
            cfg["days_ahead_teams"] = {}
            _save(cfg)
        elif choice.startswith("Refresh scores"):
            lib.get_scores(cfg, force=True)
            dmenu.notify("Scores refreshed")


if __name__ == "__main__":
    main()
