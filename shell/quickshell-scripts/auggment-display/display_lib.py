"""Core logic for the Auggment Display Waybar port.

Ports the pure helpers from the original Omarchy plugin's Model.js to Python and
targets CachyOS' classic Hyprland config (monitorv2 blocks) instead of Omarchy's
Lua config. Also owns the small amount of state the CLI and menu share.
"""

import json
import os
import subprocess

CONFIG_DIR = os.path.expanduser("~/.config/auggment")
HYPR_DIR = os.path.expanduser("~/.config/hypr")
HYPR_CONF = os.path.join(HYPR_DIR, "hyprland.conf")
# hyprland.lua dofile()s this path (see the "Managed monitor block" section of
# hyprland.lua).  It must be Lua: writing hyprlang here silently did nothing.
MANAGED_CONF = os.path.join(HYPR_DIR, "auggment-monitors.lua")
PENDING_PATH = os.path.join(CONFIG_DIR, "display-pending.json")
SELECTED_PATH = os.path.join(CONFIG_DIR, "display-selected")

SCALE_PRESETS = ["1", "1.25", "1.5", "1.6", "1.75", "1.8", "2", "2.25",
                 "2.5", "2.75", "3"]
REVERT_SECONDS = 15

BEGIN = "-- BEGIN auggment-display (managed by the Display menu, do not edit)"
END = "-- END auggment-display"


# ---------------------------------------------------------------------------
# Pure helpers (ports of Model.js)
# ---------------------------------------------------------------------------

def normalize_scale(scale):
    try:
        n = float(scale)
    except (TypeError, ValueError):
        return ""
    return str(round(n * 100) / 100)


def _gcd(a, b):
    while b:
        a, b = b, a % b
    return a


def clean_scale(scale, width, height):
    """Snap a scale to the nearest value Hyprland will honour on this mode.

    Hyprland only keeps a scale when both dimensions stay whole pixels, i.e.
    scale*120 must divide 120*gcd(width, height); it rounds to the *nearest*
    qualifying value (1.8 -> 1.875 on a 2880x1920 panel).  Rounding up like we
    used to silently disagree with Hyprland, so the value shown in the menu
    never matched what actually got applied.
    """
    try:
        requested = float(scale)
        w = int(width)
        h = int(height)
    except (TypeError, ValueError):
        return ""
    if requested <= 0 or w <= 0 or h <= 0:
        return ""
    divisor = _gcd(round(w * 120), round(h * 120))
    units = round(requested * 120)
    if units > divisor:
        units = divisor
    if units < 1:
        return ""
    if divisor % units == 0:
        return normalize_scale(units / 120)
    lo = units - 1
    while lo > 0 and divisor % lo != 0:
        lo -= 1
    hi = units + 1
    while hi <= divisor and divisor % hi != 0:
        hi += 1
    if lo < 1:
        best = hi
    elif hi > divisor:
        best = lo
    else:
        best = lo if (units - lo) <= (hi - units) else hi
    return normalize_scale(best / 120)


def available_scales(presets, width, height):
    by_effective = {}
    for i, preset in enumerate(presets):
        effective = clean_scale(preset, width, height)
        if effective == "":
            continue
        distance = abs(float(preset) - float(effective))
        if effective not in by_effective or distance < by_effective[effective][1]:
            by_effective[effective] = (i, distance)
    return [key for key, _ in sorted(by_effective.items(), key=lambda kv: kv[1][0])]


def parse_mode(text):
    import re
    m = re.match(r"^(\d+)x(\d+)@([\d.]+)Hz$", str(text or "").strip())
    if not m:
        return None
    return {"width": int(m.group(1)), "height": int(m.group(2)), "hz": round(float(m.group(3)), 2)}


def mode_string(width, height, hz):
    return "%dx%d@%.2f" % (int(width), int(height), float(hz))


def is_internal(name):
    import re
    return bool(re.match(r"^(eDP|LVDS|DSI)-", str(name or "")))


def parse_monitors(raw):
    try:
        monitors = json.loads(raw) if raw else []
    except Exception:
        monitors = []
    if not isinstance(monitors, list):
        return []
    out = []
    for m in monitors:
        seen, modes = set(), []
        for available in m.get("availableModes") or []:
            mode = parse_mode(available)
            if not mode:
                continue
            key = mode_string(mode["width"], mode["height"], mode["hz"])
            if key in seen:
                continue
            seen.add(key)
            modes.append(mode)
        name = str(m.get("name") or "")
        out.append({
            "name": name,
            "description": str(m.get("description") or ""),
            "model": str(m.get("model") or m.get("description") or name),
            "internal": is_internal(name),
            "enabled": m.get("disabled") is not True,
            "focused": m.get("focused") is True,
            "width": int(m.get("width") or 0),
            "height": int(m.get("height") or 0),
            "hz": round(float(m.get("refreshRate") or 0), 2),
            "scale": normalize_scale(m.get("scale")) or "1",
            "transform": int(m.get("transform") or 0),
            "x": int(m.get("x") or 0),
            "y": int(m.get("y") or 0),
            "mirrorOf": str(m.get("mirrorOf") or "") if m.get("mirrorOf") not in (None, "none") else "",
            "vrr": int(bool(m.get("vrr"))),
            "hdr": str(m.get("colorManagementPreset") or "").lower() == "hdr",
            "modes": modes,
        })
    return out


