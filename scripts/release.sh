#!/bin/bash
# scripts/release.sh
# Full release pipeline — pushes a new version to users.
#
# TERMINOLOGY (for Claude Code sessions):
#   "build"   = ./build.sh              → compile, sign, notarize DMG (local only)
#   "deploy"  = ./build.sh --deploy     → same + install to /Applications (local only)
#   "release" = this script             → push to users (GitHub + download page)
#
# Build and deploy are SAFE — they never affect users.
# Release is the ONLY action that pushes to production.
#
# Usage:
#   ./scripts/release.sh           # Interactive — prompts for confirmation
#   ./scripts/release.sh --dry-run # Show what would happen without doing it

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="JessOS ADM Convert"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"
APPCAST_XML="$SCRIPT_DIR/appcast.xml"
GENERATE_APPCAST="$SCRIPT_DIR/Frameworks/bin/generate_appcast"
JESSOS_WEB="$SCRIPT_DIR/../JessOS/web/admconvert"
CHANGELOG="$JESSOS_WEB/changelog.html"
DEPLOY_SCRIPT="$SCRIPT_DIR/../JessOS/scripts/deploy-web.sh"

DRY_RUN=false
for arg in "$@"; do
    case $arg in
        --dry-run) DRY_RUN=true ;;
    esac
done

# Read version from Info.plist
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SCRIPT_DIR/Info.plist")
BUILD_NUMBER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$SCRIPT_DIR/Info.plist")

echo "=== JessOS ADM Convert Release ==="
echo ""
echo "  Version:    $VERSION (build $BUILD_NUMBER)"
echo "  DMG:        $DMG_PATH"
echo "  Appcast:    $APPCAST_XML"
echo "  Web DMG:    $JESSOS_WEB/JessOS-ADM-Convert.dmg"
echo ""

ERRORS=0

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    echo "       Run ./build.sh first."
    ERRORS=$((ERRORS + 1))
fi

if [ ! -x "$GENERATE_APPCAST" ]; then
    echo "ERROR: generate_appcast not found at $GENERATE_APPCAST"
    echo "       Extract Sparkle's bin/ directory into Frameworks/bin/."
    ERRORS=$((ERRORS + 1))
fi

# Sparkle compares CFBundleVersion (build number), not CFBundleShortVersionString.
# Refuse to ship a release whose build number is <= what's already in appcast.xml,
# because existing users would never see the update.
if [ -f "$APPCAST_XML" ]; then
    LAST_BUILD=$(grep -oE '<sparkle:version>[0-9]+</sparkle:version>' "$APPCAST_XML" \
        | grep -oE '[0-9]+' | sort -rn | head -1)
    if [ -n "$LAST_BUILD" ] && [ "$BUILD_NUMBER" -le "$LAST_BUILD" ]; then
        echo "ERROR: CFBundleVersion is $BUILD_NUMBER but last published build is $LAST_BUILD."
        echo "       Sparkle compares CFBundleVersion; users won't see this as an update."
        echo "       Bump CFBundleVersion in Info.plist (to at least $((LAST_BUILD + 1))) and re-run ./build.sh."
        ERRORS=$((ERRORS + 1))
    fi
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Fix the errors above and try again."
    exit 1
fi

echo "This will:"
echo "  1. Generate signed appcast.xml from the DMG"
echo "  2. Commit appcast.xml + Info.plist and push to main"
echo "  3. Create GitHub release v$VERSION with DMG"
echo "  4. Copy DMG to download page"
echo "  5. Deploy download page DMG to S3"
echo ""

if [ "$DRY_RUN" = true ]; then
    echo "[DRY RUN] Would execute the steps above. Exiting."
    exit 0
fi

read -p "Continue? (y/N): " CONFIRM
if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
    echo "Release cancelled."
    exit 0
fi

echo ""
echo "Step 1: Generating signed appcast.xml..."

# GitHub renames release asset filenames: spaces become dots. Rename the
# local DMG to match BEFORE generate_appcast scans it, so the URL it embeds
# in appcast.xml matches what GitHub will serve.
DOTTED_DMG_NAME="${APP_NAME// /.}.dmg"
DOTTED_DMG_PATH="$BUILD_DIR/$DOTTED_DMG_NAME"
if [ -f "$DMG_PATH" ] && [ "$DMG_PATH" != "$DOTTED_DMG_PATH" ]; then
    mv "$DMG_PATH" "$DOTTED_DMG_PATH"
fi

# generate_appcast picks up release notes from a .html file with the same
# basename as the DMG. Source from release-notes/<version>.html.
NOTES_SRC="$SCRIPT_DIR/release-notes/$VERSION.html"
NOTES_DEST="$BUILD_DIR/${DOTTED_DMG_NAME%.dmg}.html"
if [ -f "$NOTES_SRC" ]; then
    cp "$NOTES_SRC" "$NOTES_DEST"
    echo "  Including notes from $NOTES_SRC -> $NOTES_DEST"
else
    echo "  WARNING: No release-notes/$VERSION.html — appcast description will be empty."
fi

"$GENERATE_APPCAST" \
    --download-url-prefix "https://github.com/Je55Jackson/ADM-Convert/releases/download/v$VERSION/" \
    -o "$APPCAST_XML" \
    "$BUILD_DIR"

echo ""
echo "Step 2: Creating GitHub release v$VERSION (DMG live before appcast points at it)..."
gh release create "v$VERSION" "$DOTTED_DMG_PATH" \
    --repo Je55Jackson/ADM-Convert \
    --title "v$VERSION" \
    --notes "JessOS ADM Convert v$VERSION"

echo ""
echo "Step 3: Committing appcast and pushing to main..."
git -C "$SCRIPT_DIR" add appcast.xml appcast.json Info.plist
git -C "$SCRIPT_DIR" commit -m "Release v$VERSION" || echo "(nothing to commit)"
git -C "$SCRIPT_DIR" push origin main

echo ""
echo "Step 4: Copying DMG to download page..."
cp "$DOTTED_DMG_PATH" "$JESSOS_WEB/JessOS-ADM-Convert.dmg"

echo ""
echo "Step 5: Deploying DMG to S3..."
cd "$SCRIPT_DIR/../JessOS"
./scripts/deploy-web.sh admconvert/JessOS-ADM-Convert.dmg

echo ""
echo "=== Release v$VERSION complete ==="
echo ""
echo "Users will receive the update via:"
echo "  - Sparkle (appcast.xml, v3.2+ installs)"
echo "  - Download page: https://jessos.com/admconvert/"
