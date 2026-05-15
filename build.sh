#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
APP_NAME="JessOS ADM Convert"
APP_BUNDLE="$BUILD_DIR/$APP_NAME.app"
DMG_NAME="$APP_NAME.dmg"
DMG_PATH="$BUILD_DIR/$DMG_NAME"
DMG_STAGING="$BUILD_DIR/dmg_staging"
SIGN_ID="Developer ID Application: Jess Jackson (K5765CY524)"
SPARKLE="$SCRIPT_DIR/Frameworks/Sparkle.framework"
DEPLOY=false

if [ ! -d "$SPARKLE" ]; then
    echo "ERROR: Sparkle.framework not found at $SPARKLE"
    echo "       Download from https://github.com/sparkle-project/sparkle/releases"
    echo "       and extract into Frameworks/."
    exit 1
fi

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
mkdir -p "$APP_BUNDLE/Contents/Frameworks"

# Rebuild ADMProgress with new styling
echo "Compiling ADMProgress..."
swiftc \
    -o "$SCRIPT_DIR/Resources/ADMProgress" \
    -target arm64-apple-macosx14.0 \
    -sdk $(xcrun --show-sdk-path) \
    -framework Cocoa \
    -framework QuartzCore \
    "$SCRIPT_DIR/ADMProgressSource/main.swift"

# Compile Swift code (manual entry point with all sources)
echo "Compiling Swift code..."
swiftc \
    -o "$APP_BUNDLE/Contents/MacOS/$APP_NAME" \
    -target arm64-apple-macosx14.0 \
    -sdk $(xcrun --show-sdk-path) \
    -F "$SCRIPT_DIR/Frameworks" \
    -framework Cocoa \
    -framework SwiftUI \
    -framework UniformTypeIdentifiers \
    -framework Sparkle \
    -Xlinker -rpath -Xlinker "@executable_path/../Frameworks" \
    "$SCRIPT_DIR/Sources/main.swift" \
    "$SCRIPT_DIR/Sources/ADMConvertApp.swift" \
    "$SCRIPT_DIR/Sources/ContentView.swift" \
    "$SCRIPT_DIR/Sources/ConversionManager.swift" \
    "$SCRIPT_DIR/Sources/AppDelegate.swift" \
    "$SCRIPT_DIR/Sources/Models/FileConversionItem.swift" \
    "$SCRIPT_DIR/Sources/Models/AFClipModels.swift" \
    "$SCRIPT_DIR/Sources/Views/FileListView.swift" \
    "$SCRIPT_DIR/Sources/Views/FileRowView.swift" \
    "$SCRIPT_DIR/Sources/Views/HeadlessProgressView.swift"

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

# Copy Sparkle.framework
echo "Copying Sparkle.framework..."
cp -R "$SPARKLE" "$APP_BUNDLE/Contents/Frameworks/"

# Create PkgInfo
echo "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Make the app executable
chmod +x "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

# Code sign — inside-out. Nested helpers first, then framework, then app.
# Hardened runtime + secure timestamp on everything for notarization.
echo "Code signing nested helpers..."
EMBEDDED_SPARKLE="$APP_BUNDLE/Contents/Frameworks/Sparkle.framework"
# Use the concrete versioned dir; Versions/Current is a symlink and find won't descend it.
SPARKLE_VERSION_DIR="$EMBEDDED_SPARKLE/Versions/B"

# Sign every nested bundle (.xpc, .app) inside the framework, deepest first.
find "$SPARKLE_VERSION_DIR" -depth -type d \( -name "*.xpc" -o -name "*.app" \) -print0 \
    | xargs -0 -I {} codesign --force --options runtime --timestamp --sign "$SIGN_ID" "{}"

# Sign loose Mach-O helpers (Autoupdate, fileop) at the framework root.
for helper in Autoupdate fileop; do
    if [ -f "$SPARKLE_VERSION_DIR/$helper" ]; then
        codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$SPARKLE_VERSION_DIR/$helper"
    fi
done

echo "Code signing Sparkle.framework..."
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$EMBEDDED_SPARKLE"

echo "Code signing ADMProgress..."
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP_BUNDLE/Contents/Resources/ADMProgress"

echo "Code signing app bundle..."
codesign --force --options runtime --timestamp --sign "$SIGN_ID" "$APP_BUNDLE"

# Verify all signatures and entitlements before notarization to fail fast locally.
echo "Verifying signatures..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

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

    # Re-register with Launch Services
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "/Applications/$APP_NAME.app"

    echo "Deployed to /Applications/$APP_NAME.app"
else
    echo ""
    echo "To test, run:"
    echo "  open \"$APP_BUNDLE\""
    echo ""
    echo "To deploy to /Applications, run:"
    echo "  ./build.sh --deploy"
fi
