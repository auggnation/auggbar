# auggbar

A single Quickshell top bar for Hyprland, made of plugins that can each be
turned on/off, moved, and configured from the bar itself.

## Install

```sh
./install.sh            # copy into ~/.config/quickshell
./install.sh --link     # symlink instead: edit this folder and the bar follows
./uninstall.sh          # remove it and restore what it replaced (--purge also drops settings)
```

Other flags: `--yes` (no prompts), `--no-deps`, `--no-autostart`, `--no-restart`.

The installer checks for the required packages (and offers to `pacman -S` the
missing ones), places the bar and its helper scripts, writes default plugin
settings if you have none, and adds a Quickshell autostart to Hyprland if there
isn't one. Whatever it replaces goes to `~/.local/share/auggbar/backup/`.

## Using it

- **Right-click or Alt+click empty bar space**: the plugin menu. Every plugin
  has an on/off switch, ‹ › to move it, a section picker, and a gear for its
  settings.
- **Right-click or Alt+click a plugin**: that plugin's settings. Weather,
  scoreboard, launcher, Bluetooth and Viking open their own panels; the others
  open a popup with show/hide, position and their options.
- Audio: middle-click mutes (right-click is settings now).

Settings live in `~/.config/auggbar/settings.json`; the menus write it, and the
bar reloads it live if you edit it by hand.

From a terminal or keybind:

```sh
qs -p ~/.config/quickshell ipc call bar settings            # plugin menu
qs -p ~/.config/quickshell ipc call bar pluginSettings cava  # one plugin
qs -p ~/.config/quickshell ipc call bar togglePlugin title
qs -p ~/.config/quickshell ipc call bar movePlugin weather -1
```

## Plugins

| id | what | options |
|---|---|---|
| launcher | app launcher button (owns Super+Space) | own panel |
| weather | temperature + condition | own panel |
| workspaces | Hyprland workspaces | |
| title | focused window title | max width |
| cava | audio visualizer; shows while music plays, click to open it as a tiled app window | bars, hide when idle, window on/off |
| power | power menu | |
| clock | date/time, click for calendar | 24h, show date, calendar accounts |
| nowplaying | MPRIS controls + ticker | ticker width |
| scoreboard | live scores for your teams | own panel |
| display | monitors + brightness | show % |
| separator | divider | |
| system | the grouped card; holds everything in the `system` section | |
| netspeed, network, audio, mic, bluetooth, battery | system controls | audio: scroll step; battery: show %; bluetooth: own panel |
| viking | running-viking CPU monitor | own panel |
| updater | CachyOS updates (arch-update) | |
| tray | system tray | |

## Layout

```
shell/                 -> ~/.config/quickshell
  shell.qml            shared state, popups, bar frame, plugin loader
  Theme.qml            palette singleton (follows the Auggment theme)
  widgets/<Plugin>.qml one file per plugin
  widgets/PluginSlot.qml  loads a plugin + routes right/Alt-click to settings
  components/          launcher + viking components
  quickshell-scripts/  scoreboard + display backends
bin/                   -> ~/.local/bin (auggment-* helpers)
config/settings.json   default plugin layout
```

### Writing a plugin

1. Create `shell/widgets/Foo.qml`. Its root needs `required property var shell`
   and `property bool shown` (false hides it), plus `implicitWidth/Height`.
   Colours come from `Theme` (`import ".."`).
2. Optional: `readonly property var settingsSchema: [{ key, label, type:
   "bool"|"number"|"action", default, min, max, step, suffix }]`, read values
   with `shell.barOpt("foo", key, default)`, handle actions in
   `function settingsAction(key)`. Or provide `function openSettings()` to
   open a panel of your own.
3. Register it in `barWidgetFiles` / `barLabels` / `barDefaults` in `shell.qml`.
