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

mkdir -p "$OUTPUT_DIR"
rm -rf "$DERIVED_DATA_PATH"

xcodebuild \
  -project "$PROJECT_PATH" \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  build

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

rm -f "$DMG_PATH"
hdiutil create \
  -volname "Vidarr" \
  -srcfolder "$APP_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

echo "Created: $DMG_PATH"
