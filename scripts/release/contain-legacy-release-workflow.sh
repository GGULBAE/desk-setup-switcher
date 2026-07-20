#!/usr/bin/env bash

set -euo pipefail
set +x
set +a
umask 077

github_token="${GH_TOKEN:-}"
github_token_alias_marker="${GITHUB_TOKEN+x}"
enterprise_token_alias_marker="${GH_ENTERPRISE_TOKEN+x}"
github_enterprise_token_alias_marker="${GITHUB_ENTERPRISE_TOKEN+x}"
mutation_marker="${DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS+x}"
mutation_enabled="${DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS:-}"
confirmation_marker="${DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION+x}"
typed_confirmation="${DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION:-}"
export -n github_token 2>/dev/null || true
unset GH_TOKEN GITHUB_TOKEN GH_HOST GH_DEBUG DEBUG GH_ENTERPRISE_TOKEN \
    GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS \
    DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
POLICY="$SCRIPT_DIR/legacy_workflow_containment_policy.rb"

REPOSITORY="GGULBAE/desk-setup-switcher"
BRANCH="master"
ORIGIN="https://github.com/GGULBAE/desk-setup-switcher.git"
WORKFLOW_ID="311269012"
WORKFLOW_PATH=".github/workflows/release.yml"
API_VERSION="2026-03-10"
API_TIMEOUT_SECONDS=20

usage() {
    printf '%s\n' \
        'Usage:' \
        '  contain-legacy-release-workflow.sh plan --expected-master SHA --receipt-output /absolute/private/plan.json' \
        '  contain-legacy-release-workflow.sh apply --expected-master SHA --plan-receipt /absolute/private/plan.json --plan-digest SHA256 --receipt-output /absolute/private/result.json' \
        '' \
        'plan is read-only. apply also requires DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1' \
        'and DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION="DISABLE WORKFLOW 311269012 AT SHA".'
}

guard_error() {
    printf 'ERROR: legacy workflow containment guard rejected the request\n' >&2
    exit 1
}

api_error() {
    printf 'ERROR: legacy workflow containment observation unavailable\n' >&2
    exit 70
}

ambiguous_error() {
    printf 'ERROR: legacy workflow containment result is ambiguous; do not retry or enable the workflow\n' >&2
    exit 75
}

mode="${1:-}"
[[ "$mode" == plan || "$mode" == apply ]] || {
    usage >&2
    exit 2
}
shift

expected_master=""
receipt_output=""
plan_receipt=""
plan_digest=""
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --expected-master)
            [[ "$#" -ge 2 && -z "$expected_master" ]] || guard_error
            expected_master="$2"
            shift 2
            ;;
        --receipt-output)
            [[ "$#" -ge 2 && -z "$receipt_output" ]] || guard_error
            receipt_output="$2"
            shift 2
            ;;
        --plan-receipt)
            [[ "$#" -ge 2 && -z "$plan_receipt" ]] || guard_error
            plan_receipt="$2"
            shift 2
            ;;
        --plan-digest)
            [[ "$#" -ge 2 && -z "$plan_digest" ]] || guard_error
            plan_digest="$2"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *) guard_error ;;
    esac
done

[[ "$expected_master" =~ ^[0-9a-f]{40}$ ]] || guard_error
if [[ "$mode" == plan ]]; then
    [[ -n "$receipt_output" && -z "$plan_receipt" && -z "$plan_digest" ]] || guard_error
    [[ -z "$mutation_marker" && -z "$confirmation_marker" ]] || guard_error
else
    [[ -n "$receipt_output" && -n "$plan_receipt" && "$receipt_output" != "$plan_receipt" \
        && "$plan_digest" =~ ^[0-9a-f]{64}$ ]] || guard_error
    [[ "$mutation_marker" == x && "$confirmation_marker" == x \
        && "$mutation_enabled" == 1 \
        && "$typed_confirmation" == "DISABLE WORKFLOW $WORKFLOW_ID AT $expected_master" ]] \
        || guard_error
