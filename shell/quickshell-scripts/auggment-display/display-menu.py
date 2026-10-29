#!/usr/bin/env python3
"""Interactive display settings menu (rofi/wofi) for the Auggment Display port.

Launched by the Waybar module's left click (or `auggment-display menu`). All
edits go through auggment-display's change flow, so they apply live and revert
after 15s unless kept.
"""

import importlib.machinery
import importlib.util
import json
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import dmenu  # noqa: E402
import display_lib as lib  # noqa: E402

_ad_path = os.path.join(HERE, "auggment-display")
_loader = importlib.machinery.SourceFileLoader("auggment_display", _ad_path)
_spec = importlib.util.spec_from_loader("auggment_display", _loader)
ad = importlib.util.module_from_spec(_spec)
_loader.exec_module(ad)

SEP = "─────────────────────────────"


def choose(prompt, options):
    """options: list of (label, action). Returns action or None."""
    labels = [label for label, _ in options]
    picked = dmenu.choose(prompt, labels)
    if picked is None:
        return None
    for label, action in options:
        if label == picked:
            return action
    return None


def refresh():
    displays = lib.read_monitors()
    selected = ad._selected_display(displays)
    return displays, selected, lib.read_pending()


def apply(patch, message):
    ad.cmd_change(json.dumps(patch))
    if message:
        dmenu.notify(message, "Auggment Display")


# ---------------------------------------------------------------------------
# Sub-menus
# ---------------------------------------------------------------------------

def menu_select_display(displays, selected):
    options = []
    for d in displays:
        mark = "●" if d["name"] == selected["name"] else "○"
        options.append(("%s %s — %s" % (mark, d["model"], d["name"]), d["name"]))
    name = choose("Display", options)
    if name:
        ad.cmd_select(name)


def menu_resolution(displays, selected):
    options = []
    for r in lib.resolutions(selected["modes"]):
        current = ""
        if r["width"] == selected["width"] and r["height"] == selected["height"]:
            current = "  ●"
        options.append(("%s%s" % (r["label"], current), r))
    result = choose("Resolution — %s" % selected["model"], options)
    if not result:
        return
    rates = lib.refresh_rates(selected["modes"], result["width"], result["height"])
    hz = rates[0]["value"] if rates else "%.2f" % selected["hz"]
    apply({"width": result["width"], "height": result["height"], "hz": float(hz)},
          "%s → %s @ %s Hz (keep within %ds)" % (selected["name"], result["label"], hz, lib.REVERT_SECONDS))


def menu_refresh_rate(selected):
    rates = lib.refresh_rates(selected["modes"], selected["width"], selected["height"])
    options = []
    for r in rates:
        mark = "  ●" if abs(float(r["value"]) - selected["hz"]) < 0.01 else ""
        options.append(("%s%s" % (r["label"], mark), float(r["value"])))
    hz = choose("Refresh rate — %s" % selected["model"], options)
    if hz is not None:
        apply({"hz": hz}, "%s → %.2f Hz" % (selected["name"], hz))


def menu_scale(selected):
    presets = (lib.config_get("scale_presets", "") or "").split()
    presets = presets or lib.SCALE_PRESETS
    scales = lib.available_scales(presets, selected["width"], selected["height"])
    options = []
    for s in scales:
        mark = "  ●" if s == selected["scale"] else ""
        options.append((s + mark, s))
    options.append(("Custom…", "custom"))
    result = choose("Scale — %s" % selected["model"], options)
    if result is None:
        return
    if result == "custom":
        typed = dmenu.ask("Scale", selected["scale"])
        if not typed:
            return
        result = lib.clean_scale(typed, selected["width"], selected["height"]) or typed
    apply({"scale": result}, "%s → scale %s" % (selected["name"], result))


def menu_rotation(selected):
    options = []
    for i, label in enumerate(lib.TRANSFORMS):
        mark = "  ●" if i == selected["transform"] % 4 else ""
        options.append(("%s%s" % (label, mark), i))
    result = choose("Rotation — %s" % selected["model"], options)
    if result is not None:
        apply({"transform": result}, "%s → %s" % (selected["name"], lib.TRANSFORMS[result]))


