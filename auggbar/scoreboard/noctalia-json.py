#!/usr/bin/env python3
"""Scoreboard data for the Noctalia auggbar plugin.

Prints {"tiles": [...], "config": {...}} where every tile carries the extra
display fields the Luau widget needs (cat, color, bar, title, detail).
Reads ~/.config/auggment/scoreboard.json, same as the Quickshell bar.

    noctalia-json.py            use the cache while it is fresh
    noctalia-json.py --force    refetch from ESPN now
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scoreboard_lib as lib  # noqa: E402


def main():
    force = "--force" in sys.argv[1:]
    cfg = lib.load_config()
    scores = lib.get_scores(cfg, force=force)
    out = []
    for tile in lib.tiles(scores, cfg):
        cat = lib.tile_category(tile)
        tile["cat"] = cat
        tile["cat_label"] = lib.category_label(cat)
        tile["color"] = lib.state_color(cfg, cat)
        tile["bar"] = lib.bar_label(cfg, scores, tile)
        tile["title"] = lib.tile_title(tile)
        tile["detail"] = lib.game_detail(tile) if tile.get("kind") == "game" else str(tile.get("detail") or "")
        out.append(tile)
    print(json.dumps({
        "tiles": out,
        "updated": lib.updated_text(scores),
        "config": {
            "rotate_seconds": cfg.get("rotate_seconds", 10),
            "refresh_seconds": cfg.get("refresh_seconds", 60),
            "teams": cfg.get("teams") or [],
            "leagues": cfg.get("leagues") or [],
            "bar_logos": cfg.get("bar_logos", True),
        },
    }))


if __name__ == "__main__":
    main()
