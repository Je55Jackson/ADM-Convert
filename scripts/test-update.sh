#!/bin/bash
# scripts/test-update.sh
# Spoof a Sparkle update locally to preview the update dialog without shipping.
#
# Usage:
#   ./scripts/test-update.sh           # set up the fake feed + override
#   ./scripts/test-update.sh revert    # restore production feed
#
# How it works:
#   1. Copies the current build/JessOS ADM Convert.dmg to /tmp/jessos-test-update/
#   2. Signs it with the EdDSA key from your Keychain
#   3. Writes a fake appcast.xml claiming version 9.9.9
#   4. Overrides SUFeedURL in the app's UserDefaults so this machine reads the
#      local appcast instead of the live GitHub one. Other users are unaffected.
#   5. Clears any "skipped version" + last-check throttle so the dialog appears.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.jessos.adm-convert"
DMG_PATH="$SCRIPT_DIR/build/JessOS ADM Convert.dmg"
SIGN_UPDATE="$SCRIPT_DIR/Frameworks/bin/sign_update"
TEST_DIR="/tmp/jessos-test-update"
TEST_DMG="$TEST_DIR/JessOS ADM Convert.dmg"
TEST_APPCAST="$TEST_DIR/test-appcast.xml"
TEST_VERSION="9.9.9"
TEST_BUILD="9999"

if [ "$1" = "revert" ]; then
    echo "Reverting test setup..."
    defaults delete "$BUNDLE_ID" SUFeedURL 2>/dev/null || true
    defaults delete "$BUNDLE_ID" SUSkippedVersion 2>/dev/null || true
    defaults delete "$BUNDLE_ID" SULastCheckTime 2>/dev/null || true
    rm -rf "$TEST_DIR"
    echo "Done. The app now reads the production appcast on next launch."
    exit 0
fi

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    echo "       Run ./build.sh first."
    exit 1
fi

if [ ! -x "$SIGN_UPDATE" ]; then
    echo "ERROR: sign_update not found at $SIGN_UPDATE"
    exit 1
fi

mkdir -p "$TEST_DIR"
cp "$DMG_PATH" "$TEST_DMG"

echo "Signing test DMG with your EdDSA key (Keychain may prompt)..."
SIG_LINE=$("$SIGN_UPDATE" "$TEST_DMG")
ED_SIG=$(echo "$SIG_LINE" | sed -E 's/.*sparkle:edSignature="([^"]+)".*/\1/')
LENGTH=$(echo "$SIG_LINE" | sed -E 's/.*length="([^"]+)".*/\1/')

# URL-encode the space in the DMG filename for the file:// URL.
DMG_URL="file://${TEST_DMG// /%20}"
PUB_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S +0000")

cat > "$TEST_APPCAST" <<EOF
<?xml version="1.0" standalone="yes"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0">
    <channel>
        <title>JessOS ADM Convert (TEST)</title>
        <item>
            <title>Version $TEST_VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$TEST_BUILD</sparkle:version>
            <sparkle:shortVersionString>$TEST_VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
            <description><![CDATA[
                <h2>Version $TEST_VERSION (Test)</h2>
                <p>This is a local-only test entry. The "update" is just a copy of your current v3.2 DMG.</p>
                <ul>
                    <li>Faster converter</li>
                    <li>Bug fixes</li>
                    <li>Small UI polish</li>
                </ul>
            ]]></description>
            <enclosure url="$DMG_URL" length="$LENGTH" type="application/octet-stream" sparkle:edSignature="$ED_SIG"/>
        </item>
    </channel>
</rss>
EOF

defaults write "$BUNDLE_ID" SUFeedURL "file://$TEST_APPCAST"
defaults delete "$BUNDLE_ID" SUSkippedVersion 2>/dev/null || true
defaults delete "$BUNDLE_ID" SULastCheckTime 2>/dev/null || true

echo ""
echo "Test setup complete."
echo "  Fake version:  $TEST_VERSION"
echo "  Feed URL:      file://$TEST_APPCAST"
echo ""
echo "Next steps:"
echo "  1. Launch JessOS ADM Convert (or quit + relaunch if already open)"
echo "  2. App menu -> Check for Updates..."
echo "  3. You'll see Sparkle's standard dialog offering $TEST_VERSION"
echo "  4. Clicking 'Install Update' reinstalls v3.2 over itself (safe)"
echo ""
echo "To revert:"
echo "  ./scripts/test-update.sh revert"
