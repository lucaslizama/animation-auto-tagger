#!/usr/bin/env sh
# Copies the plugin into Aseprite's extensions folder for development.
#
# A symlink does not work: Aseprite does not follow one when it scans for
# extensions, so the plugin is silently never loaded. It has to be a real
# directory, which means re-running this after every edit.
#
# Then restart Aseprite. Uninstall by deleting the destination directory.
set -e
cd "$(dirname "$0")"

DEST="${ASEPRITE_CONFIG:-$HOME/.config/aseprite}/extensions/animation-auto-tagger"

rm -rf "$DEST"
mkdir -p "$DEST"
while IFS= read -r f; do
  [ -n "$f" ] && cp "$f" "$DEST/"
done < plugin-files.txt

echo "installed to $DEST"
echo "restart Aseprite to pick it up"
