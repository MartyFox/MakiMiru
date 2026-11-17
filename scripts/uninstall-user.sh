#!/bin/sh
# Remove every file installed by install-user.sh; system Sushi resumes
# previewer ownership.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
MANIFEST="$REPO/build-install/manifest.txt"

[ -f "$MANIFEST" ] || { echo "No manifest at $MANIFEST — nothing to uninstall." >&2; exit 1; }

while IFS= read -r rel; do
    rm -f "$HOME/.local/$rel"
done < "$MANIFEST"

# Prune now-empty directories we may have created (ignore shared ones in use).
( cd "$HOME/.local" && find share/sushi lib/x86_64-linux-gnu/sushi \
    -type d -empty -delete 2>/dev/null ) || true

# SPEC-009: refresh the mime cache after removing our override, same
# reason install-user.sh refreshes it after adding one.
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "$HOME/.local/share/mime" >/dev/null
fi

dbus-send --session --type=method_call \
    --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig || true
pkill -f '[l]ibexec/org.gnome.NautilusPreviewer' 2>/dev/null || true

echo "Uninstalled; system Sushi active again."
