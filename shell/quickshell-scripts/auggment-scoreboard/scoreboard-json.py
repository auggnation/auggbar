#!/usr/bin/env python3
"""Emit the full scoreboard tile list as JSON for the Quickshell bar.

    {"tiles": [...], "index": N, "total": N, "config": {...}}

The Quickshell widget renders the tiles itself, so this returns data only —
no ANSI, no markup.
"""

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scoreboard_lib as lib  # noqa: E402


def main():
    cfg = lib.load_config()
    scores = lib.get_scores(cfg)
    tiles = lib.tiles(scores, cfg)
    colors = dict(lib.DEFAULT_STATE_COLORS)
    colors.update(cfg.get("state_colors") or {})
    doc = {
        "tiles": tiles,
        "index": lib.safe_index(tiles, lib.get_rotate_index()),
        "total": len(tiles),
        "config": {
            "rotate_seconds": cfg.get("rotate_seconds", 6),
            "refresh_seconds": cfg.get("refresh_seconds", 60),
            "timezone": cfg.get("timezone", ""),
            "state_colors": colors,
            "has_teams": bool(cfg.get("teams") or []),
        },
    }
    dead = (scores or {}).get("counts") or {}
    doc["counts"] = dead
    print(json.dumps(doc))


if __name__ == "__main__":
    main()
