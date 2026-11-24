#!/usr/bin/env python3
"""List the teams in an ESPN league, for the Auggment Scoreboard settings picker.

Usage: list-teams.py <league/path>
Prints JSON: [{"abbr": "KC", "name": "Kansas City Chiefs", "logo": "...", "color": "#E31837"}]
Standard library only.
"""

import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import leagues  # noqa: E402  (shared source metadata; see bin/leagues.py)
import teams_lib  # noqa: E402  (cached team lists)


def main():
    if len(sys.argv) < 2:
        print(json.dumps([]))
        return
    path = sys.argv[1]
    if leagues.source_for(path) == "tsdb":
        out = [{"abbr": t["abbr"], "name": t["name"], "logo": "", "color": ""}
               for t in leagues.TSDB_TEAMS.get(path, [])]
        out.sort(key=lambda x: x["name"].lower())
        print(json.dumps(out))
        return
    print(json.dumps(teams_lib.teams_for(path)))


if __name__ == "__main__":
    main()
