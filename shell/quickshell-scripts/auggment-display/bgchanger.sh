#!/bin/bash
# Kept for the display menu: wallpaper changes go through auggment-wallpaper-rotate,
# which also records the wallpaper and re-themes the desktop (auggment-theme-sync).
exec "$HOME/.local/bin/auggment-wallpaper-rotate" "$@"
