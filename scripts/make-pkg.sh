#!/bin/bash
# Builds an installer package for MDM deployment (Intune, Jamf, Kandji, ...).
# Usage: scripts/make-pkg.sh path/to/Lumora.app 0.8.0
#
# The package is unsigned unless DEVELOPER_ID_INSTALLER names a "Developer ID Installer"
# identity in the keychain. Intune's "macOS app (PKG)" type accepts unsigned packages.
set -euo pipefail

APP="$1"
VERSION="$2"
OUT="Lumora-$VERSION.pkg"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
IDENTIFIER="com.joshicodes.Lumora.pkg"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/root"
ditto "$APP" "$WORK/root/Lumora.app"

# Always install to /Applications, even if an older copy was moved somewhere else.
pkgbuild --analyze --root "$WORK/root" "$WORK/components.plist" > /dev/null
plutil -replace 0.BundleIsRelocatable -bool NO "$WORK/components.plist"

pkgbuild \
  --root "$WORK/root" \
  --component-plist "$WORK/components.plist" \
  --install-location /Applications \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --scripts "$ROOT/scripts/pkg" \
  "$WORK/Lumora-component.pkg"

SIGN=()
if [ -n "${DEVELOPER_ID_INSTALLER:-}" ]; then
  SIGN=(--sign "$DEVELOPER_ID_INSTALLER")
fi

productbuild \
  --identifier "$IDENTIFIER" \
  --version "$VERSION" \
  --package "$WORK/Lumora-component.pkg" \
  ${SIGN[@]+"${SIGN[@]}"} \
  "$OUT"

echo "Created $OUT"
