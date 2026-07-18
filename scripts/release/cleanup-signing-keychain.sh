#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

release_require_execution_context
[[ "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    release_die "Release cleanup is restricted to GitHub-hosted runners."
}

preserve_directory=false
if [[ "${1:-}" == --preserve-directory && "$#" == 1 ]]; then
    preserve_directory=true
elif [[ "$#" != 0 ]]; then
    release_die "Unexpected release cleanup argument."
fi

if [[ -z "${RELEASE_SIGNING_KEYCHAIN:-}" && -z "${RELEASE_SIGNING_CERTIFICATE_PATH:-}" ]]; then
    [[ "$preserve_directory" != true ]] || {
        release_die "A signing directory cannot be preserved when no signing paths exist."
    }
    printf 'No ephemeral release signing material exists.\n'
    exit 0
fi

release_require_single_line RELEASE_SIGNING_KEYCHAIN
release_require_single_line RELEASE_SIGNING_CERTIFICATE_PATH
signing_directory="$(dirname "$RELEASE_SIGNING_KEYCHAIN")"
[[ "$signing_directory" == "$(dirname "$RELEASE_SIGNING_CERTIFICATE_PATH")" ]] || {
    release_die "Release signing paths must share one private temporary directory."
}
runner_temp_resolved="$(cd "$RUNNER_TEMP" && pwd -P)"
signing_parent="$(dirname "$signing_directory")"
[[ -d "$signing_parent" ]] || release_die "Release signing directory parent is missing."
[[ "$(cd "$signing_parent" && pwd -P)" == "$runner_temp_resolved" ]] || {
    release_die "Release signing directory is outside RUNNER_TEMP."
}
[[ "$(basename "$signing_directory")" =~ ^desk-setup-release-signing\.[[:alnum:]]{6}$ ]] || {
    release_die "Unexpected release signing directory."
}
[[ "$RELEASE_SIGNING_KEYCHAIN" == "$signing_directory/signing.keychain-db" ]] || {
    release_die "Unexpected release Keychain filename."
}
[[ "$(basename "$RELEASE_SIGNING_CERTIFICATE_PATH")" =~ ^developer-id\.p12\.[[:alnum:]]{6}$ ]] || {
    release_die "Unexpected release certificate filename."
}

if [[ ! -e "$signing_directory" && ! -L "$signing_directory" ]]; then
    printf 'Ephemeral release signing material was already removed.\n'
    exit 0
fi
[[ -d "$signing_directory" && ! -L "$signing_directory" ]] || {
    release_die "Release signing directory is not a safe directory."
}
release_require_path_within "$RELEASE_SIGNING_KEYCHAIN" "$signing_directory"
release_require_path_within "$RELEASE_SIGNING_CERTIFICATE_PATH" "$signing_directory"
rm -f -- "$RELEASE_SIGNING_CERTIFICATE_PATH"
[[ ! -e "$RELEASE_SIGNING_CERTIFICATE_PATH" && ! -L "$RELEASE_SIGNING_CERTIFICATE_PATH" ]] || {
    release_die "Decoded Developer ID certificate still exists after cleanup."
}
if [[ -e "$RELEASE_SIGNING_KEYCHAIN" ]]; then
    [[ -f "$RELEASE_SIGNING_KEYCHAIN" && ! -L "$RELEASE_SIGNING_KEYCHAIN" ]] || {
        release_die "Release Keychain path is not a regular file."
    }
    security delete-keychain "$RELEASE_SIGNING_KEYCHAIN"
    [[ ! -e "$RELEASE_SIGNING_KEYCHAIN" && ! -L "$RELEASE_SIGNING_KEYCHAIN" ]] || {
        release_die "Release Keychain still exists after deletion."
    }
fi
if [[ "$preserve_directory" != true ]]; then
    rmdir "$signing_directory"
fi
printf 'Removed ephemeral release signing material.\n'
