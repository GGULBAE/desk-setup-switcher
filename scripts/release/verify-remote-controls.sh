#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077
unset GH_DEBUG DEBUG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
POLICY_PATH="$SCRIPT_DIR/remote-controls-policy.json"
POLICY_VALIDATOR="$SCRIPT_DIR/remote_controls_policy.rb"
COLLECTOR="$SCRIPT_DIR/collect_remote_controls_evidence.rb"
WORKFLOW_PATH="$ROOT_DIR/.github/workflows/release.yml"
CI_WORKFLOW_PATH="$ROOT_DIR/.github/workflows/ci.yml"
REPOSITORY="GGULBAE/desk-setup-switcher"

policy_error() {
    printf 'ERROR: remote controls policy mismatch\n' >&2
    exit 1
}

local_anchor_error() {
    printf 'ERROR: remote controls local anchor mismatch\n' >&2
    exit 1
}

api_error() {
    local endpoint_id="$1"
    printf 'ERROR: remote controls API unavailable (endpoint %s)\n' "$endpoint_id" >&2
    exit 70
}

evidence_error() {
    printf 'ERROR: remote controls evidence unavailable\n' >&2
    exit 70
}

internal_error() {
    printf 'ERROR: remote controls collection failed\n' >&2
    exit 70
}

[[ "$#" -eq 0 ]] || policy_error
command -v ruby >/dev/null 2>&1 || internal_error

# This fixed checked-in policy is the only authority for a live collection.
# In particular, configured:false must stop before gh is even resolved.
policy_status=0
ruby "$POLICY_VALIDATOR" --check-policy "$POLICY_PATH" >/dev/null 2>&1 \
    || policy_status=$?
if [[ "$policy_status" -eq 1 ]]; then
    policy_error
elif [[ "$policy_status" -ne 0 ]]; then
    internal_error
fi

command -v git >/dev/null 2>&1 || internal_error

repository_root="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)" || local_anchor_error
repository_root="$(cd "$repository_root" 2>/dev/null && pwd -P)" || local_anchor_error
[[ "$repository_root" == "$ROOT_DIR" ]] || local_anchor_error

shallow="$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository 2>/dev/null)" || local_anchor_error
[[ "$shallow" == false ]] || local_anchor_error

worktree_status="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all 2>/dev/null)" \
    || local_anchor_error
[[ -z "$worktree_status" ]] || local_anchor_error
unset worktree_status

