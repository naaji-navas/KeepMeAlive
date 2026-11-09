#!/bin/sh
# Regenerates docs/icon.png and Resources/AppIcon.icns from scripts/generate-icon.swift.
set -eu
cd "$(dirname "$0")/.."
swift scripts/generate-icon.swift docs/icon.png
SET="build/AppIcon.iconset"
rm -rf "$SET"; mkdir -p "$SET"
for s in 16 32 128 256 512; do
  sips -z $s $s docs/icon.png --out "$SET/icon_${s}x${s}.png" >/dev/null
  sips -z $((s*2)) $((s*2)) docs/icon.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o Resources/AppIcon.icns
rm -rf "$SET"
echo "Wrote Resources/AppIcon.icns"