fi
[[ -n "$github_token" && "$github_token" != *$'\n'* && "$github_token" != *$'\r'* ]] \
    || guard_error
[[ -z "$github_token_alias_marker" && -z "$enterprise_token_alias_marker" \
    && -z "$github_enterprise_token_alias_marker" ]] || guard_error
unset github_token_alias_marker enterprise_token_alias_marker \
    github_enterprise_token_alias_marker

local_head=""
helper_blob=""
validator_blob=""
library_blob=""
common_library_blob=""
read_local_blob() {
    local relative_path="$1"
    local tree_line tree_mode tree_kind tree_blob tree_name working_blob
    tree_line="$(git -C "$ROOT_DIR" ls-tree HEAD -- "$relative_path" 2>/dev/null)" \
        || guard_error
    IFS=$' \t' read -r tree_mode tree_kind tree_blob tree_name <<<"$tree_line"
    [[ "$tree_mode" == 100755 && "$tree_kind" == blob \
        && "$tree_blob" =~ ^[0-9a-f]{40}$ && "$tree_name" == "$relative_path" \
        && -f "$ROOT_DIR/$relative_path" && ! -L "$ROOT_DIR/$relative_path" \
        && -x "$ROOT_DIR/$relative_path" ]] || guard_error
    working_blob="$(git -C "$ROOT_DIR" hash-object -- "$relative_path" 2>/dev/null)" \
        || guard_error
    [[ "$working_blob" == "$tree_blob" ]] || guard_error
    printf '%s\n' "$tree_blob"
}

validate_local_context() {
    local checkout_status origin shallow
    local_head="$(git -C "$ROOT_DIR" rev-parse --verify 'HEAD^{commit}' 2>/dev/null)" \
        || guard_error
    [[ "$local_head" =~ ^[0-9a-f]{40}$ ]] || guard_error
    checkout_status="$(git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all \
        2>/dev/null)" || guard_error
    [[ -z "$checkout_status" ]] || guard_error
    shallow="$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository 2>/dev/null)" \
        || guard_error
    [[ "$shallow" == false ]] || guard_error
    origin="$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null)" || guard_error
    [[ "$origin" == "$ORIGIN" ]] || guard_error
    helper_blob="$(read_local_blob 'scripts/release/contain-legacy-release-workflow.sh')"
    validator_blob="$(read_local_blob 'scripts/release/legacy_workflow_containment_policy.rb')"
    library_blob="$(read_local_blob 'scripts/release/lib.sh')"
    common_library_blob="$(read_local_blob 'scripts/lib/common.sh')"
}

validate_local_context
source "$SCRIPT_DIR/lib.sh"
command -v gh >/dev/null 2>&1 || api_error
command -v ruby >/dev/null 2>&1 || guard_error
ruby "$POLICY" validate-output "$receipt_output" "$ROOT_DIR" >/dev/null 2>&1 \
    || guard_error

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-legacy-workflow-containment.XXXXXX" \
    2>/dev/null)" || guard_error
chmod 0700 "$temporary_root" >/dev/null 2>&1 || {
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
    guard_error
}
RUNNER_TEMP="$temporary_root/tracked-runner"
gh_config_directory="$temporary_root/gh-config"
mkdir -m 0700 "$RUNNER_TEMP" "$gh_config_directory" >/dev/null 2>&1 || guard_error
cleanup() {
    trap '' HUP INT QUIT TERM
    release_stop_active_child || true
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
}
trap cleanup EXIT
release_install_exit_signal_traps

run_gh() {
    GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$github_token" \
        "$API_TIMEOUT_SECONDS" "$@"
}