expected_commit="$(git -C "$ROOT_DIR" rev-parse --verify HEAD 2>/dev/null)" || local_anchor_error
[[ "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_workflow_blob="$(git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/release.yml' 2>/dev/null)" \
    || local_anchor_error
[[ "$expected_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_ci_workflow_blob="$(git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/ci.yml' 2>/dev/null)" \
    || local_anchor_error
[[ "$expected_ci_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_policy_blob="$(
    git -C "$ROOT_DIR" rev-parse 'HEAD:scripts/release/remote-controls-policy.json' 2>/dev/null
)" || local_anchor_error
[[ "$expected_policy_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
working_workflow_blob="$(git -C "$ROOT_DIR" hash-object -- "$WORKFLOW_PATH" 2>/dev/null)" \
    || local_anchor_error
working_ci_workflow_blob="$(git -C "$ROOT_DIR" hash-object -- "$CI_WORKFLOW_PATH" 2>/dev/null)" \
    || local_anchor_error
working_policy_blob="$(git -C "$ROOT_DIR" hash-object -- "$POLICY_PATH" 2>/dev/null)" \
    || local_anchor_error
[[ "$working_workflow_blob" == "$expected_workflow_blob" ]] || local_anchor_error
[[ "$working_ci_workflow_blob" == "$expected_ci_workflow_blob" ]] || local_anchor_error
[[ "$working_policy_blob" == "$expected_policy_blob" ]] || local_anchor_error
unset working_workflow_blob working_ci_workflow_blob working_policy_blob

policy_status=0
ci_workflow_id="$(
    ruby "$POLICY_VALIDATOR" \
        --ci-workflow-id "$POLICY_PATH" \
        --expected-workflow-blob "$expected_workflow_blob" \
        --expected-ci-workflow-blob "$expected_ci_workflow_blob" 2>/dev/null
)" || policy_status=$?
if [[ "$policy_status" -eq 1 ]]; then
    policy_error
elif [[ "$policy_status" -ne 0 ]]; then
    internal_error
fi
[[ "$ci_workflow_id" =~ ^[1-9][0-9]*$ ]] || policy_error
unset policy_status

if ! local_triggers="$(
    ruby "$COLLECTOR" local-triggers --workflow "$WORKFLOW_PATH" 2>/dev/null
)"; then
    local_anchor_error
fi
[[ "$local_triggers" == '["workflow_dispatch"]' ]] || local_anchor_error
if ! local_ci_triggers="$(
    ruby "$COLLECTOR" local-triggers --workflow "$CI_WORKFLOW_PATH" 2>/dev/null
)"; then
    local_anchor_error
fi
[[ "$local_ci_triggers" == '["pull_request","push","workflow_dispatch"]' ]] \
    || local_anchor_error

local_anchors_match() {
    local observed_root observed_shallow observed_commit
    local observed_workflow_blob observed_ci_workflow_blob observed_policy_blob
    local observed_workflow_worktree_blob observed_ci_workflow_worktree_blob
    local observed_policy_worktree_blob observed_status

    [[ -f "$WORKFLOW_PATH" && ! -L "$WORKFLOW_PATH" ]] || return 1
    [[ -f "$CI_WORKFLOW_PATH" && ! -L "$CI_WORKFLOW_PATH" ]] || return 1
    [[ -f "$POLICY_PATH" && ! -L "$POLICY_PATH" ]] || return 1
    observed_root="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 1
    observed_root="$(cd "$observed_root" 2>/dev/null && pwd -P)" || return 1
    observed_shallow="$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository 2>/dev/null)" \
        || return 1
    observed_commit="$(git -C "$ROOT_DIR" rev-parse --verify HEAD 2>/dev/null)" || return 1
    observed_workflow_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/release.yml' 2>/dev/null
    )" || return 1
    observed_ci_workflow_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/ci.yml' 2>/dev/null
    )" || return 1
    observed_policy_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:scripts/release/remote-controls-policy.json' 2>/dev/null
    )" || return 1
    observed_workflow_worktree_blob="$(
        git -C "$ROOT_DIR" hash-object -- "$WORKFLOW_PATH" 2>/dev/null
    )" || return 1
    observed_ci_workflow_worktree_blob="$(
        git -C "$ROOT_DIR" hash-object -- "$CI_WORKFLOW_PATH" 2>/dev/null
    )" || return 1
    observed_policy_worktree_blob="$(
        git -C "$ROOT_DIR" hash-object -- "$POLICY_PATH" 2>/dev/null
    )" || return 1
    observed_status="$(
        git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all 2>/dev/null
    )" || return 1

    [[ "$observed_root" == "$ROOT_DIR" ]] || return 1
    [[ "$observed_shallow" == false ]] || return 1
    [[ "$observed_commit" == "$expected_commit" ]] || return 1
    [[ "$observed_workflow_blob" == "$expected_workflow_blob" ]] || return 1
    [[ "$observed_ci_workflow_blob" == "$expected_ci_workflow_blob" ]] || return 1
    [[ "$observed_policy_blob" == "$expected_policy_blob" ]] || return 1
    [[ "$observed_workflow_worktree_blob" == "$expected_workflow_blob" ]] || return 1
    [[ "$observed_ci_workflow_worktree_blob" == "$expected_ci_workflow_blob" ]] || return 1
    [[ "$observed_policy_worktree_blob" == "$expected_policy_blob" ]] || return 1
    [[ -z "$observed_status" ]] || return 1
}

local_anchors_match || local_anchor_error

command -v gh >/dev/null 2>&1 || api_error G00
command -v cmp >/dev/null 2>&1 || internal_error
command -v cp >/dev/null 2>&1 || internal_error

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-remote-controls.XXXXXX" 2>/dev/null)" \
    || internal_error
