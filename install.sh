#!/usr/bin/env bash
# auggbar installer — one Quickshell bar with toggleable plugins.
#
#   ./install.sh            copy the bar into place
#   ./install.sh --link     symlink instead (edit this folder, the bar follows)
#   options: --yes (no prompts)  --no-deps  --no-autostart  --no-system  --no-restart
#
# Installs:
#   shell/   -> ~/.config/quickshell        (the bar itself)
#   bin/*    -> ~/.local/bin/               (helper scripts the plugins call)
#   lib/     -> ~/.local/lib/auggment       (Python modules the helpers import)
#   config/settings.json -> ~/.config/auggbar/settings.json  (only if missing)
#   system/  -> /usr/local/bin + /etc/systemd/system  (root services, via sudo:
#              Wi-Fi watchdog, mic/camera privacy switches)
# and adds a Quickshell autostart to Hyprland if there is none.
# Anything replaced is moved to ~/.local/share/auggbar/backup/<timestamp>/.
set -euo pipefail

SRC="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
LINK=0 YES=0 DEPS=1 AUTOSTART=1 SYSTEM=1 RESTART=1
for a in "$@"; do
    case "$a" in
        --link) LINK=1 ;;
        --yes|-y) YES=1 ;;
        --no-deps) DEPS=0 ;;
        --no-autostart) AUTOSTART=0 ;;
        --no-system) SYSTEM=0 ;;
        --no-restart) RESTART=0 ;;
        -h|--help) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "unknown option: $a" >&2; exit 2 ;;
    esac
done

QS_DIR="$HOME/.config/quickshell"
BIN_DIR="$HOME/.local/bin"
CFG_DIR="$HOME/.config/auggbar"
DATA_DIR="$HOME/.local/share/auggbar"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$DATA_DIR/backup/$STAMP"
MANIFEST="$DATA_DIR/manifest"

