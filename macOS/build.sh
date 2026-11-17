#!/bin/bash
# Builds PureSweep.app and PureSweep.dmg for macOS.
#   ./build.sh            universal (Apple silicon + Intel) release build
#   ./build.sh --native   this Mac's architecture only (faster)
# Output: macOS/dist/PureSweep.app and macOS/dist/PureSweep.dmg (git-ignored).
# Signing: ad-hoc by default, which is fine on this Mac but blocked by Gatekeeper after a download.
# For a download anyone can open, see "Release" in macOS/README.md:
#   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"   signs the app and the DMG
#   NOTARY_PROFILE=puresweep    also notarizes the DMG with Apple and staples the ticket
#                               (profile created once with: xcrun notarytool store-credentials puresweep)
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

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    # Hardened runtime and a secure timestamp are both required for notarization.
    codesign --force --options runtime --timestamp --sign "$SIGN_IDENTITY" "$APP"
else
    codesign --force --options runtime --sign - "$APP"
fi

# Disk image with an Applications shortcut for drag-to-install.
STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -quiet -volname PureSweep -srcfolder "$STAGE" -format UDZO -ov dist/PureSweep.dmg
rm -rf "$STAGE"

if [[ -n "${SIGN_IDENTITY:-}" ]]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" dist/PureSweep.dmg
fi
if [[ -n "${NOTARY_PROFILE:-}" ]]; then
    [[ -n "${SIGN_IDENTITY:-}" ]] || { echo "NOTARY_PROFILE needs SIGN_IDENTITY (a Developer ID Application certificate)." >&2; exit 1; }
    echo "Submitting to Apple for notarization (usually a few minutes)…"
    xcrun notarytool submit dist/PureSweep.dmg --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple dist/PureSweep.dmg
    spctl --assess --type open --context context:primary-signature -v dist/PureSweep.dmg
fi

echo "Built $(pwd)/$APP and $(pwd)/dist/PureSweep.dmg"