chmod 0700 "$temporary_root" >/dev/null 2>&1 || {
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
    internal_error
}
cleanup() {
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot_one="$temporary_root/snapshot-1"
snapshot_two="$temporary_root/snapshot-2"
mkdir "$snapshot_one" "$snapshot_two" >/dev/null 2>&1 || internal_error
chmod 0700 "$snapshot_one" "$snapshot_two" >/dev/null 2>&1 || internal_error

api_get() {
    local endpoint_id="$1"
    local endpoint="$2"
    local output="$3"
    shift 3
    if ! gh api \
        --hostname github.com \
        -X GET \
        -H 'Accept: application/vnd.github+json' \
        -H 'X-GitHub-Api-Version: 2026-03-10' \
        -H 'Cache-Control: no-cache' \
        "$@" \
        "$endpoint" 2>/dev/null >"$output"; then
        api_error "$endpoint_id"
    fi
}

collect_controls() {
    local snapshot="$1"
    local ruleset_id_lines ruleset_id ruleset_filename
    local check_suite_id workflow_run_id workflow_run_attempt workflow_job_id
    local ruleset_index=0

    # Authenticated identity and fixed repository visibility.
    api_get I01 '/user' "$snapshot/viewer.json" \
        --jq '{id: .id, login: .login, type: .type}'
    api_get I02 '/repos/GGULBAE/desk-setup-switcher' "$snapshot/repository.json" \
        --jq '{id: .id, node_id: .node_id, name: .name, full_name: .full_name, owner: {id: .owner.id, login: .owner.login, type: .owner.type}, private: .private, visibility: .visibility, default_branch: .default_branch, archived: .archived, disabled: .disabled, has_discussions: .has_discussions, description: .description, homepage: .homepage, topics: .topics}'
    api_get I03 \
        '/repos/GGULBAE/desk-setup-switcher/collaborators/GGULBAE/permission' \
        "$snapshot/permission.json" \
        --jq '{permission: .permission, user: {id: .user.id, login: .user.login, type: .user.type}}'

    # Fetch every repository ruleset detail; bypass_actors is visible only to
    # a sufficiently privileged viewer and must never be inferred as empty.
    api_get R01 \
        '/repos/GGULBAE/desk-setup-switcher/rulesets?includes_parents=false&per_page=100' \
        "$snapshot/ruleset-ids.json" \
        --paginate --jq '.[] | {id: .id, name: .name, target: .target, enforcement: .enforcement, source_type: .source_type, source: .source}'
    if ! ruleset_id_lines="$(
        ruby "$COLLECTOR" ruleset-ids --input "$snapshot/ruleset-ids.json" 2>/dev/null
    )"; then
        evidence_error
    fi
    if [[ -n "$ruleset_id_lines" ]]; then
        while IFS= read -r ruleset_id; do
            [[ "$ruleset_id" =~ ^[1-9][0-9]*$ ]] || evidence_error
            ruleset_index=$((ruleset_index + 1))
            printf -v ruleset_filename 'ruleset-detail-%04d.json' "$ruleset_index"
            api_get R02 \
                "/repos/GGULBAE/desk-setup-switcher/rulesets/$ruleset_id?includes_parents=false" \
                "$snapshot/$ruleset_filename" \
                --jq '{id: .id, name: .name, target: .target, enforcement: .enforcement, source_type: .source_type, source: .source, conditions: {ref_name: {include: .conditions.ref_name.include, exclude: .conditions.ref_name.exclude}}, bypass_actors: .bypass_actors, rules: [.rules[] | if has("parameters") then {type: .type, parameters: .parameters} else {type: .type} end]}'
        done <<<"$ruleset_id_lines"
    fi
    api_get R03 \
        '/repos/GGULBAE/desk-setup-switcher/rules/branches/master?per_page=30' \
        "$snapshot/effective-master.json" \
        --paginate --jq '.[] | {ruleset_id: .ruleset_id, ruleset_source_type: .ruleset_source_type, ruleset_source: .ruleset_source, rule: (if has("parameters") then {type: .type, parameters: .parameters} else {type: .type} end)}'

    # Credential-bearing variable endpoints are projected to names inside gh;
    # raw values never enter a file, pipe, cache, or diagnostic.
    api_get E01 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-candidate' \
        "$snapshot/environment.json" \
        --jq '{name: .name, protection_rules: [.protection_rules[] | if .type == "required_reviewers" then {type: .type, prevent_self_review: .prevent_self_review, reviewers: [.reviewers[] | {type: .type, reviewer: {id: .reviewer.id, login: .reviewer.login, type: .reviewer.type}}]} else {type: .type} end], deployment_branch_policy: {protected_branches: .deployment_branch_policy.protected_branches, custom_branch_policies: .deployment_branch_policy.custom_branch_policies}}'
    api_get E02 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-candidate/deployment-branch-policies?per_page=30' \
        "$snapshot/deployment-policies.json" \
        --paginate --jq '{total_count: .total_count, items: (.branch_policies | map({name: .name, type: .type}))}'
    api_get E03 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-candidate/secrets?per_page=30' \
        "$snapshot/environment-secrets.json" \
        --paginate --jq '{total_count: .total_count, names: (.secrets | map(.name))}'
    api_get E04 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-candidate/variables?per_page=30' \
        "$snapshot/environment-variable-names.json" \
        --paginate --jq '{total_count: .total_count, names: (.variables | map(.name))}'
    api_get C01 \
        '/repos/GGULBAE/desk-setup-switcher/actions/secrets?per_page=30' \
        "$snapshot/repository-secrets.json" \
        --paginate --jq '{total_count: .total_count, names: (.secrets | map(.name))}'
    api_get C02 \
        '/repos/GGULBAE/desk-setup-switcher/actions/variables?per_page=30' \
        "$snapshot/repository-variable-names.json" \
        --paginate --jq '{total_count: .total_count, names: (.variables | map(.name))}'

    api_get S01 \
        '/repos/GGULBAE/desk-setup-switcher/private-vulnerability-reporting' \
        "$snapshot/private-vulnerability-reporting.json" --jq '{enabled: .enabled}'
    api_get S02 \
        '/repos/GGULBAE/desk-setup-switcher/immutable-releases' \
        "$snapshot/immutable-releases.json" \
        --jq '{enabled: .enabled, enforced_by_owner: .enforced_by_owner}'
    api_get P01 \
        '/repos/GGULBAE/desk-setup-switcher/actions/permissions' \
        "$snapshot/actions-permissions.json" \
        --jq '{enabled: .enabled, allowed_actions: .allowed_actions, sha_pinning_required: .sha_pinning_required}'
    api_get P02 \
        '/repos/GGULBAE/desk-setup-switcher/actions/permissions/selected-actions' \
        "$snapshot/selected-actions.json" \
        --jq '{github_owned_allowed: .github_owned_allowed, verified_allowed: .verified_allowed, patterns_allowed: .patterns_allowed}'
    api_get P03 \
        '/repos/GGULBAE/desk-setup-switcher/actions/permissions/workflow' \
        "$snapshot/workflow-permissions.json" \
        --jq '{default_workflow_permissions: .default_workflow_permissions, can_approve_pull_request_reviews: .can_approve_pull_request_reviews}'
    api_get L01 \
        '/repos/GGULBAE/desk-setup-switcher/labels/needs-triage' \
        "$snapshot/label.json" --jq '{name: .name, present: true}'
    api_get B01 \
        '/repos/GGULBAE/desk-setup-switcher/git/matching-refs/tags/v' \
        "$snapshot/v-refs.json" --jq '.[] | {ref: .ref}'
    api_get B02 \
        '/repos/GGULBAE/desk-setup-switcher/releases?per_page=30' \
        "$snapshot/releases.json" --paginate --jq '.[] | {id: .id}'
    api_get C03 \
        "/repos/GGULBAE/desk-setup-switcher/commits/$expected_commit/check-runs?check_name=Verify%20macOS%20app&app_id=15368&filter=latest&per_page=100" \
        "$snapshot/check-runs.json" \
        --paginate --jq '{total_count: .total_count, items: (.check_runs | map({id: .id, name: .name, app_id: .app.id, check_suite_id: .check_suite.id, head_sha: .head_sha, status: .status, conclusion: .conclusion}))}'
    if ! check_suite_id="$(
        ruby "$COLLECTOR" check-suite-id --input "$snapshot/check-runs.json" 2>/dev/null
    )"; then
        evidence_error
    fi
    [[ "$check_suite_id" =~ ^[1-9][0-9]*$ ]] || evidence_error
    api_get C04 \
        "/repos/GGULBAE/desk-setup-switcher/actions/workflows/$ci_workflow_id/runs?check_suite_id=$check_suite_id&head_sha=$expected_commit&event=push&per_page=100" \
        "$snapshot/workflow-runs.json" \
        --paginate --jq '{total_count: .total_count, items: (.workflow_runs | map({id: .id, workflow_id: .workflow_id, check_suite_id: .check_suite_id, run_attempt: .run_attempt, path: .path, event: .event, head_branch: .head_branch, head_sha: .head_sha, status: .status, conclusion: .conclusion}))}'
    if ! workflow_run_id="$(
        ruby "$COLLECTOR" workflow-run-id --input "$snapshot/workflow-runs.json" 2>/dev/null
    )"; then
        evidence_error
    fi
    [[ "$workflow_run_id" =~ ^[1-9][0-9]*$ ]] || evidence_error
    if ! workflow_run_attempt="$(
        ruby "$COLLECTOR" workflow-run-attempt --input "$snapshot/workflow-runs.json" 2>/dev/null
    )"; then
        evidence_error
    fi
    [[ "$workflow_run_attempt" =~ ^[1-9][0-9]*$ ]] || evidence_error
    api_get C05 \
        "/repos/GGULBAE/desk-setup-switcher/actions/runs/$workflow_run_id/attempts/$workflow_run_attempt/jobs?per_page=100" \
        "$snapshot/workflow-jobs.json" \
        --paginate --jq "{total_count: .total_count, items: (.jobs | map({id: .id, run_id: .run_id, run_attempt: $workflow_run_attempt, name: .name, workflow_name: .workflow_name, head_branch: .head_branch, head_sha: .head_sha, status: .status, conclusion: .conclusion, check_run_url: .check_run_url}))}"
    if ! workflow_job_id="$(
        ruby "$COLLECTOR" workflow-job-id --input "$snapshot/workflow-jobs.json" 2>/dev/null
    )"; then
        evidence_error
    fi
    [[ "$workflow_job_id" =~ ^[1-9][0-9]*$ ]] || evidence_error

    COLLECTED_RULESET_COUNT="$ruleset_index"
    COLLECTED_CI_RUN_ID="$workflow_run_id"
    COLLECTED_CI_RUN_ATTEMPT="$workflow_run_attempt"
    COLLECTED_CI_JOB_ID="$workflow_job_id"
}

