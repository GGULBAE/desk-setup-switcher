#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

[[ "$#" == 1 ]] || release_die "Usage: verify-candidate.sh RELEASE_DIRECTORY"
release_directory="$1"
[[ -d "$release_directory" && ! -L "$release_directory" ]] || {
    release_die "Release candidate directory is missing or is a symlink."
}

release_require_single_line DEVELOPER_ID_APPLICATION
release_require_single_line APPLE_TEAM_ID
release_require_single_line RELEASE_TAG
release_require_single_line EXPECTED_COMMIT
release_require_single_line GITHUB_SERVER_URL
release_require_single_line GITHUB_REPOSITORY
release_require_env GITHUB_RUN_ID
release_require_env GITHUB_RUN_ATTEMPT
[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || release_die "APPLE_TEAM_ID has an invalid format."
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]] || {
    release_die "The expected Developer ID identity does not match APPLE_TEAM_ID."
}
[[ "$RELEASE_TAG" == "v$VERSION" ]] || release_die "RELEASE_TAG does not match the bundle version."
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || release_die "EXPECTED_COMMIT has an invalid format."
[[ "$GITHUB_SERVER_URL" == https://github.com ]] || release_die "Unexpected GitHub server URL."
[[ "$GITHUB_REPOSITORY" == GGULBAE/desk-setup-switcher ]] || release_die "Unexpected GitHub repository identity."

dmg_name="Desk-Setup-Switcher-$VERSION.dmg"
dmg_path="$release_directory/$dmg_name"
checksum_path="$release_directory/$dmg_name.sha256"
sbom_path="$release_directory/Desk-Setup-Switcher-$VERSION.spdx.json"
manifest_path="$release_directory/release-manifest.json"
notary_result_path="$release_directory/notary-result.json"
notary_log_path="$release_directory/notary-log.json"

for path in \
    "$dmg_path" \
    "$checksum_path" \
    "$sbom_path" \
    "$manifest_path" \
    "$notary_result_path" \
    "$notary_log_path"; do
    [[ -f "$path" && ! -L "$path" ]] || release_die "Required release asset is missing or not a regular file."
done

line_count="$(wc -l <"$checksum_path" | tr -d '[:space:]')"
[[ "$line_count" == 1 ]] || release_die "Release checksum must contain one newline-terminated entry."
IFS=' ' read -r expected_checksum expected_name unexpected_field <"$checksum_path"
[[ "$expected_checksum" =~ ^[0-9a-f]{64}$ ]] || release_die "Release checksum has an invalid SHA-256 digest."
[[ "$expected_name" == "$dmg_name" && -z "$unexpected_field" ]] || {
    release_die "Release checksum names an unexpected asset."
}
[[ "$(release_sha256 "$dmg_path")" == "$expected_checksum" ]] || {
    release_die "Release DMG checksum mismatch."
}

ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-sbom \
    --sbom "$sbom_path" \
    --dmg "$dmg_path" \
    --version "$VERSION" \
    --tag "$RELEASE_TAG" \
    --commit "$EXPECTED_COMMIT"

created_at="$(ruby -rtime -e 'puts Time.parse(ARGV.fetch(0)).utc.iso8601' "$(git show -s --format=%cI "$EXPECTED_COMMIT")")"
manifest_namespace="https://github.com/GGULBAE/desk-setup-switcher/release-evidence/$RELEASE_TAG/$expected_checksum"
run_url="$GITHUB_SERVER_URL/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-release-manifest \
    --manifest "$manifest_path" \
    --version "$VERSION" \
    --build-number "$BUILD_NUMBER" \
    --tag "$RELEASE_TAG" \
    --commit "$EXPECTED_COMMIT" \
    --namespace "$manifest_namespace" \
    --created "$created_at" \
    --run-id "$GITHUB_RUN_ID" \
    --run-attempt "$GITHUB_RUN_ATTEMPT" \
    --run-url "$run_url" \
    --asset "$dmg_name=$dmg_path" \
    --asset "$(basename "$checksum_path")=$checksum_path" \
    --asset "$(basename "$sbom_path")=$sbom_path" \
    --asset "$(basename "$notary_result_path")=$notary_result_path" \
    --asset "$(basename "$notary_log_path")=$notary_log_path"

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-release-verify.XXXXXX")"
mount_point="$temporary_root/mount"
mkdir -p "$mount_point"
attached=false

cleanup() {
    if [[ "$attached" == true ]]; then
        hdiutil detach -quiet "$mount_point" >/dev/null 2>&1 || true
    fi
    rm -rf "$temporary_root"
}
trap cleanup EXIT

codesign --verify --strict --verbose=2 "$dmg_path"
dmg_report="$temporary_root/dmg-codesign.txt"
codesign --display --verbose=4 "$dmg_path" >"$dmg_report" 2>&1
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-codesign \
    --report "$dmg_report" \
    --authority "$DEVELOPER_ID_APPLICATION" \
    --team-id "$APPLE_TEAM_ID" \
    --identifier "$BUNDLE_IDENTIFIER.dmg" \
    --kind dmg

xcrun stapler validate "$dmg_path" >"$temporary_root/stapler.txt" 2>&1
spctl --assess \
    --type open \
    --context context:primary-signature \
    --verbose=4 \
    "$dmg_path" >"$temporary_root/spctl-dmg.txt" 2>&1

hdiutil attach -quiet -nobrowse -readonly -mountpoint "$mount_point" "$dmg_path"
attached=true
[[ -L "$mount_point/Applications" && "$(readlink "$mount_point/Applications")" == /Applications ]] || {
    release_die "Release DMG Applications link is missing or incorrect."
}

mounted_app="$mount_point/$APP_NAME.app"
"$RELEASE_SCRIPTS_DIR/verify-app-bundle.sh" "$mounted_app"
app_codesign_verify="$temporary_root/app-codesign-verify.txt"
codesign --verify --deep --strict --all-architectures --verbose=2 "$mounted_app" >"$app_codesign_verify" 2>&1
app_codesign_report_arguments=()
for architecture in arm64 x86_64; do
    app_report="$temporary_root/app-codesign-$architecture.txt"
    codesign --display --verbose=4 --architecture "$architecture" "$mounted_app" >"$app_report" 2>&1
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-codesign \
        --report "$app_report" \
        --authority "$DEVELOPER_ID_APPLICATION" \
        --team-id "$APPLE_TEAM_ID" \
        --identifier "$BUNDLE_IDENTIFIER" \
        --kind app \
        --architecture "$architecture"
    app_codesign_report_arguments+=(--app-codesign-report "$architecture=$app_report")
done

designated_requirement="$temporary_root/app-designated-requirement.txt"
codesign --display --requirements - "$mounted_app" >"$designated_requirement" 2>&1
grep -q 'designated =>' "$designated_requirement" || release_die "Mounted app designated requirement is missing."

entitlements="$temporary_root/app-entitlements.plist"
codesign --display --entitlements - --xml "$mounted_app" >"$entitlements" 2>"$temporary_root/entitlements.stderr"
if [[ -s "$entitlements" ]]; then
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements --plist "$entitlements"
    entitlement_arguments=(--entitlements-plist "$entitlements")
else
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements --absent
    entitlement_arguments=(--entitlements-absent)
fi
spctl --assess --type execute --verbose=4 "$mounted_app" >"$temporary_root/spctl-app.txt" 2>&1

ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-mounted-app \
    --manifest "$manifest_path" \
    --app "$mounted_app" \
    --dmg "$dmg_path" \
    "${app_codesign_report_arguments[@]}" \
    --app-codesign-verify "$app_codesign_verify" \
    --executable "$mounted_app/Contents/MacOS/$EXECUTABLE_NAME" \
    --designated-requirement "$designated_requirement" \
    "${entitlement_arguments[@]}"

hdiutil detach -quiet "$mount_point"
attached=false
printf 'Verified signed, notarized, stapled release candidate %s.\n' "$dmg_name"