api_get() {
    local endpoint="$1"
    local output="$2"
    local projection="$3"
    shift 3
    run_gh gh api \
        --hostname github.com \
        --method GET \
        -H 'Accept: application/vnd.github+json' \
        -H "X-GitHub-Api-Version: $API_VERSION" \
        -H 'Cache-Control: no-cache' \
        "$@" \
        --jq "$projection" \
        "$endpoint" >"$output" 2>/dev/null
}

collect_observation() {
    local snapshot="$1"
    mkdir -m 0700 "$snapshot" >/dev/null 2>&1 || return 1
    api_get \
        "/repos/$REPOSITORY/git/ref/heads/$BRANCH" \
        "$snapshot/anchor-start-ref.json" \
        '{ref: .ref, object: {sha: .object.sha, type: .object.type}}' || return 1
    api_get \
        "/repos/$REPOSITORY/actions/workflows/$WORKFLOW_ID" \
        "$snapshot/anchor-start-workflow.json" \
        '{id: .id, name: .name, path: .path, state: .state}' || return 1
    api_get \
        "/repos/$REPOSITORY/contents/$WORKFLOW_PATH?ref=$expected_master" \
        "$snapshot/anchor-start-content.json" \
        '{sha: .sha, path: .path, type: .type}' || return 1
    api_get \
        '/user' \
        "$snapshot/viewer.json" \
        '{id: .id, login: .login, type: .type}' || return 1
    api_get \
        "/repos/$REPOSITORY" \
        "$snapshot/repository.json" \
        '{id: .id, node_id: .node_id, full_name: .full_name, private: .private, visibility: .visibility, default_branch: .default_branch, archived: .archived, disabled: .disabled, owner: {id: .owner.id, login: .owner.login, type: .owner.type}, permissions: {admin: .permissions.admin, push: .permissions.push}}' || return 1
    api_get \
        "/repos/$REPOSITORY/git/matching-refs/tags/v" \
        "$snapshot/v-tag-refs.json" \
        '[.[][] | {ref: .ref, object: {sha: .object.sha, type: .object.type}}]' \
        --paginate --slurp || return 1
    api_get \
        "/repos/$REPOSITORY/releases?per_page=100" \
        "$snapshot/releases.json" \
        '[.[][] | {id: .id, tag_name: .tag_name, draft: .draft, prerelease: .prerelease, target_commitish: .target_commitish}]' \
        --paginate --slurp || return 1
    api_get \
        "/repos/$REPOSITORY/actions/workflows/$WORKFLOW_ID/runs?per_page=100" \
        "$snapshot/workflow-runs.json" \
        '{reportedTotalCount: (.[0].total_count), pageTotalCounts: [.[].total_count], runs: [.[].workflow_runs[] | {id: .id, run_number: .run_number, run_attempt: .run_attempt, status: .status, conclusion: .conclusion, head_sha: .head_sha, event: .event, created_at: .created_at, updated_at: .updated_at}]}' \
        --paginate --slurp || return 1
    api_get \
        "/repos/$REPOSITORY/git/ref/heads/$BRANCH" \
        "$snapshot/anchor-end-ref.json" \
        '{ref: .ref, object: {sha: .object.sha, type: .object.type}}' || return 1
    api_get \
        "/repos/$REPOSITORY/actions/workflows/$WORKFLOW_ID" \
        "$snapshot/anchor-end-workflow.json" \
        '{id: .id, name: .name, path: .path, state: .state}' || return 1
    api_get \
        "/repos/$REPOSITORY/contents/$WORKFLOW_PATH?ref=$expected_master" \
        "$snapshot/anchor-end-content.json" \
        '{sha: .sha, path: .path, type: .type}' || return 1
}

normalize_observation() {
    local snapshot="$1"
    local output="$2"
    ruby "$POLICY" normalize-observation "$snapshot" "$expected_master" "$output" \
        >/dev/null 2>&1
}

