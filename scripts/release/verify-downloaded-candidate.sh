#!/usr/bin/env bash

set +x
set +a

unset github_token
github_token="${GH_TOKEN:-}"
export -n github_token 2>/dev/null || true
unset GH_TOKEN GITHUB_TOKEN GH_HOST GH_DEBUG DEBUG GH_ENTERPRISE_TOKEN \
    GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR

set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ -n "$github_token" && "$github_token" != *$'\n'* && "$github_token" != *$'\r'* ]] || {
    release_die "Required release input is missing or malformed: GH_TOKEN"
}
release_require_env RELEASE_SOURCE_DIR
release_require_env RELEASE_DOWNLOAD_DIR
release_require_single_line RELEASE_TAG
release_require_single_line EXPECTED_COMMIT
release_require_single_line DEVELOPER_ID_APPLICATION
release_require_single_line APPLE_TEAM_ID
release_require_single_line GITHUB_REPOSITORY

source_directory="$RELEASE_SOURCE_DIR"
download_directory="$RELEASE_DOWNLOAD_DIR"
[[ -d "$source_directory" && ! -L "$source_directory" ]] || release_die "Release source directory is invalid."
[[ -d "$download_directory" && ! -L "$download_directory" ]] || release_die "Release download directory is invalid."
[[ "$RELEASE_TAG" == "v$VERSION" ]] || release_die "RELEASE_TAG does not match the bundle version."
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || release_die "EXPECTED_COMMIT has an invalid format."
[[ "$GITHUB_REPOSITORY" == GGULBAE/desk-setup-switcher ]] || release_die "Unexpected GitHub repository identity."

dmg_name="Desk-Setup-Switcher-$VERSION.dmg"
asset_names=(
    "$dmg_name"
    "$dmg_name.sha256"
    "Desk-Setup-Switcher-$VERSION.spdx.json"
    release-manifest.json
    notary-result.json
    notary-log.json
    "Desk-Setup-Switcher-$VERSION.provenance.sigstore.json"
    "Desk-Setup-Switcher-$VERSION.sbom.sigstore.json"
    release-manifest.provenance.sigstore.json
)

actual_assets="$(find "$download_directory" -mindepth 1 -maxdepth 1 -type f -print | wc -l | tr -d '[:space:]')"
[[ "$actual_assets" == "${#asset_names[@]}" ]] || {
    release_die "Downloaded release contains an unexpected number of regular assets."
}
unexpected_entries="$(find "$download_directory" -mindepth 1 -maxdepth 1 ! -type f -print)"
[[ -z "$unexpected_entries" ]] || release_die "Downloaded release contains a non-regular entry."

for name in "${asset_names[@]}"; do
    source_path="$source_directory/$name"
    downloaded_path="$download_directory/$name"
    [[ -f "$source_path" && ! -L "$source_path" ]] || release_die "A local candidate asset is missing."
    [[ -f "$downloaded_path" && ! -L "$downloaded_path" ]] || release_die "A downloaded candidate asset is missing."
    cmp -s "$source_path" "$downloaded_path" || {
        release_die "A downloaded draft asset differs from the exact approved candidate: $name"
    }
done

"$RELEASE_SCRIPTS_DIR/verify-candidate.sh" "$download_directory"

release_require_command gh
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-attestation-verify.XXXXXX")"
gh_config_directory="$temporary_root/gh-config"
mkdir -m 0700 "$gh_config_directory"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

dmg_path="$download_directory/$dmg_name"
provenance_bundle="$download_directory/Desk-Setup-Switcher-$VERSION.provenance.sigstore.json"
sbom_bundle="$download_directory/Desk-Setup-Switcher-$VERSION.sbom.sigstore.json"
manifest_path="$download_directory/release-manifest.json"
manifest_bundle="$download_directory/release-manifest.provenance.sigstore.json"
signer_workflow="$GITHUB_REPOSITORY/.github/workflows/release.yml"
source_ref="refs/tags/$RELEASE_TAG"

GH_CONFIG_DIR="$gh_config_directory" GH_TOKEN="$github_token" gh attestation verify "$dmg_path" \
    --hostname github.com \
    --repo "$GITHUB_REPOSITORY" \
    --bundle "$provenance_bundle" \
    --signer-workflow "$signer_workflow" \
    --source-digest "$EXPECTED_COMMIT" \
    --source-ref "$source_ref" \
    --deny-self-hosted-runners \
    --format json >"$temporary_root/provenance-verification.json"

GH_CONFIG_DIR="$gh_config_directory" GH_TOKEN="$github_token" gh attestation verify "$dmg_path" \
    --hostname github.com \
    --repo "$GITHUB_REPOSITORY" \
    --bundle "$sbom_bundle" \
    --predicate-type https://spdx.dev/Document/v2.3 \
    --signer-workflow "$signer_workflow" \
    --source-digest "$EXPECTED_COMMIT" \
    --source-ref "$source_ref" \
    --deny-self-hosted-runners \
    --format json >"$temporary_root/sbom-verification.json"

GH_CONFIG_DIR="$gh_config_directory" GH_TOKEN="$github_token" gh attestation verify "$manifest_path" \
    --hostname github.com \
    --repo "$GITHUB_REPOSITORY" \
    --bundle "$manifest_bundle" \
    --signer-workflow "$signer_workflow" \
    --source-digest "$EXPECTED_COMMIT" \
    --source-ref "$source_ref" \
    --deny-self-hosted-runners \
    --format json >"$temporary_root/manifest-verification.json"

for result in \
    "$temporary_root/provenance-verification.json" \
    "$temporary_root/sbom-verification.json" \
    "$temporary_root/manifest-verification.json"; do
    ruby -rjson -e '
      value = JSON.parse(File.read(ARGV.fetch(0)))
      abort "Attestation verification returned no verified statement." unless value.is_a?(Array) && !value.empty?
    ' "$result"
done

github_token=""
printf 'Redownloaded draft assets and all three exact-candidate attestations are verified.\n'
