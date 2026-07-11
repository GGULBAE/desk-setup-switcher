#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

dmg_name="Desk-Setup-Switcher-$VERSION-unsigned.dmg"
dmg_path="${1:-$ARTIFACTS_DIR/$dmg_name}"
checksum_path="$dmg_path.sha256"

if [[ ! -f "$dmg_path" || ! -f "$checksum_path" ]]; then
    echo "Package or checksum is missing. Run make package first." >&2
    exit 1
fi

line_count="$(wc -l <"$checksum_path" | tr -d '[:space:]')"
if [[ "$line_count" != 1 ]]; then
    echo "Checksum file must contain exactly one newline-terminated entry." >&2
    exit 1
fi

IFS=' ' read -r expected_checksum expected_name unexpected_field <"$checksum_path"
if [[ ! "$expected_checksum" =~ ^[0-9a-f]{64}$ || "$expected_name" != "$(basename "$dmg_path")" || -n "$unexpected_field" ]]; then
    echo "Checksum file has an invalid SHA-256 entry." >&2
    exit 1
fi

actual_checksum="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
if [[ "$actual_checksum" != "$expected_checksum" ]]; then
    echo "SHA-256 mismatch for $dmg_path." >&2
    exit 1
fi
printf '%s: OK\n' "$(basename "$dmg_path")"

mount_point="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-switcher.XXXXXX")"
attached=false

cleanup() {
    if [[ "$attached" == true ]]; then
        hdiutil detach -quiet "$mount_point" || true
    fi
    rmdir "$mount_point" 2>/dev/null || true
}
trap cleanup EXIT

hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path"
attached=true

app_bundle="$mount_point/$APP_NAME.app"
app_binary="$app_bundle/Contents/MacOS/$EXECUTABLE_NAME"
app_plist="$app_bundle/Contents/Info.plist"
resources_directory="$app_bundle/Contents/Resources"

[[ -x "$app_binary" ]] || { echo "DMG app executable is missing." >&2; exit 1; }
[[ -L "$mount_point/Applications" ]] || { echo "DMG Applications link is missing." >&2; exit 1; }
[[ "$(readlink "$mount_point/Applications")" == /Applications ]] || {
    echo "DMG Applications link has the wrong destination." >&2
    exit 1
}

plutil -lint "$app_plist"
architectures="$(lipo -archs "$app_binary")"
for architecture in arm64 x86_64; do
    [[ " $architectures " == *" $architecture "* ]] || {
        echo "Packaged executable is missing $architecture: $architectures" >&2
        exit 1
    }
done

packaged_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$app_plist"
}

assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(packaged_plist_value "$key")"
    if [[ "$actual" != "$expected" ]]; then
        echo "Packaged $key is $actual; expected $expected." >&2
        exit 1
    fi
}

assert_plist_value CFBundleDisplayName "$APP_NAME"
assert_plist_value CFBundleExecutable "$EXECUTABLE_NAME"
assert_plist_value CFBundleIdentifier "$BUNDLE_IDENTIFIER"
assert_plist_value CFBundlePackageType APPL
assert_plist_value CFBundleShortVersionString "$VERSION"
assert_plist_value CFBundleVersion "$BUILD_NUMBER"
assert_plist_value LSMinimumSystemVersion "$MINIMUM_SYSTEM_VERSION"
assert_plist_value LSUIElement true
assert_plist_value NSLocationWhenInUseUsageDescription "$(plist_value NSLocationWhenInUseUsageDescription)"

icon_file="$(packaged_plist_value CFBundleIconFile)"
if [[ "$icon_file" != *.icns ]]; then
    icon_file="$icon_file.icns"
fi
[[ -f "$resources_directory/$icon_file" ]] || {
    echo "Packaged icon is missing: $icon_file" >&2
    exit 1
}

for localization in en ko; do
    for strings_name in InfoPlist Localizable; do
        strings_file="$resources_directory/$localization.lproj/$strings_name.strings"
        [[ -f "$strings_file" ]] || {
            echo "Packaged $localization $strings_name localization is missing." >&2
            exit 1
        }
        plutil -lint "$strings_file"
    done
    info_strings="$resources_directory/$localization.lproj/InfoPlist.strings"
    for usage_key in NSLocationUsageDescription NSLocationWhenInUseUsageDescription; do
        localized_usage="$(plutil -extract "$usage_key" raw -o - "$info_strings")"
        [[ -n "$localized_usage" ]] || {
            echo "Packaged $localization $usage_key localization is empty." >&2
            exit 1
        }
    done
done

signature_details="$(codesign --display --verbose=4 "$app_bundle" 2>&1 || true)"
if printf '%s\n' "$signature_details" | grep -q '^Authority='; then
    echo "Package is named unsigned but contains an identity-signed app." >&2
    exit 1
fi
codesign --verify --deep --strict "$app_bundle"
if ! printf '%s\n' "$signature_details" | grep -q '^Signature=adhoc$'; then
    echo "Packaged app must carry an ad-hoc integrity signature for SMAppService." >&2
    exit 1
fi

printf 'Verified %s (%s)\n' "$dmg_path" "$architectures"
