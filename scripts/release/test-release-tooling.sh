#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"
assertions=0

pass() {
    assertions=$((assertions + 1))
}

assert_contains() {
    local path="$1"
    local text="$2"
    grep -F -q -- "$text" "$path" || release_die "Expected release-tooling text is missing from $path: $text"
    pass
}

assert_not_contains() {
    local path="$1"
    local text="$2"
    if grep -F -q -- "$text" "$path"; then
        release_die "Forbidden release-tooling text is present: $text"
    fi
    pass
}

assert_before() {
    local path="$1"
    local first="$2"
    local second="$3"
    local first_line second_line
    first_line="$(grep -F -n -m 1 -- "$first" "$path" | cut -d: -f1 || true)"
    second_line="$(grep -F -n -m 1 -- "$second" "$path" | cut -d: -f1 || true)"
    [[ -n "$first_line" && -n "$second_line" && "$first_line" -lt "$second_line" ]] || {
        release_die "Expected release-tooling order is missing from $path: $first before $second"
    }
    pass
}

assert_fails() {
    if "$@" >"$temporary_root/expected-failure.stdout" 2>"$temporary_root/expected-failure.stderr"; then
        release_die "A release safety guard unexpectedly allowed execution."
    fi
    pass
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-release-tests.XXXXXX")"
runtime_secret() {
    ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))'
}
runtime_notary_secret="$(runtime_secret)"
runtime_preexisting_notary_secret="$(runtime_secret)"
runtime_gh_token="$(runtime_secret)"
runtime_github_token="$(runtime_secret)"
runtime_lowercase_token="$(runtime_secret)"
runtime_certificate="$(runtime_secret)"
runtime_certificate_password="$(runtime_secret)"
runtime_preexisting_certificate="$(runtime_secret)"
runtime_preexisting_password="$(runtime_secret)"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

ruby "$RELEASE_SCRIPTS_DIR/test_release_policy.rb"
pass

ruby "$RELEASE_SCRIPTS_DIR/test_remote_controls_policy.rb"
pass

ruby "$RELEASE_SCRIPTS_DIR/test_remote_controls_policy_v2.rb"
pass

ruby "$RELEASE_SCRIPTS_DIR/test_remote_controls_collector_v2.rb"
pass

ruby "$RELEASE_SCRIPTS_DIR/test_publication_policy.rb"
pass

"$RELEASE_SCRIPTS_DIR/test_remote_controls_collector.sh"
pass

"$RELEASE_SCRIPTS_DIR/test_prepare_draft_release.sh"
pass

"$RELEASE_SCRIPTS_DIR/test_restore_candidate_artifact.sh"
pass

"$RELEASE_SCRIPTS_DIR/test_publish_approved_release.sh"
pass

ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-entitlements \
    --plist Config/ReleaseEntitlements.plist
pass

duplicate_json="$temporary_root/duplicate.json"
sanitized_json="$temporary_root/sanitized.json"
printf '{"status":"Accepted","status":"Accepted"}\n' >"$duplicate_json"
assert_fails release_sanitize_json "$duplicate_json" "$sanitized_json"

overlap_home="$temporary_root/synthetic-home"
overlap_runner_temp="$overlap_home/work/_temp"
mkdir -p "$overlap_runner_temp"
overlap_text_input="$temporary_root/overlap-input.txt"
overlap_text_output="$temporary_root/overlap-output.txt"
printf '%s\n' "$overlap_runner_temp/notary.log:$overlap_home/file:$ROOT_DIR/artifact" >"$overlap_text_input"
original_home="${HOME:-}"
original_runner_temp="${RUNNER_TEMP:-}"
HOME="$overlap_home"
RUNNER_TEMP="$overlap_runner_temp"
release_sanitize_text "$overlap_text_input" "$overlap_text_output"
HOME="$original_home"
RUNNER_TEMP="$original_runner_temp"
expected_overlap_text='$RUNNER_TEMP/notary.log:$HOME/file:$REPOSITORY/artifact'
[[ "$(tr -d '\n' <"$overlap_text_output")" == "$expected_overlap_text" ]] || {
    release_die "Text evidence did not prefer the most-specific overlapping paths."
}
pass

release_require_absent_path "$temporary_root/absent"
dangling_path="$temporary_root/dangling"
ln -s "$temporary_root/missing" "$dangling_path"
if (release_require_absent_path "$dangling_path") >"$temporary_root/dangling.stdout" 2>"$temporary_root/dangling.stderr"; then
    release_die "A dangling symlink was accepted as an absent release path."
fi
pass

isolated_environment=(
    env -i
    "PATH=$PATH"
    "HOME=${HOME:-/tmp}"
    "TMPDIR=${TMPDIR:-/tmp}"
)
assert_fails "${isolated_environment[@]}" "$RELEASE_SCRIPTS_DIR/build-candidate.sh"
assert_fails "${isolated_environment[@]}" "$RELEASE_SCRIPTS_DIR/import-signing-certificate.sh"
assert_fails "${isolated_environment[@]}" "$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh"
assert_fails "${isolated_environment[@]}" "$RELEASE_SCRIPTS_DIR/preflight.sh"
assert_fails "${isolated_environment[@]}" DESK_SETUP_RELEASE_MUTATIONS=1 "$RELEASE_SCRIPTS_DIR/build-candidate.sh"

preflight_mock_bin="$temporary_root/preflight-mock-bin"
mkdir "$preflight_mock_bin"
cat >"$preflight_mock_bin/git" <<'MOCK_PREFLIGHT_GIT'
#!/usr/bin/env bash
set -euo pipefail
commit=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
tag_object=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
case "${1:-}" in
    rev-parse)
        [[ "${2:-}" == --verify && "$#" == 3 ]] || exit 91
        case "$3" in
            HEAD^{commit}|refs/tags/v0.1.0^{commit}) printf '%s\n' "$commit" ;;
            refs/tags/v0.1.0)
                if [[ "${MOCK_PREFLIGHT_TAG_KIND:-annotated}" == lightweight ]]; then
                    printf '%s\n' "$commit"
                else
                    printf '%s\n' "$tag_object"
                fi ;;
            *) exit 91 ;;
        esac
        ;;
    show-ref)
        [[ "$#" == 4 && "$2" == --verify && "$3" == --quiet ]] || exit 92
        [[ "$4" == refs/tags/v0.1.0 ]] || exit 1
        ;;
    cat-file)
        [[ "$#" == 3 && "$2" == -t ]] || exit 93
        if [[ "$3" == "$tag_object" ]]; then
            printf 'tag\n'
        elif [[ "$3" == "$commit" ]]; then
            printf 'commit\n'
        else
            exit 93
        fi
        ;;
    status)
        [[ "$#" == 3 && "$2" == --porcelain=v1 && "$3" == --untracked-files=all ]] || exit 94
        ;;
    *) exit 95 ;;
esac
MOCK_PREFLIGHT_GIT
chmod 0755 "$preflight_mock_bin/git"
preflight_environment=(
    env -i
    "PATH=$preflight_mock_bin:$PATH"
    "HOME=${HOME:-/tmp}"
    "TMPDIR=${TMPDIR:-/tmp}"
    "DEVELOPER_DIR=$DEVELOPER_DIR"
    RELEASE_TAG=v0.1.0
    EXPECTED_COMMIT=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
    'RELEASE_CONFIRMATION=prepare signed draft v0.1.0'
)
"${preflight_environment[@]}" "$RELEASE_SCRIPTS_DIR/preflight.sh" \
    >"$temporary_root/preflight-annotated.stdout"
assert_contains "$temporary_root/preflight-annotated.stdout" "Release preflight passed"
assert_fails "${preflight_environment[@]}" MOCK_PREFLIGHT_TAG_KIND=lightweight \
    "$RELEASE_SCRIPTS_DIR/preflight.sh"

cleanup_environment=(
    env -i
    "PATH=$PATH"
    "HOME=${HOME:-/tmp}"
    "TMPDIR=${TMPDIR:-/tmp}"
    DESK_SETUP_RELEASE_MUTATIONS=1
    GITHUB_ACTIONS=true
    GITHUB_EVENT_NAME=workflow_dispatch
    GITHUB_REF_TYPE=tag
    RELEASE_PROTECTED_ENVIRONMENT=release-candidate
    GITHUB_REPOSITORY=GGULBAE/desk-setup-switcher
    "RUNNER_TEMP=$temporary_root"
    GITHUB_RUN_ID=1
    RUNNER_ENVIRONMENT=github-hosted
)
"${cleanup_environment[@]}" "$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh" \
    >"$temporary_root/empty-cleanup.stdout"
grep -F -q 'No ephemeral release signing material exists.' "$temporary_root/empty-cleanup.stdout" || {
    release_die "Empty always-cleanup was not idempotent."
}
pass
assert_fails "${cleanup_environment[@]}" RUNNER_ENVIRONMENT=self-hosted \
    "$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh"

mock_bin="$temporary_root/mock-bin"
mkdir -p "$mock_bin"
cat >"$mock_bin/openssl" <<'MOCK_OPENSSL'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DEVELOPER_ID_CERTIFICATE_BASE64+x}" \
   || -n "${DEVELOPER_ID_CERTIFICATE_PASSWORD+x}" \
   || -n "${APPLE_NOTARY_API_KEY_BASE64+x}" \
   || -n "${certificate_base64+x}" \
   || -n "${certificate_password+x}" \
   || -n "${notary_api_key_base64+x}" ]]; then
    printf 'A release secret leaked into the mock openssl environment.\n' >&2
    exit 97
