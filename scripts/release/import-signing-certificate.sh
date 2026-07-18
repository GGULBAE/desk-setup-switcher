#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

release_require_execution_context
release_require_env DEVELOPER_ID_CERTIFICATE_BASE64
release_require_env DEVELOPER_ID_CERTIFICATE_PASSWORD
release_require_single_line DEVELOPER_ID_APPLICATION
release_require_single_line APPLE_TEAM_ID
release_require_env RELEASE_SIGNING_KEYCHAIN

[[ "$APPLE_TEAM_ID" =~ ^[A-Z0-9]{10}$ ]] || release_die "APPLE_TEAM_ID has an invalid format."
[[ "$DEVELOPER_ID_APPLICATION" == "Developer ID Application: "*" ($APPLE_TEAM_ID)" ]] || {
    release_die "DEVELOPER_ID_APPLICATION must be the exact Developer ID Application identity for APPLE_TEAM_ID."
}

release_require_path_within "$RELEASE_SIGNING_KEYCHAIN" "$RUNNER_TEMP"
[[ "$(basename "$RELEASE_SIGNING_KEYCHAIN")" == desk-setup-release.keychain-db ]] || {
    release_die "Unexpected release Keychain filename."
}
release_require_absent_path "$RELEASE_SIGNING_KEYCHAIN"

release_require_command openssl
release_require_command security

umask 077
certificate_path="$RUNNER_TEMP/desk-setup-developer-id.p12"
release_require_absent_path "$certificate_path"
keychain_password="$(openssl rand -hex 32)"
created=false
import_succeeded=false

cleanup_failed_import() {
    rm -f "$certificate_path"
    if [[ "$import_succeeded" != true && "$created" == true ]]; then
        security delete-keychain "$RELEASE_SIGNING_KEYCHAIN" >/dev/null 2>&1 || true
    fi
}
trap cleanup_failed_import EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

printf '%s' "$DEVELOPER_ID_CERTIFICATE_BASE64" \
    | openssl base64 -d -A -out "$certificate_path"
[[ -s "$certificate_path" ]] || release_die "Developer ID certificate could not be decoded."

security create-keychain -p "$keychain_password" "$RELEASE_SIGNING_KEYCHAIN"
created=true
security set-keychain-settings -lut 21600 "$RELEASE_SIGNING_KEYCHAIN"
security unlock-keychain -p "$keychain_password" "$RELEASE_SIGNING_KEYCHAIN"
security import "$certificate_path" \
    -k "$RELEASE_SIGNING_KEYCHAIN" \
    -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign \
    -T /usr/bin/security >/dev/null
security set-key-partition-list \
    -S apple-tool:,apple: \
    -s \
    -k "$keychain_password" \
    "$RELEASE_SIGNING_KEYCHAIN" >/dev/null
rm -f "$certificate_path"

identities="$(security find-identity -v -p codesigning "$RELEASE_SIGNING_KEYCHAIN")"
identity_count="$(printf '%s\n' "$identities" | grep -F -c "\"$DEVELOPER_ID_APPLICATION\"" || true)"
[[ "$identity_count" == 1 ]] || {
    release_die "The temporary Keychain must contain exactly one matching Developer ID identity."
}

import_succeeded=true
trap - EXIT INT TERM
printf 'Imported the reviewed Developer ID identity into the ephemeral release Keychain.\n'