copy_projection() {
    local source="$1"
    local destination="$2"
    [[ -f "$source" && ! -L "$source" && ! -e "$destination" && ! -L "$destination" ]] \
        || evidence_error
    cp -- "$source" "$destination" >/dev/null 2>&1 || evidence_error
    chmod 0600 "$destination" >/dev/null 2>&1 || evidence_error
}

write_manifest() {
    local snapshot="$1"
    local ruleset_count="$2"
    local manifest_index=1
    local manifest_detail
    local manifest_files
    manifest_files=(
        actions-permissions.json check-runs.json ci-workflow-content-1.json
        ci-workflow-content-2.json ci-workflow-metadata-1.json
        ci-workflow-metadata-2.json deployment-policies.json effective-master.json
        environment-secrets.json environment-variable-names.json environment.json
        immutable-releases.json label.json master-1.json master-2.json permission.json
        private-vulnerability-reporting.json releases.json repository-secrets.json
        repository-variable-names.json repository.json ruleset-ids.json
        selected-actions.json v-refs.json viewer.json workflow-jobs.json
        workflow-content-1.json workflow-content-2.json workflow-metadata-1.json
        workflow-metadata-2.json workflow-permissions.json workflow-runs.json
    )
    while [[ "$manifest_index" -le "$ruleset_count" ]]; do
        printf -v manifest_detail 'ruleset-detail-%04d.json' "$manifest_index"
        manifest_files+=("$manifest_detail")
        manifest_index=$((manifest_index + 1))
    done
    if ! ruby -rjson -e '
      path, commit, blob, ci_blob, triggers_json, ci_triggers_json, *files = ARGV
      value = {
        "schemaVersion" => "desk-setup-switcher.remote-release-controls-input/v1",
        "phase" => "final-pre-tag",
        "expectedCommit" => commit,
        "expectedWorkflowBlob" => blob,
        "expectedCIWorkflowBlob" => ci_blob,
        "localTriggers" => {
          "projection" => "strict-local-workflow-ast/v1",
          "workflowPath" => ".github/workflows/release.yml",
          "workflowBlob" => blob,
          "triggers" => JSON.parse(triggers_json, create_additions: false)
        },
        "localCITriggers" => {
          "projection" => "strict-local-workflow-ast/v1",
          "workflowPath" => ".github/workflows/ci.yml",
          "workflowBlob" => ci_blob,
          "triggers" => JSON.parse(ci_triggers_json, create_additions: false)
        },
        "files" => files.sort
      }
      raise unless value.fetch("files").uniq == value.fetch("files")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |io|
        io.write(JSON.generate(value))
        io.write("\n")
      end
    ' \
        "$snapshot/manifest.json" "$expected_commit" "$expected_workflow_blob" \
        "$expected_ci_workflow_blob" "$local_triggers" "$local_ci_triggers" \
        "${manifest_files[@]}" >/dev/null 2>&1; then
        evidence_error
    fi
}

