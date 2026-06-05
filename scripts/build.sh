#!/bin/bash
# Builds the SPM executable and assembles a signed PasteBack.app bundle.
#
# Usage: ./scripts/build.sh [debug|release]   (default: debug)
#
# Code signing & TCC stability:
#   Screen Recording AND Accessibility permissions are keyed to the app's code
#   signature. Ad-hoc signing changes identity across rebuilds, so macOS
#   re-prompts every build. To keep grants stable, create a self-signed
#   code-signing certificate ONCE:
#     Keychain Access -> Certificate Assistant -> Create a Certificate
#       Name: "PasteBack Dev"   Identity Type: Self Signed Root
#       Certificate Type: Code Signing
#   This script signs with "PasteBack Dev" if present, else falls back to ad-hoc.

set -euo pipefail

CONFIG="${1:-debug}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="PasteBack"
BUNDLE="$ROOT/$APP_NAME.app"
SIGN_IDENTITY="PasteBack Dev"

cd "$ROOT"

echo "==> swift build ($CONFIG)"
swift build -c "$CONFIG"
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"

echo "==> Assembling $APP_NAME.app"
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
cp "$BIN_PATH/$APP_NAME" "$BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT/Resources/Info.plist" "$BUNDLE/Contents/Info.plist"

if security find-certificate -c "$SIGN_IDENTITY" >/dev/null 2>&1; then
    echo "==> Signing with '$SIGN_IDENTITY'"
    codesign --force --options runtime --sign "$SIGN_IDENTITY" "$BUNDLE"
else
    echo "==> '$SIGN_IDENTITY' cert not found; ad-hoc signing (TCC grants may reset on rebuild)"
    codesign --force --sign - "$BUNDLE"
fi

echo "==> Built $BUNDLE"
