#!/bin/sh
# Builds a release zip: build/MacAwake-<version>.zip containing MacAwake.app,
# install.sh and uninstall.sh. Used by the GitHub release workflow.
set -eu
cd "$(dirname "$0")/.."
VERSION="${1:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)}"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION#v}" Resources/Info.plist
./scripts/build-app.sh
STAGE="build/MacAwake-$VERSION"
rm -rf "$STAGE" "$STAGE.zip"
mkdir -p "$STAGE"
cp -R build/MacAwake.app "$STAGE/"
cp scripts/install-release.sh "$STAGE/install.sh"
cp scripts/uninstall.sh "$STAGE/uninstall.sh"
cp LICENSE README.md "$STAGE/"
(cd build && /usr/bin/ditto -c -k --keepParent "MacAwake-$VERSION" "MacAwake-$VERSION.zip")
shasum -a 256 "$STAGE.zip" | tee "$STAGE.zip.sha256"
