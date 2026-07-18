#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

release_require_execution_context
"$RELEASE_SCRIPTS_DIR/preflight.sh"

release_require_single_line DEVELOPER_ID_APPLICATION
release_require_single_line APPLE_TEAM_ID
release_require_single_line APPLE_NOTARY_KEY_ID
release_require_single_line APPLE_NOTARY_ISSUER_ID
release_require_env APPLE_NOTARY_API_KEY_BASE64
release_require_env RELEASE_SIGNING_KEYCHAIN
release_require_env GITHUB_RUN_ATTEMPT
release_require_env GITHUB_SERVER_URL

[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || release_die "APPLE_TEAM_ID has an invalid format."
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]] || {
    release_die "The Developer ID identity does not match APPLE_TEAM_ID."
}
[[ "$APPLE_NOTARY_KEY_ID" =~ ^[A-Z0-9]{10,}$ ]] || release_die "APPLE_NOTARY_KEY_ID has an invalid format."
[[ "$APPLE_NOTARY_ISSUER_ID" =~ ^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$ ]] || {
    release_die "APPLE_NOTARY_ISSUER_ID must be a UUID."
}
release_require_path_within "$RELEASE_SIGNING_KEYCHAIN" "$RUNNER_TEMP"
[[ -f "$RELEASE_SIGNING_KEYCHAIN" ]] || release_die "Ephemeral release Keychain is missing."

for command in codesign ditto file hdiutil lipo openssl plutil ruby security shasum spctl swift xcodebuild xcrun; do
    release_require_command "$command"
done

cd "$ROOT_DIR"
ruby scripts/generate-xcode-project.rb --check
plutil -lint Config/ReleaseEntitlements.plist >/dev/null
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements \
    --plist Config/ReleaseEntitlements.plist

release_directory="$ARTIFACTS_DIR/release"
release_require_absent_path "$release_directory"
mkdir -p "$ARTIFACTS_DIR"
staging_root="$(mktemp -d "$ARTIFACTS_DIR/.signed-release.XXXXXX")"
derived_data="$staging_root/DerivedData"
signed_app="$staging_root/signed/$APP_NAME.app"
dmg_root="$staging_root/dmg-root"
output_directory="$staging_root/output"
mount_point="$staging_root/mount"
pre_notary_dmg="$staging_root/pre-notary.dmg"
notary_key="$RUNNER_TEMP/desk-setup-notary-api-key.p8"
attached=false

cleanup() {
    unset APPLE_NOTARY_API_KEY_BASE64 || true
    if [[ "$attached" == true ]]; then
        hdiutil detach -quiet "$mount_point" >/dev/null 2>&1 || true
    fi
    rm -f "$notary_key"
    rm -rf "$staging_root"
}
trap cleanup EXIT

mkdir -p "$(dirname "$signed_app")" "$dmg_root" "$output_directory" "$mount_point"

xcodebuild \
    -project DeskSetupSwitcher.xcodeproj \
    -scheme DeskSetupSwitcher \
    -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$derived_data" \
    build \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    GCC_TREAT_WARNINGS_AS_ERRORS=YES \
    SWIFT_TREAT_WARNINGS_AS_ERRORS=YES

built_app="$derived_data/Build/Products/Release/$APP_NAME.app"
[[ -d "$built_app" ]] || release_die "Xcode did not produce the Release app."
ditto "$built_app" "$signed_app"
"$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$signed_app"

codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --keychain "$RELEASE_SIGNING_KEYCHAIN" \
    --identifier "$BUNDLE_IDENTIFIER" \
    --options runtime \
    --timestamp \
    "$signed_app"
app_codesign_verify="$staging_root/app-codesign-verify.txt"
codesign --verify --deep --strict --all-architectures --verbose=2 "$signed_app" >"$app_codesign_verify" 2>&1

app_codesign_report_arguments=()
for architecture in arm64 x86_64; do
    app_codesign_report="$staging_root/app-codesign-$architecture.txt"
    codesign --display --verbose=4 --architecture "$architecture" "$signed_app" >"$app_codesign_report" 2>&1
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-codesign \
        --report "$app_codesign_report" \
        --authority "$DEVELOPER_ID_APPLICATION" \
        --team-id "$APPLE_TEAM_ID" \
        --identifier "$BUNDLE_IDENTIFIER" \
        --kind app \
        --architecture "$architecture"
    app_codesign_report_arguments+=(--app-codesign-report "$architecture=$app_codesign_report")
