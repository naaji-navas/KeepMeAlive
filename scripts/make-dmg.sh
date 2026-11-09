#!/bin/sh
# Builds build/KeepMeAlive-<version>.dmg: open it and drag KeepMeAlive into Applications.
# Usage: ./scripts/make-dmg.sh [version]   (skips the app build if KEEPMEALIVE_SKIP_BUILD=1)
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-v$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
[ "${KEEPMEALIVE_SKIP_BUILD:-0}" = "1" ] || ./scripts/build-app.sh

STAGE="build/dmg-stage"
DMG="build/KeepMeAlive-$VERSION.dmg"
rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R build/KeepMeAlive.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME FIRST.txt" <<'EOF'
KeepMeAlive: close your MacBook lid and your AI agents keep working.

1. Drag KeepMeAlive into Applications.
2. Open it. The first time, macOS may say it can't verify the developer
   (this open-source build isn't notarized by Apple). If so, go to
   System Settings > Privacy & Security, scroll down and click "Open Anyway".
3. Click the moon in the menu bar, then "Enable lid-proof mode…".

Docs and source: https://github.com/naaji-navas/KeepMeAlive
EOF

hdiutil create -volname "KeepMeAlive" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" >/dev/null
rm -rf "$STAGE"
shasum -a 256 "$DMG" | sed 's#build/##' > "$DMG.sha256"
echo "Built $DMG"
