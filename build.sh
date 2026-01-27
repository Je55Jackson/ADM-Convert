#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="JessOS ADM Convert"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_STAGING="$BUILD_DIR/dmg_staging"
DEPLOY=false

# Parse arguments
for arg in "$@"; do
    case $arg in
        --deploy)
            DEPLOY=true
            ;;
    esac
done

echo "Building $APP_NAME..."

# Clean and create build directory
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Create app bundle structure
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Scripts"

# Compile Swift code
echo "Compiling Swift code..."
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx11.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    "$SCRIPT_DIR/Sources/AppDelegate.swift"

# Copy Info.plist
echo "Copying Info.plist..."
cp "$SCRIPT_DIR/Info.plist" "$APP_BUNDLE/Contents/"

# Copy scripts
echo "Copying scripts..."
cp "$SCRIPT_DIR/Resources/Scripts/convert.sh" "$APP_BUNDLE/Contents/Resources/Scripts/"
cp "$SCRIPT_DIR/Resources/Scripts/run_with_progress.sh" "$APP_BUNDLE/Contents/Resources/Scripts/"
chmod +x "$APP_BUNDLE/Contents/Resources/Scripts/"*.sh

# Copy ADMProgress
echo "Copying ADMProgress..."
cp "$SCRIPT_DIR/Resources/ADMProgress" "$APP_BUNDLE/Contents/Resources/"

# Copy icon
echo "Copying icon..."
cp "$SCRIPT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/"

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Make the app executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Code sign with Developer ID certificate (hardened runtime + timestamp for notarization)
echo "Code signing app..."
codesign --force --options runtime --timestamp --sign "Developer ID Application: Jess Jackson (K5765CY524)" "$APP_BUNDLE/Contents/Resources/ADMProgress"
codesign --force --deep --options runtime --timestamp --sign "Developer ID Application: Jess Jackson (K5765CY524)" "$APP_BUNDLE"

# Create styled DMG using appdmg
echo "Creating DMG..."
rm -f "$DMG_PATH"
appdmg "$SCRIPT_DIR/appdmg.json" "$DMG_PATH"

# Notarize the DMG
echo ""
echo "Notarizing DMG (this may take a few minutes)..."
xcrun notarytool submit "$DMG_PATH" --keychain-profile "ADM-Convert-Notarization" --wait

# Staple the notarization ticket to the DMG
echo "Stapling notarization ticket..."
xcrun stapler staple "$DMG_PATH"

echo ""
echo "Build complete!"
echo "  App: $APP_BUNDLE"
echo "  DMG: $DMG_PATH"

# Deploy to /Applications if requested
if [ "$DEPLOY" = true ]; then
    echo ""
    echo "Deploying to /Applications..."
    rm -rf "/Applications/$APP_NAME.app"
    cp -R "$APP_BUNDLE" /Applications/

    # Re-register with Launch Services and refresh Dock
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app"
    killall Dock 2>/dev/null || true

    echo "Deployed to /Applications/$APP_NAME.app"
else
    echo ""
    echo "To test, run:"
    echo "  open \"$APP_BUNDLE\""
    echo ""
    echo "To deploy to /Applications, run:"
    echo "  ./build.sh --deploy"
fi
