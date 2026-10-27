# Auggbar

A unified, configurable Quickshell bar for Hyprland with all plugins integrated.

## Features

- All widgets and plugins in one bar
- Toggle widgets on/off individually
- Per-widget and bar settings
- Toggle menu on right-click or Alt+Left-click
- Configurable via `~/.config/auggbar/settings.json`
- Installable on any Linux machine with Quickshell, Hyprland

## Installation

1. Copy `auggbar/` to `~/.config/quickshell/auggbar/`
2. Copy or symlink configs to `~/.config/auggbar/`
3. Update Hyprland to use: `exec-once = qs -p ~/.config/quickshell/auggbar &`
4. Launch with `qs -p ~/.config/quickshell/auggbar`

## Configuration

Edit `~/.config/auggbar/settings.json` or use the toggle menu (right-click/Alt+click).

## Widgets

- launcher, workspaces, weather, calendar, nowplaying
- netspeed, audio, mic, bluetooth
- scoreboard, display, updater, clock