def resolutions(modes):
    seen, out = set(), []
    for mode in modes:
        key = "%dx%d" % (mode["width"], mode["height"])
        if key in seen:
            continue
        seen.add(key)
        out.append({"value": key, "label": "%d × %d" % (mode["width"], mode["height"]),
                    "width": mode["width"], "height": mode["height"]})
    out.sort(key=lambda r: r["width"] * r["height"], reverse=True)
    return out


def refresh_rates(modes, width, height):
    out = []
    for mode in modes:
        if mode["width"] != width or mode["height"] != height:
            continue
        out.append({"value": "%.2f" % mode["hz"], "label": "%.2f Hz" % mode["hz"]})
    out.sort(key=lambda r: float(r["value"]), reverse=True)
    return out


def settings_from_display(d):
    first = (d.get("modes") or [{}])[0]
    has_mode = d["width"] > 0 and d["height"] > 0 and d["hz"] > 0
    return {
        "output": d["name"],
        "disabled": not d["enabled"],
        "width": d["width"] if has_mode else first.get("width", 0),
        "height": d["height"] if has_mode else first.get("height", 0),
        "hz": d["hz"] if has_mode else first.get("hz", 60),
        "position": ("%dx%d" % (d["x"], d["y"])) if d["enabled"] else "auto",
        "scale": d["scale"],
        "transform": d["transform"],
        "mirror": d["mirrorOf"],
        "vrr": d["vrr"],
        "hdr": d["hdr"],
    }


def _lua_str(value):
    """Quote a string as a Lua literal."""
    return '"%s"' % str(value).replace("\\", "\\\\").replace('"', '\\"')


def _lua_num(value, default="0"):
    try:
        return repr(float(value))
    except (TypeError, ValueError):
        return repr(float(default))


def monitor_block(s):
    """One hl.monitor({ ... }) call — the monitor keyword of hyprland.lua.

    hyprland.lua dofile()s this block *after* its own base fallback monitor
    line, and later hl.monitor() calls win, so these settings are what stick.
    """
    fields = ["    output = %s" % _lua_str(s["output"])]
    if s["disabled"]:
        fields.append("    disabled = true")
    else:
        fields.append("    mode = %s" % _lua_str(mode_string(s["width"], s["height"], s["hz"])))
        fields.append("    position = %s" % _lua_str(s["position"]))
        fields.append("    scale = %s" % _lua_num(s["scale"], "1"))
        fields.append("    transform = %d" % int(s["transform"]))
        if s["mirror"]:
            fields.append("    mirror = %s" % _lua_str(s["mirror"]))
        fields.append("    vrr = %d" % int(s["vrr"]))
        if s["hdr"]:
            fields.append("    cm = %s" % _lua_str("hdr"))
            fields.append("    bitdepth = 10")
    # Lua table fields must be comma-separated.
    return "hl.monitor({\n" + ",\n".join(fields) + "\n})"


def parse_edid(raw):
    by_name = {}
    for line in str(raw or "").splitlines():
        parts = line.split("\t")
        if len(parts) < 3 or not parts[0]:
            continue
        by_name[parts[0]] = {"hdr": parts[1] == "1", "range": parts[2] or ""}
    return by_name


def parse_position(text):
    import re
    m = re.match(r"^(-?\d+)x(-?\d+)$", str(text or ""))
    return {"x": int(m.group(1)), "y": int(m.group(2))} if m else None


def logical_rect(s):
    position = parse_position(s.get("position"))
    if not position:
        return None
    rotated = int(s.get("transform", 0)) % 2 == 1
    w = round((s["height"] if rotated else s["width"]) / float(s["scale"]))
    h = round((s["width"] if rotated else s["height"]) / float(s["scale"]))
    return {"x": position["x"], "y": position["y"], "w": w, "h": h}


def bounds(rects):
    if not rects:
        return {"x": 0, "y": 0, "w": 1, "h": 1}
    xs = [r["x"] for r in rects]
    ys = [r["y"] for r in rects]
    return {"x": min(xs), "y": min(ys),
            "w": max(r["x"] + r["w"] for r in rects) - min(xs),
            "h": max(r["y"] + r["h"] for r in rects) - min(ys)}


def _overlaps(a, b):
    return a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]


def _touches(a, b):
    x = a["x"] + a["w"] == b["x"] or b["x"] + b["w"] == a["x"]
    y = a["y"] + a["h"] == b["y"] or b["y"] + b["h"] == a["y"]
    px = a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"]
    py = a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]
    return (x and py) or (y and px)


def _nearest(value, candidates, threshold):
    best, best_d = value, threshold
    for c in candidates:
        d = abs(c - value)
        if d < best_d:
            best, best_d = c, d
    return best


