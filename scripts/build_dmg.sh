#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PROJECT_PATH="$ROOT_DIR/Vidarr.xcodeproj"
SCHEME="Vidarr"
CONFIGURATION="Release"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$ROOT_DIR/build/DerivedData}"
PRODUCTS_DIR="$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION"
APP_NAME="Vidarr.app"
APP_PATH="$PRODUCTS_DIR/$APP_NAME"
OUTPUT_DIR="$ROOT_DIR/build/dist"
STAGING_DIR="$ROOT_DIR/build/dmg-root"

VERSION_TAG="${1:-local}"
RELEASE_VERSION=""
BUILD_VERSION_ARGS=()
SIGNING_IDENTITY="${SIGNING_IDENTITY:-Developer ID Application}"
TEAM_ID="${DEVELOPMENT_TEAM:-PA8WHP7G46}"

if [[ "$VERSION_TAG" != "local" ]]; then
  if [[ "$VERSION_TAG" =~ ^[vV]([0-9]+(\.[0-9]+){1,2})$ ]]; then
    RELEASE_VERSION="${BASH_REMATCH[1]}"
    BUILD_VERSION_ARGS+=("MARKETING_VERSION=$RELEASE_VERSION")
  else
    echo "Release version must look like v0.1.12: $VERSION_TAG" >&2
    exit 1
  fi
fi

if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi

if ! xcrun --find notarytool >/dev/null 2>&1; then
  echo "A full Xcode installation with notarytool is required." >&2
  exit 1
fi

if ! security find-identity -v -p codesigning | grep -Fq "${SIGNING_IDENTITY}"; then
  echo "Signing identity not found: $SIGNING_IDENTITY" >&2
  exit 1
fi

DMG_NAME="Vidarr-${VERSION_TAG}.dmg"
DMG_PATH="$OUTPUT_DIR/$DMG_NAME"

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
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  ENABLE_HARDENED_RUNTIME=YES \
  OTHER_CODE_SIGN_FLAGS="--timestamp" \
  "${BUILD_VERSION_ARGS[@]}" \
  clean build

if [[ ! -d "$APP_PATH" ]]; then
  echo "App bundle not found: $APP_PATH" >&2
  exit 1
fi

if [[ -n "$RELEASE_VERSION" ]]; then
  BUNDLED_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
  if [[ "$BUNDLED_VERSION" != "$RELEASE_VERSION" ]]; then
    echo "Release tag and bundled app version do not match: $VERSION_TAG != $BUNDLED_VERSION" >&2
    exit 1
  fi
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

mkdir -p "$STAGING_DIR"
ditto "$APP_PATH" "$STAGING_DIR/$APP_NAME"
ln -s /Applications "$STAGING_DIR/Applications"

rm -f "$DMG_PATH"
if command -v create-dmg >/dev/null 2>&1; then
  create-dmg \
    --volname "Vidarr" \
    --window-pos 200 120 \
    --window-size 720 420 \
    --icon-size 120 \
    --icon "$APP_NAME" 200 220 \
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

codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
codesign --verify --strict --verbose=2 "$DMG_PATH"

if [[ -n "${NOTARYTOOL_PROFILE:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARYTOOL_PROFILE" \
    --wait
elif [[ -n "${NOTARY_API_KEY_PATH:-}" && -n "${NOTARY_API_KEY_ID:-}" && -n "${NOTARY_API_ISSUER_ID:-}" ]]; then
  xcrun notarytool submit "$DMG_PATH" \
    --key "$NOTARY_API_KEY_PATH" \
    --key-id "$NOTARY_API_KEY_ID" \
    --issuer "$NOTARY_API_ISSUER_ID" \
    --wait
else
  echo "Notarization credentials are required (NOTARYTOOL_PROFILE or App Store Connect API key variables)." >&2
  exit 1
fi

xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"

echo "Created, signed, notarized, and stapled: $DMG_PATH"
