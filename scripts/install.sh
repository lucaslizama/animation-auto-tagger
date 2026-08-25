#!/usr/bin/env sh
# Copies the plugin into Aseprite's extensions folder for development.
#
# A symlink does not work: Aseprite does not follow one when it scans for
# extensions, so the plugin is silently never loaded. It has to be a real
# directory, which means re-running this after every edit.
#
# Then restart Aseprite. Uninstall by deleting the destination directory.
set -e
# Every path below is relative to the repo root, which is one level up now.
cd "$(dirname "$0")/.."

DEST="${ASEPRITE_CONFIG:-$HOME/.config/aseprite}/extensions/animation-auto-tagger"

# Aseprite keeps the plugin's saved settings in __pref.lua inside the extension
# folder, so wiping the folder to reinstall would reset every option between
# runs. Held aside and put back.
PREFS="$DEST/__pref.lua"
KEEP=""
if [ -f "$PREFS" ]; then
  KEEP="$(mktemp)"
  cp "$PREFS" "$KEEP"
fi

rm -rf "$DEST"
mkdir -p "$DEST"
# Flattened on the way in, the same as build.sh does: Aseprite resolves an
# extension's requires from the extension root, so src/naming.lua has to land
# as naming.lua next to the rest.
while IFS= read -r f; do
  [ -n "$f" ] && cp "$f" "$DEST/"
done < plugin-files.txt

if [ -n "$KEEP" ]; then
  cp "$KEEP" "$PREFS"
  rm -f "$KEEP"
fi

echo "installed to $DEST"
echo "restart Aseprite to pick it up"
