#!/usr/bin/env sh
# Runs the test suites with a stock Lua interpreter. Aseprite is not needed:
# naming.lua is dependency-free and the builder tests run against the fake API
# in tests/fake_aseprite.lua.
set -e
cd "$(dirname "$0")"

LUA="${LUA:-}"
if [ -z "$LUA" ]; then
  for candidate in lua lua5.4 lua5.3 luajit; do
    if command -v "$candidate" >/dev/null 2>&1; then LUA="$candidate"; break; fi
  done
fi
if [ -z "$LUA" ]; then
  echo "No Lua interpreter found. Install lua or set LUA=/path/to/lua." >&2
  exit 1
fi

echo "== naming =="
"$LUA" tests/run_tests.lua
echo
echo "== builder =="
"$LUA" tests/test_builder.lua
echo
echo "== watcher =="
"$LUA" tests/test_watcher.lua

# The suites above use a stand-in API. If a real Aseprite is around, also run
# the end-to-end check through it - that is what catches things the double
# cannot know about, like Aseprite loading numbered files as one sequence.
ASEPRITE="${ASEPRITE:-}"
if [ -z "$ASEPRITE" ]; then
  for candidate in \
    "$(command -v aseprite 2>/dev/null)" \
    "$HOME/.local/share/Steam/steamapps/common/Aseprite/aseprite" \
    "$HOME/.steam/steam/steamapps/common/Aseprite/aseprite"
  do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then ASEPRITE="$candidate"; break; fi
  done
fi

if [ -n "$ASEPRITE" ]; then
  echo
  echo "== end-to-end (real Aseprite) =="
  "$ASEPRITE" --batch --script e2e_aseprite.lua
  echo
  echo "== end-to-end, drag path (files opened by Aseprite itself) =="
  "$ASEPRITE" --batch samples/hero/*.png --script e2e_dragpath.lua
else
  echo
  echo "(no Aseprite found - skipping the end-to-end check; set ASEPRITE=/path/to/aseprite)"
fi
