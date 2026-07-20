#!/usr/bin/env bash

set -euo pipefail
set +x
set +a
umask 077

# The job-scoped GitHub token is deliberately non-exported and is used only for
# the one exact-ID PATCH. Every GET/download uses the protected read-only token.
unset write_token
write_token="${GH_TOKEN:-}"
export -n write_token 2>/dev/null || true
unset admin_read_token
admin_read_token="${RELEASE_ADMIN_READ_TOKEN:-}"
export -n admin_read_token 2>/dev/null || true
unset GH_TOKEN GITHUB_TOKEN RELEASE_ADMIN_READ_TOKEN GH_HOST GH_DEBUG DEBUG \
    GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR
source "$(dirname "$0")/lib.sh"

publication_mutation_state=pre
release_die() {
    case "${publication_mutation_state:-pre}" in
        pre) printf 'SAFE_PRE_PATCH_FAILURE\n' >&2 ;;
        attempting|incident) printf 'INCIDENT_ONLY_FAILURE\n' >&2 ;;
        *) printf 'INCIDENT_ONLY_FAILURE\n' >&2 ;;
    esac
    printf 'Release tooling error: %s\n' "$1" >&2
    exit 1
}

release_incident_die() {
    publication_mutation_state=incident
    printf 'INCIDENT_ONLY_FAILURE\n' >&2
    printf 'Release tooling error: %s\n' "$1" >&2
    exit 1
}

release_require_execution_context release-publication

for name in \
    RELEASE_OPERATION \
    RELEASE_TAG \
    EXPECTED_COMMIT \
    RELEASE_CONFIRMATION \
    RELEASE_ID \
    RELEASE_CANDIDATE_RUN_ID \
    RELEASE_CANDIDATE_RUN_ATTEMPT \
    RELEASE_CANDIDATE_ARTIFACT_ID \
    RELEASE_CANDIDATE_ARTIFACT_SHA256 \
    RELEASE_FINAL_DMG_SHA256 \
    RELEASE_APPROVAL_RECORD_COMMIT \
    RELEASE_APPROVAL_RECORD_SHA256 \
    RELEASE_APPROVAL_RECORD_PATH \
    RELEASE_APPROVER_LOGIN \
    RELEASE_PUBLISHER_LOGIN \
    RELEASE_NOTES_PATH \
    RELEASE_SOURCE_DIR \
    RELEASE_DOWNLOAD_DIR \
    GITHUB_REPOSITORY \
    GITHUB_ACTOR \
    GITHUB_ACTOR_ID \
    GITHUB_TRIGGERING_ACTOR \
    GITHUB_REF \
    GITHUB_REF_NAME; do
    release_require_single_line "$name"
done
release_require_env GITHUB_RUN_ATTEMPT
if [[ "$GITHUB_RUN_ATTEMPT" =~ ^[2-9][0-9]*$ ]]; then
    release_incident_die "Publication workflow reruns are forbidden and require incident review."
fi

[[ -n "$write_token" && "$write_token" != *$'\n'* && "$write_token" != *$'\r'* ]] || {
    release_die "The GitHub publication credential is missing or malformed."
}
[[ -n "$admin_read_token" && "$admin_read_token" != *$'\n'* && "$admin_read_token" != *$'\r'* ]] || {
    release_die "The immutable-release read credential is missing or malformed."
}
[[ "$write_token" != "$admin_read_token" ]] || {
    release_die "The publication write and administration-read credentials must be distinct."
}

for command_name in git gh ruby cp cmp find chmod mktemp mv shasum awk; do
    release_require_command "$command_name"
done

same_github_login() {
    ruby -e 'exit(ARGV.fetch(0).casecmp?(ARGV.fetch(1)) ? 0 : 1)' "$1" "$2" \
        >/dev/null 2>&1
}