# One outer code anchor brackets both complete mutable-control observations.
api_get A01 \
    '/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master' \
    "$snapshot_one/master-1.json" \
    --jq '{ref: .ref, object: {type: .object.type, sha: .object.sha}}'
if ! master_sha_1="$(
    ruby "$COLLECTOR" master-sha --input "$snapshot_one/master-1.json" 2>/dev/null
)"; then
    evidence_error
fi
[[ "$master_sha_1" =~ ^[0-9a-f]{40}$ ]] || evidence_error
api_get A02 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/release.yml?ref=$master_sha_1" \
    "$snapshot_one/workflow-content-1.json" \
    --jq "{commit_sha: \"$master_sha_1\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A03 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml' \
    "$snapshot_one/workflow-metadata-1.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A04 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/ci.yml?ref=$master_sha_1" \
    "$snapshot_one/ci-workflow-content-1.json" \
    --jq "{commit_sha: \"$master_sha_1\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A05 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml' \
    "$snapshot_one/ci-workflow-metadata-1.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'

COLLECTED_RULESET_COUNT=0
COLLECTED_CI_RUN_ID=0
COLLECTED_CI_RUN_ATTEMPT=0
COLLECTED_CI_JOB_ID=0
collect_controls "$snapshot_one"
ruleset_count_one="$COLLECTED_RULESET_COUNT"
ci_run_id_one="$COLLECTED_CI_RUN_ID"
ci_run_attempt_one="$COLLECTED_CI_RUN_ATTEMPT"
ci_job_id_one="$COLLECTED_CI_JOB_ID"
collect_controls "$snapshot_two"
ruleset_count_two="$COLLECTED_RULESET_COUNT"
ci_run_id_two="$COLLECTED_CI_RUN_ID"
ci_run_attempt_two="$COLLECTED_CI_RUN_ATTEMPT"
ci_job_id_two="$COLLECTED_CI_JOB_ID"
[[ "$ci_run_id_two" == "$ci_run_id_one" ]] || evidence_error
[[ "$ci_run_attempt_two" == "$ci_run_attempt_one" ]] || evidence_error
[[ "$ci_job_id_two" == "$ci_job_id_one" ]] || evidence_error

api_get A06 \
    '/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master' \
    "$snapshot_two/master-2.json" \
    --jq '{ref: .ref, object: {type: .object.type, sha: .object.sha}}'
if ! master_sha_2="$(
    ruby "$COLLECTOR" master-sha --input "$snapshot_two/master-2.json" 2>/dev/null
)"; then
    evidence_error
fi
[[ "$master_sha_2" =~ ^[0-9a-f]{40}$ ]] || evidence_error
api_get A07 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/release.yml?ref=$master_sha_2" \
    "$snapshot_two/workflow-content-2.json" \
    --jq "{commit_sha: \"$master_sha_2\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A08 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml' \
    "$snapshot_two/workflow-metadata-2.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A09 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/ci.yml?ref=$master_sha_2" \
    "$snapshot_two/ci-workflow-content-2.json" \
    --jq "{commit_sha: \"$master_sha_2\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A10 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml' \
    "$snapshot_two/ci-workflow-metadata-2.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'

for anchor_name in \
    master-1.json workflow-content-1.json workflow-metadata-1.json \
    ci-workflow-content-1.json ci-workflow-metadata-1.json; do
    copy_projection "$snapshot_one/$anchor_name" "$snapshot_two/$anchor_name"
done
for anchor_name in \
    master-2.json workflow-content-2.json workflow-metadata-2.json \
    ci-workflow-content-2.json ci-workflow-metadata-2.json; do
    copy_projection "$snapshot_two/$anchor_name" "$snapshot_one/$anchor_name"
done

write_manifest "$snapshot_one" "$ruleset_count_one"
write_manifest "$snapshot_two" "$ruleset_count_two"
evidence_one="$temporary_root/evidence-1.json"
evidence_two="$temporary_root/evidence-2.json"
if ! checks_count_one="$(
    ruby "$COLLECTOR" collect --input-dir "$snapshot_one" --output "$evidence_one" 2>/dev/null
)"; then
    evidence_error
fi
if ! checks_count_two="$(
    ruby "$COLLECTOR" collect --input-dir "$snapshot_two" --output "$evidence_two" 2>/dev/null
)"; then
    evidence_error
fi
[[ "$checks_count_one" =~ ^[1-9][0-9]*$ ]] || evidence_error
[[ "$checks_count_two" == "$checks_count_one" ]] || evidence_error
cmp -s "$evidence_one" "$evidence_two" || evidence_error
checks_count="$checks_count_two"
evidence_path="$evidence_two"

# Close local race windows as well as remote ones. A policy, workflow, HEAD, or
# worktree change during collection invalidates the trusted local authority.
local_anchors_match || local_anchor_error

policy_status=0
ruby "$POLICY_VALIDATOR" \
    --policy "$POLICY_PATH" \
    --evidence "$evidence_path" \
    --expected-commit "$expected_commit" \
    --expected-workflow-blob "$expected_workflow_blob" \
    --expected-ci-workflow-blob "$expected_ci_workflow_blob" >/dev/null 2>&1 \
    || policy_status=$?
if [[ "$policy_status" -eq 1 ]]; then
    policy_error
elif [[ "$policy_status" -ne 0 ]]; then
    evidence_error
fi
unset policy_status

# The validator itself is an external process. Recheck immediately after it
# returns so it cannot mutate or replace a trusted local anchor before output.
local_anchors_match || local_anchor_error

printf 'OK remote-controls final-pre-tag repository=%s commit=%s release_workflow_blob=%s ci_workflow_blob=%s ci_run_id=%s ci_run_attempt=%s ci_job_id=%s checks=%s manual_gates=1\n' \
    "$REPOSITORY" \
    "$expected_commit" \
    "$expected_workflow_blob" \
    "$expected_ci_workflow_blob" \
    "$ci_run_id_two" \
    "$ci_run_attempt_two" \
    "$ci_job_id_two" \
    "$checks_count"
