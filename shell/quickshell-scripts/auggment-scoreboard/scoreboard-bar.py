#!/usr/bin/env python3
"""Waybar custom-module producer for the Auggment Scoreboard.

Prints one JSON object for Waybar:
    {"text": "...", "tooltip": "...", "class": "live", "alt": "..."}

Run with no arguments it advances the rotation by one tile (Waybar calls it
every rotate_seconds). Pass --no-advance to render the current tile without
stepping (used right after settings changes, scroll, etc.).
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import scoreboard_lib as lib  # noqa: E402


def render(config, scores, tile, index, total, loading=False):
    parts = []
    cls = lib.tile_category(tile) if tile else "empty"

    if tile and tile.get("kind") == "game":
        away = tile.get("away") or {}
        home = tile.get("home") or {}
        state = lib.state_color(config, cls)
        fg = state
        away_abbr = away.get("abbr") or "?"
        home_abbr = home.get("abbr") or "?"
        detail = lib.game_detail(tile)
        if tile.get("state") == "pre":
            text = "%s @ %s   %s" % (away_abbr, home_abbr, detail)
        else:
            text = "%s %s-%s %s   %s" % (
                away_abbr, away.get("score", ""), home.get("score", ""), home_abbr,
                detail if detail != "Final" else "Final")
        tip = "%s\n%s\n%s" % (lib.tile_title(tile), detail, lib.summary(config, scores))
    else:
        state = lib.state_color(config, cls)
        label = lib.bar_label(config, scores, tile, loading)
        text = label
        tip = lib.tile_title(tile) if tile else lib.summary(config, scores, loading)
        if tile:
            tip = "%s\n%s" % (tip, lib.summary(config, scores))
        else:
            tip = "%s\nNo teams selected yet — open settings to pick teams." % tip

    if total > 1:
        tip += "\n%d / %d — scroll to step" % (index + 1, total)

    alt = "sports"
    return {"text": text, "tooltip": tip, "class": cls, "alt": alt}


def main():
    advance = "--no-advance" not in sys.argv[1:]
    config = lib.load_config()
    scores = lib.get_scores(config)
    tl = lib.tiles(scores, config)

    idx = lib.get_rotate_index()
    if advance and len(tl) > 1:
        idx = (idx + 1) % len(tl)
        lib.set_rotate_index(idx)

    si = lib.safe_index(tl, idx)
    tile = tl[si] if tl else None
    loading = not scores.get("games")
    print(json.dumps(render(config, scores, tile, si, len(tl), loading)))


if __name__ == "__main__":
    main()