[[ "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
    release_die "Release publication is restricted to GitHub-hosted runners."
}
[[ "$RELEASE_OPERATION" == publish-release ]] || {
    release_die "This helper is restricted to the publish-release operation."
}
[[ "$GITHUB_REPOSITORY" == GGULBAE/desk-setup-switcher ]] || {
    release_die "Unexpected GitHub repository identity."
}
[[ "$RELEASE_TAG" == "v$VERSION" ]] || {
    release_die "RELEASE_TAG does not match the bundle version."
}
[[ "$EXPECTED_COMMIT" =~ ^[0-9a-f]{40}$ ]] || {
    release_die "EXPECTED_COMMIT has an invalid format."
}
[[ "$RELEASE_ID" =~ ^[1-9][0-9]*$ ]] || release_die "RELEASE_ID must be a positive integer."
[[ "$RELEASE_CANDIDATE_RUN_ID" =~ ^[1-9][0-9]*$ ]] || release_die "Candidate run ID is invalid."
[[ "$RELEASE_CANDIDATE_RUN_ATTEMPT" == 1 ]] || release_die "Candidate origin attempt must be 1."
[[ "$RELEASE_CANDIDATE_ARTIFACT_ID" =~ ^[1-9][0-9]*$ ]] || release_die "Candidate artifact ID is invalid."
[[ "$RELEASE_CANDIDATE_ARTIFACT_SHA256" =~ ^[0-9a-f]{64}$ ]] || release_die "Candidate archive digest is invalid."
[[ "$RELEASE_FINAL_DMG_SHA256" =~ ^[0-9a-f]{64}$ ]] || release_die "Final DMG digest is invalid."
[[ "$RELEASE_APPROVAL_RECORD_COMMIT" =~ ^[0-9a-f]{40}$ ]] || release_die "Approval-record commit is invalid."
[[ "$RELEASE_APPROVAL_RECORD_SHA256" =~ ^[0-9a-f]{64}$ ]] || release_die "Approval-record digest is invalid."
[[ "$GITHUB_RUN_ID" =~ ^[1-9][0-9]*$ && "$GITHUB_RUN_ATTEMPT" == 1 ]] || {
    release_die "Publication workflow run identity is invalid."
}
[[ "$GITHUB_RUN_ID" != "$RELEASE_CANDIDATE_RUN_ID" ]] || {
    release_die "Publication must run separately from the candidate origin."
}
[[ "$RELEASE_CONFIRMATION" == "publish approved $RELEASE_TAG release $RELEASE_ID" ]] || {
    release_die "The final publication confirmation phrase does not match."
}
[[ "$GITHUB_REF" == "refs/tags/$RELEASE_TAG" && "$GITHUB_REF_NAME" == "$RELEASE_TAG" ]] || {
    release_die "The workflow ref does not identify the exact release tag."
}
[[ "$RELEASE_NOTES_PATH" == "docs/releases/$RELEASE_TAG.md" ]] || {
    release_die "RELEASE_NOTES_PATH does not identify the pinned curated notes."
}
[[ "$RELEASE_APPROVAL_RECORD_PATH" == "docs/evidence/releases/$RELEASE_TAG/publication-approval.json" ]] || {
    release_die "RELEASE_APPROVAL_RECORD_PATH does not identify the fixed approval record."
}
remote_controls_evidence_path="docs/evidence/releases/$RELEASE_TAG/remote-controls-pre-publication.json"
remote_controls_policy_path="scripts/release/remote-controls-policy.json"
candidate_manual_evidence_path="docs/evidence/releases/$RELEASE_TAG/release-candidate-admin-bypass.json"
publication_manual_evidence_path="docs/evidence/releases/$RELEASE_TAG/release-publication-admin-token-scope.json"
final_pre_tag_evidence_path="docs/evidence/releases/$RELEASE_TAG/remote-controls-final-pre-tag.json"
if ! same_github_login "$GITHUB_ACTOR" "$RELEASE_PUBLISHER_LOGIN" \
    || ! same_github_login "$GITHUB_TRIGGERING_ACTOR" "$RELEASE_PUBLISHER_LOGIN"; then
    release_die "The dispatch and triggering actors do not match the approved publisher."
fi
[[ -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || {
    release_die "RUNNER_TEMP is missing or is a symlink."
}

case "$RELEASE_SOURCE_DIR" in
    /*) source_directory="$RELEASE_SOURCE_DIR" ;;
    *) source_directory="$ROOT_DIR/$RELEASE_SOURCE_DIR" ;;
esac
case "$RELEASE_DOWNLOAD_DIR" in
    /*) download_directory="$RELEASE_DOWNLOAD_DIR" ;;
    *) download_directory="$ROOT_DIR/$RELEASE_DOWNLOAD_DIR" ;;
esac
notes_path="$ROOT_DIR/$RELEASE_NOTES_PATH"

[[ -d "$source_directory" && ! -L "$source_directory" ]] || {
    release_die "Release source directory is missing or unsafe."
}
[[ -f "$notes_path" && ! -L "$notes_path" && -s "$notes_path" ]] || {
    release_die "Curated release notes must be one nonempty regular file."
}
release_require_absent_path "$download_directory"
download_parent="$(dirname "$download_directory")"
[[ -d "$download_parent" && ! -L "$download_parent" ]] || {
    release_die "Release download parent is missing or unsafe."
}

resolved_root="$(cd "$ROOT_DIR" && pwd -P)"
resolved_runner_temp="$(cd "$RUNNER_TEMP" && pwd -P)"
resolved_download="$(cd "$download_parent" && pwd -P)/$(basename "$download_directory")"
case "$resolved_download" in
    "$resolved_root"/*|"$resolved_runner_temp"/*) ;;
    *) release_die "Release download path is outside the checkout and runner temporary directory." ;;
esac

repository_root="$(git rev-parse --show-toplevel)" || release_die "The release checkout root could not be resolved."
[[ "$(cd "$repository_root" && pwd -P)" == "$resolved_root" ]] || {
    release_die "The release checkout root is unexpected."
}
origin_url="$(git remote get-url origin)" || release_die "The origin URL could not be read."
case "$origin_url" in
    https://github.com/GGULBAE/desk-setup-switcher|https://github.com/GGULBAE/desk-setup-switcher.git|git@github.com:GGULBAE/desk-setup-switcher.git) ;;
    *) release_die "The origin URL does not identify the expected repository." ;;
esac

git check-ref-format --allow-onelevel "$RELEASE_TAG" >/dev/null || release_die "RELEASE_TAG is invalid."
git show-ref --verify --quiet "refs/tags/$RELEASE_TAG" || release_die "The local release tag is missing."
tag_commit="$(git rev-parse "refs/tags/$RELEASE_TAG^{commit}")" || release_die "The local tag commit is unavailable."
tag_object="$(git rev-parse "refs/tags/$RELEASE_TAG")" || release_die "The local tag object is unavailable."
checkout_commit="$(git rev-parse HEAD)" || release_die "The checkout commit is unavailable."
[[ "$tag_object" =~ ^[0-9a-f]{40}$ ]] || release_die "The local tag object is invalid."
[[ "$(git cat-file -t "$tag_object" 2>/dev/null)" == tag ]] || {
    release_die "The release tag must be one annotated tag object."
}
[[ "$tag_commit" == "$EXPECTED_COMMIT" && "$checkout_commit" == "$EXPECTED_COMMIT" ]] || {
    release_die "The local tag, checkout, and expected commit differ."
}
tracked_notes="$(git ls-files --error-unmatch -- "$RELEASE_NOTES_PATH")" || {
    release_die "Curated release notes are not tracked."
}
[[ "$tracked_notes" == "$RELEASE_NOTES_PATH" ]] || release_die "Curated release notes path is ambiguous."
[[ -z "$(git status --porcelain=v1 --untracked-files=all)" ]] || {
    release_die "The publication checkout is not clean."
}

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

ruby -e '
  directory = ARGV.shift
  expected = ARGV
  actual = Dir.children(directory)
  abort unless actual.sort == expected.sort
  expected.each do |name|
    stat = File.lstat(File.join(directory, name))
    abort unless stat.file? && !stat.symlink? && stat.size.positive?
  end
' "$source_directory" "${asset_names[@]}" >/dev/null || {
    release_die "The publication source is not the exact nonempty nine-asset candidate."
}
[[ "$(release_sha256 "$source_directory/$dmg_name")" == "$RELEASE_FINAL_DMG_SHA256" ]] || {
    release_die "The source DMG differs from the approved final digest."
}

temporary_root="$(mktemp -d "$RUNNER_TEMP/desk-setup-release-publication.XXXXXX")"
candidate_snapshot="$temporary_root/candidate"
notes_snapshot="$temporary_root/release-notes.md"
approval_record="$temporary_root/publication-approval.json"
approval_tree="$temporary_root/approval-tree.txt"
approval_diff="$temporary_root/approval-diff.txt"
approval_parent="$temporary_root/approval-parent.txt"
remote_controls_evidence="$temporary_root/remote-controls-pre-publication.json"
remote_controls_tree="$temporary_root/remote-controls-tree.txt"
remote_controls_policy="$temporary_root/remote-controls-policy.json"
remote_controls_policy_tree="$temporary_root/remote-controls-policy-tree.txt"
candidate_manual_evidence="$temporary_root/release-candidate-admin-bypass.json"
candidate_manual_tree="$temporary_root/release-candidate-admin-bypass-tree.txt"
publication_manual_evidence="$temporary_root/release-publication-admin-token-scope.json"
publication_manual_tree="$temporary_root/release-publication-admin-token-scope-tree.txt"
final_candidate_manual_evidence="$temporary_root/final-release-candidate-admin-bypass.json"
final_candidate_manual_tree="$temporary_root/final-release-candidate-admin-bypass-tree.txt"
final_publication_manual_evidence="$temporary_root/final-release-publication-admin-token-scope.json"
final_publication_manual_tree="$temporary_root/final-release-publication-admin-token-scope-tree.txt"
final_pre_tag_evidence="$temporary_root/remote-controls-final-pre-tag.json"
final_pre_tag_evidence_tree="$temporary_root/remote-controls-final-pre-tag-tree.txt"
final_pre_tag_introduction_log="$temporary_root/final-pre-tag-introduction-log.txt"
final_pre_tag_first_parent_log="$temporary_root/final-pre-tag-first-parent-log.txt"
final_pre_tag_introduction_parent="$temporary_root/final-pre-tag-introduction-parent.txt"
final_pre_tag_introduction_diff="$temporary_root/final-pre-tag-introduction-diff.txt"
publication_contract="$temporary_root/publication-approval-contract.json"
approver_identity="$temporary_root/approver-identity.json"
publisher_identity="$temporary_root/publisher-identity.json"
admin_token_owner_identity="$temporary_root/admin-token-owner-identity.json"
approval_workflow_runs="$temporary_root/approval-workflow-runs.json"
approval_workflow_jobs="$temporary_root/approval-workflow-jobs.json"
remote_tag_refs="$temporary_root/remote-tag-refs.txt"
tag_object_payload="$temporary_root/tag-object.txt"
remote_master_ref="$temporary_root/remote-master-ref.txt"
immutable_response="$temporary_root/immutable.json"
immutable_fingerprint="$temporary_root/immutable-fingerprint.txt"
release_response="$temporary_root/release.json"
release_list_response="$temporary_root/release-list.json"
assets_response="$temporary_root/assets.json"
release_state="$temporary_root/release-state.txt"
release_fingerprint="$temporary_root/release-fingerprint.txt"
asset_fingerprint="$temporary_root/asset-fingerprint.txt"
asset_ids="$temporary_root/asset-ids.tsv"
pre_release_fingerprint="$temporary_root/pre-release-fingerprint.txt"
pre_asset_fingerprint="$temporary_root/pre-asset-fingerprint.txt"
pre_immutable_fingerprint="$temporary_root/pre-immutable-fingerprint.txt"
publish_request="$temporary_root/publish-request.json"
publish_response="$temporary_root/publish-response.json"
remote_error="$temporary_root/remote-command.stderr"
parse_error="$temporary_root/parse.stderr"
gh_config_directory="$temporary_root/gh-config"
pre_download="$temporary_root/pre-download"
post_download_staging=""

cleanup() {
    trap '' HUP INT QUIT TERM
    release_stop_active_child || true
    rm -rf -- "$temporary_root"
    if [[ -n "${post_download_staging:-}" ]]; then
        rm -rf -- "$post_download_staging"
    fi
}
trap cleanup EXIT
release_install_exit_signal_traps

mkdir -m 0700 "$candidate_snapshot" "$pre_download" "$gh_config_directory"
for name in "${asset_names[@]}"; do
    cp -- "$source_directory/$name" "$candidate_snapshot/$name"
    [[ -f "$source_directory/$name" && ! -L "$source_directory/$name" ]] || {
        release_die "A source candidate asset changed during snapshotting."
    }
    cmp -s "$source_directory/$name" "$candidate_snapshot/$name" || {
        release_die "A source candidate asset changed during snapshotting."
    }
done
[[ "$(release_sha256 "$candidate_snapshot/$dmg_name")" == "$RELEASE_FINAL_DMG_SHA256" ]] || {
    release_die "The snapshotted DMG differs from the approved final digest."
}
cp -- "$notes_path" "$notes_snapshot"
[[ -f "$notes_path" && ! -L "$notes_path" ]] || release_die "Curated notes changed during snapshotting."
cmp -s "$notes_path" "$notes_snapshot" || release_die "Curated notes changed during snapshotting."

read_remote_master() {
    : >"$remote_master_ref"
    printf 'Publication verification: protected remote read in progress.\n' >&2
    if ! release_run_tracked_timeout 90 git ls-remote --exit-code origin refs/heads/master \
        >"$remote_master_ref" 2>"$remote_error"; then
        release_die "The remote default branch could not be read."
    fi
    observed_remote_master="$(ruby -e '
      path = ARGV.fetch(0)
      rows = File.readlines(path, chomp: true).map { |line| line.split("\t", -1) }
      abort unless rows.length == 1 && rows.fetch(0).fetch(0).match?(/\A[0-9a-f]{40}\z/) && rows.fetch(0).fetch(1) == "refs/heads/master"
      puts rows.fetch(0).fetch(0)
    ' "$remote_master_ref" 2>"$parse_error")" || release_die "The remote default-branch response is invalid."
    [[ "$observed_remote_master" =~ ^[0-9a-f]{40}$ ]] || {
        release_die "The remote default-branch response is invalid."
    }
}

require_remote_tag() {
    : >"$remote_tag_refs"
    printf 'Publication verification: protected remote read in progress.\n' >&2
    if ! release_run_tracked_timeout 90 git ls-remote --exit-code --tags origin \
        "refs/tags/$RELEASE_TAG" "refs/tags/$RELEASE_TAG^{}" \
        >"$remote_tag_refs" 2>"$remote_error"; then
        release_die "The remote release tag could not be read."
    fi
    ruby -e '
      expected_commit, expected_object, tag, path = ARGV
      direct_ref = "refs/tags/#{tag}"
      peeled_ref = "#{direct_ref}^{}"
      rows = File.readlines(path, chomp: true).map { |line| line.split("\t", -1) }
      abort unless rows.all? { |row| row.length == 2 && row[0].match?(/\A[0-9a-f]{40}\z/) }
      abort unless rows.all? { |row| [direct_ref, peeled_ref].include?(row[1]) }
      direct = rows.select { |row| row[1] == direct_ref }
      peeled = rows.select { |row| row[1] == peeled_ref }
      abort unless direct.length == 1 && peeled.length == 1 && rows.length == 2
      abort unless direct.fetch(0).fetch(0) == expected_object
      abort unless peeled.fetch(0).fetch(0) == expected_commit
    ' "$EXPECTED_COMMIT" "$tag_object" "$RELEASE_TAG" "$remote_tag_refs" \
        2>"$parse_error" || release_die "The remote release tag moved or is ambiguous."
}

github_get() {
    local endpoint="$1"
    local destination="$2"
    shift 2
    : >"$destination"
    : >"$remote_error"
    printf 'Publication verification: protected remote read in progress.\n' >&2
    if ! GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$admin_read_token" 90 gh api \
        --hostname github.com \
        --method GET \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        "$@" "$endpoint" >"$destination" 2>"$remote_error"; then
        release_die "A required GitHub publication record could not be read."
    fi
}

read_policy_actor_identity() {
    local login="$1"
    local expected_id="$2"
    local expected_login="$3"
    local destination="$4"
    github_get "/users/$login" "$destination" --jq '{id: .id, login: .login, type: .type}'
    ruby -rjson -e '
      path, expected_id_text, expected_login = ARGV
      value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
      raise unless value.is_a?(Hash) && value.keys.sort == %w[id login type]
      raise unless value.fetch("id") == Integer(expected_id_text, 10)
      login = value.fetch("login")
      raise unless login.is_a?(String) && login.casecmp?(expected_login)
      raise unless value.fetch("type") == "User"
    ' "$destination" "$expected_id" "$expected_login" 2>"$parse_error" || {
        release_die "A runtime GitHub actor does not match the reviewed remote-controls policy."
    }
}

read_authenticated_admin_token_owner() {
    local expected_id="$1"
    local expected_login="$2"
    local destination="$3"
    github_get "/user" "$destination" --jq '{id: .id, login: .login, type: .type}'
    ruby -rjson -e '
      path, expected_id_text, expected_login = ARGV
      value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
      raise unless value.is_a?(Hash) && value.keys.sort == %w[id login type]
      raise unless value.fetch("id") == Integer(expected_id_text, 10)
      login = value.fetch("login")
      raise unless login.is_a?(String) && login.casecmp?(expected_login)
      raise unless value.fetch("type") == "User"
    ' "$destination" "$expected_id" "$expected_login" 2>"$parse_error" || {
        release_die "The administration-read credential owner does not match the reviewed policy."
    }
}

verify_approval_commit_ci() {
    local run_fields workflow_run_id workflow_run_attempt
    github_get \
        "/repos/$GITHUB_REPOSITORY/actions/workflows/$ci_workflow_id/runs?head_sha=$RELEASE_APPROVAL_RECORD_COMMIT&event=push&per_page=100" \
        "$approval_workflow_runs" \
        --jq '{total_count: .total_count, items: (.workflow_runs | map({id: .id, workflow_id: .workflow_id, check_suite_id: .check_suite_id, run_attempt: .run_attempt, path: .path, event: .event, head_branch: .head_branch, head_sha: .head_sha, status: .status, conclusion: .conclusion}))}'
    run_fields="$(ruby -rjson -e '
      value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
      workflow_id = Integer(ARGV.fetch(1), 10)
      commit = ARGV.fetch(2)
      raise unless value.is_a?(Hash) && value.keys.sort == %w[items total_count]
      items = value.fetch("items")
      raise unless value.fetch("total_count") == 1 && items.is_a?(Array) && items.length == 1
      run = items.fetch(0)
      raise unless run.is_a?(Hash) && run.keys.sort ==
        %w[check_suite_id conclusion event head_branch head_sha id path run_attempt status workflow_id]
      raise unless run.fetch("id").is_a?(Integer) && run.fetch("id").positive?
      raise unless run.fetch("run_attempt").is_a?(Integer) && run.fetch("run_attempt").positive?
      raise unless run.fetch("workflow_id") == workflow_id
      raise unless run.fetch("check_suite_id").is_a?(Integer) &&
        run.fetch("check_suite_id").positive?
      raise unless run.fetch("path") == ".github/workflows/ci.yml" && run.fetch("event") == "push"
      raise unless run.fetch("head_branch") == "master" && run.fetch("head_sha") == commit
      raise unless run.fetch("status") == "completed" && run.fetch("conclusion") == "success"
      puts [run.fetch("id"), run.fetch("run_attempt")].join("\t")
    ' "$approval_workflow_runs" "$ci_workflow_id" \
        "$RELEASE_APPROVAL_RECORD_COMMIT" 2>"$parse_error")" || {
        release_die "The approval commit CI run is not one exact successful master push run."
    }
    IFS=$'\t' read -r workflow_run_id workflow_run_attempt <<<"$run_fields"
    github_get \
        "/repos/$GITHUB_REPOSITORY/actions/runs/$workflow_run_id/attempts/$workflow_run_attempt/jobs?per_page=100" \
        "$approval_workflow_jobs" \
        --jq "{total_count: .total_count, items: (.jobs | map({id: .id, run_id: .run_id, run_attempt: $workflow_run_attempt, name: .name, workflow_name: .workflow_name, head_branch: .head_branch, head_sha: .head_sha, status: .status, conclusion: .conclusion, check_run_url: .check_run_url}))}"
    ruby -rjson -e '
      value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
      run_id = Integer(ARGV.fetch(1), 10)
      attempt = Integer(ARGV.fetch(2), 10)
      commit = ARGV.fetch(3)
      raise unless value.is_a?(Hash) && value.keys.sort == %w[items total_count]
      items = value.fetch("items")
      raise unless value.fetch("total_count").is_a?(Integer) &&
        value.fetch("total_count").positive? && items.is_a?(Array) &&
        items.length == value.fetch("total_count")
      matches = items.select { |job| job.is_a?(Hash) && job["name"] == "Verify macOS app" }
      raise unless matches.length == 1
      job = matches.fetch(0)
      raise unless job.keys.sort ==
        %w[check_run_url conclusion head_branch head_sha id name run_attempt run_id status workflow_name]
      raise unless job.fetch("id").is_a?(Integer) && job.fetch("id").positive?
      raise unless job.fetch("run_id") == run_id && job.fetch("run_attempt") == attempt
      raise unless job.fetch("workflow_name") == "CI" && job.fetch("head_branch") == "master" &&
        job.fetch("head_sha") == commit
      raise unless job.fetch("status") == "completed" && job.fetch("conclusion") == "success"
      raise unless job.fetch("check_run_url") ==
        "https://api.github.com/repos/GGULBAE/desk-setup-switcher/check-runs/#{job.fetch("id")}"
    ' "$approval_workflow_jobs" "$workflow_run_id" "$workflow_run_attempt" \
        "$RELEASE_APPROVAL_RECORD_COMMIT" 2>"$parse_error" || {
        release_die "The approval commit named CI job did not succeed exactly."
    }
}

read_immutable_setting() {
    : >"$immutable_response"
    : >"$remote_error"
    printf 'Publication verification: protected remote read in progress.\n' >&2
    if ! GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$admin_read_token" 90 gh api \
        --hostname github.com \
        --method GET \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        "/repos/$GITHUB_REPOSITORY/immutable-releases" \
        >"$immutable_response" 2>"$remote_error"; then
        release_die "The protected immutable-release setting could not be read."
    fi
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json --json "$immutable_response" \
        >/dev/null 2>"$parse_error" || release_die "The immutable-release response is not strict JSON."
    ruby -rjson -e '
      input, output = ARGV
      value = JSON.parse(File.binread(input), allow_nan: false)
      abort unless value.is_a?(Hash) && value.keys.sort == %w[enabled enforced_by_owner]
      abort unless value["enabled"] == true
      enforced = value["enforced_by_owner"]
      abort unless enforced == true || enforced == false
      File.binwrite(output, "enabled=true\nenforced_by_owner=#{enforced}\n")
    ' "$immutable_response" "$immutable_fingerprint" 2>"$parse_error" || {
        release_die "Immutable Releases are not enabled."
    }
}

read_release_state() {
    local expected_state="$1"
    local observation_mode="${2:-repository-list}"
    local observed_list_state
    [[ "$observation_mode" == repository-list || "$observation_mode" == exact-id ]] || {
        release_die "The Release observation mode is invalid."
    }
    : >"$release_list_response"
    : >"$remote_error"
    printf 'Publication verification: protected remote read in progress.\n' >&2
    if ! GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$admin_read_token" 90 gh api \
            --hostname github.com \
            --method GET \
            --paginate \
            --slurp \
            -H "Accept: application/vnd.github+json" \
            -H "X-GitHub-Api-Version: 2026-03-10" \
            "/repos/$GITHUB_REPOSITORY/releases?per_page=100" \
            >"$release_list_response" 2>"$remote_error"; then
            release_die "The authenticated Release list could not be read."
    fi
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json --json "$release_list_response" \
        >/dev/null 2>"$parse_error" || release_die "The Release list is not strict JSON."
    observed_list_state="$(ruby -rjson -e '
      path, release_id_text, tag = ARGV
      release_id = Integer(release_id_text, 10)
      pages = JSON.parse(File.binread(path), allow_nan: false)
      abort unless pages.is_a?(Array) && pages.all? { |page| page.is_a?(Array) }
      releases = pages.flatten(1)
      abort unless releases.length == 1 && releases.fetch(0).is_a?(Hash)
      release = releases.fetch(0)
      abort unless release["id"] == release_id && release["tag_name"] == tag
      abort unless release["node_id"].is_a?(String) && !release["node_id"].empty?
      abort unless release["draft"] == true || release["draft"] == false
      puts release["draft"] == true ? "draft" : "published"
    ' "$release_list_response" "$RELEASE_ID" "$RELEASE_TAG" \
        2>"$parse_error")" || {
        release_die "The repository does not contain exactly the one approved Release."
    }
    if [[ "$expected_state" == any && "$observed_list_state" == published ]]; then
        publication_mutation_state=incident
    fi

    if [[ "$observation_mode" == repository-list && "$expected_state" == published ]]; then
        github_get "/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID" "$release_response"
    elif [[ "$observation_mode" == repository-list ]]; then
        cp -- "$release_list_response" "$release_response"
    fi
    : >"$assets_response"
    printf 'Publication verification: protected remote read in progress.\n' >&2
    if ! GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$admin_read_token" 90 gh api \
        --hostname github.com \
        --method GET \
        --paginate \
        --slurp \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        "/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID/assets?per_page=100" \
        >"$assets_response" 2>"$remote_error"; then
        release_die "The exact Release asset list could not be read."
    fi
    # In the mutation-bound exact-ID mode, the Release object is deliberately
    # the final network read. Its embedded assets cross-bind the immediately
    # preceding paginated asset projection, closing metadata drift during that
    # asset request before the one PATCH.
    if [[ "$observation_mode" == exact-id ]]; then
        github_get "/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID" "$release_response"
    fi
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json --json "$release_response" \
        >/dev/null 2>"$parse_error" || release_die "The Release response is not strict JSON."
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json --json "$assets_response" \
        >/dev/null 2>"$parse_error" || release_die "The Release asset response is not strict JSON."

    ruby -rjson -rdigest -rtime -e '
      begin
        release_path, assets_path, notes_path, source_dir, expected_state, observation_mode, release_id_text,
          tag, title, repository, expected_commit, state_path, release_fingerprint_path,
          asset_fingerprint_path, asset_ids_path, approval_path, *expected_names = ARGV
        release_id = Integer(release_id_text, 10)
        release_payload = JSON.parse(File.binread(release_path), allow_nan: false)
        pages = JSON.parse(File.binread(assets_path), allow_nan: false)
        release = if observation_mode == "exact-id" || expected_state == "published"
          raise unless release_payload.is_a?(Hash)
          release_payload
        else
          raise unless release_payload.is_a?(Array) && release_payload.all? { |page| page.is_a?(Array) }
          releases = release_payload.flatten(1)
          # v0.1.0 is the first repository publication. Refuse to publish
          # while any unrelated draft or public Release exists: selecting one
          # matching ID would otherwise hide unexpected repository state.
          raise unless releases.length == 1 && releases.fetch(0).is_a?(Hash)
          raise unless releases.fetch(0)["id"] == release_id
          releases.fetch(0)
        end
        raise unless pages.is_a?(Array) && pages.all? { |page| page.is_a?(Array) }
        assets = pages.flatten(1)
        raise unless assets.length == expected_names.length && assets.all? { |asset| asset.is_a?(Hash) }
        raise unless release["id"] == release_id
        node_id = release["node_id"]
        raise unless node_id.is_a?(String) && !node_id.empty?
        raise unless release["tag_name"] == tag && release["name"] == title
        # GitHub ignores target_commitish when the tag already exists. The
        # independently verified direct/peeled tag is authoritative; retain
        # this API field only as a nonempty, drift-detected metadata value.
        target_commitish = release["target_commitish"]
        raise unless target_commitish.is_a?(String) && !target_commitish.empty?
        raise if target_commitish.match?(/[\t\r\n]/)
        raise unless release["body"] == File.binread(notes_path).force_encoding(Encoding::UTF_8)
        raise unless release["prerelease"] == true
        raise unless release["url"] == "https://api.github.com/repos/#{repository}/releases/#{release_id}"
        raise unless release["upload_url"] == "https://uploads.github.com/repos/#{repository}/releases/#{release_id}/assets{?name,label}"
        created_at = release["created_at"]
        updated_at = release["updated_at"]
        raise unless created_at.is_a?(String) && !created_at.empty?
        raise unless updated_at.is_a?(String) && !updated_at.empty?
        raise unless release["draft"] == true || release["draft"] == false
        actual_state = release["draft"] == true ? "draft" : "published"
        raise unless ["any", actual_state].include?(expected_state)
        if actual_state == "draft"
          raise unless release["draft"] == true
          raise unless release["published_at"].nil?
          raise unless release["immutable"] == false
          published_at_time = nil
        else
          raise unless release["draft"] == false
          raise unless release["published_at"].is_a?(String) && !release["published_at"].empty?
          published_at_time = Time.iso8601(release["published_at"])
          raise unless release["immutable"] == true
          raise unless release["html_url"] == "https://github.com/#{repository}/releases/tag/#{tag}"
        end
        raise unless release["assets_url"] == "https://api.github.com/repos/#{repository}/releases/#{release_id}/assets"
        raise unless release["html_url"].is_a?(String) && release["html_url"].start_with?("https://github.com/#{repository}/releases/")

        normalize = lambda do |asset|
          id = asset["id"]
          name = asset["name"]
          size = asset["size"]
          raise unless id.is_a?(Integer) && id.positive?
          raise unless name.is_a?(String) && expected_names.include?(name)
          raise unless asset["state"] == "uploaded"
          source = File.join(source_dir, name)
          raise unless File.file?(source) && !File.symlink?(source)
          raise unless size.is_a?(Integer) && size == File.size(source) && size.positive?
          raise unless asset["url"] == "https://api.github.com/repos/#{repository}/releases/assets/#{id}"
          browser_url = asset["browser_download_url"]
          raise unless browser_url.is_a?(String) && browser_url.start_with?("https://github.com/#{repository}/releases/download/") && browser_url.end_with?("/#{name}")
          if actual_state == "published"
            raise unless browser_url == "https://github.com/#{repository}/releases/download/#{tag}/#{name}"
          end
          digest = asset["digest"]
          source_digest = Digest::SHA256.file(source).hexdigest
          raise unless digest.nil? || digest == "sha256:#{source_digest}"
          asset_created_at = asset["created_at"]
          asset_updated_at = asset["updated_at"]
          raise unless asset_created_at.is_a?(String) && !asset_created_at.empty?
          raise unless asset_updated_at.is_a?(String) && !asset_updated_at.empty?
          [name, id, size, asset_created_at, asset_updated_at, digest || "none"]
        end

        normalized = assets.map { |asset| normalize.call(asset) }.sort_by(&:first)
        raise unless normalized.map(&:first).sort == expected_names.sort
        raise unless normalized.map { |row| row.fetch(1) }.uniq.length == normalized.length
        embedded = release["assets"]
        raise unless embedded.is_a?(Array) && embedded.length == assets.length
        embedded_normalized = embedded.map { |asset| normalize.call(asset) }.sort_by(&:first)
        raise unless embedded_normalized == normalized

        approval = JSON.parse(File.binread(approval_path), allow_nan: false)
        approved_at = Time.iso8601(approval.fetch("approval").fetch("approvedAt"))
        expires_at = Time.iso8601(approval.fetch("approval").fetch("expiresAt"))
        evidence_timestamp_values = [created_at, *normalized.map { |row| row.fetch(4) }]
        evidence_timestamp_values << updated_at if actual_state == "draft"
        evidence_times = evidence_timestamp_values.map { |value| Time.iso8601(value) }
        raise unless evidence_times.all? { |value| value <= approved_at }
        if published_at_time
          raise unless approved_at <= published_at_time && published_at_time <= expires_at
          raise unless published_at_time <= Time.now.utc
        end

        release_lines = [
          release_id, node_id, tag, expected_commit, target_commitish, title,
          Digest::SHA256.file(notes_path).hexdigest,
          created_at, updated_at,
          actual_state, "prerelease", release["published_at"] || "unpublished",
          release["immutable"] == true ? "immutable" : "mutable"
        ]
        File.binwrite(state_path, "#{actual_state}\n")
        File.binwrite(release_fingerprint_path, release_lines.join("\t") + "\n")
        static_identity = [
          "release", release_id, node_id, tag, expected_commit, target_commitish, title,
          Digest::SHA256.file(notes_path).hexdigest, created_at
        ]
        File.binwrite(asset_fingerprint_path, ([static_identity] + normalized).map { |row| row.join("\t") }.join("\n") + "\n")
        File.binwrite(asset_ids_path, normalized.map { |row| "#{row.fetch(0)}\t#{row.fetch(1)}" }.join("\n") + "\n")
      rescue StandardError
        exit 1
      end
    ' "$release_response" "$assets_response" "$notes_snapshot" "$candidate_snapshot" \
        "$expected_state" "$observation_mode" "$RELEASE_ID" "$RELEASE_TAG" \
        "Desk Setup Switcher $RELEASE_TAG public beta" "$GITHUB_REPOSITORY" "$EXPECTED_COMMIT" \
        "$release_state" "$release_fingerprint" "$asset_fingerprint" "$asset_ids" "$approval_record" \
        "${asset_names[@]}" >/dev/null 2>"$parse_error" || {
        release_die "The exact GitHub Release metadata or nine-asset set is invalid."
    }
}

download_exact_assets() {
    local destination="$1"
    [[ -d "$destination" && ! -L "$destination" ]] || release_die "Publication download staging is invalid."
    [[ -z "$(find "$destination" -mindepth 1 -maxdepth 1 -print -quit)" ]] || {
        release_die "Publication download staging is not empty."
    }
    while IFS=$'\t' read -r name asset_id; do
        [[ -n "$name" && "$asset_id" =~ ^[1-9][0-9]*$ ]] || release_die "Release asset identity is malformed."
        : >"$destination/$name"
        printf 'Publication verification: protected remote read in progress.\n' >&2
        if ! GH_CONFIG_DIR="$gh_config_directory" \
            release_run_tracked_secret_env_timeout GH_TOKEN "$admin_read_token" 90 gh api \
            --hostname github.com \
            --method GET \
            -H "Accept: application/octet-stream" \
            -H "X-GitHub-Api-Version: 2026-03-10" \
            "/repos/$GITHUB_REPOSITORY/releases/assets/$asset_id" \
            >"$destination/$name" 2>"$remote_error"; then
            release_die "An exact Release asset could not be downloaded."
        fi
        [[ -f "$destination/$name" && ! -L "$destination/$name" ]] || {
            release_die "A downloaded Release asset is not a regular file."
        }
        cmp -s "$candidate_snapshot/$name" "$destination/$name" || {
            release_die "A downloaded Release asset differs from the exact approved candidate."
        }
    done <"$asset_ids"
    ruby -e '
      directory, *expected = ARGV
      abort unless Dir.children(directory).sort == expected.sort
      expected.each do |name|
        stat = File.lstat(File.join(directory, name))
        abort unless stat.file? && !stat.symlink?
      end
    ' "$destination" "${asset_names[@]}" >/dev/null || {
        release_die "The downloaded Release is not the exact nine regular assets."
    }
}

observed_remote_master=""
read_remote_master
initial_master="$observed_remote_master"
[[ "$RELEASE_APPROVAL_RECORD_COMMIT" == "$initial_master" ]] || {
    release_die "The approval record is not the exact effective default-branch commit."
}
printf 'Publication verification: protected remote read in progress.\n' >&2
release_run_tracked_timeout 90 git fetch --no-tags --quiet origin "$initial_master" \
    2>"$remote_error" || {
    release_die "The exact remote default-branch commit could not be fetched read-only."
}
git cat-file -e "$RELEASE_APPROVAL_RECORD_COMMIT^{commit}" 2>"$parse_error" || {
    release_die "The approval-record commit is unavailable after the exact default-branch fetch."
}

# The reviewed controls snapshot is produced against the pre-approval master.
# The approval commit must be its single direct successor and may add exactly
# the snapshot plus the approval record—nothing executable or release-critical.
git rev-list --parents -n 1 "$RELEASE_APPROVAL_RECORD_COMMIT" >"$approval_parent" 2>"$parse_error" || {
    release_die "The approval-record commit ancestry could not be read."
}
observed_master="$(ruby -e '
  row = File.read(ARGV.fetch(0)).strip.split(" ")
  abort unless row.length == 2 && row.all? { |value| value.match?(/\A[0-9a-f]{40}\z/) }
  puts row.fetch(1)
' "$approval_parent" 2>"$parse_error")" || {
    release_die "The approval-record commit is not one direct successor."
}
[[ "$observed_master" =~ ^[0-9a-f]{40}$ ]] || {
    release_die "The pre-approval master identity is invalid."
}
git cat-file -e "$observed_master^{commit}" 2>"$parse_error" || {
    release_die "The pre-approval master commit is unavailable."
}
git merge-base --is-ancestor "$EXPECTED_COMMIT" "$observed_master" || {
    release_die "The controls snapshot commit does not descend from the release commit."
}
# The final-pre-tag record is collected while A is a clean future tag target.
# After its digest is fixed, the local annotated tag candidate targets A and the
# record enters history exactly once in direct child B as the only changed path;
# no later ancestry may rewrite those bytes.
git log --full-history --format=%H --reverse "$EXPECTED_COMMIT..$observed_master" -- \
    "$final_pre_tag_evidence_path" >"$final_pre_tag_introduction_log" 2>"$parse_error" || {
    release_die "The final-pre-tag evidence introduction history could not be read."
}
final_pre_tag_introduction_commit="$(ruby -e '
  rows = File.readlines(ARGV.fetch(0), chomp: true)
  raise unless rows.length == 1 && rows.fetch(0).match?(/\A[0-9a-f]{40}\z/)
  puts rows.fetch(0)
' "$final_pre_tag_introduction_log" 2>"$parse_error")" || {
    release_die "The final-pre-tag evidence was not introduced exactly once."
}
git rev-list --first-parent "$observed_master" \
    >"$final_pre_tag_first_parent_log" 2>"$parse_error" || {
    release_die "The final-pre-tag first-parent history could not be read."
}
ruby -e '
  path, expected = ARGV
  rows = File.readlines(path, chomp: true)
  raise unless rows.count(expected) == 1
' "$final_pre_tag_first_parent_log" "$final_pre_tag_introduction_commit" \
    >/dev/null 2>"$parse_error" || {
    release_die "The final-pre-tag evidence commit is not on the effective master first-parent path."
}
git rev-list --parents -n 1 "$final_pre_tag_introduction_commit" \
    >"$final_pre_tag_introduction_parent" 2>"$parse_error" || {
    release_die "The final-pre-tag evidence introduction ancestry could not be read."
}
ruby -e '
  input, commit, parent = ARGV
  row = File.read(input).strip.split(" ")
  raise unless row == [commit, parent]
' "$final_pre_tag_introduction_parent" "$final_pre_tag_introduction_commit" \
    "$EXPECTED_COMMIT" 2>"$parse_error" || {
    release_die "The final-pre-tag evidence introduction is not the tag commit direct child."
}
git diff-tree --no-commit-id --name-status -r "$EXPECTED_COMMIT" \
    "$final_pre_tag_introduction_commit" >"$final_pre_tag_introduction_diff" 2>"$parse_error" || {
    release_die "The final-pre-tag evidence introduction change set could not be read."
}
ruby -e '
  input, path = ARGV
  raise unless File.readlines(input, chomp: true) == ["A\t#{path}"]
' "$final_pre_tag_introduction_diff" "$final_pre_tag_evidence_path" \
    2>"$parse_error" || {
    release_die "The final-pre-tag evidence introduction was not exact add-only."
}
git merge-base --is-ancestor "$final_pre_tag_introduction_commit" "$observed_master" || {
    release_die "The final-pre-tag evidence introduction does not precede the controls snapshot."
}
git diff-tree --no-commit-id --name-status -r "$observed_master" "$RELEASE_APPROVAL_RECORD_COMMIT" \
    >"$approval_diff" 2>"$parse_error" || {
    release_die "The approval-record commit change set could not be read."
}
ruby -e '
  input, approval_path, controls_path = ARGV
  rows = File.readlines(input, chomp: true)
  expected = ["A\t#{approval_path}", "A\t#{controls_path}"].sort
  abort unless rows.sort == expected
' "$approval_diff" "$RELEASE_APPROVAL_RECORD_PATH" "$remote_controls_evidence_path" \
    >/dev/null 2>"$parse_error" || {
    release_die "The approval-record commit changed paths outside the exact evidence allowlist."
}
for critical_path in .github/workflows scripts/release; do
    release_tree="$(git rev-parse "$EXPECTED_COMMIT:$critical_path" 2>"$parse_error")" || {
        release_die "A release-critical tree is unavailable at the release commit."
    }
    observed_tree="$(git rev-parse "$observed_master:$critical_path" 2>"$parse_error")" || {
        release_die "A release-critical tree is unavailable at the controls commit."
    }
    approval_tree_sha="$(git rev-parse "$RELEASE_APPROVAL_RECORD_COMMIT:$critical_path" 2>"$parse_error")" || {
        release_die "A release-critical tree is unavailable at the approval commit."
    }
    [[ "$release_tree" == "$observed_tree" && "$observed_tree" == "$approval_tree_sha" ]] || {
        release_die "Release-critical workflows or scripts changed after the release commit."
    }
done
unset release_tree observed_tree approval_tree_sha critical_path

materialize_exact_blob() {
    local commit="$1"
    local path="$2"
    local tree_output="$3"
    local destination="$4"
    git ls-tree "$commit" -- "$path" >"$tree_output" 2>"$parse_error" || return 1
    ruby -e '
      path, input = ARGV
      rows = File.readlines(input, chomp: true)
      abort unless rows.length == 1
      match = rows.fetch(0).match(/\A100644 blob ([0-9a-f]{40})\t(.+)\z/)
      abort unless match && match[2] == path
    ' "$path" "$tree_output" >/dev/null 2>"$parse_error" || return 1
    git show "$commit:$path" >"$destination" 2>"$parse_error" || return 1
    [[ -f "$destination" && ! -L "$destination" && -s "$destination" ]]
}

materialize_exact_blob \
    "$RELEASE_APPROVAL_RECORD_COMMIT" "$RELEASE_APPROVAL_RECORD_PATH" \
    "$approval_tree" "$approval_record" || {
    release_die "The approval record is not one ordinary tracked blob."
}
materialize_exact_blob \
    "$RELEASE_APPROVAL_RECORD_COMMIT" "$remote_controls_evidence_path" \
    "$remote_controls_tree" "$remote_controls_evidence" || {
    release_die "The pre-publication controls evidence is not one ordinary tracked blob."
}
materialize_exact_blob \
    "$RELEASE_APPROVAL_RECORD_COMMIT" "$remote_controls_policy_path" \
    "$remote_controls_policy_tree" "$remote_controls_policy" || {
    release_die "The authoritative remote-controls policy is unavailable."
}
materialize_exact_blob \
    "$RELEASE_APPROVAL_RECORD_COMMIT" "$candidate_manual_evidence_path" \
    "$candidate_manual_tree" "$candidate_manual_evidence" || {
    release_die "The release-candidate manual control evidence is unavailable."
}
materialize_exact_blob \
    "$RELEASE_APPROVAL_RECORD_COMMIT" "$publication_manual_evidence_path" \
    "$publication_manual_tree" "$publication_manual_evidence" || {
    release_die "The release-publication manual control evidence is unavailable."
}
materialize_exact_blob \
    "$EXPECTED_COMMIT" "$candidate_manual_evidence_path" \
    "$final_candidate_manual_tree" "$final_candidate_manual_evidence" || {
    release_die "The final-pre-tag release-candidate manual evidence is unavailable."
}
materialize_exact_blob \
    "$EXPECTED_COMMIT" "$publication_manual_evidence_path" \
    "$final_publication_manual_tree" "$final_publication_manual_evidence" || {
    release_die "The final-pre-tag release-publication manual evidence is unavailable."
}
materialize_exact_blob \
    "$final_pre_tag_introduction_commit" "$final_pre_tag_evidence_path" \
    "$final_pre_tag_evidence_tree" "$final_pre_tag_evidence" || {
    release_die "The durable final-pre-tag controls evidence is unavailable."
}
[[ "$(release_sha256 "$approval_record")" == "$RELEASE_APPROVAL_RECORD_SHA256" ]] || {
    release_die "The approval record differs from its explicitly approved digest."
}
remote_controls_manifest_sha256="$(release_sha256 "$remote_controls_evidence")"
expected_candidate_workflow_blob="$(git rev-parse "$observed_master:.github/workflows/release.yml" 2>"$parse_error")" || {
    release_die "The observed candidate workflow blob is unavailable."
}
expected_ci_workflow_blob="$(git rev-parse "$observed_master:.github/workflows/ci.yml" 2>"$parse_error")" || {
    release_die "The observed CI workflow blob is unavailable."
}
expected_publication_workflow_blob="$(git rev-parse "$observed_master:.github/workflows/publish-release.yml" 2>"$parse_error")" || {
    release_die "The observed publication workflow blob is unavailable."
}
ci_workflow_id="$(ruby "$RELEASE_SCRIPTS_DIR/remote_controls_policy.rb" \
    --ci-workflow-id "$remote_controls_policy" \
    --expected-workflow-blob "$expected_candidate_workflow_blob" \
    --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
    --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
    2>"$parse_error")" || {
    release_die "The reviewed CI workflow identity is unavailable."
}
[[ "$ci_workflow_id" =~ ^[1-9][0-9]*$ ]] || {
    release_die "The reviewed CI workflow identity is invalid."
}
ruby "$RELEASE_SCRIPTS_DIR/remote_controls_policy.rb" \
    --policy "$remote_controls_policy" \
    --evidence "$remote_controls_evidence" \
    --expected-commit "$observed_master" \
    --expected-workflow-blob "$expected_candidate_workflow_blob" \
    --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
    --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
    --expected-release-commit "$EXPECTED_COMMIT" \
    --expected-release-id "$RELEASE_ID" \
    --expected-release-tag-object "$tag_object" >/dev/null 2>"$parse_error" || {
    release_die "The reviewed pre-publication remote-controls manifest is invalid."
}
ruby "$RELEASE_SCRIPTS_DIR/remote_controls_policy.rb" \
    --publication-approval-contract "$remote_controls_policy" \
    >"$publication_contract" 2>"$parse_error" || {
    release_die "The reviewed publication actor contract is unavailable."
}
publication_contract_fields="$(ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
  raise unless value.is_a?(Hash) &&
    value.keys.sort == %w[approvalMode operator publisher reviewer schemaVersion]
  raise unless value.fetch("schemaVersion") == "desk-setup-switcher.publication-approval-contract/v1"
  operator = value.fetch("operator")
  reviewer = value.fetch("reviewer")
  publisher = value.fetch("publisher")
  [operator, reviewer, publisher].each do |actor|
    raise unless actor.is_a?(Hash) && actor.keys.sort == %w[id login type]
    raise unless actor.fetch("id").is_a?(Integer) && actor.fetch("id").positive?
    raise unless actor.fetch("login").is_a?(String) && !actor.fetch("login").empty?
    raise unless actor.fetch("type") == "User"
  end
  fields = [
    value.fetch("approvalMode"), operator.fetch("id"), operator.fetch("login"),
    reviewer.fetch("id"), reviewer.fetch("login"),
    publisher.fetch("id"), publisher.fetch("login")
  ]
  raise if fields.any? { |field| field.to_s.match?(/[\t\r\n]/) }
  puts fields.join("\t")
' "$publication_contract" 2>"$parse_error")" || {
    release_die "The reviewed publication actor contract is invalid."
}
IFS=$'\t' read -r expected_approval_mode expected_operator_id expected_operator_login \
    expected_reviewer_id expected_reviewer_login \
    expected_publisher_id expected_publisher_login <<<"$publication_contract_fields"
[[ "$expected_operator_id" =~ ^[1-9][0-9]*$ && \
    "$expected_reviewer_id" =~ ^[1-9][0-9]*$ && \
    "$expected_publisher_id" =~ ^[1-9][0-9]*$ ]] || {
    release_die "The reviewed publication actor identities are invalid."
}
same_github_login "$RELEASE_APPROVER_LOGIN" "$expected_reviewer_login" || {
    release_die "The approval input does not match the policy reviewer."
}
same_github_login "$RELEASE_PUBLISHER_LOGIN" "$expected_publisher_login" || {
    release_die "The publisher input does not match the policy publisher."
}
same_github_login "$GITHUB_ACTOR" "$expected_publisher_login" || {
    release_die "The dispatch actor does not match the policy publisher."
}
same_github_login "$GITHUB_TRIGGERING_ACTOR" "$expected_publisher_login" || {
    release_die "The triggering actor does not match the policy publisher."
}
[[ "$GITHUB_ACTOR_ID" == "$expected_publisher_id" ]] || {
    release_die "The dispatch actor numeric identity does not match the policy publisher."
}
[[ "$expected_operator_id" == "$expected_publisher_id" ]] \
    && same_github_login "$expected_operator_login" "$expected_publisher_login" || {
    release_die "The policy operator and publisher identities do not match."
}
read_policy_actor_identity \
    "$RELEASE_APPROVER_LOGIN" "$expected_reviewer_id" "$expected_reviewer_login" "$approver_identity"
read_policy_actor_identity \
    "$RELEASE_PUBLISHER_LOGIN" "$expected_publisher_id" "$expected_publisher_login" "$publisher_identity"
read_authenticated_admin_token_owner \
    "$expected_operator_id" "$expected_operator_login" "$admin_token_owner_identity"
manual_manifest_fields="$(ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
  manual = value.fetch("manualEvidence")
  raise unless manual.is_a?(Hash) && manual.keys.sort == %w[complete items] &&
    manual.fetch("complete") == true
  expected_controls = [
    "release-candidate-administrator-bypass-disabled",
    "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope"
  ]
  items = manual.fetch("items")
  raise unless items.is_a?(Array) && items.length == 2
  items.each_with_index do |item, index|
    raise unless item.is_a?(Hash) && item.keys.sort == %w[control sha256]
    raise unless item.fetch("control") == expected_controls.fetch(index)
    raise unless item.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
  end
  final_digest = value.fetch("finalPreTagEvidenceSHA256")
  collected_at = value.fetch("collectedAt")
  raise unless final_digest.is_a?(String) && final_digest.match?(/\A[0-9a-f]{64}\z/)
  raise unless collected_at.is_a?(String) && !collected_at.match?(/[\t\r\n]/)
  puts [*items.map { |item| item.fetch("sha256") }, final_digest, collected_at].join("\t")
' "$remote_controls_evidence" 2>"$parse_error")" || {
    release_die "The reviewed manual-control manifest binding is invalid."
}
IFS=$'\t' read -r expected_candidate_manual_sha256 expected_publication_manual_sha256 \
    expected_final_pre_tag_evidence_sha256 pre_publication_collected_at \
    <<<"$manual_manifest_fields"
[[ "$(release_sha256 "$final_pre_tag_evidence")" == "$expected_final_pre_tag_evidence_sha256" ]] || {
    release_die "The durable final-pre-tag controls evidence digest does not match the manifest."
}
ruby "$RELEASE_SCRIPTS_DIR/remote_controls_policy.rb" \
    --policy "$remote_controls_policy" \
    --evidence "$final_pre_tag_evidence" \
    --expected-commit "$EXPECTED_COMMIT" \
    --expected-workflow-blob "$expected_candidate_workflow_blob" \
    --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
    --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
    >/dev/null 2>"$parse_error" || {
    release_die "The durable final-pre-tag controls evidence cannot be replayed."
}
git cat-file -p "$tag_object" >"$tag_object_payload" 2>"$parse_error" || {
    release_die "The annotated tag payload is unavailable."
}
ruby -e '
  source, digest = ARGV
  _headers, separator, message = File.binread(source).partition("\n\n")
  expected = "remote-controls-final-pre-tag-sha256: #{digest}\n"
  raise unless separator == "\n\n" && message == expected
' "$tag_object_payload" "$expected_final_pre_tag_evidence_sha256" 2>"$parse_error" || {
    release_die "The annotated tag does not bind the final-pre-tag evidence digest."
}
final_manifest_fields="$(ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
  manual = value.fetch("manualEvidence")
  items = manual.fetch("items")
  expected_controls = [
    "release-candidate-administrator-bypass-disabled",
    "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope"
  ]
  raise unless manual.keys.sort == %w[complete items] && manual.fetch("complete") == true &&
    items.is_a?(Array) && items.length == 2
  items.each_with_index do |item, index|
    raise unless item.keys.sort == %w[control sha256] &&
      item.fetch("control") == expected_controls.fetch(index) &&
      item.fetch("sha256").match?(/\A[0-9a-f]{64}\z/)
  end
  collected_at = value.fetch("collectedAt")
  raise unless collected_at.is_a?(String) && !collected_at.match?(/[\t\r\n]/)
  puts [*items.map { |item| item.fetch("sha256") }, collected_at].join("\t")
' "$final_pre_tag_evidence" 2>"$parse_error")" || {
    release_die "The final-pre-tag manual-control bindings are invalid."
}
IFS=$'\t' read -r expected_final_candidate_manual_sha256 \
    expected_final_publication_manual_sha256 final_pre_tag_collected_at \
    <<<"$final_manifest_fields"
verify_manual_controls_now() {
    local verified_at candidate_result publication_result final_candidate_result
    local final_publication_result fields
    verified_at="$(ruby -rtime -e 'puts Time.now.utc.iso8601')" || {
        release_die "The current manual-control verification time is unavailable."
    }
    candidate_result="$(ruby "$RELEASE_SCRIPTS_DIR/collect_remote_controls_evidence.rb" \
        manual-evidence \
        --input "$candidate_manual_evidence" \
        --control release-candidate-administrator-bypass-disabled \
        --permission-profile candidate \
        --actor-id "$expected_operator_id" \
        --actor-login "$expected_operator_login" \
        --verified-at "$verified_at" \
        --phase pre-publication \
        --release-commit "$EXPECTED_COMMIT" \
        --release-id "$RELEASE_ID" \
        --release-tag-object "$tag_object" 2>"$parse_error")" || {
        release_die "The release-candidate manual control evidence is invalid or stale."
    }
    publication_result="$(ruby "$RELEASE_SCRIPTS_DIR/collect_remote_controls_evidence.rb" \
        manual-evidence \
        --input "$publication_manual_evidence" \
        --control release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope \
        --permission-profile publication \
        --actor-id "$expected_operator_id" \
        --actor-login "$expected_operator_login" \
        --verified-at "$verified_at" \
        --phase pre-publication \
        --release-commit "$EXPECTED_COMMIT" \
        --release-id "$RELEASE_ID" \
        --release-tag-object "$tag_object" 2>"$parse_error")" || {
        release_die "The release-publication manual control evidence is invalid or stale."
    }
    final_candidate_result="$(ruby "$RELEASE_SCRIPTS_DIR/collect_remote_controls_evidence.rb" \
        manual-evidence \
        --input "$final_candidate_manual_evidence" \
        --control release-candidate-administrator-bypass-disabled \
        --permission-profile candidate \
        --actor-id "$expected_operator_id" \
        --actor-login "$expected_operator_login" \
        --verified-at "$final_pre_tag_collected_at" \
        --phase final-pre-tag 2>"$parse_error")" || {
        release_die "The final-pre-tag release-candidate manual evidence is invalid or stale."
    }
    final_publication_result="$(ruby "$RELEASE_SCRIPTS_DIR/collect_remote_controls_evidence.rb" \
        manual-evidence \
        --input "$final_publication_manual_evidence" \
        --control release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope \
        --permission-profile publication \
        --actor-id "$expected_operator_id" \
        --actor-login "$expected_operator_login" \
        --verified-at "$final_pre_tag_collected_at" \
        --phase final-pre-tag 2>"$parse_error")" || {
        release_die "The final-pre-tag release-publication manual evidence is invalid or stale."
    }
    fields="$(ruby -rjson -e '
      expected_candidate, expected_publication, expected_final_candidate,
        expected_final_publication, *sources = ARGV
      rows = sources.map { |source| JSON.parse(source, allow_nan: false, create_additions: false) }
      rows.each do |row|
        raise unless row.is_a?(Hash) &&
          row.keys.sort == %w[control observedAt sha256 sourceArtifactSHA256]
      end
      raise unless rows.fetch(0).fetch("sha256") == expected_candidate
      raise unless rows.fetch(1).fetch("sha256") == expected_publication
      raise unless rows.fetch(2).fetch("sha256") == expected_final_candidate
      raise unless rows.fetch(3).fetch("sha256") == expected_final_publication
      raise unless rows.map { |row| row.fetch("sourceArtifactSHA256") }.uniq.length == 4
      puts "OK"
    ' "$expected_candidate_manual_sha256" "$expected_publication_manual_sha256" \
        "$expected_final_candidate_manual_sha256" "$expected_final_publication_manual_sha256" \
        "$candidate_result" "$publication_result" "$final_candidate_result" \
        "$final_publication_result" 2>"$parse_error")" || {
        release_die "Fresh manual controls do not match the reviewed manifest."
    }
    [[ "$fields" == OK ]] || release_die "Fresh manual-control validation is ambiguous."
}
verify_evidence_approval_ordering() {
    ruby -rjson -rtime -e '
      approval_path, final_path, pre_path, *manual_paths = ARGV
      approval = JSON.parse(File.binread(approval_path), allow_nan: false, create_additions: false)
      approved_at_text = approval.fetch("approval").fetch("approvedAt")
      approved_at = Time.iso8601(approved_at_text)
      raise unless approved_at_text == approved_at.utc.iso8601
      evidence_times = [final_path, pre_path].map do |path|
        evidence = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
        collected_at_text = evidence.fetch("collectedAt")
        collected_at = Time.iso8601(collected_at_text)
        raise unless collected_at_text == collected_at.utc.iso8601
        collected_at
      end
      manual_times = manual_paths.map do |path|
        manual = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
        observed_at_text = manual.fetch("observedAt")
        observed_at = Time.iso8601(observed_at_text)
        raise unless observed_at_text == observed_at.utc.iso8601
        observed_at
      end
      final_collected, pre_collected = evidence_times
      current_manual = manual_times.first(2)
      final_manual = manual_times.drop(2).first(2)
      raise unless final_manual.all? { |time| time <= final_collected }
      raise unless current_manual.all? { |time| final_collected <= time && time <= pre_collected }
      raise unless pre_collected <= approved_at
    ' "$approval_record" "$final_pre_tag_evidence" "$remote_controls_evidence" \
        "$candidate_manual_evidence" "$publication_manual_evidence" \
        "$final_candidate_manual_evidence" "$final_publication_manual_evidence" \
        >/dev/null 2>"$parse_error" || {
        release_die "The approval predates controls evidence for this release."
    }
}
verify_approval_record_now() {
    local verified_at
    verified_at="$(ruby -rtime -e 'puts Time.now.utc.iso8601')" || {
        release_die "The current publication verification time is unavailable."
    }
    ruby "$RELEASE_SCRIPTS_DIR/publication_policy.rb" verify-approval \
        --json "$approval_record" \
        --repository "$GITHUB_REPOSITORY" \
        --tag "$RELEASE_TAG" \
        --commit "$EXPECTED_COMMIT" \
        --release-id "$RELEASE_ID" \
        --candidate-run-id "$RELEASE_CANDIDATE_RUN_ID" \
        --candidate-artifact-id "$RELEASE_CANDIDATE_ARTIFACT_ID" \
        --candidate-artifact-sha256 "$RELEASE_CANDIDATE_ARTIFACT_SHA256" \
        --final-dmg-sha256 "$RELEASE_FINAL_DMG_SHA256" \
        --remote-controls-observed-master "$observed_master" \
        --remote-controls-manifest-sha256 "$remote_controls_manifest_sha256" \
        --approval-sha256 "$RELEASE_APPROVAL_RECORD_SHA256" \
        --approver-login "$RELEASE_APPROVER_LOGIN" \
        --publisher-login "$RELEASE_PUBLISHER_LOGIN" \
        --approval-mode "$expected_approval_mode" \
        --verified-at "$verified_at" >/dev/null || {
        release_die "The publication approval record does not approve this exact candidate."
    }
}
verify_approval_now() {
    verify_approval_record_now
    verify_evidence_approval_ordering
    verify_manual_controls_now
}
verify_approval_now
require_remote_tag
read_immutable_setting
cp -- "$immutable_fingerprint" "$pre_immutable_fingerprint"
read_release_state any
initial_state="$(tr -d '\n' <"$release_state")"
[[ "$initial_state" == draft ]] || {
    release_incident_die "A pre-existing public Release requires read-only incident review."
}
cp -- "$release_fingerprint" "$pre_release_fingerprint"
cp -- "$asset_fingerprint" "$pre_asset_fingerprint"
download_exact_assets "$pre_download"

# Re-observe every mutable boundary immediately before the only mutation.
read_remote_master
[[ "$observed_remote_master" == "$initial_master" ]] || release_die "The default branch changed during publication review."
require_remote_tag
read_immutable_setting
cmp -s "$pre_immutable_fingerprint" "$immutable_fingerprint" || {
    release_die "The immutable-release setting changed during publication review."
}
state_before="$(tr -d '\n' <"$release_state")"
read_release_state "$state_before"
cmp -s "$pre_release_fingerprint" "$release_fingerprint" || {
    release_die "The Release metadata changed during publication review."
}
cmp -s "$pre_asset_fingerprint" "$asset_fingerprint" || {
    release_die "The Release assets changed during publication review."
}
verify_approval_now

if [[ "$state_before" == draft ]]; then
    # The approval commit itself carries the add-only manifest/approval pair
    # and must pass the full-history CI audit before any publication mutation.
    verify_approval_commit_ci
    read_release_state draft
    cmp -s "$pre_release_fingerprint" "$release_fingerprint" || {
        release_die "The Release metadata changed while approval-commit CI was checked."
    }
    cmp -s "$pre_asset_fingerprint" "$asset_fingerprint" || {
        release_die "The Release assets changed while approval-commit CI was checked."
    }
    # Complete every independent control before the final exact-ID target read.
    # The repository-list read above retains the one-Release invariant without
    # widening the final exact-ID GET-to-PATCH window.
    read_remote_master
    [[ "$observed_remote_master" == "$initial_master" ]] || {
        release_die "The default branch changed immediately before publication."
    }
    require_remote_tag
    read_immutable_setting
    cmp -s "$pre_immutable_fingerprint" "$immutable_fingerprint" || {
        release_die "The immutable-release setting changed immediately before publication."
    }
    verify_approval_now
    # These are the final network reads: the same exact Release ID used by the
    # PATCH and its exact paginated asset route. The embedded asset projection
    # must equal the standalone asset projection and the approved draft bytes.
    read_release_state draft exact-id
    cmp -s "$pre_release_fingerprint" "$release_fingerprint" || {
        release_die "The exact Release metadata changed immediately before publication."
    }
    cmp -s "$pre_asset_fingerprint" "$asset_fingerprint" || {
        release_die "The exact Release assets changed immediately before publication."
    }
    # Only a local, digest-bound approval time check follows the final target
    # observation. It closes expiration drift without another network call.
    verify_approval_record_now
    printf '{"draft":false,"prerelease":true,"make_latest":"false"}\n' >"$publish_request"
    chmod 0600 "$publish_request"
    : >"$publish_response"
    publication_mutation_state=attempting
    printf 'PATCH_ATTEMPT_BEGIN\n' >&2
    patch_status=0
    GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$write_token" 90 gh api \
        --hostname github.com \
        --method PATCH \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2026-03-10" \
        --input "$publish_request" \
        "/repos/$GITHUB_REPOSITORY/releases/$RELEASE_ID" \
        >"$publish_response" 2>"$remote_error" || patch_status=$?
    publication_mutation_state=incident
    if [[ -n "${release_active_child_pid:-}" ]]; then
        release_incident_die "The publication helper process tree could not be proven stopped."
    fi
    if [[ "$patch_status" != 0 ]]; then
        : >"$publish_response"
    fi
    unset patch_status
    response_valid=false
    if [[ -s "$publish_response" ]] \
        && ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json --json "$publish_response" \
            >/dev/null 2>"$parse_error" \
        && ruby -rjson -e '
      release = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false)
      expected_id = Integer(ARGV.fetch(1), 10)
      expected_tag = ARGV.fetch(2)
      abort unless release.is_a?(Hash) && release["id"] == expected_id
      abort unless release["tag_name"] == expected_tag
      abort unless release["draft"] == false && release["prerelease"] == true
      abort unless release["immutable"] == true
    ' "$publish_response" "$RELEASE_ID" "$RELEASE_TAG" >/dev/null 2>"$parse_error"; then
        response_valid=true
    fi
    if [[ "$response_valid" != true ]]; then
        # The server may have committed the exact PATCH even if the response was
        # interrupted. Resolve that ambiguity only by an exact-ID public read.
        require_remote_tag
        read_immutable_setting
        read_release_state published
        cmp -s "$pre_asset_fingerprint" "$asset_fingerprint" || {
            release_die "Publication returned ambiguously and exact public recovery did not match."
        }
    fi
else
    release_die "The Release is no longer the approved draft."
fi

# A failure after the exact PATCH is incident-only. This run may confirm its own
# ambiguous PATCH response, but a later workflow run never adopts public state.
read_remote_master
[[ "$observed_remote_master" == "$initial_master" ]] || release_die "The default branch changed during publication."
require_remote_tag
read_immutable_setting
cmp -s "$pre_immutable_fingerprint" "$immutable_fingerprint" || {
    release_die "The immutable-release setting changed during publication."
}
read_release_state published
cmp -s "$pre_asset_fingerprint" "$asset_fingerprint" || {
    release_die "The published Release asset identity differs from the approved draft."
}

post_download_staging="$(mktemp -d "$download_parent/.desk-setup-public-release.XXXXXX")"
download_exact_assets "$post_download_staging"
cp -- "$release_fingerprint" "$pre_release_fingerprint"
cp -- "$asset_fingerprint" "$pre_asset_fingerprint"
read_release_state published
cmp -s "$pre_release_fingerprint" "$release_fingerprint" || {
    release_die "The public Release metadata changed during final download."
}
cmp -s "$pre_asset_fingerprint" "$asset_fingerprint" || {
    release_die "The public Release assets changed during final download."
}
read_remote_master
[[ "$observed_remote_master" == "$initial_master" ]] || release_die "The default branch changed during final verification."
require_remote_tag

mv -- "$post_download_staging" "$download_directory"
post_download_staging=""
printf 'Published exact immutable public beta Release ID %s and redownloaded all nine assets.\n' "$RELEASE_ID"
