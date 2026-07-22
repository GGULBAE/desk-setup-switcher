#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

assertions=0
temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-release-history-tests.XXXXXX")"
runner_temp="$temporary_root/runner"
mkdir -m 0700 "$runner_temp"
export RUNNER_TEMP="$runner_temp"

cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT

pass() {
    assertions=$((assertions + 1))
}

fail() {
    release_die "$1"
}

write_tag_source_files() {
    local repository="$1"
    mkdir -p \
        "$repository/.github/workflows" \
        "$repository/scripts/release" \
        "$repository/docs/evidence/releases/v0.1.0"
    printf 'candidate\n' >"$repository/.github/workflows/signed-release-candidate.yml"
    printf 'ci\n' >"$repository/.github/workflows/ci.yml"
    printf 'publication\n' >"$repository/.github/workflows/publish-release.yml"
    printf 'retired legacy tombstone\n' >"$repository/.github/workflows/release.yml"
    printf '{}\n' >"$repository/scripts/release/remote-controls-policy.json"
    printf '# synthetic dependency\n' >"$repository/scripts/release/release_policy.rb"
    cat >"$repository/scripts/release/remote_controls_policy.rb" <<'RUBY'
#!/usr/bin/env ruby
require "json"

if ARGV.first == "--publication-approval-contract"
  puts JSON.generate("operator" => { "id" => 1001, "login" => "synthetic-operator" })
end
RUBY
    cat >"$repository/scripts/release/collect_remote_controls_evidence.rb" <<'RUBY'
#!/usr/bin/env ruby
require "json"

control_index = ARGV.index("--control") or abort
control = ARGV.fetch(control_index + 1)
candidate = control == "release-candidate-administrator-bypass-disabled"
abort unless candidate ||
  control == "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope"
puts JSON.generate(
  "control" => control,
  "sha256" => (candidate ? "1" : "2") * 64,
  "sourceArtifactSHA256" => (candidate ? "3" : "4") * 64
)
RUBY
    printf '{}\n' >"$repository/docs/evidence/releases/v0.1.0/release-candidate-admin-bypass.json"
    printf '{}\n' >"$repository/docs/evidence/releases/v0.1.0/release-publication-admin-token-scope.json"
}

write_predecessor_evidence() {
    local destination="$1"
    mkdir -p "$(dirname "$destination")"
    printf '{"phase":"predecessor-pre-tag","schemaVersion":"synthetic/v3"}\n' >"$destination"
}

write_final_evidence() {
    local destination="$1"
    mkdir -p "$(dirname "$destination")"
    cat >"$destination" <<'JSON'
{
  "collectedAt": "2026-07-17T00:00:00Z",
  "manualEvidence": {
    "items": [
      {
        "control": "release-candidate-administrator-bypass-disabled",
        "sha256": "1111111111111111111111111111111111111111111111111111111111111111"
      },
      {
        "control": "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
        "sha256": "2222222222222222222222222222222222222222222222222222222222222222"
      }
    ]
  }
}
JSON
}

fixture_repository=""
predecessor_commit=""
predecessor_tag_object=""
predecessor_introduction_commit=""
release_commit=""
release_tag_object=""
final_introduction_commit=""
history_tip=""