fi

case "${1:-}" in
    rand)
        exec /usr/bin/openssl rand -hex 32
        ;;
    base64)
        output=""
        while [[ "$#" -gt 0 ]]; do
            if [[ "$1" == -out ]]; then
                shift
                output="${1:-}"
            fi
            shift
        done
        [[ -n "$output" ]] || exit 98
        payload=""
        while IFS= read -r line || [[ -n "$line" ]]; do
            payload="$payload$line"
        done
        printf '%s' "$payload" >"$output"
        ;;
    *)
        exit 99
        ;;
esac
MOCK_OPENSSL

cat >"$mock_bin/security" <<'MOCK_SECURITY'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DEVELOPER_ID_CERTIFICATE_BASE64+x}" \
   || -n "${DEVELOPER_ID_CERTIFICATE_PASSWORD+x}" \
   || -n "${APPLE_NOTARY_API_KEY_BASE64+x}" \
   || -n "${certificate_base64+x}" \
   || -n "${certificate_password+x}" \
   || -n "${notary_api_key_base64+x}" ]]; then
    printf 'A release secret leaked into the mock security environment.\n' >&2
    exit 97
fi

last_argument=""
for argument in "$@"; do
    last_argument="$argument"
done

case "${1:-}" in
    create-keychain)
        : >"$last_argument"
        ;;
    import)
        [[ "${STUB_SECURITY_FAIL_IMPORT:-0}" != 1 ]] || exit 42
        ;;
    find-identity)
        case "${STUB_SECURITY_IDENTITY_SCENARIO:-exact}" in
            exact)
                printf '  1) 0123456789012345678901234567890123456789 "%s"\n     1 valid identities found\n' \
                    "$DEVELOPER_ID_APPLICATION"
                ;;
            extra-valid)
                printf '  1) 0123456789012345678901234567890123456789 "%s"\n' \
                    "$DEVELOPER_ID_APPLICATION"
                printf '  2) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: Unexpected Identity (ZZZZZ99999)"\n'
                printf '     2 valid identities found\n'
                ;;
            matching-missing)
                printf '  1) FEDCBA9876543210FEDCBA9876543210FEDCBA98 "Developer ID Application: Unexpected Identity (ZZZZZ99999)"\n'
                printf '     1 valid identities found\n'
                ;;
            malformed-summary)
                printf '  1) 0123456789012345678901234567890123456789 "%s"\n     2 valid identities found\n' \
                    "$DEVELOPER_ID_APPLICATION"
                ;;
            *) exit 98 ;;
        esac
        ;;
    delete-keychain)
        rm -f -- "$last_argument"
        ;;
    set-keychain-settings|unlock-keychain|set-key-partition-list)
        ;;
    *)
        exit 99
        ;;
esac
MOCK_SECURITY

cat >"$mock_bin/dirname" <<'MOCK_DIRNAME'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DEVELOPER_ID_CERTIFICATE_BASE64+x}" \
   || -n "${DEVELOPER_ID_CERTIFICATE_PASSWORD+x}" \
   || -n "${APPLE_NOTARY_API_KEY_BASE64+x}" \
   || -n "${certificate_base64+x}" \
   || -n "${certificate_password+x}" \
   || -n "${notary_api_key_base64+x}" \
   || -n "${GH_TOKEN+x}" \
   || -n "${GITHUB_TOKEN+x}" \
   || -n "${github_token+x}" ]]; then
    printf 'A release secret reached the first external child command.\n' >&2
    exit 97
fi
if [[ -n "${RELEASE_SECRET_PROBE_MARKER:-}" ]]; then
    printf 'dirname environment was isolated\n' >>"$RELEASE_SECRET_PROBE_MARKER"
fi
exec /usr/bin/dirname "$@"
MOCK_DIRNAME
chmod 0755 "$mock_bin/openssl" "$mock_bin/security" "$mock_bin/dirname"

build_secret_probe="$temporary_root/build-secret-probe.txt"
assert_fails env -i \
    "PATH=$mock_bin:$PATH" \
    "HOME=${HOME:-/tmp}" \
    "TMPDIR=${TMPDIR:-/tmp}" \
    "DEVELOPER_DIR=$DEVELOPER_DIR" \
    "RELEASE_SECRET_PROBE_MARKER=$build_secret_probe" \
    "APPLE_NOTARY_API_KEY_BASE64=$runtime_notary_secret" \
    "notary_api_key_base64=$runtime_preexisting_notary_secret" \
    "$RELEASE_SCRIPTS_DIR/build-candidate.sh"
[[ -s "$build_secret_probe" ]] || release_die "The build secret isolation probe never reached the first child command."
pass

github_token_probe="$temporary_root/github-token-probe.txt"
assert_fails env -i \
    "PATH=$mock_bin:$PATH" \
    "HOME=${HOME:-/tmp}" \
    "TMPDIR=${TMPDIR:-/tmp}" \
    "RELEASE_SECRET_PROBE_MARKER=$github_token_probe" \
    "GH_TOKEN=$runtime_gh_token" \
    "GITHUB_TOKEN=$runtime_github_token" \
    "github_token=$runtime_lowercase_token" \
    "$RELEASE_SCRIPTS_DIR/verify-downloaded-candidate.sh"
[[ -s "$github_token_probe" ]] || {
    release_die "The downloaded verifier did not isolate inherited GitHub credentials before its first child command."
}
pass

credential_environment=(
    env -i
    "PATH=$mock_bin:$PATH"
    "HOME=${HOME:-/tmp}"
    "TMPDIR=${TMPDIR:-/tmp}"
    "DEVELOPER_DIR=$DEVELOPER_DIR"
    DESK_SETUP_RELEASE_MUTATIONS=1
    GITHUB_ACTIONS=true
    GITHUB_EVENT_NAME=workflow_dispatch
    GITHUB_REF_TYPE=tag
    RELEASE_PROTECTED_ENVIRONMENT=release-candidate
    GITHUB_REPOSITORY=GGULBAE/desk-setup-switcher
    GITHUB_RUN_ID=1
    RUNNER_ENVIRONMENT=github-hosted
    'DEVELOPER_ID_APPLICATION=Developer ID Application: Synthetic Maintainer (ABCDE12345)'
    APPLE_TEAM_ID=ABCDE12345
)

read_handoff_paths() {
    local environment_file="$1"
    local name value
    RELEASE_SIGNING_KEYCHAIN=""
    RELEASE_SIGNING_CERTIFICATE_PATH=""
    while IFS='=' read -r name value; do
        case "$name" in
            RELEASE_SIGNING_KEYCHAIN) RELEASE_SIGNING_KEYCHAIN="$value" ;;
            RELEASE_SIGNING_CERTIFICATE_PATH) RELEASE_SIGNING_CERTIFICATE_PATH="$value" ;;
        esac
    done <"$environment_file"
    [[ -n "$RELEASE_SIGNING_KEYCHAIN" && -n "$RELEASE_SIGNING_CERTIFICATE_PATH" ]] || {
        release_die "Signing path handoff was incomplete."
    }
}

successful_runner="$temporary_root/mock-runner-success"
successful_github_env="$successful_runner/github-env"
mkdir -p "$successful_runner"
"${credential_environment[@]}" \
    "RUNNER_TEMP=$successful_runner" \
    "GITHUB_ENV=$successful_github_env" \
    "DEVELOPER_ID_CERTIFICATE_BASE64=$runtime_certificate" \
    "DEVELOPER_ID_CERTIFICATE_PASSWORD=$runtime_certificate_password" \
    "certificate_base64=$runtime_preexisting_certificate" \
    "certificate_password=$runtime_preexisting_password" \
    "$RELEASE_SCRIPTS_DIR/import-signing-certificate.sh" \
    >"$temporary_root/mock-import-success.stdout"
read_handoff_paths "$successful_github_env"
successful_signing_directory="$(dirname "$RELEASE_SIGNING_KEYCHAIN")"
[[ -d "$successful_signing_directory" && ! -L "$successful_signing_directory" \
   && "$(stat -f %Lp "$successful_signing_directory")" == 700 \
   && -f "$RELEASE_SIGNING_KEYCHAIN" && ! -L "$RELEASE_SIGNING_KEYCHAIN" \
   && "$(stat -f %Lp "$RELEASE_SIGNING_KEYCHAIN")" == 600 \
   && ! -e "$RELEASE_SIGNING_CERTIFICATE_PATH" && ! -L "$RELEASE_SIGNING_CERTIFICATE_PATH" ]] || {
    release_die "Successful mock signing import did not preserve the constrained handoff state."
}
pass
"${credential_environment[@]}" \
    "RUNNER_TEMP=$successful_runner" \
    "RELEASE_SIGNING_KEYCHAIN=$RELEASE_SIGNING_KEYCHAIN" \
    "RELEASE_SIGNING_CERTIFICATE_PATH=$RELEASE_SIGNING_CERTIFICATE_PATH" \
    "$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh" \
    >"$temporary_root/mock-cleanup-success.stdout"
[[ ! -e "$successful_signing_directory" && ! -L "$successful_signing_directory" ]] || {
    release_die "Mock signing cleanup left the successful signing directory behind."
}
pass