def snap_position(moving, others, threshold=60):
    xs, ys = [], []
    for o in others:
        xs += [o["x"] + o["w"], o["x"] - moving["w"], o["x"], o["x"] + o["w"] - moving["w"]]
        ys += [o["y"] + o["h"], o["y"] - moving["h"], o["y"], o["y"] + o["h"] - moving["h"]]
    rect = {"x": _nearest(moving["x"], xs, threshold),
            "y": _nearest(moving["y"], ys, threshold),
            "w": moving["w"], "h": moving["h"]}
    for _ in range(8):
        pushed = False
        for other in others:
            if not _overlaps(rect, other):
                continue
            moves = [{"x": other["x"] + other["w"], "y": rect["y"]},
                     {"x": other["x"] - rect["w"], "y": rect["y"]},
                     {"x": rect["x"], "y": other["y"] + other["h"]},
                     {"x": rect["x"], "y": other["y"] - rect["h"]}]
            best = min(moves, key=lambda m: abs(m["x"] - rect["x"]) + abs(m["y"] - rect["y"]))
            rect["x"], rect["y"] = best["x"], best["y"]
            pushed = True
        if not pushed:
            break
    for other in others:
        if _touches(rect, other):
            break
    else:
        if others:
            rect["x"], rect["y"] = rect["x"], rect["y"]
    return {"x": round(rect["x"]), "y": round(rect["y"])}


TRANSFORMS = ["0°", "90°", "180°", "270°"]


def transform_label(transform):
    return TRANSFORMS[int(transform) % 4]


def brightness_name(percent):
    p = round(percent)
    if p >= 95:
        return "Sun blast"
    if p >= 80:
        return "Solar flare"
    if p >= 65:
        return "Golden hour"
    if p >= 45:
        return "Even day"
    if p >= 30:
        return "Soft glow"
    if p >= 20:
        return "Lamp light"
    if p >= 10:
        return "Candlelit"
    return "Night owl"


# ---------------------------------------------------------------------------
# System access
# ---------------------------------------------------------------------------

def _managed_vrr():
    """Configured per-monitor VRR policy, read back from the managed Lua block.

    hyprctl's `vrr` field is only the *currently active* VRR state (see
    hyprwm/Hyprland#14740), never the policy we set, and it collapses to a
    boolean — so it can never report "Fullscreen" (2).  The managed file is the
    policy we actually wrote, so read it back from there.
    """
    import re
    out = {}
    try:
        with open(MANAGED_CONF) as fh:
            text = fh.read()
    except OSError:
        return out
    for block in re.findall(r"hl\.monitor\(\{(.*?)\n\}\)", text, re.S):
        name = re.search(r'output\s*=\s*"([^"]+)"', block)
        vrr = re.search(r"\bvrr\s*=\s*(\d+)", block)
        if name and vrr:
            out[name.group(1)] = int(vrr.group(1))
    return out


def read_monitors():
    try:
        out = subprocess.run(["hyprctl", "monitors", "all", "-j"],
                             capture_output=True, text=True, timeout=10)
        monitors = parse_monitors(out.stdout)
    except Exception:
        return []
    policy = _managed_vrr()
    for m in monitors:
        if m["name"] in policy:
            m["vrr"] = policy[m["name"]]
    return monitors


def read_edid():
    """Best-effort HDR / VRR-range detection from the kernel EDID copy."""
    import shutil
    decoder = shutil.which("edid-decode") or shutil.which("di-edid-decode")
    if not decoder:
        return {}
    script = (
        'for d in /sys/class/drm/card*-*/; do '
        '[ -f "$d/edid" ] || continue; '
        'out=$(' + decoder + ' "$d/edid" 2>/dev/null); [ -n "$out" ] || continue; '
        'base=${d%/}; base=${base##*/}; name=${base#*-}; hdr=0; '
        'grep -q "HDR Static Metadata" <<<"$out" && hdr=1; '
        'range=$(grep -o -m1 "[0-9]*-[0-9]* Hz V" <<<"$out" | sed "s/ Hz V//"); '
        'printf "%s\\t%s\\t%s\\n" "$name" "$hdr" "$range"; done'
    )
    try:
        out = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=10)
        return parse_edid(out.stdout)
    except Exception:
        return {}


def config_get(key, default=""):
    path = os.path.join(CONFIG_DIR, key)
    try:
        with open(path) as fh:
            return fh.read().strip()
    except OSError:
        return default


def config_set(key, value):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    with open(os.path.join(CONFIG_DIR, key), "w") as fh:
        fh.write(str(value))


def read_pending():
    try:
        with open(PENDING_PATH) as fh:
            return json.load(fh)
    except Exception:
        return {}


def write_pending(data):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    if data:
        with open(PENDING_PATH, "w") as fh:
            json.dump(data, fh)
    elif os.path.exists(PENDING_PATH):
        os.unlink(PENDING_PATH)


def get_selected():
    try:
        with open(SELECTED_PATH) as fh:
            return fh.read().strip()
    except OSError:
        return ""


def set_selected(name):
    os.makedirs(CONFIG_DIR, mode=0o700, exist_ok=True)
    with open(SELECTED_PATH, "w") as fh:
        fh.write(name)
