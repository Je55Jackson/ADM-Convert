#!/bin/bash
# scripts/test-update.sh
# Test Sparkle's update flow following the official guidance at
# https://sparkle-project.org/documentation/#test-sparkle-out
#
# Builds a "low version" copy of the app (CFBundleShortVersionString set to
# 3.0 by default), signs it, installs it to /Applications, and clears Sparkle's
# last-check timer so the next launch checks immediately. The production
# appcast.xml on GitHub serves the "new" version — your installed app sees the
# real published v3.2 (or whatever is current) and offers the real DMG.
#
# Usage:
#   ./scripts/test-update.sh           # install low-version test build
#   ./scripts/test-update.sh restore   # rebuild + deploy real notarized v3.2
#
# Sparkle defers the auto-check permission prompt until the SECOND launch.
# So after this script runs: launch the app, quit, launch again — then the
# update offer should appear. Or use App menu -> Check for Updates... at any time.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUNDLE_ID="com.jessos.adm-convert"
INFO_PLIST="$SCRIPT_DIR/Info.plist"
LOW_VERSION="${LOW_VERSION:-3.0}"
LOW_BUILD="${LOW_BUILD:-0}"

if [ "$1" = "restore" ]; then
    echo "Rebuilding + deploying real notarized v3.2..."
    "$SCRIPT_DIR/build.sh" --deploy
    exit 0
fi

REAL_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
REAL_BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
echo "Current Info.plist: short=$REAL_VERSION build=$REAL_BUILD"
echo "Building test copy at short=$LOW_VERSION build=$LOW_BUILD (Sparkle compares CFBundleVersion)..."

# Restore the plist whether the build succeeds, fails, or is interrupted.
trap '/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $REAL_VERSION" "$INFO_PLIST"; /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $REAL_BUILD" "$INFO_PLIST"' EXIT

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $LOW_VERSION" "$INFO_PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $LOW_BUILD" "$INFO_PLIST"
"$SCRIPT_DIR/build.sh" --deploy --fast

# Bypass Sparkle's 24h check throttle so the next launch checks immediately.
defaults delete "$BUNDLE_ID" SULastCheckTime 2>/dev/null || true
defaults delete "$BUNDLE_ID" SUSkippedVersion 2>/dev/null || true

echo ""
echo "Test build deployed at v$LOW_VERSION."
echo "Info.plist already restored to $REAL_VERSION."
echo ""
echo "Next steps (per Sparkle's official test flow):"
echo "  1. Launch JessOS ADM Convert (first launch — Sparkle is silent here)"
echo "  2. Quit it"
echo "  3. Launch again (second launch — Sparkle's update permission prompt fires)"
echo "  4. Accept, and the update to v$REAL_VERSION should be offered"
echo ""
echo "Or skip the wait and manually invoke App menu -> Check for Updates..."
echo ""
echo "Tail Sparkle's logs live (separate terminal):"
echo "  log stream --predicate 'subsystem == \"org.sparkle-project.Sparkle\"' --info"
echo ""
echo "Restore real notarized v$REAL_VERSION when done:"
echo "  ./scripts/test-update.sh restore"