assert_identity_inventory_rejected() {
    local scenario="$1"
    local expected_error="$2"
    local runner="$temporary_root/mock-runner-identity-$scenario"
    local github_env="$runner/github-env"
    local signing_directory
    mkdir -p "$runner"
    assert_fails "${credential_environment[@]}" \
        "RUNNER_TEMP=$runner" \
        "GITHUB_ENV=$github_env" \
        "DEVELOPER_ID_CERTIFICATE_BASE64=$runtime_certificate" \
        "DEVELOPER_ID_CERTIFICATE_PASSWORD=$runtime_certificate_password" \
        "STUB_SECURITY_IDENTITY_SCENARIO=$scenario" \
        "$RELEASE_SCRIPTS_DIR/import-signing-certificate.sh"
    read_handoff_paths "$github_env"
    signing_directory="$(dirname "$RELEASE_SIGNING_KEYCHAIN")"
    [[ ! -e "$signing_directory" && ! -L "$signing_directory" ]] || {
        release_die "Rejected signing identity inventory left credential material behind: $scenario"
    }
    pass
    grep -F -q -- "$expected_error" "$temporary_root/expected-failure.stderr" || {
        release_die "Rejected signing identity inventory used an unexpected diagnostic: $scenario"
    }
    pass
    if grep -F -q -- 'Unexpected Identity' "$temporary_root/expected-failure.stderr"; then
        release_die "Rejected signing identity inventory disclosed an unreviewed identity name: $scenario"
    fi
    pass
}

assert_identity_inventory_rejected \
    extra-valid \
    'The temporary Keychain must contain exactly one valid codesigning identity, and it must match the reviewed Developer ID identity.'
assert_identity_inventory_rejected \
    matching-missing \
    'The temporary Keychain must contain exactly one valid codesigning identity, and it must match the reviewed Developer ID identity.'
assert_identity_inventory_rejected \
    malformed-summary \
    'The temporary Keychain identity inventory is invalid.'

failed_runner="$temporary_root/mock-runner-failure"
failed_github_env="$failed_runner/github-env"
mkdir -p "$failed_runner"
assert_fails "${credential_environment[@]}" \
    "RUNNER_TEMP=$failed_runner" \
    "GITHUB_ENV=$failed_github_env" \
    "DEVELOPER_ID_CERTIFICATE_BASE64=$runtime_certificate" \
    "DEVELOPER_ID_CERTIFICATE_PASSWORD=$runtime_certificate_password" \
    STUB_SECURITY_FAIL_IMPORT=1 \
    "$RELEASE_SCRIPTS_DIR/import-signing-certificate.sh"
read_handoff_paths "$failed_github_env"
failed_signing_directory="$(dirname "$RELEASE_SIGNING_KEYCHAIN")"
[[ ! -e "$failed_signing_directory" && ! -L "$failed_signing_directory" ]] || {
    release_die "Failed mock signing import left credential material behind."
}
"${credential_environment[@]}" \
    "RUNNER_TEMP=$failed_runner" \
    "RELEASE_SIGNING_KEYCHAIN=$RELEASE_SIGNING_KEYCHAIN" \
    "RELEASE_SIGNING_CERTIFICATE_PATH=$RELEASE_SIGNING_CERTIFICATE_PATH" \
    "$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh" \
    >"$temporary_root/mock-cleanup-failure.stdout"
grep -F -q 'already removed' "$temporary_root/mock-cleanup-failure.stdout" || {
    release_die "Always-cleanup was not idempotent after a failed import."
}
pass

symlink_runner="$temporary_root/mock-runner-symlink"
mkdir -p "$symlink_runner"
symlink_signing_directory="$(mktemp -d "$symlink_runner/desk-setup-release-signing.XXXXXX")"
symlink_certificate="$(mktemp "$symlink_signing_directory/developer-id.p12.XXXXXX")"
rm -f -- "$symlink_certificate"
symlink_target="$temporary_root/symlink-target"
printf 'preserve me\n' >"$symlink_target"
symlink_keychain="$symlink_signing_directory/signing.keychain-db"
ln -s "$symlink_target" "$symlink_keychain"
assert_fails "${credential_environment[@]}" \
    "RUNNER_TEMP=$symlink_runner" \
    "RELEASE_SIGNING_KEYCHAIN=$symlink_keychain" \
    "RELEASE_SIGNING_CERTIFICATE_PATH=$symlink_certificate" \
    "$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh"
[[ -L "$symlink_keychain" && "$(tr -d '\n' <"$symlink_target")" == 'preserve me' ]] || {
    release_die "Signing cleanup followed or changed an unsafe Keychain symlink."
}
pass
rm -f -- "$symlink_keychain"
rmdir "$symlink_signing_directory"

fixture_app="$temporary_root/Fixture.app"
mkdir -p "$fixture_app/Contents/MacOS" "$fixture_app/Contents/Resources"
printf 'fixture executable\n' >"$fixture_app/Contents/MacOS/Fixture"
printf 'fixture resource\n' >"$fixture_app/Contents/Resources/value.txt"
chmod 0755 "$fixture_app/Contents/MacOS/Fixture"

first_manifest="$temporary_root/first-bundle.json"
second_manifest="$temporary_root/second-bundle.json"
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-bundle-manifest \
    --app "$fixture_app" \
    --output "$first_manifest" >/dev/null
ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-bundle-manifest \
    --app "$fixture_app" \
    --output "$second_manifest" >/dev/null
cmp -s "$first_manifest" "$second_manifest" || release_die "Bundle manifest generation is not deterministic."
pass
"$RELEASE_SCRIPTS_DIR/compare-bundle-manifest.sh" "$first_manifest" "$fixture_app" >/dev/null
pass
printf 'tamper\n' >>"$fixture_app/Contents/Resources/value.txt"
assert_fails "$RELEASE_SCRIPTS_DIR/compare-bundle-manifest.sh" "$first_manifest" "$fixture_app"

workflow=.github/workflows/release.yml
publication_workflow=.github/workflows/publish-release.yml
prepare_draft="$RELEASE_SCRIPTS_DIR/prepare-draft-release.sh"
restore_candidate="$RELEASE_SCRIPTS_DIR/restore-candidate-artifact.sh"
verify_candidate="$RELEASE_SCRIPTS_DIR/verify-candidate.sh"
verify_downloaded="$RELEASE_SCRIPTS_DIR/verify-downloaded-candidate.sh"
publication_helper="$RELEASE_SCRIPTS_DIR/publish-approved-release.sh"
publication_policy="$RELEASE_SCRIPTS_DIR/publication_policy.rb"
assert_contains "$workflow" "workflow_dispatch:"
assert_contains "$workflow" "environment: release-candidate"
assert_contains "$workflow" "DESK_SETUP_RELEASE_MUTATIONS: \"1\""
assert_contains "$workflow" "RELEASE_CANDIDATE_RUN_ATTEMPT: \"1\""
assert_contains "$workflow" "- build-candidate"
assert_contains "$workflow" "- prepare-draft"
assert_contains "$workflow" "candidate_origin_run_id:"
assert_contains "$workflow" "candidate_artifact_id:"
assert_contains "$workflow" "candidate_artifact_sha256:"
assert_contains "$workflow" "needs: validate-dispatch"
assert_contains "$workflow" "Never rerun a build-candidate operation."
assert_contains "$workflow" "actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6"
assert_contains "$workflow" "overwrite: false"
assert_contains "$workflow" 'signed-candidate-${{ github.run_id }}-attempt-1'
assert_contains "$workflow" "run: exec /bin/bash scripts/release/restore-candidate-artifact.sh"
assert_contains "$workflow" "run: exec /bin/bash scripts/release/prepare-draft-release.sh"
assert_contains "$workflow" "make verify-downloaded-release"
assert_before "$workflow" "Retain the signed candidate before any draft mutation" "Create or resume the exact additive-only draft"
assert_before "$workflow" "Run draft recovery preflight" "Prepare private candidate paths"
assert_before "$workflow" "Prepare private candidate paths" "Restore the exact candidate from its separate origin run"
assert_before "$workflow" "Restore the exact candidate from its separate origin run" "Verify the exact origin candidate and attestations before draft mutation"
assert_before "$workflow" "Verify the exact origin candidate and attestations before draft mutation" "Create or resume the exact additive-only draft"
assert_before "$workflow" "Create or resume the exact additive-only draft" "Verify the redownloaded draft and attestations"
assert_not_contains "$workflow" "push:"
assert_not_contains "$workflow" "--generate-notes"
assert_not_contains "$workflow" "--draft=false"
assert_not_contains "$workflow" "gh release edit"
assert_not_contains "$workflow" "gh release delete"
assert_not_contains "$workflow" "--clobber"
assert_not_contains "$workflow" "unsigned"
assert_not_contains "$workflow" "artifacts/*.dmg"
assert_not_contains "$workflow" "RELEASE_SIGNING_KEYCHAIN:"
assert_contains "$workflow" "run: exec /bin/bash scripts/release/import-signing-certificate.sh"
assert_contains "$workflow" "run: exec /bin/bash scripts/release/build-candidate.sh"
assert_not_contains "$workflow" "run: make release-candidate"

