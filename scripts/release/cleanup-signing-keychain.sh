#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

release_require_execution_context
release_require_env RELEASE_SIGNING_KEYCHAIN
release_require_path_within "$RELEASE_SIGNING_KEYCHAIN" "$RUNNER_TEMP"
[[ "$(basename "$RELEASE_SIGNING_KEYCHAIN")" == desk-setup-release.keychain-db ]] || {
    release_die "Unexpected release Keychain filename."
}

rm -f \
    "$RUNNER_TEMP/desk-setup-developer-id.p12" \
    "$RUNNER_TEMP/desk-setup-notary-api-key.p8"
if [[ -e "$RELEASE_SIGNING_KEYCHAIN" ]]; then
    security delete-keychain "$RELEASE_SIGNING_KEYCHAIN"
fi
printf 'Removed ephemeral release signing material.\n'
