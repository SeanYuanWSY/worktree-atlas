#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
[[ "$(uname -s)" == Darwin ]] || { echo "DMG packaging requires macOS." >&2; exit 1; }
cd "$ROOT"
CONFIGURATION=release ./script/build_and_run.sh --build-only
ARCH="$(uname -m)"
STAGE="$(mktemp -d "$ROOT/dist/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$ROOT/dist/WorktreeAtlas.app" "$STAGE/WorktreeAtlas.app"
ln -s /Applications "$STAGE/Applications"
DMG="$ROOT/dist/WorktreeAtlas-0.1.0-dev-$ARCH.dmg"
hdiutil create -volname "Worktree Atlas" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
shasum -a 256 "$DMG" > "$DMG.sha256"
echo "Created local development DMG: $DMG"
echo "Not notarized. Public trusted distribution requires Developer ID signing and Apple notarization."
