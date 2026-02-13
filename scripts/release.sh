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
APPCAST="$SCRIPT_DIR/appcast.json"
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
VERSION=$(defaults read "$SCRIPT_DIR/Info.plist" CFBundleShortVersionString 2>/dev/null || \
    /usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$SCRIPT_DIR/Info.plist")

echo "=== JessOS ADM Convert Release ==="
echo ""
echo "  Version:    $VERSION"
echo "  DMG:        $DMG_PATH"
echo "  Appcast:    $APPCAST"
echo "  Web DMG:    $JESSOS_WEB/JessOS-ADM-Convert.dmg"
echo ""

# Pre-flight checks
ERRORS=0

if [ ! -f "$DMG_PATH" ]; then
    echo "ERROR: DMG not found at $DMG_PATH"
    echo "       Run ./build.sh first."
    ERRORS=$((ERRORS + 1))
fi

if [ ! -f "$APPCAST" ]; then
    echo "ERROR: appcast.json not found."
    ERRORS=$((ERRORS + 1))
fi

if [ $ERRORS -gt 0 ]; then
    echo ""
    echo "Fix the errors above and try again."
    exit 1
fi

# Check appcast version matches
APPCAST_VERSION=$(python3 -c "import json; print(json.load(open('$APPCAST'))['version'])" 2>/dev/null || echo "unknown")
if [ "$APPCAST_VERSION" != "$VERSION" ]; then
    echo "WARNING: appcast.json version ($APPCAST_VERSION) != Info.plist version ($VERSION)"
    echo "         Update appcast.json before releasing."
fi

echo "This will:"
echo "  1. Push to main branch"
echo "  2. Create GitHub release v$VERSION with DMG"
echo "  3. Copy DMG to download page"
echo "  4. Deploy download page DMG to S3"
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
echo "Step 1: Pushing to main..."
git -C "$SCRIPT_DIR" push origin main

echo ""
echo "Step 2: Creating GitHub release v$VERSION..."
gh release create "v$VERSION" "$DMG_PATH" \
    --repo Je55Jackson/ADM-Convert \
    --title "v$VERSION" \
    --notes "JessOS ADM Convert v$VERSION"

echo ""
echo "Step 3: Copying DMG to download page..."
cp "$DMG_PATH" "$JESSOS_WEB/JessOS-ADM-Convert.dmg"

echo ""
echo "Step 4: Deploying DMG to S3..."
cd "$SCRIPT_DIR/../JessOS"
./scripts/deploy-web.sh admconvert/JessOS-ADM-Convert.dmg

echo ""
echo "=== Release v$VERSION complete ==="
echo ""
echo "Users will receive the update via:"
echo "  - Auto-updater (checks appcast.json on launch)"
echo "  - Download page: https://jessos.com/admconvert/"
