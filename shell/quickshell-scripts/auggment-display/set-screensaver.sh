#!/bin/bash
# Set the Auggment screensaver (lock) timeout and regenerate hypridle.conf.
#   set-screensaver.sh <seconds>   (0 disables the lock listener)
set -euo pipefail

val=${1:-}
[[ $val =~ ^[0-9]+$ ]] || { echo "usage: set-screensaver.sh <seconds>" >&2; exit 2; }

CONFIG="$HOME/.config/auggment"
mkdir -p "$CONFIG"

old_umask=$(umask)
umask 077
printf '%s\n' "$val" > "$CONFIG/screensaver_timeout"
umask "$old_umask"

"$(dirname "$(readlink -f "$0")")/auggment-idle-sync.sh"
