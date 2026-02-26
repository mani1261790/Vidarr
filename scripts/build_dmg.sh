#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Vidarr.xcodeproj"
SCHEME="Vidarr"
CONFIGURATION="Release"
DERIVED_DATA_PATH="$ROOT_DIR/build/DerivedData"
PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_NAME="Vidarr.app"
APP_PATH="$PRODUCTS_DIR/$APP_NAME"

VERSION_TAG="${1:-local}"
OUTPUT_DIR="$ROOT_DIR/build/dist"
DMG_NAME="Vidarr-${VERSION_TAG}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"
STAGING_DIR="$ROOT_DIR/build/dmg-root"
FIRST_LAUNCH_HELPER_NAME="2) First Launch Fix.command"

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_PATH"
rm -rf "$STAGING_DIR"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  -jobs 1 \
  CODE_SIGNING_ALLOWED=NO \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

# Re-sign ad-hoc so Gatekeeper does not treat the bundle as malformed/damaged.
codesign --force --deep --sign - "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

# Prepare DMG root: app + Applications link.
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

cat > "$STAGING_DIR/$FIRST_LAUNCH_HELPER_NAME" <<'EOF'
#!/bin/bash
set -euo pipefail

APP_PATH="/Applications/Vidarr.app"

if [[ ! -d "$APP_PATH" ]]; then
  osascript -e 'display dialog "Vidarr.app が /Applications に見つかりません。先にDMGから Applications へコピーしてください。" buttons {"OK"} default button "OK" with title "Vidarr"'
  exit 1
fi

xattr -dr com.apple.quarantine "$APP_PATH"
open "$APP_PATH"
osascript -e 'display dialog "初回保護解除を実行しました。Vidarr を起動します。" buttons {"OK"} default button "OK" with title "Vidarr"'
EOF
chmod +x "$STAGING_DIR/$FIRST_LAUNCH_HELPER_NAME"

rm -f "$DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Vidarr" \
    --window-pos 200 120 \
    --window-size 720 420 \
    --icon-size 120 \
    --icon "$APP_NAME" 200 220 \
    --icon "Applications" 520 220 \
    --icon "$FIRST_LAUNCH_HELPER_NAME" 360 335 \
    --app-drop-link 520 220 \
    --hide-extension "$APP_NAME" \
    --no-internet-enable \
    "$DMG_PATH" \
    "$STAGING_DIR"
else
  hdiutil create \
    -volname "Vidarr" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"
fi

echo "Created: $DMG_PATH"