done

designated_requirement="$staging_root/app-designated-requirement.txt"
codesign --display --requirements - "$signed_app" >"$designated_requirement" 2>&1
grep -q 'designated =>' "$designated_requirement" || release_die "Signed app designated requirement is missing."

app_entitlements="$staging_root/app-entitlements.plist"
codesign --display --entitlements - --xml "$signed_app" >"$app_entitlements" 2>"$staging_root/app-entitlements.stderr"
if [[ -s "$app_entitlements" ]]; then
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements --plist "$app_entitlements"
else
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements --absent
fi

signed_app_manifest="$staging_root/signed-app-manifest.json"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-bundle-manifest \
    --app "$signed_app" \
    --output "$signed_app_manifest"

packaged_app="$dmg_root/$APP_NAME.app"
ditto "$signed_app" "$packaged_app"
packaged_app_manifest="$staging_root/packaged-app-manifest.json"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-bundle-manifest \
    --app "$packaged_app" \
    --output "$packaged_app_manifest"
cmp -s "$signed_app_manifest" "$packaged_app_manifest" || {
    release_die "The app changed while entering the DMG staging tree."
}
ln -s /Applications "$dmg_root/Applications"

dmg_name="Desk-Setup-Switcher-$VERSION.dmg"
dmg_path="$output_directory/$dmg_name"
checksum_path="$output_directory/$dmg_name.sha256"
sbom_path="$output_directory/Desk-Setup-Switcher-$VERSION.spdx.json"
manifest_path="$output_directory/release-manifest.json"
notary_result_path="$output_directory/notary-result.json"
notary_log_path="$output_directory/notary-log.json"

hdiutil create \
    -quiet \
    -format UDZO \
    -volname "$APP_NAME" \
    -srcfolder "$dmg_root" \
    "$dmg_path"

dmg_identifier="$BUNDLE_IDENTIFIER.dmg"
codesign \
    --force \
    --sign "$DEVELOPER_ID_APPLICATION" \
    --keychain "$RELEASE_SIGNING_KEYCHAIN" \
    --identifier "$dmg_identifier" \
    --timestamp \
    "$dmg_path"
pre_notary_dmg_codesign_verify="$staging_root/pre-notary-dmg-codesign-verify.txt"
codesign --verify --strict --verbose=2 "$dmg_path" >"$pre_notary_dmg_codesign_verify" 2>&1

pre_notary_dmg_codesign_report="$staging_root/pre-notary-dmg-codesign.txt"
codesign --display --verbose=4 "$dmg_path" >"$pre_notary_dmg_codesign_report" 2>&1
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-codesign \
    --report "$pre_notary_dmg_codesign_report" \
    --authority "$DEVELOPER_ID_APPLICATION" \
    --team-id "$APPLE_TEAM_ID" \
    --identifier "$dmg_identifier" \
    --kind dmg
"$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh"

hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path"
attached=true
"$RELEASE_SCRIPTS_DIR/compare-bundle-manifest.sh" \
    "$signed_app_manifest" \
    "$mount_point/$APP_NAME.app"
hdiutil detach -quiet "$mount_point"
attached=false

cp "$dmg_path" "$pre_notary_dmg"

umask 077
release_require_absent_path "$notary_key"
printf '%s' "$APPLE_NOTARY_API_KEY_BASE64" | openssl base64 -d -A -out "$notary_key"
unset APPLE_NOTARY_API_KEY_BASE64
[[ -s "$notary_key" ]] || release_die "Notary API key could not be decoded."
grep -q '^-----BEGIN PRIVATE KEY-----$' "$notary_key" || release_die "Notary API key has an invalid PEM format."

raw_notary_result="$staging_root/notary-result.raw.json"
raw_notary_log="$staging_root/notary-log.raw.json"
xcrun notarytool submit "$dmg_path" \
    --key "$notary_key" \
    --key-id "$APPLE_NOTARY_KEY_ID" \
    --issuer "$APPLE_NOTARY_ISSUER_ID" \
    --wait \
    --timeout 45m \
    --no-progress \
    --output-format json >"$raw_notary_result"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-notary --json "$raw_notary_result"