say()  { printf '\033[1;34m::\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*"; }
ask()  { [ "$YES" = 1 ] && return 0; read -r -p "$1 [y/N] " r; [[ "$r" =~ ^[Yy] ]]; }

backup() {  # move $1 into the backup folder, keeping its path under $HOME
    local p="$1" rel="${1#"$HOME"/}"
    mkdir -p "$BACKUP/$(dirname "$rel")"
    mv "$p" "$BACKUP/$rel"
    echo "backup $p" >> "$MANIFEST.new"
}
# Paths a previous install placed: replaced in place, never backed up, so
# the backups only ever hold what was there before auggbar.
declare -A OURS=()
if [ -f "$MANIFEST" ]; then
    while read -r kind path; do [ "$kind" = file ] && OURS["$path"]=1; done < "$MANIFEST"
fi
place() {  # place source $1 at target $2 (copy or symlink), backing up what is there
    local src="$1" dst="$2"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
        echo "file $dst" >> "$MANIFEST.new"; return
    fi
    if [ -n "${OURS[$dst]:-}" ]; then
        rm -rf "$dst"
    elif [ -e "$dst" ] || [ -L "$dst" ]; then
        backup "$dst"
    fi
    mkdir -p "$(dirname "$dst")"
    if [ "$LINK" = 1 ]; then ln -s "$src" "$dst"; else cp -a "$src" "$dst"; fi
    echo "file $dst" >> "$MANIFEST.new"
}

# ---------------------------------------------------------------- deps
if [ "$DEPS" = 1 ] && command -v pacman >/dev/null; then
    say "Checking dependencies"
    # command:package
    need=( qs:quickshell cava:cava brightnessctl:brightnessctl wpctl:wireplumber
           nmcli:networkmanager playerctl:playerctl python3:python jq:jq curl:curl
           bluetoothctl:bluez-utils hyprctl:hyprland swaybg:swaybg magick:imagemagick
           gpioinfo:libgpiod v4l2-ctl:v4l-utils fuser:psmisc )
    missing=()
    for pair in "${need[@]}"; do
        command -v "${pair%%:*}" >/dev/null || missing+=("${pair##*:}")
    done
    # (grep without -q: an early exit would SIGPIPE fc-list and trip pipefail)
    python3 -c 'import dateutil' 2>/dev/null || missing+=(python-dateutil)
    fc-list : family 2>/dev/null | grep -i 'JetBrainsMono Nerd' >/dev/null || missing+=(ttf-jetbrains-mono-nerd)
    if [ "${#missing[@]}" -gt 0 ]; then
        warn "Missing packages: ${missing[*]}"
        if ask "Install them with pacman?"; then
            sudo pacman -S --needed "${missing[@]}" || warn "pacman failed; install them yourself: ${missing[*]}"
        else
            warn "Continuing without them; the matching plugins will not work."
        fi
    else
        say "All required packages present"
    fi
    for opt in arch-update:"Updater plugin" ghostty:"Updater plugin terminal" hyprlauncher:"Launcher plugin"; do
        command -v "${opt%%:*}" >/dev/null || [ -x "$BIN_DIR/${opt%%:*}" ] || warn "Optional: ${opt%%:*} not found (${opt#*:})"
    done
fi

# ---------------------------------------------------------------- install
mkdir -p "$DATA_DIR"
: > "$MANIFEST.new"
echo "mode $([ "$LINK" = 1 ] && echo link || echo copy)" >> "$MANIFEST.new"
echo "source $SRC" >> "$MANIFEST.new"
# Keep the record of earlier backups so uninstall can still restore them.
[ -f "$MANIFEST" ] && grep '^backup ' "$MANIFEST" >> "$MANIFEST.new" || true

say "Installing bar -> $QS_DIR"
place "$SRC/shell" "$QS_DIR"

say "Installing helpers -> $BIN_DIR"
for f in "$SRC"/bin/*; do
    place "$f" "$BIN_DIR/$(basename "$f")"
done

say "Installing helper libraries -> $HOME/.local/lib/auggment"
place "$SRC/lib" "$HOME/.local/lib/auggment"

if [ ! -f "$CFG_DIR/settings.json" ]; then
    say "Installing default plugin settings -> $CFG_DIR/settings.json"
    mkdir -p "$CFG_DIR"
    cp "$SRC/config/settings.json" "$CFG_DIR/settings.json"
else
    say "Keeping existing $CFG_DIR/settings.json"
fi

# ---------------------------------------------------------------- autostart
if [ "$AUTOSTART" = 1 ]; then
    LUA="$HOME/.config/hypr/hyprland.lua" CONF="$HOME/.config/hypr/hyprland.conf"
    if [ -f "$LUA" ]; then
        if grep -q 'qs -p' "$LUA"; then
            say "Hyprland already starts Quickshell (hyprland.lua)"
            grep -q '>>> auggbar autostart >>>' "$LUA" && echo "autostart $LUA" >> "$MANIFEST.new"
        else
            say "Adding Quickshell autostart to hyprland.lua"
            cat >> "$LUA" <<'EOF'

-- >>> auggbar autostart >>>
hl.on("hyprland.start", function()
    hl.exec_cmd("qs -p " .. (os.getenv("HOME") or "") .. "/.config/quickshell")
end)
-- <<< auggbar autostart <<<
EOF
            echo "autostart $LUA" >> "$MANIFEST.new"
        fi
    elif [ -f "$CONF" ]; then
        if grep -q 'qs -p' "$CONF"; then
            say "Hyprland already starts Quickshell (hyprland.conf)"
            grep -q '>>> auggbar autostart >>>' "$CONF" && echo "autostart $CONF" >> "$MANIFEST.new"
        else
            say "Adding Quickshell autostart to hyprland.conf"
            printf '\n# >>> auggbar autostart >>>\nexec-once = qs -p %s/.config/quickshell\n# <<< auggbar autostart <<<\n' "$HOME" >> "$CONF"
            echo "autostart $CONF" >> "$MANIFEST.new"
        fi
    else
        warn "No Hyprland config found; start the bar with: qs -p ~/.config/quickshell"
    fi
fi

# ---------------------------------------------------------------- system services
# Root services are always copied (never linked): a root unit must not run code
# out of a user's home folder.
if [ "$SYSTEM" = 1 ] && [ -d "$SRC/system" ]; then
    say "Installing system services (needs sudo)"
    for f in "$SRC"/system/bin/*; do
        sudo install -m 755 "$f" "/usr/local/bin/$(basename "$f")"
        echo "sysfile /usr/local/bin/$(basename "$f")" >> "$MANIFEST.new"
    done
    for f in "$SRC"/system/systemd/*.service; do
        sudo install -m 644 "$f" "/etc/systemd/system/$(basename "$f")"
        echo "sysfile /etc/systemd/system/$(basename "$f")" >> "$MANIFEST.new"
    done
    sudo systemctl daemon-reload
    for f in "$SRC"/system/systemd/*.service; do
        sudo systemctl enable --now "$(basename "$f")" >/dev/null 2>&1 &&
            echo "unit $(basename "$f")" >> "$MANIFEST.new"
    done
fi

mv "$MANIFEST.new" "$MANIFEST"
[ -d "$BACKUP" ] && say "Replaced files were backed up to $BACKUP"

# ---------------------------------------------------------------- restart
if [ "$RESTART" = 1 ] && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    say "Restarting the bar"
    pkill -x qs 2>/dev/null || true
    pkill -x quickshell 2>/dev/null || true
    sleep 1
    setsid -f qs -p "$QS_DIR" >/dev/null 2>&1 < /dev/null
fi

say "Done. Right-click (or Alt+click) empty bar space for the plugin menu,"
say "or any plugin for its own settings."
