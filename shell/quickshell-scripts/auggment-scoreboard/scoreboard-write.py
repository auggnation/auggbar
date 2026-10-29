#!/usr/bin/env python3
"""Merge a JSON object into the Auggment Scoreboard config.

Used by the Quickshell scoreboard settings window. Any keys present in the
incoming object overwrite the stored values; everything else is preserved.

The JSON is accepted either as a ``--data`` argument (preferred: nothing
depends on a stdin pipe being closed) or on stdin.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import scoreboard_lib as lib  # noqa: E402


def read_payload(argv):
    if "--data" in argv:
        i = argv.index("--data")
        if i + 1 < len(argv):
            return argv[i + 1]
    return sys.stdin.read()


def main():
    raw = read_payload(sys.argv[1:])
    try:
        patch = json.loads(raw) if raw.strip() else {}
    except Exception as exc:  # noqa: BLE001
        print("scoreboard-write: bad json: %s" % exc, file=sys.stderr)
        return 2
    if not isinstance(patch, dict):
        print("scoreboard-write: expected an object", file=sys.stderr)
        return 2
    cfg = lib.load_config()
    cfg.update(patch)
    lib.save_config(cfg)
    print("ok")
    return 0


if __name__ == "__main__":
    sys.exit(main())
