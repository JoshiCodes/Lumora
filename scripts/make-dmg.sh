#!/bin/bash
# Usage: scripts/make-dmg.sh path/to/Lumora.app 0.2.0
set -euo pipefail

APP="$1"
VERSION="$2"
OUT="Lumora-$VERSION.dmg"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

STAGE="$(mktemp -d)"
ART="$(mktemp -d)"
trap 'rm -rf "$STAGE" "$ART"' EXIT

cp -R "$APP" "$STAGE/"
tiffutil -cathidpicheck "$ROOT/Installer/background.png" "$ROOT/Installer/background@2x.png" \
  -out "$ART/background.tiff"

VOLICON=()
if [ -f "$APP/Contents/Resources/AppIcon.icns" ]; then
  VOLICON=(--volicon "$APP/Contents/Resources/AppIcon.icns")
fi

rm -f "$OUT"

# create-dmg lays out the window through Finder. If that fails on a headless
# runner, fall back to a plain image that still has the Applications shortcut.
if ! create-dmg \
    --volname "Lumora" \
    ${VOLICON[@]+"${VOLICON[@]}"} \
    --background "$ART/background.tiff" \
    --window-pos 200 120 \
    --window-size 660 400 \
    --icon-size 128 \
    --text-size 13 \
    --icon "Lumora.app" 175 190 \
    --hide-extension "Lumora.app" \
    --app-drop-link 485 190 \
    "$OUT" "$STAGE"; then
  echo "create-dmg failed, building a plain disk image instead"
  rm -f "$OUT"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "Lumora" -srcfolder "$STAGE" -ov -format UDZO "$OUT"
fi

echo "Created $OUT"