collect_pair() {
    local prefix="$1"
    collect_observation "$temporary_root/$prefix-1" || return 1
    normalize_observation "$temporary_root/$prefix-1" "$temporary_root/$prefix-1.json" \
        || return 1
    collect_observation "$temporary_root/$prefix-2" || return 1
    normalize_observation "$temporary_root/$prefix-2" "$temporary_root/$prefix-2.json" \
        || return 1
}

if [[ "$mode" == plan ]]; then
    collect_pair plan || api_error
    generated_digest="$(ruby "$POLICY" create-plan \
        "$temporary_root/plan-1.json" \
        "$temporary_root/plan-2.json" \
        "$expected_master" \
        "$local_head" \
        "$helper_blob" \
        "$validator_blob" \
        "$library_blob" \
        "$common_library_blob" \
        "$ROOT_DIR" \
        "$receipt_output" 2>/dev/null)" || guard_error
    [[ "$generated_digest" =~ ^[0-9a-f]{64}$ ]] || guard_error
    printf 'Legacy workflow containment plan digest: %s\n' "$generated_digest"
    exit 0
fi

planned_state="$(ruby "$POLICY" validate-plan \
    "$plan_receipt" \
    "$plan_digest" \
    "$expected_master" \
    "$local_head" \
    "$helper_blob" \
    "$validator_blob" \
    "$library_blob" \
    "$common_library_blob" \
    "$ROOT_DIR" 2>/dev/null)" || guard_error
[[ "$planned_state" == active || "$planned_state" == disabled_manually ]] || guard_error
unset mutation_marker mutation_enabled confirmation_marker typed_confirmation

collect_pair pre-apply || api_error
current_state="$(ruby "$POLICY" validate-pre \
    "$plan_receipt" \
    "$temporary_root/pre-apply-1.json" \
    "$temporary_root/pre-apply-2.json" 2>/dev/null)" || guard_error
[[ "$current_state" == active || "$current_state" == disabled_manually ]] || guard_error

mutation_attempted=false
if [[ "$current_state" == active ]]; then
    # From the first byte of the sole mutation attempt onward, cancellation and
    # every uncertain response/postcondition are exit 75. This helper never
    # sends an enable request and never retries the disable request. --include
    # lets the private validator require this endpoint's documented 204 with
    # an empty response body.
    trap 'release_terminate_with_child 75' HUP INT QUIT TERM
    mutation_attempted=true
    mutation_response="$temporary_root/mutation-response"
    if ! run_gh gh api \
        --hostname github.com \
        --method PUT \
        -H 'Accept: application/vnd.github+json' \
        -H "X-GitHub-Api-Version: $API_VERSION" \
        --include \
        "/repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable" \
        >"$mutation_response" 2>/dev/null; then
        ambiguous_error
    fi
    ruby "$POLICY" validate-put-response "$mutation_response" >/dev/null 2>&1 \
        || ambiguous_error
fi

collect_pair post-apply || ambiguous_error
ruby "$POLICY" validate-post \
    "$temporary_root/pre-apply-1.json" \
    "$temporary_root/pre-apply-2.json" \
    "$temporary_root/post-apply-1.json" \
    "$temporary_root/post-apply-2.json" >/dev/null 2>&1 || ambiguous_error

result_digest="$(ruby "$POLICY" create-success \
    "$plan_receipt" \
    "$plan_digest" \
    "$expected_master" \
    "$local_head" \
    "$helper_blob" \
    "$validator_blob" \
    "$library_blob" \
    "$common_library_blob" \
    "$ROOT_DIR" \
    "$temporary_root/pre-apply-1.json" \
    "$temporary_root/pre-apply-2.json" \
    "$temporary_root/post-apply-1.json" \
    "$temporary_root/post-apply-2.json" \
    "$mutation_attempted" \
    "$receipt_output" 2>/dev/null)" || ambiguous_error
[[ "$result_digest" =~ ^[0-9a-f]{64}$ ]] || ambiguous_error
printf 'Legacy workflow containment result digest: %s\n' "$result_digest"
