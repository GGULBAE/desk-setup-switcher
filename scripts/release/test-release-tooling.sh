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

assert_fails() {
    if "$@" >"$temporary_root/expected-failure.stdout" 2>"$temporary_root/expected-failure.stderr"; then
        release_die "A release safety guard unexpectedly allowed execution."
    fi
    pass
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-release-tests.XXXXXX")"
cleanup() {
    rm -rf "$temporary_root"
}
trap cleanup EXIT

ruby "$RELEASE_SCRIPTS_DIR/test_release_policy.rb"
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
        printf '0000000000000000000000000000000000000000000000000000000000000000\n'
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
        printf '  1) SYNTHETIC "%s"\n     1 valid identities found\n' "$DEVELOPER_ID_APPLICATION"
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
   || -n "${notary_api_key_base64+x}" ]]; then
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
    APPLE_NOTARY_API_KEY_BASE64=synthetic-notary-secret \
    notary_api_key_base64=preexisting-exported-secret \
    "$RELEASE_SCRIPTS_DIR/build-candidate.sh"
[[ -s "$build_secret_probe" ]] || release_die "The build secret isolation probe never reached the first child command."
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
    DEVELOPER_ID_CERTIFICATE_BASE64=synthetic-certificate \
    DEVELOPER_ID_CERTIFICATE_PASSWORD=synthetic-password \
    certificate_base64=preexisting-exported-certificate \
    certificate_password=preexisting-exported-password \
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

failed_runner="$temporary_root/mock-runner-failure"
failed_github_env="$failed_runner/github-env"
mkdir -p "$failed_runner"
assert_fails "${credential_environment[@]}" \
    "RUNNER_TEMP=$failed_runner" \
    "GITHUB_ENV=$failed_github_env" \
    DEVELOPER_ID_CERTIFICATE_BASE64=synthetic-certificate \
    DEVELOPER_ID_CERTIFICATE_PASSWORD=synthetic-password \
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
assert_contains "$workflow" "workflow_dispatch:"
assert_contains "$workflow" "environment: release-candidate"
assert_contains "$workflow" "DESK_SETUP_RELEASE_MUTATIONS: \"1\""
assert_contains "$workflow" "--draft"
assert_contains "$workflow" "--prerelease"
assert_contains "$workflow" "actions/attest@f7c74d28b9d84cb8768d0b8ca14a4bac6ef463e6"
assert_contains "$workflow" "make verify-downloaded-release"
assert_not_contains "$workflow" "push:"
assert_not_contains "$workflow" "--generate-notes"
assert_not_contains "$workflow" "--draft=false"
assert_not_contains "$workflow" "gh release edit"
assert_not_contains "$workflow" "unsigned"
assert_not_contains "$workflow" "artifacts/*.dmg"
assert_not_contains "$workflow" "RELEASE_SIGNING_KEYCHAIN:"
assert_contains "$workflow" "run: exec /bin/bash scripts/release/import-signing-certificate.sh"
assert_contains "$workflow" "run: exec /bin/bash scripts/release/build-candidate.sh"
assert_not_contains "$workflow" "run: make release-candidate"

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

tracked_signal_root="$temporary_root/tracked-signal"
tracked_signal_marker="$temporary_root/tracked-signal-cleanup-ran"
tracked_child_pid_file="$tracked_signal_root/child.pid"
tracked_key="$tracked_signal_root/api-key.p8"
mkdir -p "$tracked_signal_root"
bash -c '
  source "$1"
  signal_root="$2"
  marker="$3"
  child_pid_file="$4"
  key="$5"
  printf "synthetic key\n" >"$key"
  cleanup_on_exit() {
    local exit_status=$?
    trap - EXIT
    trap "" INT TERM
    set +e
    release_stop_active_child
    rm -f -- "$key" "$child_pid_file"
    rmdir "$signal_root"
    : >"$marker"
    exit "$exit_status"
  }
  trap cleanup_on_exit EXIT
  release_install_exit_signal_traps
  release_run_tracked ruby -e "Signal.trap(\"TERM\", \"IGNORE\"); File.write(ARGV.fetch(0), Process.pid.to_s); sleep 10" "$child_pid_file"
' _ "$RELEASE_SCRIPTS_DIR/lib.sh" "$tracked_signal_root" "$tracked_signal_marker" \
    "$tracked_child_pid_file" "$tracked_key" &
tracked_harness_pid=$!
for _attempt in $(seq 1 100); do
    [[ -s "$tracked_child_pid_file" ]] && break
    sleep 0.02
done
[[ -s "$tracked_child_pid_file" ]] || {
    kill -TERM "$tracked_harness_pid" >/dev/null 2>&1 || true
    wait "$tracked_harness_pid" >/dev/null 2>&1 || true
    release_die "Tracked child did not start for the cancellation cleanup test."
}
tracked_child_pid="$(tr -d '\n' <"$tracked_child_pid_file")"
tracked_started_at=$SECONDS
kill -TERM "$tracked_harness_pid"
set +e
wait "$tracked_harness_pid"
tracked_harness_status=$?
set -e
tracked_elapsed=$((SECONDS - tracked_started_at))
tracked_child_stopped=false
if ! kill -0 "$tracked_child_pid" >/dev/null 2>&1; then
    tracked_child_stopped=true
fi
[[ "$tracked_harness_status" == 143 && "$tracked_elapsed" -lt 5 \
   && -f "$tracked_signal_marker" \
   && ! -e "$tracked_signal_root" && ! -L "$tracked_signal_root" \
   && "$tracked_child_stopped" == true ]] || {
    release_die "TERM did not stop the tracked child and remove plaintext key state promptly."
}
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
