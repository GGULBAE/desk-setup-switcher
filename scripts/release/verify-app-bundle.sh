#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ "$#" == 1 ]] || release_die "Usage: verify-app-bundle.sh APP_BUNDLE"
app_bundle="$1"
app_binary="$app_bundle/Contents/MacOS/$EXECUTABLE_NAME"
app_plist="$app_bundle/Contents/Info.plist"
resources_directory="$app_bundle/Contents/Resources"

release_require_command file

[[ -d "$app_bundle" && ! -L "$app_bundle" ]] || release_die "Release app bundle is missing or is a symlink."
[[ -x "$app_binary" && ! -L "$app_binary" ]] || release_die "Release executable is missing or is a symlink."
[[ -f "$app_plist" && ! -L "$app_plist" ]] || release_die "Release Info.plist is missing or is a symlink."

plutil -lint "$app_plist" >/dev/null

packaged_plist_value() {
    /usr/libexec/PlistBuddy -c "Print :$1" "$app_plist"
}

assert_plist_value() {
    local key="$1"
    local expected="$2"
    local actual
    actual="$(packaged_plist_value "$key")"
    [[ "$actual" == "$expected" ]] || {
        release_die "Release $key is $actual; expected $expected."
    }
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

architectures="$(lipo -archs "$app_binary")"
for architecture in arm64 x86_64; do
    [[ " $architectures " == *" $architecture "* ]] || {
        release_die "Release executable is missing $architecture: $architectures"
    }
done

icon_file="$(packaged_plist_value CFBundleIconFile)"
if [[ "$icon_file" != *.icns ]]; then
    icon_file="$icon_file.icns"
fi
[[ -f "$resources_directory/$icon_file" && ! -L "$resources_directory/$icon_file" ]] || {
    release_die "Release icon is missing: $icon_file"
}

for localization in en ko; do
    for strings_name in InfoPlist Localizable; do
        strings_file="$resources_directory/$localization.lproj/$strings_name.strings"
        [[ -f "$strings_file" && ! -L "$strings_file" ]] || {
            release_die "Release $localization $strings_name localization is missing."
        }
        plutil -lint "$strings_file" >/dev/null
    done
    info_strings="$resources_directory/$localization.lproj/InfoPlist.strings"
    for usage_key in NSLocationUsageDescription NSLocationWhenInUseUsageDescription; do
        localized_usage="$(plutil -extract "$usage_key" raw -o - "$info_strings")"
        [[ -n "$localized_usage" ]] || {
            release_die "Release $localization $usage_key localization is empty."
        }
    done
done

for nested_directory in Frameworks PlugIns XPCServices Helpers Library/LoginItems; do
    [[ ! -e "$app_bundle/Contents/$nested_directory" ]] || {
        release_die "Unexpected nested code requires an explicit inside-out signing policy: $nested_directory"
    }
done

unexpected_executable="$({
    find "$app_bundle/Contents" -type f -perm -111 -print
} | while IFS= read -r path; do
    [[ "$path" == "$app_binary" ]] || printf '%s\n' "$path"
done)"
[[ -z "$unexpected_executable" ]] || {
    release_die "Unexpected executable file exists inside the release app."
}

unexpected_mach_o="$({
    find "$app_bundle/Contents" -type f -print0
} | while IFS= read -r -d '' path; do
    [[ "$path" == "$app_binary" ]] && continue
    description="$(file -b "$path")"
    if [[ "$description" == *Mach-O* ]]; then
        printf '%s\n' "$path"
    fi
done)"
[[ -z "$unexpected_mach_o" ]] || {
    release_die "Unexpected Mach-O code exists inside the release app."
}

printf 'Verified release app metadata and resources (%s).\n' "$architectures"
