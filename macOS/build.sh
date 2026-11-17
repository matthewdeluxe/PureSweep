#!/bin/bash
# Builds PureSweep.app and PureSweep.dmg for macOS.
#   ./build.sh            universal (Apple silicon + Intel) release build
#   ./build.sh --native   this Mac's architecture only (faster)
# Output: macOS/dist/PureSweep.app and macOS/dist/PureSweep.dmg (git-ignored).
# Signing: ad-hoc by default. Set SIGN_IDENTITY="Developer ID Application: ..." to sign for distribution.
set -euo pipefail
cd "$(dirname "$0")"

ARCHS=(--arch arm64 --arch x86_64)
[[ "${1:-}" == "--native" ]] && ARCHS=()

swift build -c release ${ARCHS[@]+"${ARCHS[@]}"}
BIN="$(swift build -c release ${ARCHS[@]+"${ARCHS[@]}"} --show-bin-path)/PureSweep"

APP=dist/PureSweep.app
rm -rf "$APP" dist/PureSweep.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/PureSweep"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Icon: drawn by tools/make-icon.swift, regenerated only when missing.
if [[ ! -f Resources/AppIcon.icns ]]; then
    TMP="$(mktemp -d)"
    swift tools/make-icon.swift "$TMP/AppIcon.iconset"
    iconutil -c icns "$TMP/AppIcon.iconset" -o Resources/AppIcon.icns
    rm -rf "$TMP"
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

codesign --force --deep --options runtime --sign "${SIGN_IDENTITY:--}" "$APP"

# Disk image with an Applications shortcut for drag-to-install.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname PureSweep -srcfolder "$STAGE" -format UDZO -ov dist/PureSweep.dmg
rm -rf "$STAGE"

echo "Built $(pwd)/$APP and $(pwd)/dist/PureSweep.dmg"