build_fixture() {
    local scenario="$1"
    local case_root="$temporary_root/$scenario"
    local predecessor_path final_path predecessor_digest final_digest tag_digest
    fixture_repository="$case_root/repository"
    mkdir -p "$fixture_repository"
    git -C "$fixture_repository" init -q -b master
    git -C "$fixture_repository" config user.name "Synthetic Release Test"
    git -C "$fixture_repository" config user.email "release-test@example.invalid"
    write_tag_source_files "$fixture_repository"
    git -C "$fixture_repository" add .
    git -C "$fixture_repository" commit -qm "predecessor tag target"
    predecessor_commit="$(git -C "$fixture_repository" rev-parse HEAD)"

    predecessor_path="$fixture_repository/docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json"
    write_predecessor_evidence "$predecessor_path"
    predecessor_digest="$(release_sha256 "$predecessor_path")"
    tag_digest="$predecessor_digest"
    if [[ "$scenario" == predecessor-tag-digest-mismatch ]]; then
        tag_digest="$(printf '0%.0s' {1..64})"
    fi
    git -C "$fixture_repository" tag -a v0.0.9 "$predecessor_commit" \
        -m "remote-controls-predecessor-pre-tag-sha256: $tag_digest"
    predecessor_tag_object="$(git -C "$fixture_repository" rev-parse refs/tags/v0.0.9)"

    if [[ "$scenario" == predecessor-second-parent ]]; then
        git -C "$fixture_repository" switch -qc predecessor-evidence
        git -C "$fixture_repository" add \
            docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json
        git -C "$fixture_repository" commit -qm "introduce predecessor evidence"
        predecessor_introduction_commit="$(git -C "$fixture_repository" rev-parse HEAD)"
        git -C "$fixture_repository" switch -q master
        git -C "$fixture_repository" commit --allow-empty -qm "first-parent bridge"
        git -C "$fixture_repository" merge --no-ff -qm "merge predecessor evidence as second parent" \
            predecessor-evidence
    else
        if [[ "$scenario" == predecessor-extra-path ]]; then
            printf 'unexpected\n' >"$fixture_repository/unexpected.txt"
        fi
        git -C "$fixture_repository" add .
        git -C "$fixture_repository" commit -qm "introduce predecessor evidence"
        predecessor_introduction_commit="$(git -C "$fixture_repository" rev-parse HEAD)"
        if [[ "$scenario" == predecessor-blob-drift ]]; then
            printf '{"drifted":true}\n' >"$predecessor_path"
            git -C "$fixture_repository" add "$predecessor_path"
            git -C "$fixture_repository" commit -qm "drift predecessor evidence before final tag"
        fi
        if [[ "$scenario" == critical-tree-drift ]]; then
            printf 'changed ci\n' >"$fixture_repository/.github/workflows/ci.yml"
            git -C "$fixture_repository" add .github/workflows/ci.yml
            git -C "$fixture_repository" commit -qm "drift release-critical tree"
        fi
        git -C "$fixture_repository" commit --allow-empty -qm "final tag target"
    fi
    release_commit="$(git -C "$fixture_repository" rev-parse HEAD)"

    final_path="$fixture_repository/docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json"
    write_final_evidence "$final_path"
    final_digest="$(release_sha256 "$final_path")"
    tag_digest="$final_digest"
    if [[ "$scenario" == final-tag-digest-mismatch ]]; then
        tag_digest="$(printf 'f%.0s' {1..64})"
    fi
    git -C "$fixture_repository" tag -a v0.1.0 "$release_commit" \
        -m "remote-controls-final-pre-tag-sha256: $tag_digest"
    release_tag_object="$(git -C "$fixture_repository" rev-parse refs/tags/v0.1.0)"

    if [[ "$scenario" == final-second-parent ]]; then
        git -C "$fixture_repository" switch -qc final-evidence
        git -C "$fixture_repository" add \
            docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json
        git -C "$fixture_repository" commit -qm "introduce final evidence"
        final_introduction_commit="$(git -C "$fixture_repository" rev-parse HEAD)"
        git -C "$fixture_repository" switch -q master
        git -C "$fixture_repository" commit --allow-empty -qm "final first-parent bridge"
        git -C "$fixture_repository" merge --no-ff -qm "merge final evidence as second parent" \
            final-evidence
    else
        if [[ "$scenario" == final-extra-path ]]; then
            printf 'unexpected final\n' >"$fixture_repository/final-unexpected.txt"
        fi
        git -C "$fixture_repository" add .
        git -C "$fixture_repository" commit -qm "introduce final evidence"
        final_introduction_commit="$(git -C "$fixture_repository" rev-parse HEAD)"
    fi
    if [[ "$scenario" == final-blob-drift ]]; then
        printf '{"drifted":true}\n' >"$final_path"
        git -C "$fixture_repository" add "$final_path"
        git -C "$fixture_repository" commit -qm "drift final evidence"
    fi
    if [[ "$scenario" == predecessor-post-final-drift ]]; then
        printf '{"lateDrift":true}\n' >"$predecessor_path"
        git -C "$fixture_repository" add "$predecessor_path"
        git -C "$fixture_repository" commit -qm "drift predecessor evidence after final tag"
    elif [[ "$scenario" == predecessor-post-final-delete ]]; then
        git -C "$fixture_repository" rm -q -- \
            docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json
        git -C "$fixture_repository" commit -qm "delete predecessor evidence after final tag"
    elif [[ "$scenario" == critical-tip-drift ]]; then
        printf 'changed tooling\n' >>"$fixture_repository/scripts/release/release_policy.rb"
        git -C "$fixture_repository" add scripts/release/release_policy.rb
        git -C "$fixture_repository" commit -qm "drift release-critical tip tree"
    fi
    history_tip="$(git -C "$fixture_repository" rev-parse HEAD)"
}

