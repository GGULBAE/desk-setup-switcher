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
    grep -F -q -- "$text" "$path" || release_die "Expected release-tooling text is missing."
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

ruby -e '
  workflow = File.read(ARGV.fetch(0))
  uses = workflow.scan(/^\s*uses:\s*([^\s#]+)/).flatten
  abort "Release workflow has no pinned actions." if uses.empty?
  bad = uses.reject { |item| item.match?(/\A[^@\s]+@[0-9a-f]{40}\z/) }
  abort "Release workflow action is not pinned by commit SHA." unless bad.empty?
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
