#!/bin/sh
# Builds KeepMeAlive.app into ./build (release, ad-hoc signed).
# Set KEEPMEALIVE_VERSION=v1.2.3 to override the version shown in the app.
set -eu
cd "$(dirname "$0")/.."
swift build -c release
BIN="$(swift build -c release --show-bin-path)/KeepMeAlive"
APP="build/KeepMeAlive.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/KeepMeAlive"
cp Resources/Info.plist "$APP/Contents/Info.plist"
# Release builds stamp their version into the bundle only, never into the source plist.
if [ -n "${KEEPMEALIVE_VERSION:-}" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${KEEPMEALIVE_VERSION#v}" "$APP/Contents/Info.plist"
fi
cp Resources/watchdog.sh "$APP/Contents/Resources/watchdog.sh"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
echo "Built $APP"
