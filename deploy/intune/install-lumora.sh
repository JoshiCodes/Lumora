#!/bin/bash
# Installs or updates Lumora from the latest GitHub release.
# Use as an Intune shell script (Devices > macOS > Scripts), run as root,
# for example once a day. It only downloads when a newer version is out.
set -euo pipefail

REPO="JoshiCodes/Lumora"
APP="/Applications/Lumora.app"

release=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest")
url=$(printf '%s' "$release" | grep -o '"browser_download_url": *"[^"]*\.pkg"' | head -1 | cut -d'"' -f4)
if [ -z "$url" ]; then
  echo "No installer package in the latest release"
  exit 1
fi

latest=$(basename "$url" .pkg | sed 's/^Lumora-//')
installed=$(defaults read "$APP/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "none")
if [ "$installed" = "$latest" ]; then
  echo "Lumora $installed is up to date"
  exit 0
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fsSL "$url" -o "$tmp/Lumora.pkg"
installer -pkg "$tmp/Lumora.pkg" -target /
echo "Installed Lumora $latest (was $installed)"
