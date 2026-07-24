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

# A local build gets a valid ad-hoc bundle signature by default. This avoids
# shipping an app whose linker-only signature makes Gatekeeper report it as
# damaged. Ad-hoc signing is not Apple verification; Developer ID signing
# remains available for a notarized distribution.
if [[ -z "${SIGNING_MODE:-}" ]]; then
    if [[ "$CODE_SIGNING_ALLOWED" == "YES" ]]; then
        SIGNING_MODE="developer-id"
    else
        SIGNING_MODE="adhoc"
    fi
fi

case "$SIGNING_MODE" in
    adhoc|developer-id|none)
        ;;
    *)
        printf 'Unsupported SIGNING_MODE: %s (use adhoc, developer-id, or none)\n' "$SIGNING_MODE" >&2
        exit 1
        ;;
esac

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

case "$SIGNING_MODE" in
    adhoc)
        # CODE_SIGNING_ALLOWED=NO can leave only a linker signature on the
        # executable. Sign the complete bundle so its resources are sealed.
        /usr/bin/codesign --force --deep --sign - "$APP_PATH"
        ;;
    developer-id)
        if [[ "$CODE_SIGNING_ALLOWED" != "YES" || "$CODE_SIGNING_REQUIRED" != "YES" || "$CODE_SIGN_IDENTITY" == "-" ]]; then
            printf '%s\n' 'developer-id signing requires CODE_SIGNING_ALLOWED=YES, CODE_SIGNING_REQUIRED=YES, and a Developer ID identity.' >&2
            exit 1
        fi
        ;;
    none)
        printf '%s\n' 'Warning: building an unsigned app bundle; it is not suitable for distribution.' >&2
        ;;
esac

if [[ "$SIGNING_MODE" != "none" ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$APP_PATH"
fi

# mktemp keeps each staging directory isolated. It is intentionally left in the
# system temporary directory so the script never removes user files.
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/cellium-dmg.XXXXXX")"
DITTO_OPTIONS=(--norsrc --noqtn)

ditto "${DITTO_OPTIONS[@]}" "$APP_PATH" "$STAGING_DIR/Cellium.app"
if [[ "$SIGNING_MODE" != "none" ]]; then
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$STAGING_DIR/Cellium.app"
fi
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "Cellium $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -format UDZO \
    -imagekey zlib-level=9 \
    "$DMG_PATH"

hdiutil verify "$DMG_PATH"

printf '\nCreated installer:\n%s\n' "$DMG_PATH"
printf 'Open it with: open %q\n' "$DMG_PATH"
