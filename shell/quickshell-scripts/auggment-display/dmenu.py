"""Thin wrapper over rofi/wofi/hyprlauncher for the Auggment Waybar modules.

Every interactive menu (scoreboard board, scoreboard settings, display
settings) goes through here so the whole port works with whichever menu backend
is installed. rofi is preferred when present because it supports -multi-select
and predictable -no-custom behaviour. hyprlauncher is the fallback and the one
this machine actually has (neither rofi nor wofi is installed); it has no
prompt/-i support, so the prompt is simply not shown.
"""

import shutil
import subprocess


def backend():
    """Return (name, path) for the first available menu backend."""
    for name in ("rofi", "wofi", "hyprlauncher"):
        path = shutil.which(name)
        if path:
            return name, path
    return None, None


def available():
    return backend()[0] is not None


def choose(prompt, items, allow_custom=False):
    """Show a single-select dmenu. Returns the chosen string or None on cancel.

    allow_custom permits typing a value that is not in the list (used for the
    number / hex / driver-name prompts).
    """
    name, path = backend()
    if name is None:
        return None
    data = "\n".join(items)
    if name == "rofi":
        cmd = [path, "-dmenu", "-i", "-p", prompt, "-mesg", ""]
        if not allow_custom:
            cmd.append("-no-custom")
    elif name == "hyprlauncher":
        # No prompt or -i support: it just picks one line off stdin.
        cmd = [path, "--dmenu", "--quiet"]
    else:
        cmd = [path, "--dmenu", "-i", "-p", prompt]
    try:
        proc = subprocess.run(cmd, input=data, text=True, capture_output=True)
    except Exception:
        return None
    if proc.returncode != 0:
        return None
    out = proc.stdout.rstrip("\n")
    return out if out != "" else None


def ask(prompt, initial="", allow_custom=True):
    """Single-line text prompt pre-filled with `initial`."""
    return choose(prompt, [initial] if initial else [], allow_custom=allow_custom)


def notify(message, title="Auggment Scoreboard", urgency="normal"):
    notifier = shutil.which("notify-send")
    if notifier:
        try:
            subprocess.Popen([notifier, "-u", urgency, title, message])
        except Exception:
            pass
