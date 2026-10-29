#!/usr/bin/env bash
# auggbar uninstaller. Removes what install.sh placed (from its manifest),
# restores the files it backed up, and removes the autostart block it added.
#   ./uninstall.sh            keep ~/.config/auggbar (your plugin settings)
#   ./uninstall.sh --purge    remove it too
set -euo pipefail

DATA_DIR="$HOME/.local/share/auggbar"
MANIFEST="$DATA_DIR/manifest"
PURGE=0
[ "${1:-}" = "--purge" ] && PURGE=1

[ -f "$MANIFEST" ] || { echo "auggbar does not look installed (no $MANIFEST)" >&2; exit 1; }

pkill -x qs 2>/dev/null || true

# Root services first (they were installed with sudo).
while read -r kind path; do
    [ "$kind" = unit ] && sudo systemctl disable --now "$path" >/dev/null 2>&1 && echo "disabled $path"
done < "$MANIFEST"
while read -r kind path; do
    [ "$kind" = sysfile ] && sudo rm -f "$path" && echo "removed $path"
done < "$MANIFEST"
grep -q '^sysfile ' "$MANIFEST" && sudo systemctl daemon-reload

while read -r kind path; do
    case "$kind" in
        file) [ -L "$path" ] || [ -e "$path" ] && rm -rf "$path" && echo "removed $path" ;;
        autostart)
            sed -i '/>>> auggbar autostart >>>/,/<<< auggbar autostart <<</d' "$path"
            echo "removed autostart from $path" ;;
    esac
done < "$MANIFEST"

# Restore the oldest backup of each replaced path (what was there before auggbar).
while read -r kind path; do
    [ "$kind" = backup ] || continue
    rel="${path#"$HOME"/}"
    src="$(ls -d "$DATA_DIR"/backup/*/"$rel" 2>/dev/null | sort | head -1 || true)"
    if [ -n "$src" ] && [ ! -e "$path" ]; then
        mkdir -p "$(dirname "$path")"
        mv "$src" "$path" && echo "restored $path"
    fi
done < "$MANIFEST"

rm -f "$MANIFEST"
[ "$PURGE" = 1 ] && rm -rf "$HOME/.config/auggbar" && echo "removed ~/.config/auggbar"
echo "auggbar uninstalled. Backups (if any) remain in $DATA_DIR/backup."