assert_contains "$publication_workflow" "workflow_dispatch:"
assert_contains "$publication_workflow" "environment: release-publication"
assert_contains "$publication_workflow" "group: signed-release-candidate-v0.1.0"
assert_contains "$publication_workflow" "run: exec /bin/bash scripts/release/restore-candidate-artifact.sh"
assert_contains "$publication_workflow" "run: exec /bin/bash scripts/release/publish-approved-release.sh"
assert_contains "$publication_workflow" "RELEASE_ADMIN_READ_TOKEN: \${{ secrets.RELEASE_ADMIN_READ_TOKEN }}"
assert_contains "$publication_workflow" "make verify-downloaded-release"
assert_not_contains "$publication_workflow" "push:"
assert_not_contains "$publication_workflow" "schedule:"
assert_not_contains "$publication_workflow" "gh release create"
assert_not_contains "$publication_workflow" "gh release edit"
assert_not_contains "$publication_workflow" "gh release delete"
assert_not_contains "$publication_workflow" "--clobber"
assert_not_contains "$publication_workflow" "git tag"
assert_not_contains "$publication_workflow" "git push"
assert_not_contains "$publication_workflow" "DEVELOPER_ID_CERTIFICATE_BASE64"
assert_not_contains "$publication_workflow" "APPLE_NOTARY_API_KEY_BASE64"

ruby -ryaml -rjson -e '
  workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
  triggers = workflow.fetch(true)
  abort "publication must be manual-only" unless triggers.keys == ["workflow_dispatch"]
  inputs = triggers.fetch("workflow_dispatch").fetch("inputs")
  expected_inputs = %w[
    tag expected_commit release_id candidate_origin_run_id candidate_artifact_id
    candidate_artifact_sha256 final_dmg_sha256 approval_record_commit
    approval_record_sha256 approver_login publisher_login confirmation
  ]
  abort "publication input schema differs" unless inputs.keys.sort == expected_inputs.sort
  abort "publication input is optional or non-string" unless
    inputs.values.all? { |input| input.fetch("required") == true && input.fetch("type") == "string" }
  abort "publication global permissions differ" unless workflow.fetch("permissions") == {}
  concurrency = workflow.fetch("concurrency")
  abort "publication concurrency differs" unless concurrency == {
    "group" => "signed-release-candidate-v0.1.0", "cancel-in-progress" => false
  }
  jobs = workflow.fetch("jobs")
  abort "publication jobs differ" unless jobs.keys.sort == %w[publish-approved-release validate-publication]
  guard = jobs.fetch("validate-publication")
  publish = jobs.fetch("publish-approved-release")
  abort "publication guard permissions differ" unless guard.fetch("permissions") == {}
  abort "publication job dependency differs" unless publish.fetch("needs") == "validate-publication"
  abort "publication environment differs" unless publish.fetch("environment") == "release-publication"
  abort "publication permissions differ" unless publish.fetch("permissions") == {
    "contents" => "write"
  }
  abort "publication mutation marker differs" unless publish.fetch("env").fetch("DESK_SETUP_RELEASE_MUTATIONS") == "1"
  steps = publish.fetch("steps")
  names = steps.map { |step| step.fetch("name") }
  checkout = names.index("Check out the immutable release tag")
  restore = names.index("Restore the exact candidate from its origin artifact")
  preverify = names.index("Verify origin candidate and all attestations before publication")
  mutate = names.index("Publish only the exact approved Release ID")
  postverify = names.index("Verify public redownload and all attestations")
  abort "publication verification/mutation order differs" unless
    [checkout, restore, preverify, mutate, postverify].all? &&
      checkout < restore && restore < preverify && preverify < mutate && mutate < postverify
  checkout_step = steps.fetch(checkout)
  abort "publication checkout action is not the sole reviewed action" unless
    checkout_step.fetch("uses") ==
      "actions/checkout@9c091bb21b7c1c1d1991bb908d89e4e9dddfe3e0" &&
      steps.count { |step| step.key?("uses") } == 1
  read_token = "${{ secrets.RELEASE_ADMIN_READ_TOKEN }}"
  abort "publication checkout identity differs" unless checkout_step.fetch("with") == {
    "ref" => "${{ inputs.tag }}", "fetch-depth" => 0, "persist-credentials" => false,
    "token" => read_token
  }
  [restore, preverify, postverify].each do |index|
    abort "publication read step does not use the protected read-only credential" unless
      steps.fetch(index).fetch("env").fetch("GH_TOKEN") == read_token
  end
  publish_step = steps.fetch(mutate)
  abort "publication helper invocation differs" unless
    publish_step.fetch("run") == "exec /bin/bash scripts/release/publish-approved-release.sh"
  abort "admin-read credential is not step-scoped" unless
    publish_step.fetch("env").fetch("RELEASE_ADMIN_READ_TOKEN") == read_token
  abort "job write token is not scoped to the exact publication helper" unless
    publish_step.fetch("env").fetch("GH_TOKEN") == "${{ github.token }}"
  serialized = JSON.generate(workflow)
  abort "admin-read secret reference count differs" unless
    serialized.scan(read_token).length == 5
  abort "job write token reference count differs" unless
    serialized.scan("${{ github.token }}").length == 1
  abort "publication workflow gained a signing secret" if
    serialized.match?(/secrets\.(?:DEVELOPER_ID|APPLE_NOTARY)/)
' "$publication_workflow"
pass

[[ "$(grep -F -c 'persist-credentials:' "$publication_workflow")" == 1 ]] || {
    release_die "Publication workflow checkout credential policy is duplicated or missing."
}
pass

ruby -e '
  helper, policy = ARGV.map { |path| File.read(path) }
  abort "publication helper must contain exactly one PATCH callsite" unless
    helper.scan(/--method PATCH/).length == 1
  abort "publication helper mutation endpoint differs" unless
    helper.include?(%q{"/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID"})
  abort "publication PATCH body differs" unless
    helper.include?(%q{{"draft":false,"prerelease":true,"make_latest":"false"}})
  abort "publication helper permits a forbidden mutation" if
    helper.match?(/\bgh release (?:create|edit|delete|upload)\b|--clobber|\bgit (?:push|tag)\b/)
  abort "publication helper contains another API mutation method" if
    helper.match?(/--method (?:POST|PUT|DELETE)/)
  abort "publication helper does not bind approval commit to master" unless
    helper.include?(%q{[[ "$RELEASE_APPROVAL_RECORD_COMMIT" == "$initial_master" ]]})
  abort "publication helper can hide another repository Release" unless
    helper.include?(%q{raise unless releases.length == 1})
  abort "publication helper does not enforce an exact confirmation" unless
    helper.include?(%q{publish approved $RELEASE_TAG release $RELEASE_ID})
  abort "publication helper does not exact-ID redownload assets" unless
    helper.include?(%q{/releases/assets/$asset_id})
  abort "publication helper does not isolate credentials through the tracked timeout launcher" unless
    helper.scan(%q{release_run_tracked_secret_env_timeout GH_TOKEN "$write_token" 90 gh api}).length == 1 &&
      helper.scan(%q{release_run_tracked_secret_env_timeout GH_TOKEN "$admin_read_token" 90 gh api}).length == 5 &&
      !helper.match?(/GH_TOKEN="\$(?:write_token|admin_read_token)"\s+gh api/)
  abort "publication helper does not bind the direct approval successor" unless
    helper.include?(%q{git rev-list --parents -n 1 "$RELEASE_APPROVAL_RECORD_COMMIT"}) &&
      helper.include?(%q{remote-controls-pre-publication.json})
  abort "release-only approval schema still contains site publication authority" if
    policy.include?(%q{sitePublication})
  abort "publication policy lacks a safe generic failure boundary" unless
    policy.include?("rescue StandardError") &&
      policy.include?("Publication policy error: approval verification failed safely.")
' "$publication_helper" "$publication_policy"
pass

ruby -ryaml -rjson -e '
  workflow = YAML.safe_load(File.read(ARGV.fetch(0)), aliases: true)
  jobs = workflow.fetch("jobs")
  guard = jobs.fetch("validate-dispatch")
  build = jobs.fetch("build-candidate")
  draft = jobs.fetch("signed-draft")
  abort "dispatch guard unexpectedly has token permissions" unless guard.fetch("permissions") == {}
  abort "build does not depend only on the dispatch guard" unless build.fetch("needs") == "validate-dispatch"
  abort "draft does not depend only on the dispatch guard" unless draft.fetch("needs") == "validate-dispatch"
  abort "build phase condition differs" unless build.fetch("if") == "${{ inputs.operation == '\''build-candidate'\'' }}"
  abort "draft phase condition differs" unless draft.fetch("if") == "${{ inputs.operation == '\''prepare-draft'\'' }}"
  abort "build permissions differ" unless build.fetch("permissions") == {
    "contents" => "read", "id-token" => "write", "attestations" => "write", "artifact-metadata" => "write"
  }
  abort "draft permissions differ" unless draft.fetch("permissions") == {
    "actions" => "read", "attestations" => "read", "contents" => "write"
  }
  abort "protected environments differ" unless [build, draft].all? { |job| job.fetch("environment") == "release-candidate" }
  abort "draft contains a signing secret expression" if JSON.generate(draft).include?("${{ secrets.")
  names = draft.fetch("steps").map { |step| step.fetch("name") }
  private_paths = names.index("Prepare private candidate paths")
  restore = names.index("Restore the exact candidate from its separate origin run")
  preverify = names.index("Verify the exact origin candidate and attestations before draft mutation")
  mutate = names.index("Create or resume the exact additive-only draft")
  postverify = names.index("Verify the redownloaded draft and attestations")
  abort "draft verification/mutation order differs" unless [private_paths, restore, preverify, mutate, postverify].all? && private_paths < restore && restore < preverify && preverify < mutate && mutate < postverify
  private_paths_script = draft.fetch("steps").fetch(private_paths).fetch("run")
  abort "private candidate paths are not fail-closed" unless
    private_paths_script.include?(%q{if [[ -e "$path" || -L "$path" ]]}) &&
    private_paths_script.include?(%q{mkdir -m 0700 -- "$path"})
  preverify_step = draft.fetch("steps").fetch(preverify)
  abort "pre-mutation attestation gate differs" unless preverify_step.fetch("run") == "make verify-downloaded-release" && preverify_step.fetch("env").fetch("RELEASE_DOWNLOAD_DIR") == "artifacts/release"
