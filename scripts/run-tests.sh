#!/usr/bin/env sh
# Runs the test suites with a stock Lua interpreter. Aseprite is not needed:
# naming.lua is dependency-free and the builder tests run against the fake API
# in tests/fake_aseprite.lua.
set -e
# Every path below is relative to the repo root, which is one level up now.
cd "$(dirname "$0")/.."

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
echo
echo "== reorder =="
"$LUA" tests/test_reorder.lua

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

# Aseprite exits 0 whatever the script decides, so the verdict has to be read
# out of the output instead. Without this a failing end-to-end suite scrolls
# past and the runner still reports success.
run_e2e() {
  label="$1"; shift
  echo
  echo "== $label =="
  out="$("$@" 2>&1)"
  echo "$out"
  # A FAIL marker means the suite ran and found something. No marker at all
  # means it died partway, which must not read as a pass either.
  if echo "$out" | grep -q "e2e-result: FAIL"; then
    e2e_failed=1
  elif ! echo "$out" | grep -q "e2e-result: ok"; then
    echo "  (the suite ended without reporting a result)" >&2
    e2e_failed=1
  fi
}

if [ -n "$ASEPRITE" ]; then
  e2e_failed=0
  run_e2e "end-to-end (real Aseprite)" \
    "$ASEPRITE" --batch --script tests/e2e_aseprite.lua

  # The drag path needs Aseprite to open the frames itself, so they have to
  # exist before it starts. They are written to a temp directory rather than
  # kept in the repository, and this asks where that was.
  SAMPLES="$("$ASEPRITE" --batch --script tests/make_samples.lua \
             | sed -n 's/^samples-dir: //p')"
  [ -n "$SAMPLES" ] || { echo "could not make the sample frames" >&2; exit 1; }
  # shellcheck disable=SC2086
  run_e2e "end-to-end, drag path (files opened by Aseprite itself)" \
    "$ASEPRITE" --batch "$SAMPLES"/*.png --script tests/e2e_dragpath.lua
  # A half-updated install has to announce itself rather than failing later
  # with a nil function inside a callback. Simulated by taking one function
  # away from the packaged ui.lua, which is what a stale file amounts to.
  echo
  echo "== half-updated install is reported =="
  ./scripts/build.sh >/dev/null
  MIXED="$(mktemp -d)"
  mkdir -p "$MIXED/extensions/animation-auto-tagger"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q dist/animation-auto-tagger.aseprite-extension \
      -d "$MIXED/extensions/animation-auto-tagger"
    # Demoted to an unused local, so the module still parses but no longer
    # exposes it. Appending after the file's own return would not even compile.
    sed -i 's/^function M\.groupLines(/local function groupLines_gone(/' \
      "$MIXED/extensions/animation-auto-tagger/ui.lua"
    said="$(ASEPRITE_USER_FOLDER="$MIXED" "$ASEPRITE" --batch \
            --script tests/noop.lua 2>&1 | grep -c 'part new and part old' || true)"
    if [ "$said" -ge 1 ]; then
      echo "  ok, it said so"
    else
      echo "  FAIL: a half-updated install was not reported" >&2
      e2e_failed=1
    fi
  else
    echo "  (skipped, unzip not available)"
  fi
  rm -rf "$MIXED"

  if [ "$e2e_failed" -ne 0 ]; then
    echo
    echo "end-to-end suite failed" >&2
    exit 1
  fi
else
  echo
  echo "(no Aseprite found - skipping the end-to-end check; set ASEPRITE=/path/to/aseprite)"
fi
