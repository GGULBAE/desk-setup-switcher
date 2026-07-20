#!/usr/bin/env bash

set +x
set +a

unset certificate_base64 certificate_password
certificate_base64="${DEVELOPER_ID_CERTIFICATE_BASE64:-}"
certificate_password="${DEVELOPER_ID_CERTIFICATE_PASSWORD:-}"
unset DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD

set -euo pipefail
source "$(dirname "$0")/lib.sh"

release_require_execution_context
[[ "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    release_die "Release signing is restricted to GitHub-hosted runners."
}
[[ -n "$certificate_base64" ]] || release_die "Required release input is missing: DEVELOPER_ID_CERTIFICATE_BASE64"
[[ -n "$certificate_password" ]] || release_die "Required release input is missing: DEVELOPER_ID_CERTIFICATE_PASSWORD"
release_require_single_line DEVELOPER_ID_APPLICATION
release_require_single_line APPLE_TEAM_ID
release_require_env GITHUB_ENV

[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || release_die "APPLE_TEAM_ID has an invalid format."
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]] || {
    release_die "DEVELOPER_ID_APPLICATION must be the exact Developer ID Application identity for APPLE_TEAM_ID."
}

release_require_path_within "$GITHUB_ENV" "$RUNNER_TEMP"
[[ ! -L "$GITHUB_ENV" && ( ! -e "$GITHUB_ENV" || -f "$GITHUB_ENV" ) ]] || {
    release_die "GITHUB_ENV must be a regular runner command file."
}

release_require_command openssl
release_require_command ruby
release_require_command security
release_require_command sleep
release_require_command stat

umask 077
unset signing_directory keychain_password certificate_path
unset RELEASE_SIGNING_KEYCHAIN RELEASE_SIGNING_CERTIFICATE_PATH
signing_directory=""
keychain_password=""
certificate_path=""
RELEASE_SIGNING_KEYCHAIN=""
RELEASE_SIGNING_CERTIFICATE_PATH=""
created=false

cleanup_failed_import() {
    local exit_status=$?
    local cleanup_failed=false
    trap - EXIT
    trap '' HUP INT QUIT TERM
    set +e

    if ! release_stop_active_child; then
        printf 'Release tooling error: a tracked signing child did not terminate.\n' >&2
        cleanup_failed=true
    fi
    certificate_base64=""
    certificate_password=""
    keychain_password=""
    if [[ -n "$certificate_path" ]]; then
        rm -f -- "$certificate_path"
        if [[ -e "$certificate_path" || -L "$certificate_path" ]]; then
            printf 'Release tooling error: decoded certificate remains after failed import cleanup.\n' >&2
            cleanup_failed=true
        fi
        certificate_path=""
    fi
    if [[ -n "$RELEASE_SIGNING_KEYCHAIN" ]]; then
        if [[ "$created" == true ]]; then
            security delete-keychain "$RELEASE_SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
        fi
        rm -f -- "$RELEASE_SIGNING_KEYCHAIN"
        if [[ -e "$RELEASE_SIGNING_KEYCHAIN" || -L "$RELEASE_SIGNING_KEYCHAIN" ]]; then
            printf 'Release tooling error: ephemeral Keychain remains after failed import cleanup.\n' >&2
            cleanup_failed=true
        fi
    fi
    if [[ -n "$signing_directory" ]]; then
        if ! rmdir "$signing_directory" >/dev/null 2>&1 \
            || [[ -e "$signing_directory" || -L "$signing_directory" ]]; then
            printf 'Release tooling error: private signing directory remains after failed import cleanup.\n' >&2
            cleanup_failed=true
        fi
        signing_directory=""
    fi
    if [[ "$exit_status" == 0 && "$cleanup_failed" == true ]]; then
        exit_status=1
    fi
    exit "$exit_status"
}
trap cleanup_failed_import EXIT
release_install_exit_signal_traps