verify_predecessor_fixture() {
    (
        cd "$fixture_repository"
        release_verify_predecessor_pre_tag_evidence_chain \
            v0.0.9 "$predecessor_commit" "$predecessor_tag_object" "$history_tip"
    )
}

verify_final_fixture() {
    (
        cd "$fixture_repository"
        release_verify_final_pre_tag_evidence_chain \
            v0.1.0 "$release_commit" "$release_tag_object" "$history_tip"
    )
}

assert_success() {
    local label="$1"
    shift
    "$@" || fail "$label unexpectedly failed."
    pass
}

assert_failure() {
    local label="$1"
    shift
    if "$@"; then
        fail "$label unexpectedly passed."
    fi
    pass
}

build_fixture success
assert_success "The predecessor production history gate" verify_predecessor_fixture
assert_success "The final production history gate" verify_final_fixture
assert_success "The predecessor first-parent membership helper" \
    release_verify_first_parent_commit_once \
    "$fixture_repository" "$release_commit" "$predecessor_introduction_commit"
assert_success "The final first-parent membership helper" \
    release_verify_first_parent_commit_once \
    "$fixture_repository" "$history_tip" "$final_introduction_commit"

for scenario in \
    predecessor-extra-path \
    predecessor-blob-drift \
    predecessor-tag-digest-mismatch \
    predecessor-post-final-drift \
    predecessor-post-final-delete \
    critical-tree-drift \
    critical-tip-drift \
    final-extra-path \
    final-blob-drift \
    final-tag-digest-mismatch; do
    build_fixture "$scenario"
    assert_failure "The $scenario production history case" verify_final_fixture
done

build_fixture predecessor-second-parent
assert_failure "The predecessor second-parent membership case" \
    release_verify_first_parent_commit_once \
    "$fixture_repository" "$release_commit" "$predecessor_introduction_commit"
assert_failure "The predecessor second-parent production history case" verify_final_fixture

build_fixture final-second-parent
assert_failure "The final second-parent membership case" \
    release_verify_first_parent_commit_once \
    "$fixture_repository" "$history_tip" "$final_introduction_commit"
assert_failure "The final second-parent production history case" verify_final_fixture

ruby -e '
  verifier, preparer, publisher = ARGV.map { |path| File.binread(path) }
  raise unless verifier.scan(/release_verify_first_parent_commit_once/).length == 2
  raise unless verifier.scan(/release_verify_predecessor_pre_tag_evidence_chain/).length == 1
  raise unless verifier.scan(/release_verify_final_pre_tag_evidence_chain/).length == 1
  raise unless preparer.scan(/release_verify_final_pre_tag_evidence_chain/).length == 1
  raise unless publisher.scan(/release_verify_final_pre_tag_evidence_chain/).length == 1
' \
    "$RELEASE_SCRIPTS_DIR/verify-remote-controls.sh" \
    "$RELEASE_SCRIPTS_DIR/prepare-draft-release.sh" \
    "$RELEASE_SCRIPTS_DIR/publish-approved-release.sh" || {
    fail "The operational release paths do not share the production evidence-history gates."
}
pass

printf 'Release evidence history tests passed: %d assertions.\n' "$assertions"
