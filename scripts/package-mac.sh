#!/usr/bin/env bash
set -euo pipefail

APP_NAME="GDriveVault"
BUNDLE_ID="com.gdrivevault.agent"
MIN_MACOS="14.0"
VERSION="${VERSION:-1.0.0}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/$APP_NAME-mac-arm64-$VERSION.zip"

echo "Building $APP_NAME ($CONFIGURATION)..."
cd "$ROOT_DIR"
mkdir -p "$ROOT_DIR/.build/module-cache" "$ROOT_DIR/.build/swiftpm-cache"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_HOME="$ROOT_DIR/.build/swiftpm-cache"
swift build -c "$CONFIGURATION" --scratch-path "$ROOT_DIR/.build"

EXECUTABLE_PATH="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE_PATH="$BUILD_DIR/${APP_NAME}_GoogleDriveClone.bundle"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing built executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -d "$RESOURCE_BUNDLE_PATH" ]]; then
  echo "Missing SwiftPM resource bundle: $RESOURCE_BUNDLE_PATH" >&2
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$APP_DIR" "$ZIP_PATH"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_MACOS</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

echo "Signing app with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"

echo "Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"

echo "Creating installer zip..."
ditto -c -k --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Packaged app:"
echo "  $APP_DIR"
echo
echo "Install zip:"
echo "  $ZIP_PATH"
echo
echo "Copy the zip to another Mac, unzip it, drag $APP_NAME.app into /Applications, and make sure rclone is installed."