' "$workflow"
pass

draft_job="$temporary_root/signed-draft-job.yml"
sed -n '/^  signed-draft:/,$p' "$workflow" >"$draft_job"
assert_contains "$draft_job" "actions: read"
assert_contains "$draft_job" "attestations: read"
assert_contains "$draft_job" "contents: write"
assert_not_contains "$draft_job" '${{ secrets.'

assert_contains "$prepare_draft" "--draft"
assert_contains "$prepare_draft" "--prerelease"
assert_not_contains "$prepare_draft" "--clobber"
assert_not_contains "$prepare_draft" "gh release edit"
assert_not_contains "$prepare_draft" "gh release delete"
assert_contains "$verify_candidate" "release_require_env RELEASE_CANDIDATE_RUN_ATTEMPT"
assert_contains "$verify_candidate" "release_require_env RELEASE_CANDIDATE_RUN_ID"
assert_contains "$verify_candidate" '--run-id "$RELEASE_CANDIDATE_RUN_ID"'
assert_not_contains "$verify_candidate" '--run-id "$GITHUB_RUN_ID"'
assert_contains "$verify_candidate" '--run-attempt "$RELEASE_CANDIDATE_RUN_ATTEMPT"'
assert_not_contains "$verify_candidate" '--run-attempt "$GITHUB_RUN_ATTEMPT"'
assert_contains "$prepare_draft" "Draft preparation must restore a candidate from a separate origin run."
assert_contains "$prepare_draft" "unset github_token"
assert_contains "$prepare_draft" 'github_token="${GH_TOKEN:-}"'
assert_contains "$prepare_draft" "export -n github_token"
assert_contains "$prepare_draft" "unset GH_TOKEN GITHUB_TOKEN"
assert_before "$prepare_draft" "unset github_token" 'github_token="${GH_TOKEN:-}"'
assert_before "$prepare_draft" 'github_token="${GH_TOKEN:-}"' "unset GH_TOKEN GITHUB_TOKEN"
assert_before "$prepare_draft" "unset GH_TOKEN GITHUB_TOKEN" 'source "$(dirname "$0")/lib.sh"'
assert_contains "$restore_candidate" 'github_token="${GH_TOKEN:-}"'
assert_contains "$restore_candidate" "unset GH_TOKEN"
assert_contains "$restore_candidate" "RELEASE_CANDIDATE_ARTIFACT_SHA256"
assert_not_contains "$restore_candidate" "gh release"
assert_contains "$verify_downloaded" "unset github_token"
assert_contains "$verify_downloaded" 'github_token="${GH_TOKEN:-}"'
assert_contains "$verify_downloaded" "export -n github_token"
assert_contains "$verify_downloaded" "unset GH_TOKEN GITHUB_TOKEN"
assert_before "$verify_downloaded" "unset github_token" 'github_token="${GH_TOKEN:-}"'
assert_before "$verify_downloaded" 'github_token="${GH_TOKEN:-}"' "unset GH_TOKEN GITHUB_TOKEN"
assert_before "$verify_downloaded" "unset GH_TOKEN GITHUB_TOKEN" 'source "$(dirname "$0")/lib.sh"'
assert_contains "$verify_downloaded" 'GH_TOKEN="$github_token" gh attestation verify'
assert_not_contains "$verify_downloaded" "release_require_env GH_TOKEN"

ruby -e '
  prepare, downloaded = ARGV.map { |path| File.binread(path) }
  abort "draft reconciler does not use four tracked credential boundaries" unless
    prepare.scan(/release_run_tracked_secret_env_timeout\s+GH_TOKEN\s+"\$github_token"\s+90\b/).length == 4 &&
      !prepare.match?(/GH_TOKEN="\$github_token"\s+gh /)
  downloaded_gh = downloaded.lines.grep(/\bgh attestation verify /)
  abort "downloaded verifier has an unscoped gh command" unless
    downloaded_gh.length == 3 && downloaded_gh.all? { |line| line.include?(%q{GH_TOKEN="$github_token" gh }) }
' "$prepare_draft" "$verify_downloaded"
pass

import_signing="$RELEASE_SCRIPTS_DIR/import-signing-certificate.sh"
build_candidate="$RELEASE_SCRIPTS_DIR/build-candidate.sh"
cleanup_signing="$RELEASE_SCRIPTS_DIR/cleanup-signing-keychain.sh"

for script in "$import_signing" "$build_candidate" "$cleanup_signing"; do
    assert_contains "$script" '"${RUNNER_ENVIRONMENT:-}" == github-hosted'
done
assert_contains "$import_signing" 'umask 077'
assert_contains "$import_signing" 'certificate_base64="${DEVELOPER_ID_CERTIFICATE_BASE64:-}"'
assert_contains "$import_signing" 'unset DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD'
assert_contains "$import_signing" 'mktemp -d "$RUNNER_TEMP/desk-setup-release-signing.XXXXXX"'
assert_contains "$import_signing" 'mktemp "$signing_directory/developer-id.p12.XXXXXX"'
assert_contains "$import_signing" 'printf '\''RELEASE_SIGNING_KEYCHAIN=%s\n'\'' "$RELEASE_SIGNING_KEYCHAIN"'
assert_contains "$import_signing" 'printf '\''RELEASE_SIGNING_CERTIFICATE_PATH=%s\n'\'' "$RELEASE_SIGNING_CERTIFICATE_PATH"'
assert_not_contains "$import_signing" 'desk-setup-release.keychain-db'
assert_not_contains "$import_signing" 'desk-setup-developer-id.p12'

assert_contains "$build_candidate" 'cleanup-signing-keychain.sh" --preserve-directory'
assert_contains "$build_candidate" 'mktemp -d "$RUNNER_TEMP/desk-setup-release-notary.XXXXXX"'
assert_contains "$build_candidate" 'mktemp "$notary_directory/api-key.p8.XXXXXX"'
assert_contains "$build_candidate" 'The imported Developer ID certificate was not deleted immediately.'
assert_contains "$build_candidate" '--toolchain "runner-environment=$RUNNER_ENVIRONMENT"'
assert_contains "$build_candidate" 'Ephemeral release Keychain must use mode 0600.'
assert_contains "$build_candidate" 'Notary API key directory is unsafe.'
assert_contains "$build_candidate" 'notary_api_key_base64="${APPLE_NOTARY_API_KEY_BASE64:-}"'
assert_contains "$build_candidate" 'unset APPLE_NOTARY_API_KEY_BASE64'
assert_contains "$build_candidate" 'release_install_exit_signal_traps'
assert_contains "$build_candidate" 'verify-notary'
assert_contains "$build_candidate" '--print-id)'
assert_not_contains "$build_candidate" 'JSON.parse(File.read'
assert_not_contains "$build_candidate" 'desk-setup-notary-api-key.p8'

assert_contains "$cleanup_signing" 'rm -f -- "$RELEASE_SIGNING_CERTIFICATE_PATH"'
assert_contains "$cleanup_signing" 'security delete-keychain "$RELEASE_SIGNING_KEYCHAIN"'
assert_contains "$cleanup_signing" 'Release Keychain still exists after deletion.'
assert_contains "$cleanup_signing" 'rmdir "$signing_directory"'
assert_not_contains "$cleanup_signing" 'desk-setup-developer-id.p12'
assert_not_contains "$cleanup_signing" 'desk-setup-notary-api-key.p8'
assert_contains "$cleanup_signing" 'Ephemeral release signing material was already removed.'

template_signing_directory="$(mktemp -d "$temporary_root/template-signing.XXXXXX")"
template_certificate="$(mktemp "$template_signing_directory/developer-id.p12.XXXXXX")"
template_notary_directory="$(mktemp -d "$temporary_root/template-notary.XXXXXX")"
template_notary_key="$(mktemp "$template_notary_directory/api-key.p8.XXXXXX")"
[[ "$(stat -f %Lp "$template_signing_directory")" == 700 ]] || {
    release_die "Random signing directory mode is not 0700."
}
for secret_file in "$template_certificate" "$template_notary_key"; do
    [[ "$(stat -f %Lp "$secret_file")" == 600 ]] || {
        release_die "Random release secret file mode is not 0600."
    }
done
pass

private_evidence_root="$(mktemp -d "$temporary_root/remote-controls-output.XXXXXX")"
chmod 0700 "$private_evidence_root"
private_evidence_output="$private_evidence_root/remote-controls-final-pre-tag.json"
remote_controls_dry_run="$temporary_root/remote-controls-make-dry-run.txt"
make -n --no-print-directory verify-remote-controls \
    REMOTE_CONTROLS_EVIDENCE_OUTPUT="$private_evidence_output" \
    >"$remote_controls_dry_run" 2>&1
