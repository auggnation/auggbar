# ASCII wordmark

The AUGGMENT wordmark, in the shapes it is used.

| file | what it is |
|---|---|
| `banner.txt` | the plain wordmark - printed by the terminal greeting |
| `auggment-login-banner.txt` | the wordmark plus the host line, used by the login banner |
| `logo.png` | the wordmark rendered as an image |

```
    ___   __  ________________  __________   ________
   /   | / / / / ____/ ____/  |/  / ____/ | / /_  __/
  / /| |/ / / / / __/ / __/ /|_/ / __/ /  |/ / / /   
 / ___ / /_/ / /_/ / /_/ / /  / / /___/ /|  / / /    
/_/  |_\____/\____/\____/_/  /_/_____/_/ |_/ /_/     
```

`logo.png` is also the image the Plymouth boot splash draws - see
`../plymouth/SOURCE.md`. `../installers/08-boot-splash.sh` copies it into
the theme directory.

The greeting that prints `banner.txt` lives in `~/.local/bin/auggment-greeting`
and is wired up by `../installers/07-hyprland.sh` (it writes
`~/.config/fish/config.fish`).
