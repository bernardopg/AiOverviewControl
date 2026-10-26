#!/usr/bin/env bash
# scripts/package-release refuses an archive that would not install: a missing
# runtime file or native adapter, an uncommitted version bump and a provider
# script without its executable bit. Each case runs the real script, through a
# symlink, against a throwaway repository built from HEAD.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
VERSION="$(jq -r .version "$ROOT/plugin.json")"

# fixture NAME: a committed copy of HEAD whose package-release is the real one.
fixture() {
  local repo="$TMP/$1"
  mkdir -p "$repo"
  git -C "$ROOT" archive HEAD | tar -x -C "$repo"
  git -C "$repo" init -q
  git -C "$repo" -c core.fileMode=true add -A
  git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qm fixture
  ln -sf "$ROOT/scripts/package-release" "$repo/scripts/package-release"
  printf '%s' "$repo"
}
commit() { git -C "$1" -c user.name=Fixture -c user.email=fixture@example.invalid commit -qam "$2"; }
# refuse REPO MESSAGE: packaging fails and says why.
refuse() {
  if "$1/scripts/package-release" "v$VERSION" "$TMP/dist" >"$TMP/out" 2>&1; then
    fail "packaged despite: $2"
  fi
  grep -qF -- "$2" "$TMP/out" || fail "expected '$2', got: $(tail -n 3 "$TMP/out")"
}

repo="$(fixture missing-file)"
git -C "$repo" rm -q qmldir
commit "$repo" 'drop qmldir'
refuse "$repo" 'Release archive is missing qmldir'

repo="$(fixture missing-native)"
: > "$repo/providers/native/untracked.bash"
refuse "$repo" 'Release archive missing native adapter providers/native/untracked.bash'

repo="$(fixture uncommitted-version)"
jq '.version = "99.0.0"' "$repo/plugin.json" > "$TMP/plugin.json"
mv "$TMP/plugin.json" "$repo/plugin.json"
printf '# Changelog\n\n## 99.0.0\n\n- Fixture release.\n' > "$repo/CHANGELOG.md"
if "$repo/scripts/package-release" v99.0.0 "$TMP/dist" >"$TMP/out" 2>&1; then
  fail "packaged an uncommitted version bump"
fi
grep -qF "Archived plugin.json version is $VERSION but the working tree says 99.0.0" "$TMP/out" \
  || fail "uncommitted version message: $(tail -n 3 "$TMP/out")"

repo="$(fixture non-executable)"
chmod -x "$repo/providers/get-ai21-usage"
git -C "$repo" -c core.fileMode=true -c user.name=Fixture -c user.email=fixture@example.invalid \
  commit -qam 'drop the executable bit'
refuse "$repo" 'Release archive contains a non-executable provider script: providers/get-ai21-usage'

echo 'OK: package-release refuses incomplete archives'
