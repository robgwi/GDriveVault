#!/usr/bin/env bash
set -euo pipefail

APP_NAME="GDriveVault"
BUNDLE_ID="com.gdrivevault.agent"
MIN_MACOS="14.0"
VERSION="${VERSION:-1.3.5}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"
CONFIGURATION="${CONFIGURATION:-release}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="${TMPDIR:-/tmp}/gdrivevault-package-$VERSION"
APP_DIR="$STAGING_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
ZIP_PATH="$DIST_DIR/$APP_NAME-mac-arm64-$VERSION.zip"
ICON_SOURCE="$ROOT_DIR/Sources/GoogleDriveClone/Resources/Images/gdrivevault-app-icon.png"
ICONSET_DIR="$STAGING_DIR/$APP_NAME.iconset"
ICON_PATH="$RESOURCES_DIR/$APP_NAME.icns"

strip_signing_xattrs() {
  local path="$1"
  xattr -cr "$path" 2>/dev/null || true
  find "$path" -exec xattr -c {} \; 2>/dev/null || true
  find "$path" -print0 | xargs -0 -n 1 xattr -d com.apple.FinderInfo 2>/dev/null || true
  find "$path" -print0 | xargs -0 -n 1 xattr -d "com.apple.fileprovider.fpfs#P" 2>/dev/null || true
  find "$path" -print0 | xargs -0 -n 1 xattr -d com.apple.ResourceFork 2>/dev/null || true
  find "$path" -print0 | xargs -0 -n 1 xattr -d com.apple.provenance 2>/dev/null || true
}

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

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "Missing app icon source: $ICON_SOURCE" >&2
  exit 1
fi

echo "Creating app bundle..."
rm -rf "$STAGING_DIR" "$ZIP_PATH"
mkdir -p "$DIST_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$APP_NAME"
cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/"

echo "Creating app icon..."
mkdir -p "$ICONSET_DIR"
sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
iconutil -c icns "$ICONSET_DIR" -o "$ICON_PATH"
rm -rf "$ICONSET_DIR"

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
  <key>CFBundleIconFile</key>
  <string>$APP_NAME</string>
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

strip_signing_xattrs "$APP_DIR"

echo "Signing app with identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_DIR"
strip_signing_xattrs "$APP_DIR"

echo "Verifying signature..."
codesign --verify --deep --strict "$APP_DIR"

echo "Creating installer zip..."
ditto -c -k --norsrc --keepParent "$APP_DIR" "$ZIP_PATH"

echo
echo "Packaged app:"
echo "  $APP_DIR"
echo
echo "Install zip:"
echo "  $ZIP_PATH"
echo
echo "Copy the zip to another Mac, unzip it, drag $APP_NAME.app into /Applications, and make sure rclone is installed."
