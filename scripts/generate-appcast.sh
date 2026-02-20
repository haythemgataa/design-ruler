#!/bin/bash
# Generate Sparkle appcast.xml
# Usage: ./generate-appcast.sh [output-file]
# Required env vars: VERSION, BUILD_NUMBER, ED_SIGNATURE, FILE_LENGTH, DOWNLOAD_URL, REPO_URL
set -euo pipefail

OUTPUT="${1:-appcast.xml}"

cat > "$OUTPUT" << EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
     xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"
     xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Design Ruler Updates</title>
    <link>${REPO_URL}</link>
    <description>Most recent changes with links to updates.</description>
    <language>en</language>
    <item>
      <title>Version ${VERSION}</title>
      <pubDate>$(date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>${BUILD_NUMBER}</sparkle:version>
      <sparkle:shortVersionString>${VERSION}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      <enclosure
        url="${DOWNLOAD_URL}"
        sparkle:edSignature="${ED_SIGNATURE}"
        length="${FILE_LENGTH}"
        type="application/octet-stream" />
    </item>
  </channel>
</rss>
EOF

echo "Generated appcast: $OUTPUT"
