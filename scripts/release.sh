#!/usr/bin/env sh
# Tags a release from the version in package.json, refusing to do so unless the
# tree is actually in a fit state to be tagged.
#
#   scripts/release.sh                    tag and push
#   scripts/release.sh --no-push          tag only, push it yourself
#   scripts/release.sh --dry-run          run every check, change nothing
#   scripts/release.sh --notes FILE       take the tag message from FILE
#
# The point is the checks rather than the convenience: a tag that disagrees with
# the version inside the package is worse than no tag, because it is the one
# thing nobody thinks to doubt later.
set -e
cd "$(dirname "$0")/.."

PUSH=1
DRY=0
NOTES=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-push) PUSH=0 ;;
    --dry-run) DRY=1; PUSH=0 ;;
    --notes) shift; NOTES="$1"; [ -n "$NOTES" ] || { echo "--notes needs a file" >&2; exit 1; } ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
  shift
done

fail() { echo "release: $1" >&2; exit 1; }

# ------------------------------------------------------------------ version

VERSION="$(sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' package.json | head -1)"
[ -n "$VERSION" ] || fail "could not read the version out of package.json"

case "$VERSION" in
  [0-9]*.[0-9]*.[0-9]*) ;;
  *) fail "version \"$VERSION\" is not major.minor.patch" ;;
esac

TAG="v$VERSION"
echo "release: package.json says $VERSION, so the tag is $TAG"

# -------------------------------------------------------------- the tree

[ -z "$(git status --porcelain)" ] || fail "there are uncommitted changes; commit them first"

if git rev-parse -q --verify "refs/tags/$TAG" >/dev/null 2>&1; then
  fail "$TAG already exists. Bump the version in package.json first"
fi

[ -z "$NOTES" ] || [ -f "$NOTES" ] || fail "no such notes file: $NOTES"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[ "$BRANCH" = "main" ] || echo "release: warning, tagging $BRANCH rather than main"

# Every file the package claims to ship has to be there, or the extension goes
# out missing a module and only fails once someone installs it.
while IFS= read -r f; do
  [ -z "$f" ] && continue
  [ -f "$f" ] || fail "plugin-files.txt lists $f, which does not exist"
done < plugin-files.txt

# --------------------------------------------------------------- the code

echo "release: running the suites"
./scripts/run-tests.sh

echo "release: building the package"
./scripts/build.sh

if [ "$DRY" -eq 1 ]; then
  echo "release: dry run, nothing tagged"
  exit 0
fi

# ------------------------------------------------------------------- tag

if [ -n "$NOTES" ]; then
  git tag -a "$TAG" -F "$NOTES"
else
  git tag -a "$TAG" -m "Animation Auto-Tagger $VERSION"
fi
echo "release: tagged $TAG"

if [ "$PUSH" -eq 1 ]; then
  git push origin "$TAG"
  echo "release: pushed $TAG"
else
  echo "release: push it with  git push origin $TAG"
fi