if grep -F -q -- "$private_evidence_output" "$remote_controls_dry_run"; then
    release_die "The remote-controls make dry run disclosed its private evidence path."
fi
grep -F -q -- '${REMOTE_CONTROLS_EVIDENCE_OUTPUT:-}' \
    "$remote_controls_dry_run" \
    && grep -F -q -- '${REMOTE_CONTROLS_EVIDENCE_OUTPUT}' \
        "$remote_controls_dry_run" || {
    release_die "The remote-controls make recipe does not defer its private path to the shell."
}
pass

remote_controls_mock_bin="$temporary_root/remote-controls-mock-bin"
remote_controls_gh_marker="$temporary_root/remote-controls-gh-called"
remote_controls_operational_log="$temporary_root/remote-controls-operational.log"
mkdir "$remote_controls_mock_bin"
cat >"$remote_controls_mock_bin/gh" <<'MOCK_REMOTE_CONTROLS_GH'
#!/usr/bin/env bash
set -euo pipefail
: >"${MOCK_REMOTE_CONTROLS_GH_MARKER:?}"
exit 99
MOCK_REMOTE_CONTROLS_GH
chmod 0755 "$remote_controls_mock_bin/gh"
set +e
PATH="$remote_controls_mock_bin:$PATH" \
MOCK_REMOTE_CONTROLS_GH_MARKER="$remote_controls_gh_marker" \
REMOTE_CONTROLS_EVIDENCE_OUTPUT="$private_evidence_output" \
    make --no-print-directory verify-remote-controls \
    >"$remote_controls_operational_log" 2>&1
remote_controls_operational_status=$?
set -e
[[ "$remote_controls_operational_status" -ne 0 \
   && ! -e "$private_evidence_output" && ! -L "$private_evidence_output" \
   && ! -e "$remote_controls_gh_marker" && ! -L "$remote_controls_gh_marker" ]] || {
    release_die "The disabled remote-controls gate wrote evidence or resolved gh."
}
grep -F -q -- 'ERROR: remote controls policy mismatch' \
    "$remote_controls_operational_log" || {
    release_die "The operational remote-controls check did not stop at configured:false."
}
if grep -F -q -- "$private_evidence_output" "$remote_controls_operational_log"; then
    release_die "The disabled remote-controls gate disclosed its private evidence path."
fi
pass

run_tracked_signal_case() {
    local disposition="$1"
    local signal_name="$2"
    local expected_status="$3"
    local case_root="$temporary_root/tracked-signal-$disposition-$signal_name"
    local runner_temp="$case_root/runner"
    local signal_root="$case_root/state"
    local marker="$case_root/cleanup-ran"
    local custom_marker="$case_root/original-trap-ran"
    local child_pid_audit="$case_root/child-audit.pid"
    local child_pid harness_status started_at elapsed child_was_alive=false
    mkdir -p "$runner_temp" "$signal_root"
    chmod 0700 "$runner_temp"
    started_at=$SECONDS
    set +e
    RUNNER_TEMP="$runner_temp" bash -c '
      source "$1"
      signal_root="$2"
      marker="$3"
      custom_marker="$4"
      disposition="$5"
      signal_name="$6"
      child_pid_audit="$7"
      harness_pid="${BASHPID:-$$}"
      cleanup_on_exit() {
        local exit_status=$?
        trap - EXIT
        trap "" HUP INT QUIT TERM
        set +e
        release_stop_active_child
        rmdir "$signal_root"
        : >"$marker"
        exit "$exit_status"
      }
      trap cleanup_on_exit EXIT
      case "$disposition" in
        default) trap - "$signal_name" ;;
        ignored) trap "" "$signal_name" ;;
        custom) trap ": >\"$custom_marker\"" "$signal_name" ;;
        *) exit 92 ;;
      esac
      release_run_tracked ruby -e "
        signal_name, harness_pid_text, audit_path = ARGV
        harness_pid = Integer(harness_pid_text, 10)
        File.binwrite(audit_path, Process.pid.to_s + %Q[\\n])
        Process.kill(signal_name, harness_pid)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
        sleep 0.05 while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
        fallback = signal_name == %q[TERM] ? %q[HUP] : %q[TERM]
        begin
          Process.kill(fallback, harness_pid)
        rescue Errno::ESRCH
          exit!(0)
        end
        sleep 0.5
        begin
          Process.kill(%q[KILL], harness_pid)
        rescue Errno::ESRCH
        end
      " "$signal_name" "$harness_pid" "$child_pid_audit"
    ' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$signal_root" "$marker" \
        "$custom_marker" "$disposition" "$signal_name" "$child_pid_audit"
    harness_status=$?
    set -e
    elapsed=$((SECONDS - started_at))
    [[ -s "$child_pid_audit" ]] || {
        release_die "Tracked child did not start for the $signal_name cancellation test."
    }
    child_pid="$(tr -d '\n' <"$child_pid_audit")"
    if kill -0 "$child_pid" >/dev/null 2>&1; then
        child_was_alive=true
        kill -KILL -- "-$child_pid" >/dev/null 2>&1 \
            || kill -KILL "$child_pid" >/dev/null 2>&1 || true
        for _attempt in {1..40}; do
            kill -0 "$child_pid" >/dev/null 2>&1 || break
            sleep 0.05
        done
    fi
    [[ "$harness_status" == "$expected_status" && "$elapsed" -lt 5 \
       && -f "$marker" && ! -e "$signal_root" && ! -L "$signal_root" \
       && ! -e "$custom_marker" && ! -L "$custom_marker" \
       && "$child_was_alive" == false \
       && -z "$(find "$runner_temp" -maxdepth 1 -name 'desk-setup-tracked-launch.*' -print -quit)" ]] || {
        release_die "$disposition $signal_name did not cancel the tracked child with exact cleanup semantics."
    }
    pass
}

for tracked_disposition in default ignored custom; do
    run_tracked_signal_case "$tracked_disposition" HUP 129
    run_tracked_signal_case "$tracked_disposition" INT 130
    run_tracked_signal_case "$tracked_disposition" QUIT 131
    run_tracked_signal_case "$tracked_disposition" TERM 143
done

tracked_restore_root="$temporary_root/tracked-signal-restoration"
mkdir -m 0700 "$tracked_restore_root"
RUNNER_TEMP="$tracked_restore_root" bash -c '
  source "$1"
  for disposition in default ignored custom; do
    for signal_name in HUP INT QUIT TERM; do
      case "$disposition" in
        default) trap - "$signal_name" ;;
        ignored) trap "" "$signal_name" ;;
        custom) trap "custom_trap_counter=\$((custom_trap_counter + 1))" "$signal_name" ;;
      esac
      before="$(trap -p "$signal_name")"
      release_run_tracked ruby -e "exit 0"
      after="$(trap -p "$signal_name")"
      [[ "$after" == "$before" && -z "${release_active_child_pid:-}" \
         && -z "${release_active_launch_root:-}" ]]
      [[ -z "$(find "$RUNNER_TEMP" -maxdepth 1 \
          -name "desk-setup-tracked-launch.*" -print -quit)" ]]
    done
  done
' _ "$RELEASE_SCRIPTS_DIR/lib.sh" || {
    release_die "Tracked execution did not restore the caller signal dispositions after normal exit."
}
pass

tracked_boundary_root="$temporary_root/tracked-boundaries"
mkdir -m 0700 "$tracked_boundary_root"

RUNNER_TEMP="$tracked_boundary_root" bash -c '
  source "$1"
  output="$2"
  set +e
  release_run_tracked ruby -e "exit 23"
  status=$?
  set -e
  [[ "$status" == 23 ]]
  secret="$(ruby -rsecurerandom -e "STDOUT.write(SecureRandom.hex(32))")"
  expected="$(printf "%s" "$secret" | shasum -a 256 | cut -d " " -f 1)"
  release_run_tracked_secret_env TEST_SCOPED_SECRET "$secret" ruby -rdigest -e "
    value = ENV.delete(%q[TEST_SCOPED_SECRET])
    raise unless value && STDIN.stat.chardev? && STDIN.read.empty?
    File.binwrite(ARGV.fetch(0), Digest::SHA256.hexdigest(value) + %Q[\\n])
  " "$output"
  [[ "$(tr -d "\\n" <"$output")" == "$expected" ]]
  [[ -z "$(find "$RUNNER_TEMP" -maxdepth 1 -name "desk-setup-tracked-launch.*" -print -quit)" ]]
' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$tracked_boundary_root/secret-result.txt" || {
    release_die "Tracked plain/secret normal exit or /dev/null stdin boundary failed."
}
pass

set +e
RUNNER_TEMP="$tracked_boundary_root" bash -c '
  source "$1"
  release_run_tracked_timeout 1 ruby -e "Signal.trap(%q[TERM], %q[IGNORE]); sleep 10"
' _ "$RELEASE_SCRIPTS_DIR/lib.sh"
tracked_timeout_status=$?
set -e
[[ "$tracked_timeout_status" == 124 \
   && -z "$(find "$tracked_boundary_root" -maxdepth 1 -name 'desk-setup-tracked-launch.*' -print -quit)" ]] || {
    release_die "Tracked timeout did not return 124 and clean its launch root."
}
pass