submission_id="$(ruby -rjson -e 'puts JSON.parse(File.read(ARGV.fetch(0))).fetch("id")' "$raw_notary_result")"
xcrun notarytool log "$submission_id" "$raw_notary_log" \
    --key "$notary_key" \
    --key-id "$APPLE_NOTARY_KEY_ID" \
    --issuer "$APPLE_NOTARY_ISSUER_ID"
rm -f "$notary_key"

release_sanitize_json "$raw_notary_result" "$notary_result_path"
release_sanitize_json "$raw_notary_log" "$notary_log_path"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-notary --json "$notary_result_path"

stapler_output="$staging_root/stapler-validate.txt"
xcrun stapler staple "$dmg_path"
xcrun stapler validate "$dmg_path" >"$stapler_output" 2>&1

final_dmg_codesign_verify="$staging_root/final-dmg-codesign-verify.txt"
codesign --verify --strict --verbose=2 "$dmg_path" >"$final_dmg_codesign_verify" 2>&1
final_dmg_codesign_report="$staging_root/final-dmg-codesign.txt"
codesign --display --verbose=4 "$dmg_path" >"$final_dmg_codesign_report" 2>&1
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-codesign \
    --report "$final_dmg_codesign_report" \
    --authority "$DEVELOPER_ID_APPLICATION" \
    --team-id "$APPLE_TEAM_ID" \
    --identifier "$dmg_identifier" \
    --kind dmg

spctl_dmg_output="$staging_root/spctl-dmg.txt"
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$dmg_path" >"$spctl_dmg_output" 2>&1

hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path"
attached=true
mounted_app="$mount_point/$APP_NAME.app"
"$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$mounted_app"
"$RELEASE_SCRIPTS_DIR/compare-bundle-manifest.sh" "$signed_app_manifest" "$mounted_app"
mounted_app_codesign_verify="$staging_root/mounted-app-codesign-verify.txt"
codesign --verify --deep --strict --all-architectures --verbose=2 "$mounted_app" >"$mounted_app_codesign_verify" 2>&1

for architecture in arm64 x86_64; do
    mounted_app_codesign_report="$staging_root/mounted-app-codesign-$architecture.txt"
    codesign --display --verbose=4 --architecture "$architecture" "$mounted_app" >"$mounted_app_codesign_report" 2>&1
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-codesign \
        --report "$mounted_app_codesign_report" \
        --authority "$DEVELOPER_ID_APPLICATION" \
        --team-id "$APPLE_TEAM_ID" \
        --identifier "$BUNDLE_IDENTIFIER" \
        --kind app \
        --architecture "$architecture"
done

mounted_entitlements="$staging_root/mounted-app-entitlements.plist"
codesign --display --entitlements - --xml "$mounted_app" >"$mounted_entitlements" 2>"$staging_root/mounted-entitlements.stderr"
if [[ -s "$mounted_entitlements" ]]; then
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements --plist "$mounted_entitlements"
else
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements --absent
fi

spctl_app_output="$staging_root/spctl-app.txt"
spctl --assess --type execute --verbose=4 "$mounted_app" >"$spctl_app_output" 2>&1
hdiutil detach -quiet "$mount_point"
attached=false

final_dmg_sha="$(release_sha256 "$dmg_path")"
final_dmg_size="$(stat -f %z "$dmg_path")"
printf '%s  %s\n' "$final_dmg_sha" "$dmg_name" >"$checksum_path"
chmod 0644 "$dmg_path" "$checksum_path" "$notary_result_path" "$notary_log_path"

package_dump="$staging_root/package-dump.json"
swift package dump-package >"$package_dump"
created_at="$(ruby -rtime -e 'puts Time.parse(ARGV.fetch(0)).utc.iso8601' "$(git show -s --format=%cI "$EXPECTED_COMMIT")")"
sbom_namespace="https://github.com/GGULBAE/desk-setup-switcher/sbom/$RELEASE_TAG/$final_dmg_sha"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-sbom \
    --dmg "$dmg_path" \
    --sha256 "$final_dmg_sha" \
    --size "$final_dmg_size" \
    --version "$VERSION" \
    --tag "$RELEASE_TAG" \
    --commit "$EXPECTED_COMMIT" \
    --namespace "$sbom_namespace" \
    --created "$created_at" \
    --package-dump "$package_dump" \
    --output "$sbom_path"

