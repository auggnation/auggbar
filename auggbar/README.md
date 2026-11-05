# auggbar for Noctalia

The parts of [auggbar](https://github.com/auggnation/auggbar) that Noctalia does
not already ship, as Noctalia bar widgets:

| Widget | Type | What it does |
|---|---|---|
| Scoreboard | `auggnation/auggbar:scoreboard` | Rotates through your teams' games (logos, live scores). Click for the board, scroll to step through games. The board's **Teams** tab adds/removes favourites. |
| RunViking | `auggnation/auggbar:viking` | A viking that runs faster as CPU load rises. Click to open `btop`. Inspired by [RunCat](https://github.com/win0err/gnome-runcat) by win0err. |
| Updater | `auggnation/auggbar:updater` | Pending pacman updates (`checkupdates`). Hidden when current; click to update in a terminal, right-click to re-check. |

Scores come from ESPN through the python backend in `scoreboard/` and are read
from `~/.config/auggment/scoreboard.json`, the same file the Quickshell auggbar
uses. IPC: `noctalia msg plugin auggnation/auggbar:scores all refresh|next|prev`.

## Install

```sh
noctalia msg plugins source add auggbar git https://github.com/auggnation/auggbar
noctalia msg plugins enable auggnation/auggbar
```

Then add the widgets to a bar in Settings, or in `config.toml`:

```toml
[widget.scoreboard]
type = "auggnation/auggbar:scoreboard"
[widget.viking]
type = "auggnation/auggbar:viking"
[widget.updater]
type = "auggnation/auggbar:updater"
```

`noctalia/config.toml` in this folder is the full niri + Noctalia layout that
mirrors the old auggbar (built-in widgets for everything else, wallpaper
rotation every 5 minutes from `~/Documents/backgrounds`).
