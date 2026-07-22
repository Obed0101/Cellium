#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_PATH="${PROJECT_PATH:-$ROOT_DIR/Cellium.xcodeproj}"
SCHEME="${SCHEME:-Cellium}"
CONFIGURATION="${CONFIGURATION:-Release}"
ARCHS="${ARCHS:-arm64}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT_DIR/.build/CelliumInstallerDerivedData}"
OUTPUT_DIR="${OUTPUT_DIR:-$ROOT_DIR/Distribution}"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/App/Info.plist")}"
DMG_PATH="${OUTPUT_PATH:-$OUTPUT_DIR/Cellium-${VERSION}.dmg}"

if ! command -v hdiutil >/dev/null 2>&1; then
    printf '%s\n' 'hdiutil is required on macOS.' >&2
    exit 1
fi

if [[ -e "$DMG_PATH" ]]; then
    printf 'Refusing to overwrite existing disk image: %s\n' "$DMG_PATH" >&2
    printf '%s\n' 'Set OUTPUT_PATH to a new location or move the old artifact to Trash first.' >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"

CODE_SIGNING_ALLOWED="${CODE_SIGNING_ALLOWED:-NO}"
CODE_SIGNING_REQUIRED="${CODE_SIGNING_REQUIRED:-NO}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

xcodebuild \
    -project "$PROJECT_PATH" \
    -scheme "$SCHEME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath "$DERIVED_DATA" \
    ARCHS="$ARCHS" \
    CODE_SIGNING_ALLOWED="$CODE_SIGNING_ALLOWED" \
    CODE_SIGNING_REQUIRED="$CODE_SIGNING_REQUIRED" \
    CODE_SIGN_IDENTITY="$CODE_SIGN_IDENTITY" \
    build

APP_PATH="$DERIVED_DATA/Build/Products/$CONFIGURATION/Cellium.app"
if [[ ! -d "$APP_PATH" ]]; then
    printf 'Built app was not found at %s\n' "$APP_PATH" >&2
    exit 1
fi

# mktemp keeps each staging directory isolated. It is intentionally left in the
# system temporary directory so the script never removes user files.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cellium-dmg.XXXXXX")"
DITTO_OPTIONS=(--norsrc --noqtn)

ditto "${DITTO_OPTIONS[@]}" "$APP_PATH" "$STAGING_DIR/Cellium.app"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "Cellium $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

printf '\nCreated installer:\n%s\n' "$DMG_PATH"
printf 'Open it with: open %q\n' "$DMG_PATH"