xcode_version="$(xcodebuild -version | paste -sd ';' -)"
swift_version="$(swift --version | head -n 1)"
runner_macos="$(sw_vers -productVersion)"
sdk_version="$(xcrun --show-sdk-version)"
runner_architecture="$(uname -m)"
run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
manifest_namespace="https://github.com/GGULBAE/desk-setup-switcher/release-evidence/$RELEASE_TAG/$final_dmg_sha"

sanitized_app_codesign="$staging_root/app-codesign-verify.sanitized.txt"
sanitized_dmg_codesign="$staging_root/dmg-codesign-verify.sanitized.txt"
sanitized_designated_requirement="$staging_root/app-designated-requirement.sanitized.txt"
sanitized_stapler="$staging_root/stapler-validate.sanitized.txt"
sanitized_spctl_dmg="$staging_root/spctl-dmg.sanitized.txt"
sanitized_spctl_app="$staging_root/spctl-app.sanitized.txt"
release_sanitize_text "$app_codesign_verify" "$sanitized_app_codesign"
release_sanitize_text "$final_dmg_codesign_verify" "$sanitized_dmg_codesign"
release_sanitize_text "$designated_requirement" "$sanitized_designated_requirement"
release_sanitize_text "$stapler_output" "$sanitized_stapler"
release_sanitize_text "$spctl_dmg_output" "$sanitized_spctl_dmg"
release_sanitize_text "$spctl_app_output" "$sanitized_spctl_app"

ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-release-manifest \
    --version "$VERSION" \
    --tag "$RELEASE_TAG" \
    --commit "$EXPECTED_COMMIT" \
    --namespace "$manifest_namespace" \
    --created "$created_at" \
    --run-id "$GITHUB_RUN_ID" \
    --run-attempt "$GITHUB_RUN_ATTEMPT" \
    --run-url "$run_url" \
    --toolchain "xcode=$xcode_version" \
    --toolchain "swift=$swift_version" \
    --toolchain "macos=$runner_macos" \
    --toolchain "sdk=$sdk_version" \
    --toolchain "runner-architecture=$runner_architecture" \
    --toolchain "minimum-system-version=$MINIMUM_SYSTEM_VERSION" \
    --app "$signed_app" \
    --build-number "$BUILD_NUMBER" \
    --executable "$signed_app/Contents/MacOS/$EXECUTABLE_NAME" \
    "${app_codesign_report_arguments[@]}" \
    --designated-requirement "$sanitized_designated_requirement" \
    --entitlements-absent \
    --authority "$DEVELOPER_ID_APPLICATION" \
    --team-id "$APPLE_TEAM_ID" \
    --identifier "$BUNDLE_IDENTIFIER" \
    --pre-notary-dmg "$pre_notary_dmg" \
    --final-dmg "$dmg_path" \
    --notary-json "$notary_result_path" \
    --notary-log "$notary_log_path" \
    --asset "$dmg_name=$dmg_path" \
    --asset "$(basename "$checksum_path")=$checksum_path" \
    --asset "$(basename "$sbom_path")=$sbom_path" \
    --asset "$(basename "$notary_result_path")=$notary_result_path" \
    --asset "$(basename "$notary_log_path")=$notary_log_path" \
    --verification "appCodesign=$sanitized_app_codesign" \
    --verification "dmgCodesign=$sanitized_dmg_codesign" \
    --verification "staplerValidate=$sanitized_stapler" \
    --verification "spctlDMG=$sanitized_spctl_dmg" \
    --verification "spctlApp=$sanitized_spctl_app" \
    --output "$manifest_path"

chmod 0644 "$sbom_path" "$manifest_path"
"$RELEASE_SCRIPTS_DIR/verify-candidate.sh" "$output_directory"

mv "$output_directory" "$release_directory"
printf 'Created verified signed release candidate at %s.\n' "$release_directory"
