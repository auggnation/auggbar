#!/usr/bin/env python3
"""auggbar display backend for mangowm (port of the Hyprland auggment-display).

Works under mangowm and Hyprland. Reads outputs with `wlr-randr --json`, applies changes live with wlr-randr, and
on `keep` persists them in a managed block of ~/.config/mango/cfg/monitors.conf
(monitor_rule lines) or ~/.config/hypr/auggment-monitors.lua (hl.monitor calls). A change reverts after REVERT_SECONDS unless kept.

  display.py state
  display.py apply NAME '{"width":1920,"height":1200,"hz":120,"scale":1.5,"transform":0,"enabled":true,"x":0,"y":0}'
  display.py keep | revert | revert-unless-kept
  display.py brightness get|set [PERCENT] [--monitor NAME]
"""
import json, os, re, subprocess, sys, time

REVERT_SECONDS = 15
HYPR = bool(os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")) or (
    not os.environ.get("MANGO_SOCKET") and os.path.isdir(os.path.expanduser("~/.config/hypr")) and
    not os.path.isdir(os.path.expanduser("~/.config/mango")))
CONF = os.path.expanduser("~/.config/hypr/auggment-monitors.lua" if HYPR else "~/.config/mango/cfg/monitors.conf")
STATE = os.path.expanduser("~/.config/auggment/display-pending.json")
_C = "--" if HYPR else "#"
BEGIN = _C + " BEGIN auggbar-display (managed by the Display panel)"
END = _C + " END auggbar-display"
TRANSFORMS = ["normal", "90", "180", "270"]


def run(cmd, timeout=15):
    return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)


def read_outputs():
    try:
        raw = json.loads(run(["wlr-randr", "--json"]).stdout)
    except Exception:
        return []
    outs = []
    for o in raw:
        cur = next((m for m in o.get("modes", []) if m.get("current")), None)
        pos = o.get("position") or {}
        tr = str(o.get("transform", "normal"))
        outs.append({
            "name": o["name"],
            "model": o.get("model") or o.get("description") or o["name"],
            "internal": bool(re.match(r"^(eDP|LVDS|DSI)-", o["name"])),
            "enabled": bool(o.get("enabled", True)),
            "width": cur["width"] if cur else 0,
            "height": cur["height"] if cur else 0,
            "hz": round(cur["refresh"], 2) if cur else 0,
            "scale": round(float(o.get("scale", 1)), 3),
            "transform": TRANSFORMS.index(tr) if tr in TRANSFORMS else 0,
            "x": pos.get("x", 0), "y": pos.get("y", 0),
            "modes": [{"width": m["width"], "height": m["height"], "hz": round(m["refresh"], 2)}
                      for m in o.get("modes", [])],
        })
    return outs


def pending():
    try:
        return json.load(open(STATE))
    except Exception:
        return {}


def save_pending(d):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    if d:
        json.dump(d, open(STATE, "w"))
    elif os.path.exists(STATE):
        os.unlink(STATE)


def apply_settings(name, s):
    cmd = ["wlr-randr", "--output", name]
    if s.get("enabled") is False:
        cmd.append("--off")
    else:
        cmd.append("--on")
        if s.get("width") and s.get("height"):
            cmd += ["--mode", "%dx%d@%.3fHz" % (s["width"], s["height"], float(s.get("hz") or 60))]
        if s.get("scale"):
            cmd += ["--scale", str(s["scale"])]
        cmd += ["--transform", TRANSFORMS[int(s.get("transform", 0)) % 4]]
        if "x" in s and "y" in s:
            cmd += ["--pos", "%d,%d" % (s["x"], s["y"])]
    r = run(cmd)
    return r.returncode == 0, r.stderr.strip()


def cmd_state():
    print(json.dumps({"displays": read_outputs(), "pending": pending(),
                      "revert_seconds": REVERT_SECONDS}))


def cmd_apply(name, patch):
    outs = read_outputs()
    cur = next((o for o in outs if o["name"] == name), None)
    if not cur:
        print(json.dumps({"ok": False, "error": "unknown output"})); return
    if cur["enabled"] and patch.get("enabled") is False and sum(o["enabled"] for o in outs) <= 1:
        print(json.dumps({"ok": False, "error": "can't turn off the only display"})); return
    p = pending()
    before = p[name]["before"] if name in p else cur
    new = {k: cur[k] for k in ("enabled", "width", "height", "hz", "scale", "transform", "x", "y")}
    new.update(patch)
    ok, err = apply_settings(name, new)
    if not ok:
        print(json.dumps({"ok": False, "error": err})); return
    p[name] = {"before": before, "deadline": time.time() + REVERT_SECONDS}
    save_pending(p)
    subprocess.Popen(["bash", "-c", "sleep %d; python3 -I %s revert-unless-kept" %
                      (REVERT_SECONDS + 1, os.path.abspath(__file__))],
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    print(json.dumps({"ok": True}))


def write_conf(outs):
    lines = [BEGIN]
    for o in outs:
        if HYPR:
            if not o["enabled"]:
                lines.append('hl.monitor({ output = "%s", disabled = true })' % o["name"])
            else:
                lines.append('hl.monitor({ output = "%s", mode = "%dx%d@%s", position = "%dx%d", scale = %s, transform = %d })' % (
                    o["name"], o["width"], o["height"], ("%.3f" % o["hz"]).rstrip("0").rstrip("."),
                    o["x"], o["y"], o["scale"], o["transform"]))
            continue
        if not o["enabled"]:
            lines.append("monitor_rule = name:^%s$,disable:1" % o["name"])
            continue
        lines.append("monitor_rule = name:^%s$,width:%d,height:%d,refresh:%s,x:%d,y:%d,scale:%s,rr:%d" % (
            o["name"], o["width"], o["height"], ("%.3f" % o["hz"]).rstrip("0").rstrip("."),
            max(0, o["x"]), max(0, o["y"]), o["scale"], o["transform"]))
    lines.append(END)
    text = open(CONF).read() if os.path.exists(CONF) else ""
    text = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END) + r"\n?", "", text, flags=re.S)
    os.makedirs(os.path.dirname(CONF), exist_ok=True)
    open(CONF, "w").write(text.rstrip("\n") + "\n\n" + "\n".join(lines) + "\n")


def cmd_keep():
    write_conf(read_outputs())
    save_pending({})


def cmd_revert():
    p = pending()
    for name, e in p.items():
        apply_settings(name, e["before"])
    save_pending({})


def cmd_revert_unless_kept():
    p = pending()
    if p and time.time() >= max(e["deadline"] for e in p.values()):
        cmd_revert()


def cmd_brightness(args):
    """Read from sysfs; set through Noctalia so its OSD and state stay in sync."""
    import glob
    if args and args[0] == "set" and len(args) > 1:
        pct = max(1, min(100, int(args[1])))
        run(["noctalia", "msg", "brightness-set", "%d%%" % pct])
        return
    for d in glob.glob("/sys/class/backlight/*"):
        try:
            cur = int(open(d + "/brightness").read()); mx = int(open(d + "/max_brightness").read())
            print(round(cur * 100 / mx)); return
        except Exception:
            continue
    print("")


def main():
    a = sys.argv[1:]
    c = a[0] if a else "state"
    if c == "state": cmd_state()
    elif c == "apply": cmd_apply(a[1], json.loads(a[2]))
    elif c == "keep": cmd_keep()
    elif c == "revert": cmd_revert()
    elif c == "revert-unless-kept": cmd_revert_unless_kept()
    elif c == "brightness": cmd_brightness(a[1:])
    else: print(__doc__); sys.exit(2)


if __name__ == "__main__":
    main()
