#!/bin/sh
# Builds MacAwake.app into ./build (release, ad-hoc signed).
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacAwake"
APP="build/MacAwake.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacAwake"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/watchdog.sh "$APP/Contents/Resources/watchdog.sh"
[ -f Resources/AppIcon.icns ] && cp Resources/AppIcon.icns "$APP/Contents/Resources/" && \
  /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$APP/Contents/Info.plist" 2>/dev/null || true
codesign --force --deep --sign - "$APP"
echo "Built $APP"
