#!/usr/bin/env sh
# Packs the plugin into dist/animation-auto-tagger.aseprite-extension,
# which Aseprite installs from Edit > Preferences > Extensions > Add Extension.
# An .aseprite-extension is just a zip, so either zip(1) or python3 will do.
set -e
cd "$(dirname "$0")"

NAME="animation-auto-tagger"
OUT="dist/$NAME.aseprite-extension"

FILES="$(tr '\n' ' ' < plugin-files.txt)"

mkdir -p dist
rm -f "$OUT"

if command -v zip >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  zip -q -X "$OUT" $FILES
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$OUT" $FILES <<'PY'
import sys, zipfile
out, files = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f)
PY
else
  echo "need zip or python3 to package the extension" >&2
  exit 1
fi

echo "built $OUT"