signing_directory="$(mktemp -d "$RUNNER_TEMP/desk-setup-release-signing.XXXXXX")"
RELEASE_SIGNING_KEYCHAIN="$signing_directory/signing.keychain-db"
keychain_password="$(openssl rand -hex 32)"
[[ -d "$signing_directory" && ! -L "$signing_directory" \
   && "$(stat -f %Lp "$signing_directory")" == 700 ]] || {
    release_die "Release signing directory is unsafe."
}
[[ "$keychain_password" =~ ^[0-9a-f]{64}$ ]] || {
    release_die "Ephemeral Keychain password generation failed."
}

certificate_path="$(mktemp "$signing_directory/developer-id.p12.XXXXXX")"
RELEASE_SIGNING_CERTIFICATE_PATH="$certificate_path"
release_require_path_within "$RELEASE_SIGNING_KEYCHAIN" "$RUNNER_TEMP"
release_require_path_within "$RELEASE_SIGNING_CERTIFICATE_PATH" "$RUNNER_TEMP"
release_require_absent_path "$RELEASE_SIGNING_KEYCHAIN"

{
    printf 'RELEASE_SIGNING_KEYCHAIN=%s\n' "$RELEASE_SIGNING_KEYCHAIN"
    printf 'RELEASE_SIGNING_CERTIFICATE_PATH=%s\n' "$RELEASE_SIGNING_CERTIFICATE_PATH"
} >>"$GITHUB_ENV"

if ! printf '%s' "$certificate_base64" \
    | openssl base64 -d -A -out "$certificate_path"; then
    certificate_base64=""
    release_die "Developer ID certificate could not be decoded."
fi
certificate_base64=""
[[ -s "$certificate_path" ]] || release_die "Developer ID certificate could not be decoded."

security create-keychain -p "$keychain_password" "$RELEASE_SIGNING_KEYCHAIN"
created=true
chmod 0600 "$RELEASE_SIGNING_KEYCHAIN"
[[ -f "$RELEASE_SIGNING_KEYCHAIN" && ! -L "$RELEASE_SIGNING_KEYCHAIN" \
   && "$(stat -f %Lp "$RELEASE_SIGNING_KEYCHAIN")" == 600 ]] || {
    release_die "Ephemeral release Keychain is unsafe."
}
security set-keychain-settings -lut 21600 "$RELEASE_SIGNING_KEYCHAIN"
security unlock-keychain -p "$keychain_password" "$RELEASE_SIGNING_KEYCHAIN"
if ! security import "$certificate_path" \
    -k "$RELEASE_SIGNING_KEYCHAIN" \
    -P "$certificate_password" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null; then
    certificate_password=""
    release_die "Developer ID certificate import failed."
fi
certificate_password=""
security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$keychain_password" \
    "$RELEASE_SIGNING_KEYCHAIN" >/dev/null
keychain_password=""
rm -f -- "$certificate_path"
[[ ! -e "$certificate_path" && ! -L "$certificate_path" ]] || {
    release_die "Decoded Developer ID certificate still exists after deletion."
}

identities="$(security find-identity -v -p codesigning "$RELEASE_SIGNING_KEYCHAIN")"
identity_counts="$(printf '%s\n' "$identities" | ruby -e '
  expected = ARGV.fetch(0)
  lines = STDIN.read.lines(chomp: true)
  raise if lines.empty?
  summary = lines.pop
  summary_match = summary.match(/\A\s*([0-9]+) valid identities found\z/)
  raise unless summary_match
  declared_count = Integer(summary_match[1], 10)
  names = lines.map do |line|
    match = line.match(/\A\s*[0-9]+\) [0-9A-Fa-f]{40} "(.*)"\z/)
    raise unless match
    match[1]
  end
  raise unless names.length == declared_count
  puts [declared_count, names.count(expected)].join("\t")
' "$DEVELOPER_ID_APPLICATION" 2>/dev/null)" || {
    release_die "The temporary Keychain identity inventory is invalid."
}
IFS=$'\t' read -r valid_identity_count matching_identity_count <<<"$identity_counts"
[[ "$valid_identity_count" == 1 && "$matching_identity_count" == 1 ]] || {
    release_die "The temporary Keychain must contain exactly one valid codesigning identity, and it must match the reviewed Developer ID identity."
}
unset identities identity_counts valid_identity_count matching_identity_count

trap - EXIT HUP INT QUIT TERM
printf 'Imported the reviewed Developer ID identity into the ephemeral release Keychain.\n'
