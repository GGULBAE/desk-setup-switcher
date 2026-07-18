#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib.sh"

[[ "$#" == 2 ]] || release_die "Usage: compare-bundle-manifest.sh EXPECTED_MANIFEST APP_BUNDLE"
expected_manifest="$1"
app_bundle="$2"
[[ -f "$expected_manifest" ]] || release_die "Expected bundle manifest is missing."
[[ -d "$app_bundle" ]] || release_die "App bundle to compare is missing."

actual_manifest="$(mktemp "${TMPDIR:-/tmp}/desk-setup-bundle-manifest.XXXXXX")"
cleanup() {
    rm -f "$actual_manifest"
}
trap cleanup EXIT

ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" generate-bundle-manifest \
    --app "$app_bundle" \
    --output "$actual_manifest" >/dev/null
cmp -s "$expected_manifest" "$actual_manifest" || {
    release_die "Packaged app files or modes differ from the signed candidate."
}
printf 'Mounted app matches the exact signed-app manifest.\n'
