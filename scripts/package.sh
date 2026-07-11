#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"
ruby scripts/generate-xcode-project.rb --check

xcodebuild \
    -project DeskSetupSwitcher.xcodeproj \
    -scheme DeskSetupSwitcher \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$BUILD_DIR/xcode-package" \
    build \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

built_app="$BUILD_DIR/xcode-package/Build/Products/Release/$APP_NAME.app"
if [[ ! -d "$built_app" ]]; then
    echo "Missing Xcode Release app: $built_app" >&2
    exit 1
fi

mkdir -p "$ARTIFACTS_DIR"
staging_root="$(mktemp -d "$ARTIFACTS_DIR/.staging.XXXXXX")"
dmg_root="$staging_root/dmg"
app_bundle="$dmg_root/$APP_NAME.app"
dmg_name="Desk-Setup-Switcher-$VERSION-unsigned.dmg"
dmg_path="$ARTIFACTS_DIR/$dmg_name"
checksum_path="$dmg_path.sha256"
temporary_dmg_path="$staging_root/$dmg_name"
temporary_checksum_path="$staging_root/$dmg_name.sha256"

cleanup() {
    rm -rf "$staging_root"
}
trap cleanup EXIT

mkdir -p "$dmg_root"
ditto "$built_app" "$app_bundle"

# SMAppService requires a valid code signature. An ad-hoc signature is free and
# local: it provides code integrity but no Developer ID identity or notarization.
codesign --force --deep --sign - --timestamp=none "$app_bundle"
codesign --verify --deep --strict "$app_bundle"

ln -s /Applications "$dmg_root/Applications"

plutil -lint "$app_bundle/Contents/Info.plist"
if [[ ! -x "$app_bundle/Contents/MacOS/$EXECUTABLE_NAME" ]]; then
    echo "Packaged app executable is missing before DMG creation." >&2
    exit 1
fi

architectures="$(lipo -archs "$app_bundle/Contents/MacOS/$EXECUTABLE_NAME")"
for architecture in arm64 x86_64; do
    if [[ " $architectures " != *" $architecture "* ]]; then
        echo "Universal binary is missing $architecture: $architectures" >&2
        exit 1
    fi
done

hdiutil create \
    -quiet \
    -format UDZO \
    -volname "$APP_NAME" \
    -srcfolder "$dmg_root" \
    "$temporary_dmg_path"

checksum="$(shasum -a 256 "$temporary_dmg_path" | awk '{print $1}')"
printf '%s  %s\n' "$checksum" "$dmg_name" >"$temporary_checksum_path"
chmod 0644 "$temporary_dmg_path" "$temporary_checksum_path"

mv -f "$temporary_checksum_path" "$checksum_path"
mv -f "$temporary_dmg_path" "$dmg_path"
printf 'Created %s\nCreated %s\n' "$dmg_path" "$checksum_path"
