#!/bin/bash
# Signs the update archive and writes appcast.xml for Sparkle.
# Usage: SPARKLE_PRIVATE_KEY=... scripts/make-appcast.sh Lumora-0.4.0.zip 0.4.0 42
set -euo pipefail

ARCHIVE="$1"
VERSION="$2"
BUILD="$3"
SPARKLE_VERSION="2.6.4"
REPO="JoshiCodes/Lumora"

if [ -z "${SPARKLE_PRIVATE_KEY:-}" ]; then
  echo "::warning::SPARKLE_PRIVATE_KEY is not set, skipping the update feed"
  exit 0
fi

TOOLS="$(mktemp -d)"
trap 'rm -rf "$TOOLS"' EXIT
curl -sSL "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" \
  | tar -xJ -C "$TOOLS"

SIGNATURE=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$TOOLS/bin/sign_update" --ed-key-file - "$ARCHIVE")

cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Lumora</title>
    <item>
      <title>Lumora $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <link>https://github.com/$REPO/releases/tag/v$VERSION</link>
      <sparkle:releaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:releaseNotesLink>
      <sparkle:version>$BUILD</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/$(basename "$ARCHIVE")"
                 type="application/octet-stream"
                 $SIGNATURE />
    </item>
  </channel>
</rss>
XML

echo "Wrote appcast.xml for $VERSION ($BUILD)"
