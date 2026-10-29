# Boot splash source

These are the files the Plymouth boot splash is built from. They are the
**only** copy - the installers read them from here.

| file | what it is |
|---|---|
| `auggment.plymouth` | the Plymouth theme definition (`Name=AUGGMENT`) |
| `auggment.script` | the script that draws the wordmark |
| `login-banner.png` | the wordmark image for the login screen |
| `auggment-login-banner` | the legacy helper that stamped the wordmark onto a photo wallpaper (kept for reference - the greeter now paints the wordmark directly) |
| `bin/auggment-theme-sync` (`write_login`) | paints the wordmark, recoloured to the wallpaper accent, for the greetd/ReGreet login screen (`/var/lib/auggment-login`) |

The wordmark image is `logo.png` - it is already red (#FF3B30) on a
transparent background, so the boot splash has no background image at all.
It lives in `../ascii-art/logo.png` so all the artwork sits in one place.

## Who installs them

* `../installers/08-boot-splash.sh` - the boot splash
* `../installers/09-login-screen.sh` - the login screen

```bash
../restore-auggment.sh 08-boot-splash
../restore-auggment.sh 09-login-screen
```

They ask for the sudo password once. `08` adds a new theme directory and
edits `/etc/plymouth/plymouthd.conf` (one key at a time, original kept as
`plymouthd.conf.auggment-bak`). `../rollback-auggment.sh` puts the original
back.

## Note on the theme name

The theme directory on this machine is spelled with a double "g" -
`/usr/share/plymouth/themes/auggment/`. The installers read the real name off
the filesystem, so it is never typed by hand.
