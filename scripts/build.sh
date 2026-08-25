#!/usr/bin/env sh
# Packs the plugin into dist/animation-auto-tagger.aseprite-extension,
# which Aseprite installs from Edit > Preferences > Extensions > Add Extension.
# An .aseprite-extension is just a zip, so either zip(1) or python3 will do.
set -e
# Every path below is relative to the repo root, which is one level up now.
cd "$(dirname "$0")/.."

NAME="animation-auto-tagger"
OUT="dist/$NAME.aseprite-extension"

FILES="$(tr '\n' ' ' < plugin-files.txt)"

mkdir -p dist
rm -f "$OUT"

# -j / basename: the sources live under src/ in the repo, but Aseprite resolves
# an extension's requires from the extension root, so the package has to be
# flat. This is the only place the two layouts differ.
if command -v zip >/dev/null 2>&1; then
  # shellcheck disable=SC2086
  zip -q -X -j "$OUT" $FILES
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$OUT" $FILES <<'PY'
import os, sys, zipfile
out, files = sys.argv[1], sys.argv[2:]
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.write(f, arcname=os.path.basename(f))
PY
else
  echo "need zip or python3 to package the extension" >&2
  exit 1
fi

echo "built $OUT"
