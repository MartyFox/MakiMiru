#!/bin/sh
# Sync the container-staged install tree into ~/.local and make this fork
# the active Nautilus previewer. Fully reversible via uninstall-user.sh.
set -eu

REPO="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$REPO/build-install$HOME/.local"
MANIFEST="$REPO/build-install/manifest.txt"

[ -d "$STAGE" ] || { echo "No staged tree. Run scripts/container-build.sh first." >&2; exit 1; }

# Record every installed file (relative to ~/.local) for uninstall.
( cd "$STAGE" && find . -type f | sed 's|^\./||' ) > "$MANIFEST"

rsync -a "$STAGE/" "$HOME/.local/"

# SPEC-009: refresh the per-user shared-mime-info cache so the .obj
# override (data/org.gnome.NautilusPreviewer-model.xml) actually takes
# effect — installing the XML alone doesn't update the binary cache
# gio/Nautilus actually query.
if command -v update-mime-database >/dev/null 2>&1; then
    update-mime-database "$HOME/.local/share/mime" >/dev/null
fi

# Ask the session bus to re-read service files; new owner activates once the
# current one exits (bracketed pattern: plain pkill -f self-matches callers).
dbus-send --session --type=method_call \
    --dest=org.freedesktop.DBus / org.freedesktop.DBus.ReloadConfig || true
pkill -f '[l]ibexec/org.gnome.NautilusPreviewer' 2>/dev/null || true

echo "Installed $(wc -l < "$MANIFEST") files into ~/.local"
echo "Service: $HOME/.local/share/dbus-1/services/org.gnome.NautilusPreviewer.service"