def menu_mirror(displays, selected):
    options = [("None", "")]
    for d in displays:
        if d["name"] != selected["name"]:
            options.append(("%s (%s)" % (d["model"], d["name"]), d["name"]))
    result = choose("Mirror — %s" % selected["model"], options)
    if result is not None:
        apply({"mirror": result}, "%s mirror %s" % (selected["name"], result or "off"))


def menu_brightness(displays, selected):
    current = ad._brightness_get(selected["name"])
    options = []
    for p in range(10, 101, 10):
        mark = "  ●" if current is not None and abs(current - p) <= 2 else ""
        options.append(("%d%%%s" % (p, mark), p))
    options.append(("Custom…", "custom"))
    result = choose("Brightness — %s" % selected["model"], options)
    if result is None:
        return
    if result == "custom":
        typed = dmenu.ask("Brightness %", str(current) if current is not None else "70")
        if not typed or not typed.strip().isdigit():
            return
        result = int(typed)
    if ad._brightness_set(selected["name"], result):
        dmenu.notify("%s → %d%%" % (selected["name"], result), "Auggment Display")


def menu_arrange(displays, selected):
    others = [lib.logical_rect(lib.settings_from_display(d)) for d in displays
              if d["name"] != selected["name"] and d["enabled"]]
    others = [r for r in others if r]
    options = [
        ("Extend to the right", "right"),
        ("Extend to the left", "left"),
        ("Above", "above"),
        ("Below", "below"),
        ("Set position manually…", "manual"),
        ("Open nwg-displays (if installed)", "nwg"),
    ]
    result = choose("Arrange — %s" % selected["model"], options)
    if result is None:
        return
    if result == "nwg":
        exe = shutil.which("nwg-displays")
        if exe:
            subprocess.Popen([exe], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        else:
            dmenu.notify("nwg-displays is not installed (pacman -S nwg-displays)")
        return
    rect = lib.logical_rect(lib.settings_from_display(selected))
    b = lib.bounds(others) if others else {"x": 0, "y": 0, "w": rect["w"], "h": rect["h"]}
    if result == "right":
        pos = (b["x"] + b["w"], b["y"])
    elif result == "left":
        pos = (b["x"] - rect["w"], b["y"])
    elif result == "above":
        pos = (b["x"], b["y"] - rect["h"])
    elif result == "below":
        pos = (b["x"], b["y"] + b["h"])
    else:
        xs = dmenu.ask("Position X", str(rect["x"]))
        ys = dmenu.ask("Position Y", str(rect["y"]))
        if xs is None or ys is None:
            return
        try:
            pos = (int(xs), int(ys))
        except ValueError:
            return
    apply({"position": "%dx%d" % pos}, "%s → %dx%d" % (selected["name"], pos[0], pos[1]))


def menu_auggment(displays, selected):
    while True:
        interval = lib.config_get("bg_interval", "0")
        screensaver = lib.config_get("screensaver_timeout", "600")
        screenoff = lib.config_get("screen_off_timeout", "600")
        auto = lib.config_get("auto_color_match", "1")
        mode = lib.config_get("theme_mode", "dark")
        options = [
            ("Rotate background now", "now"),
            ("Background rotation: %s" % ("every %ss" % interval if interval not in ("", "0") else "off"), "interval"),
            ("Screensaver timeout: %ss" % screensaver, "screensaver"),
            ("Screen off timeout: %ss" % screenoff, "screenoff"),
            ("Auto color match: %s" % ("on" if auto == "1" else "off"), "auto"),
            ("Dark mode: %s" % ("on" if mode != "light" else "off"), "dark"),
            (SEP, None),
            ("Back", "back"),
        ]
        result = choose("Auggment", options)
        if result in (None, "back"):
            return
        if result == "now":
            subprocess.Popen([os.path.join(HERE, "bgchanger.sh"), "--once"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            continue
        if result == "interval":
            pick = dmenu.choose("Rotate background every", ["60", "300", "600", "1800", "3600", "Off", "Custom…"])
            if pick is None:
                continue
            if pick == "Off":
                lib.config_set("bg_interval", "0")
            elif pick == "Custom…":
                typed = dmenu.ask("Seconds", interval)
                if typed and typed.strip().isdigit():
                    lib.config_set("bg_interval", typed.strip())
            else:
                lib.config_set("bg_interval", pick)
            continue
        if result == "screensaver":
            typed = dmenu.ask("Screensaver seconds", screensaver)
            if typed and typed.strip().isdigit():
                subprocess.run([os.path.join(HERE, "set-screensaver.sh"), typed.strip()])
            continue
        if result == "screenoff":
            typed = dmenu.ask("Screen off seconds", screenoff)
            if typed and typed.strip().isdigit():
                lib.config_set("screen_off_timeout", typed.strip())
                subprocess.run([os.path.join(HERE, "auggment-idle-sync.sh")])
            continue
        if result == "auto":
            lib.config_set("auto_color_match", "0" if auto == "1" else "1")
            continue
        if result == "dark":
            # Flip the stored mode and let auggment-theme-sync rebuild the whole
            # system theme (bar, KDE/Qt, GTK, terminals, borders) around it.
            lib.config_set("theme_mode", "light" if mode != "light" else "dark")
            subprocess.Popen(["auggment-theme-sync"],
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            continue


# ---------------------------------------------------------------------------
# Root menu
# ---------------------------------------------------------------------------

def root_menu(displays, selected, pending):
    options = [
        ("Display: %s  ▸" % selected["model"], "display"),
        (SEP, None),
        ("Resolution: %d×%d  ▸" % (selected["width"], selected["height"]), "resolution"),
        ("Refresh rate: %.2f Hz  ▸" % selected["hz"], "refresh"),
        ("Scale: %s  ▸" % selected["scale"], "scale"),
        ("Rotation: %s  ▸" % lib.transform_label(selected["transform"]), "rotation"),
        ("Mirror: %s  ▸" % (selected["mirrorOf"] or "off"), "mirror"),
        ("VRR: %s" % ("on" if selected["vrr"] else "off"), "vrr"),
        ("HDR: %s" % ("on" if selected["hdr"] else "off"), "hdr"),
        ("Enabled: %s" % ("yes" if selected["enabled"] else "no"), "enabled"),
        ("Brightness  ▸", "brightness"),
        ("Arrange  ▸", "arrange"),
        (SEP, None),
        ("Keep changes", "keep"),
        ("Revert changes", "revert"),
        ("Forget saved layout", "forget"),
        (SEP, None),
        ("Auggment  ▸", "auggment"),
        ("Quit", "quit"),
    ]
    if not pending:
        options = [o for o in options if o[0] not in ("Keep changes", "Revert changes")]

    result = choose("Displays", options)
    if result is None or result == "quit":
        return False
    if result == "display":
        menu_select_display(displays, selected)
    elif result == "resolution":
        menu_resolution(displays, selected)
    elif result == "refresh":
        menu_refresh_rate(selected)
    elif result == "scale":
        menu_scale(selected)
    elif result == "rotation":
        menu_rotation(selected)
    elif result == "mirror":
        menu_mirror(displays, selected)
    elif result == "vrr":
        apply({"vrr": 0 if selected["vrr"] else 1}, "%s VRR %s" % (selected["name"], "off" if selected["vrr"] else "on"))
    elif result == "hdr":
        apply({"hdr": not selected["hdr"]}, "%s HDR %s" % (selected["name"], "off" if selected["hdr"] else "on"))
    elif result == "enabled":
        ad.cmd_toggle_enabled(selected["name"])
    elif result == "brightness":
        menu_brightness(displays, selected)
    elif result == "arrange":
        menu_arrange(displays, selected)
    elif result == "keep":
        ad.cmd_keep()
        dmenu.notify("Changes kept", "Auggment Display")
    elif result == "revert":
        ad.cmd_revert()
        dmenu.notify("Changes reverted", "Auggment Display")
    elif result == "forget":
        ad.cmd_forget()
        dmenu.notify("Saved layout forgotten", "Auggment Display")
    elif result == "auggment":
        menu_auggment(displays, selected)
    return True


def main():
    if not dmenu.available():
        dmenu.notify("Install rofi or wofi to use the display menu", "Auggment Display", "critical")
        sys.exit(1)
    while True:
        displays, selected, pending = refresh()
        if not selected:
            dmenu.notify("No displays detected", "Auggment Display", "critical")
            sys.exit(1)
        if not root_menu(displays, selected, pending):
            break


if __name__ == "__main__":
    main()
