#!/bin/bash
# Regenerate ~/.config/hypr/hypridle.conf from the Auggment settings.
#
# Owns only a managed hypridle.conf. If you already have your own file it is
# backed up to hypridle.conf.auggment.bak the first time and never touched again
# while it carries the managed marker. CachyOS' hyprlock is the lock command.
set -eu

CONFIG="$HOME/.config/auggment"
CONF="$HOME/.config/hypr/hypridle.conf"
MARKER="# Managed by Auggment Display. Do not edit; the Display menu regenerates this file."

SCREEN=$(cat "$CONFIG/screen_off_timeout" 2>/dev/null || echo 600)
SAVER=$(cat "$CONFIG/screensaver_timeout" 2>/dev/null || echo 0)
[[ -z $SCREEN || $SCREEN -le 0 ]] 2>/dev/null && SCREEN=600

# pidof guard: a second hyprlock instance can't lock an already-locked session.
LOCK_CMD="pidof hyprlock || hyprlock"
command -v hyprlock >/dev/null 2>&1 || LOCK_CMD="loginctl lock-session"
# Lock through logind instead of running hyprlock directly: hypridle waits for
# its commands to finish, and hyprlock only finishes when the screen is
# unlocked - running it here would block suspend until logind's inhibitor
# timeout expires (the "Delay lock is active ... inhibitor timeout" messages).
BEFORE_SLEEP="loginctl lock-session"

mkdir -p "$HOME/.config/hypr"

if [[ -f $CONF ]] && ! grep -qF "Managed by Auggment Display" "$CONF"; then
  cp -p "$CONF" "$CONF.auggment.bak"
fi

old_umask=$(umask)
umask 077
tmp=$(mktemp "$(dirname "$CONF")/.hypridle.conf.XXXXXX")
umask "$old_umask"

{
  echo "$MARKER"
  echo "general {"
  echo "    lock_cmd = $LOCK_CMD"
  echo "    before_sleep_cmd = $BEFORE_SLEEP"
  echo "    after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'"
  echo "    ignore_dbus_inhibit = false"
  echo "}"
  echo
  if [[ $SAVER =~ ^[0-9]+$ ]] && (( SAVER > 0 )); then
    echo "listener {"
    echo "    timeout = $SAVER"
    echo "    on-timeout = $LOCK_CMD"
    echo "}"
    echo
  fi
  echo "listener {"
  echo "    timeout = $SCREEN"
  echo "    on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = \"off\" })'"
  echo "    on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = \"on\" })'"
  echo "}"
} > "$tmp"

chmod 644 "$tmp" 2>/dev/null || true
mv -f "$tmp" "$CONF"

systemctl --user stop hypridle.service 2>/dev/null || true
pkill -x hypridle 2>/dev/null || true
sleep 0.2
systemctl --user start hypridle.service 2>/dev/null || { setsid hypridle >/dev/null 2>&1 & }