run_lingering_boundary_case() {
    local mode="$1"
    local case_root="$tracked_boundary_root/lingering-$mode"
    local pid_file="$case_root/descendant.pid"
    local status descendant_pid
    mkdir -m 0700 "$case_root"
    set +e
    RUNNER_TEMP="$case_root" bash -c '
      source "$1"
      mode="$2"
      pid_file="$3"
      hold_open=false
      [[ "$mode" == timeout ]] && hold_open=true
      command=(ruby -rrbconfig -e "
        child = Process.spawn(RbConfig.ruby, %q[-e], %q[Signal.trap(\"TERM\", \"IGNORE\"); sleep 10])
        File.binwrite(ARGV.fetch(0), child.to_s + %Q[\\n])
        sleep 10 if ARGV.fetch(1) == %q[true]
      " "$pid_file" "$hold_open")
      if [[ "$mode" == secret ]]; then
        secret="$(ruby -rsecurerandom -e "STDOUT.write(SecureRandom.hex(32))")"
        release_run_tracked_secret_env TEST_SCOPED_SECRET "$secret" "${command[@]}"
      elif [[ "$mode" == timeout ]]; then
        release_run_tracked_timeout 1 "${command[@]}"
      else
        release_run_tracked "${command[@]}"
      fi
    ' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$mode" "$pid_file"
    status=$?
    set -e
    [[ -s "$pid_file" ]] || release_die "The $mode lingering descendant did not start."
    descendant_pid="$(tr -d '\n' <"$pid_file")"
    [[ "$status" == 70 ]] || release_die "The $mode lingering descendant was not reported safely."
    for _attempt in {1..40}; do
        if ! kill -0 "$descendant_pid" >/dev/null 2>&1; then
            break
        fi
        sleep 0.05
    done
    if kill -0 "$descendant_pid" >/dev/null 2>&1; then
        release_die "The $mode lingering descendant remained alive."
    fi
    [[ -z "$(find "$case_root" -maxdepth 1 -name 'desk-setup-tracked-launch.*' -print -quit)" ]] || {
        release_die "The $mode lingering case leaked launch state."
    }
    pass
}

run_lingering_boundary_case plain
run_lingering_boundary_case secret
run_lingering_boundary_case timeout

tracked_foreign_root="$tracked_boundary_root/foreign-entry"
tracked_foreign_runner="$tracked_foreign_root/runner"
tracked_foreign_sentinel="$tracked_foreign_root/outside-sentinel"
tracked_foreign_audit="$tracked_foreign_root/pointer-audit"
mkdir -p "$tracked_foreign_runner"
chmod 0700 "$tracked_foreign_runner"
printf 'outside-safe\n' >"$tracked_foreign_sentinel"
set +e
RUNNER_TEMP="$tracked_foreign_runner" bash -c '
  source "$1"
  audit_path="$2"
  sentinel_path="$3"
  set +e
  release_run_tracked ruby -e "
    sentinel_path = ARGV.fetch(0)
    roots = Dir.glob(File.join(ENV.fetch(%q[RUNNER_TEMP]), %q[desk-setup-tracked-launch.*]))
    raise unless roots.length == 1
    root = roots.fetch(0)
    File.binwrite(File.join(root, %q[foreign-file]), %Q[foreign\n])
    Dir.mkdir(File.join(root, %q[foreign-directory]))
    File.binwrite(File.join(root, %q[foreign-directory], %q[value]), %Q[value\n])
    File.symlink(sentinel_path, File.join(root, %q[foreign-symlink]))
  " "$sentinel_path"
  status=$?
  set -e
  printf "%s\t%s\n" "${release_active_child_pid:-}" \
    "${release_active_launch_root:-}" >"$audit_path"
  exit "$status"
' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$tracked_foreign_audit" \
    "$tracked_foreign_sentinel"
tracked_foreign_status=$?
set -e
[[ "$tracked_foreign_status" == 70 \
   && "$(tr -d '\n' <"$tracked_foreign_sentinel")" == outside-safe \
   && -z "$(find "$tracked_foreign_runner" -maxdepth 1 \
       -name 'desk-setup-tracked-launch.*' -print -quit)" ]] || {
    release_die "A foreign launch-root entry was not removed safely with status 70."
}
ruby -e 'raise unless File.binread(ARGV.fetch(0)) == "\t\n"' \
    "$tracked_foreign_audit" || {
    release_die "Foreign-entry cleanup retained an active child or launch-root pointer."
}
pass

ruby -e '
  source = File.binread(ARGV.fetch(0))
  abort "timeout supervisor installs the secret in its own ENV" if
    source.include?(%q{ENV[environment_name] = secret})
  spawn = source.index(%q{child = Process.spawn(child_environment, *command)}) or
    abort "timeout supervisor lacks child-only secret environment"
  secret_clear = source.index(%q{secret.clear}, spawn) or
    abort "timeout supervisor does not clear the secret string"
  environment_clear = source.index(%q{child_environment.clear}, spawn) or
    abort "timeout supervisor does not clear the child environment hash"
  abort "timeout supervisor secret clearing order differs" unless
    spawn < secret_clear && secret_clear < environment_clear
' "$RELEASE_SCRIPTS_DIR/lib.sh"
pass

tracked_supervisor_root="$tracked_boundary_root/secret-timeout-supervisor"
tracked_supervisor_runner="$tracked_supervisor_root/runner"
tracked_supervisor_audit="$tracked_supervisor_root/child-audit"
tracked_supervisor_permit="$tracked_supervisor_root/permit-exit"
tracked_supervisor_ps="$tracked_supervisor_root/supervisor-ps.txt"
tracked_supervisor_stdout="$tracked_supervisor_root/harness.stdout"
tracked_supervisor_stderr="$tracked_supervisor_root/harness.stderr"
mkdir -p "$tracked_supervisor_runner"
chmod 0700 "$tracked_supervisor_runner"
tracked_supervisor_secret="$(runtime_secret)"
export -n tracked_supervisor_secret 2>/dev/null || true
tracked_supervisor_expected="$(printf '%s' "$tracked_supervisor_secret" \
    | shasum -a 256 | cut -d ' ' -f 1)"
{ printf '%s\n' "$tracked_supervisor_secret"; } | \
RUNNER_TEMP="$tracked_supervisor_runner" bash -c '
  source "$1"
  audit_path="$2"
  permit_path="$3"
  IFS= read -r scoped_secret
  release_run_tracked_secret_env_timeout TEST_SCOPED_SECRET "$scoped_secret" 5 \
    ruby -rdigest -e "
      audit_path, permit_path = ARGV
      value = ENV.delete(%q[TEST_SCOPED_SECRET])
      raise unless value && STDIN.stat.chardev? && STDIN.read.empty?
      value = String.new(value)
      digest = Digest::SHA256.hexdigest(value)
      value.clear
      File.binwrite(audit_path, [Process.ppid, Process.pid, digest].join(%Q[\t]) + %Q[\n])
      sleep 0.01 until File.exist?(permit_path)
    " "$audit_path" "$permit_path"
' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$tracked_supervisor_audit" \
    "$tracked_supervisor_permit" >"$tracked_supervisor_stdout" \
    2>"$tracked_supervisor_stderr" &
tracked_supervisor_harness_pid=$!
for _attempt in {1..400}; do
    [[ -s "$tracked_supervisor_audit" ]] && break
    sleep 0.005
done
[[ -s "$tracked_supervisor_audit" ]] || {
    kill -KILL "$tracked_supervisor_harness_pid" >/dev/null 2>&1 || true
    wait "$tracked_supervisor_harness_pid" >/dev/null 2>&1 || true
    release_die "The secret timeout supervisor child did not start."
}
IFS=$'\t' read -r tracked_supervisor_pid tracked_supervisor_child_pid \
    tracked_supervisor_actual <"$tracked_supervisor_audit"
[[ "$tracked_supervisor_pid" =~ ^[1-9][0-9]*$ \
   && "$tracked_supervisor_child_pid" =~ ^[1-9][0-9]*$ \
   && "$tracked_supervisor_actual" == "$tracked_supervisor_expected" ]] || {
    release_die "The secret timeout supervisor child boundary differs."
}
ps eww -p "$tracked_supervisor_pid" -o command= >"$tracked_supervisor_ps"
: >"$tracked_supervisor_permit"
set +e
wait "$tracked_supervisor_harness_pid"
tracked_supervisor_status=$?
set -e
[[ "$tracked_supervisor_status" == 0 \
   && -z "$(find "$tracked_supervisor_runner" -maxdepth 1 \
       -name 'desk-setup-tracked-launch.*' -print -quit)" ]] || {
    release_die "The secret timeout supervisor did not exit and clean normally."
}
if printf '%s' "$tracked_supervisor_secret" | ruby -e '
  secret = STDIN.read
  root = ARGV.fetch(0)
  paths = Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)
  leaked = paths.any? do |path|
    next false unless File.file?(path) && !File.symlink?(path)
    File.binread(path).include?(secret)
  rescue Errno::ENOENT
    false
  end
  exit(leaked ? 0 : 1)
' "$tracked_supervisor_root"; then
    release_die "The timeout supervisor exposed its raw secret through argv, environment, logs, or files."
fi
unset tracked_supervisor_secret
pass

tracked_race_root="$tracked_boundary_root/launch-race"
tracked_race_runner="$tracked_race_root/runner"
tracked_race_pid_file="$tracked_race_root/child.pid"
tracked_race_permit="$tracked_race_root/permit-late-effect"
tracked_race_marker="$tracked_race_root/late-marker"
mkdir -p "$tracked_race_runner"
chmod 0700 "$tracked_race_runner"
RUNNER_TEMP="$tracked_race_runner" bash -c '
  source "$1"
  release_install_exit_signal_traps
  release_run_tracked ruby -e "
    pid_path, permit_path, marker_path = ARGV
    File.binwrite(pid_path, Process.pid.to_s + %Q[\\n])
    sleep 0.01 until File.exist?(permit_path)
    File.binwrite(marker_path, %Q[late\\n])
    sleep 10
  " "$2" "$3" "$4"
' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$tracked_race_pid_file" "$tracked_race_permit" \
    "$tracked_race_marker" &
tracked_race_harness_pid=$!
tracked_race_observed=false
for _attempt in {1..400}; do
    if [[ -n "$(find "$tracked_race_runner" -maxdepth 1 \
        -name 'desk-setup-tracked-launch.*' -print -quit)" ]]; then
        tracked_race_observed=true
        break
    fi
    sleep 0.005
done
set +e
kill -TERM "$tracked_race_harness_pid" >/dev/null 2>&1
tracked_race_kill_status=$?
wait "$tracked_race_harness_pid"
tracked_race_status=$?
set -e
: >"$tracked_race_permit"
sleep 0.7
tracked_race_launch_state=false
[[ -z "$(find "$tracked_race_runner" -maxdepth 1 \
    -name 'desk-setup-tracked-launch.*' -print -quit)" ]] || tracked_race_launch_state=true
if [[ "$tracked_race_observed" != true || "$tracked_race_kill_status" != 0 \
    || "$tracked_race_status" != 143 || -e "$tracked_race_marker" \
    || -L "$tracked_race_marker" || "$tracked_race_launch_state" != false ]]; then
    release_die "Launch-race cancellation failed (observed=$tracked_race_observed kill=$tracked_race_kill_status status=$tracked_race_status marker=$([[ -e "$tracked_race_marker" || -L "$tracked_race_marker" ]] && printf present || printf absent) launch-state=$tracked_race_launch_state)."
fi
if [[ -s "$tracked_race_pid_file" ]]; then
    tracked_race_child_pid="$(tr -d '\n' <"$tracked_race_pid_file")"
    if kill -0 "$tracked_race_child_pid" >/dev/null 2>&1; then
        release_die "Launch-race cancellation left the tracked child alive."
    fi
fi
pass

ruby -e '
  import, build, cleanup = ARGV.map { |path| File.read(path) }

  position = lambda do |text, needle, message|
    text.index(needle) || abort(message)
  end

  import_no_export = position.call(import, "set +a", "Certificate script does not disable allexport.")
  import_local_unset = position.call(import, "unset certificate_base64 certificate_password", "Inherited local certificate variables are not cleared.")
  import_capture = position.call(import, "certificate_base64=\"${DEVELOPER_ID_CERTIFICATE_BASE64:-}\"", "Certificate secret capture is missing.")
  import_unset = position.call(import, "unset DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD", "Certificate secret unexport is missing.")
  import_source = position.call(import, "source \"$(dirname", "Release library import is missing.")
  import_umask = position.call(import, "umask 077", "Signing umask is missing.")
  signing_dir = position.call(import, "signing_directory=\"$(mktemp -d", "Random signing directory is missing.")
  certificate = position.call(import, "certificate_path=\"$(mktemp", "Random certificate path is missing.")
  handoff = position.call(import, "} >>\"$GITHUB_ENV\"", "Runner environment handoff is missing.")
  decode = position.call(import, "openssl base64 -d -A -out \"$certificate_path\"", "Certificate decode is missing.")
  delete_certificate = import.index("rm -f -- \"$certificate_path\"", decode) || abort("Immediate certificate deletion is missing.")
  abort "Certificate secrets reach a child process before being unexported." unless import_no_export < import_local_unset && import_local_unset < import_capture && import_capture < import_unset && import_unset < import_source
  abort "Signing secret setup ordering is unsafe." unless import_source < import_umask && import_umask < signing_dir && signing_dir < certificate && certificate < handoff && handoff < decode && decode < delete_certificate
  import_tail = import.byteslice(import_unset..)
  abort "Exported certificate base64 is referenced after unexport." if import_tail.match?(/\$\{?DEVELOPER_ID_CERTIFICATE_BASE64/)
  abort "Exported certificate password is referenced after unexport." if import_tail.match?(/\$\{?DEVELOPER_ID_CERTIFICATE_PASSWORD/)

  notary_no_export = position.call(build, "set +a", "Notary script does not disable allexport.")
  notary_local_unset = position.call(build, "unset notary_api_key_base64", "Inherited local notary variable is not cleared.")
  notary_capture = position.call(build, "notary_api_key_base64=\"${APPLE_NOTARY_API_KEY_BASE64:-}\"", "Notary secret capture is missing.")
  notary_unset = position.call(build, "unset APPLE_NOTARY_API_KEY_BASE64", "Notary secret unexport is missing.")
  build_source = position.call(build, "source \"$(dirname", "Release library import is missing.")
  build_trap = position.call(build, "trap cleanup EXIT", "Notary cleanup trap is missing.")
  signal_traps = position.call(build, "release_install_exit_signal_traps", "Interrupt cleanup traps are missing.")
  notary_dir = position.call(build, "notary_directory=\"$(mktemp -d", "Random notary directory is missing.")
  notary_key = position.call(build, "notary_key=\"$(mktemp", "Random notary key is missing.")
  notary_decode = position.call(build, "openssl base64 -d -A -out \"$notary_key\"", "Notary key decode is missing.")
  notary_submit = position.call(build, "release_run_tracked xcrun notarytool submit", "Notary submission is not a tracked child.")
  notary_log = position.call(build, "release_run_tracked xcrun notarytool log", "Notary log fetch is not a tracked child.")
  delete_notary_key = build.index("rm -f -- \"$notary_key\"", notary_log) || abort("Immediate notary key deletion is missing.")
  verify_notary_key_deletion = build.index("Decoded notary API key still exists after deletion.", delete_notary_key) || abort("Notary key deletion is not verified.")
  abort "Notary secret reaches a child process before being unexported." unless notary_no_export < notary_local_unset && notary_local_unset < notary_capture && notary_capture < notary_unset && notary_unset < build_source
  abort "Notary secret lifecycle ordering is unsafe." unless build_source < build_trap && build_trap < signal_traps && signal_traps < notary_dir && notary_dir < notary_key && notary_key < notary_decode && notary_decode < notary_submit && notary_submit < notary_log && notary_log < delete_notary_key && delete_notary_key < verify_notary_key_deletion
  build_tail = build.byteslice(notary_unset..)
  abort "Exported notary base64 is referenced after unexport." if build_tail.match?(/\$\{?APPLE_NOTARY_API_KEY_BASE64/)

  abort "Cleanup may delete wildcard paths." if cleanup.match?(/\brm\b[^\n]*\*/)
  abort "Cleanup must only remove handed-off signing paths." if cleanup.include?("$RUNNER_TEMP/desk-setup-")
' "$import_signing" "$build_candidate" "$cleanup_signing"
pass

ruby -e '
  workflow = File.read(ARGV.fetch(0))
  uses = workflow.scan(/^\s*uses:\s*([^\s#]+)/).flatten
  abort "Release workflow has no pinned actions." if uses.empty?
  bad = uses.reject { |item| item.match?(/\A[^@\s]+@[0-9a-f]{40}\z/) }
  abort "Release workflow action is not pinned by commit SHA." unless bad.empty?
  %w[
    DEVELOPER_ID_CERTIFICATE_BASE64
    DEVELOPER_ID_CERTIFICATE_PASSWORD
    APPLE_NOTARY_API_KEY_BASE64
  ].each do |name|
    reference = "${{ secrets.#{name} }}"
    abort "Release secret #{name} must be scoped to exactly one consuming step." unless workflow.scan(reference).length == 1
  end
' "$workflow"
pass

ruby -e '
  script = File.read(ARGV.fetch(0))
  staple = script.index(%q{xcrun stapler staple "$dmg_path"}) or abort "Stapling step is missing."
  final_codesign = script.index(
    %q{codesign --verify --strict --verbose=2 "$dmg_path" >"$final_dmg_codesign_verify" 2>&1},
    staple
  ) or abort "Final DMG signature evidence is not captured after stapling."
  manifest = script.index(
    %q{--verification "dmgCodesign=$sanitized_dmg_codesign"},
    final_codesign
  ) or abort "Final DMG signature evidence is not bound into the release manifest."
  abort "Final DMG evidence ordering is invalid." unless staple < final_codesign && final_codesign < manifest
' "$RELEASE_SCRIPTS_DIR/build-candidate.sh"
pass

for script in "$RELEASE_SCRIPTS_DIR"/*.sh "$RELEASE_SCRIPTS_DIR"/*.rb; do
    [[ -x "$script" ]] || release_die "Release tooling is not executable: $script"
done
pass

printf 'Release tooling shell checks passed: %d assertions.\n' "$assertions"
