#!/bin/bash
# Builds dist/macos/PicoSlip.app (universal: Apple silicon and Intel) and
# dist/macos/PicoSlip-<version>.dmg. Run on a Mac with Xcode 26:
#
#   tools/make-macos-dmg.sh
#
# Signing: ad-hoc by default. To sign with your own certificate (a free
# Apple Development one works for your Macs), pass its name:
#   SIGN_IDENTITY="Apple Development: Name Surname (TEAMID)" tools/make-macos-dmg.sh
# List them with: security find-identity -v -p codesigning
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-1.2.0}"
BUILD="${BUILD:-$(git rev-list --count HEAD 2>/dev/null || echo 1)}"
IDENTITY="${SIGN_IDENTITY:--}"
OUT="dist/macos"
APP="$OUT/PicoSlip.app"
DMG="$OUT/PicoSlip-$VERSION.dmg"

echo "Building PicoSlip $VERSION ($BUILD)…"
rm -rf "$OUT"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swift build -c release --arch arm64 --arch x86_64 --product PicoSlip
BIN_DIR="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)"
cp "$BIN_DIR/PicoSlip" "$APP/Contents/MacOS/PicoSlip"

echo "Assembling the app bundle…"
sed -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" macos/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
ICONSET="$OUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" macos/Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    sips -z $((size * 2)) $((size * 2)) macos/Resources/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$ICONSET"

echo "Signing ($([ "$IDENTITY" = "-" ] && echo ad-hoc || echo "$IDENTITY"))…"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP"
codesign --verify --strict --verbose=1 "$APP"

echo "Creating the disk image…"
STAGE="$OUT/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "PicoSlip" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"
[ "$IDENTITY" = "-" ] || codesign --force --timestamp=none --sign "$IDENTITY" "$DMG"
hdiutil verify "$DMG" >/dev/null

echo "Done: $DMG"
