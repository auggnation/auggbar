#!/usr/bin/env python3
"""Emit the audio graph as JSON for the Quickshell sound panel.

    {"sinks": [...], "sources": [...], "streams": [...],
     "default_sink": ID|null, "default_source": ID|null}

Each entry is {"id", "name", "volume" (0..1), "muted", "default"}.
Backed by `wpctl`, which is already the source of truth for the bar widget.
"""

import json
import re
import subprocess


def run(args):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=5).stdout
    except Exception:
        return ""


def get_volume(pid):
    out = run(["wpctl", "get-volume", str(pid)])
    m = re.search(r"Volume:\s*([0-9.]+)", out)
    vol = float(m.group(1)) if m else 0.0
    return vol, ("[MUTED]" in out)


def parse_status():
    out = run(["wpctl", "status"])
    buckets = {"Sinks": [], "Sources": [], "Streams": []}
    cur = None
    region = None
    for raw in out.splitlines():
        # Drop the tree glyphs (│├└─) that `wpctl status` draws down the left.
        s = raw.strip().lstrip("│├└─ \t")
        if raw.strip() in ("Audio", "Video"):
            region = raw.strip()
            cur = None
            continue
        if s.endswith("Sinks:"):
            cur = "Sinks"
            continue
        if s.endswith("Sources:"):
            cur = "Sources"
            continue
        if s.endswith("Streams:"):
            cur = "Streams"
            continue
        if s.endswith(("Filters:", "Devices:", "Clients:")):
            cur = None
            continue
        if cur is None or region != "Audio":
            continue
        m = re.match(r"^(\*?)\s*(\d+)\.\s+(.*?)(?:\s+\[vol:[^\]]*\])?\s*$", s)
        if not m:
            continue
        buckets[cur].append({
            "id": int(m.group(2)),
            "name": m.group(3).strip(),
            "default": m.group(1) == "*",
        })
    return buckets


def main():
    st = parse_status()
    result = {"sinks": [], "sources": [], "streams": []}
    for key, out_key in (("Sinks", "sinks"), ("Sources", "sources"), ("Streams", "streams")):
        for entry in st[key]:
            # A stream opened by our own mic probe should not clutter the panel.
            if out_key == "streams" and "pw-record" in entry["name"]:
                continue
            vol, muted = get_volume(entry["id"])
            result[out_key].append({
                "id": entry["id"],
                "name": entry["name"],
                "volume": round(vol, 4),
                "muted": muted,
                "default": entry["default"],
            })
    result["default_sink"] = next((e["id"] for e in result["sinks"] if e["default"]), None)
    result["default_source"] = next((e["id"] for e in result["sources"] if e["default"]), None)
    print(json.dumps(result))


if __name__ == "__main__":
    main()
