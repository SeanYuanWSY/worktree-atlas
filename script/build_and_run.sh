#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${1:-run}"
APP_NAME="WorktreeAtlas"
BUNDLE_ID="io.github.SeanYuanWSY.WorktreeAtlas"
CONFIGURATION="${CONFIGURATION:-debug}"
case "$MODE" in run|--demo|--build-only|--debug|--logs|--telemetry|--verify) ;; *) echo "Usage: $0 [--demo|--build-only|--debug|--logs|--telemetry|--verify]" >&2; exit 2;; esac
[[ "$(uname -s)" == Darwin ]] || { echo "The GUI requires macOS 14+ and Xcode/Swift 6. Run 'swift test' for Linux core tests." >&2; exit 1; }
[[ "$CONFIGURATION" == debug || "$CONFIGURATION" == release ]] || { echo "Invalid CONFIGURATION" >&2; exit 2; }
cd "$ROOT_DIR"
command -v swift >/dev/null || { echo "Install Xcode with the Swift 6 toolchain." >&2; exit 1; }
swift build -c "$CONFIGURATION" --product "$APP_NAME"
BUILD_BIN="$(swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ICONSET="$DIST_DIR/Atlas.iconset"
# Only replace this project's generated app. Never touch /Applications or user data.
if [[ -L "$DIST_DIR" ]]; then echo "Refusing to use a symlink dist directory." >&2; exit 1; fi
mkdir -p "$DIST_DIR"
if [[ -L "$APP_BUNDLE" ]]; then echo "Refusing to replace a symlink app bundle." >&2; exit 1; fi
if [[ -L "$ICONSET" ]]; then echo "Refusing to use a symlink iconset directory." >&2; exit 1; fi
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_BIN" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp LICENSE THIRD_PARTY_NOTICES.md "$APP_BUNDLE/Contents/Resources/"
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>Worktree Atlas</string>
<key>CFBundleDisplayName</key><string>Worktree Atlas</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
mkdir -p "$ICONSET"
swift "$ROOT_DIR/script/make_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
# Ad-hoc signing is for local testing only, not an Apple-notarized release.
if [[ -n "${SIGN_IDENTITY:-}" ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --sign - "$APP_BUNDLE"
fi
codesign --verify --strict "$APP_BUNDLE"
plutil -lint "$APP_BUNDLE/Contents/Info.plist"
echo "Built: $APP_BUNDLE"
case "$MODE" in
  --build-only) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --demo) /usr/bin/open -n "$APP_BUNDLE" --args --demo ;;
  --debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\"" ;;
  --telemetry) /usr/bin/open -n "$APP_BUNDLE"; /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\"" ;;
  --verify) /usr/bin/open -n "$APP_BUNDLE"; sleep 2; pgrep -x "$APP_NAME" >/dev/null; echo "App process detected. UI still needs visual inspection." ;;
esac
