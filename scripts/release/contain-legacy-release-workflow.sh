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
capture_secret_marker="${DESK_SETUP_CAPTURE_SECRETS+x}"
rubyopt_marker="${RUBYOPT+x}"
rubylib_marker="${RUBYLIB+x}"
dyld_insert_marker="${DYLD_INSERT_LIBRARIES+x}"
dyld_library_marker="${DYLD_LIBRARY_PATH+x}"
dyld_framework_marker="${DYLD_FRAMEWORK_PATH+x}"
export -n github_token 2>/dev/null || true
unset GH_TOKEN GITHUB_TOKEN GH_HOST GH_DEBUG DEBUG GH_ENTERPRISE_TOKEN \
    GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS \
    DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION DESK_SETUP_CAPTURE_SECRETS \
    RUBYOPT RUBYLIB DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
POLICY="$SCRIPT_DIR/legacy_workflow_containment_policy.rb"

ORIGIN="https://github.com/GGULBAE/desk-setup-switcher.git"
WORKFLOW_ID="311269012"
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
[[ -n "$github_token" && "$github_token" != *$'\n'* && "$github_token" != *$'\r'* \
    && "$github_token" != *$'\t'* ]] \
    || guard_error
[[ -z "$github_token_alias_marker" && -z "$enterprise_token_alias_marker" \
    && -z "$github_enterprise_token_alias_marker" && -z "$capture_secret_marker" \
    && -z "$rubyopt_marker" && -z "$rubylib_marker" \
    && -z "$dyld_insert_marker" && -z "$dyld_library_marker" \
    && -z "$dyld_framework_marker" ]] \
    || guard_error
unset github_token_alias_marker enterprise_token_alias_marker \
    github_enterprise_token_alias_marker capture_secret_marker \
    rubyopt_marker rubylib_marker dyld_insert_marker dyld_library_marker \
    dyld_framework_marker

command -v ruby >/dev/null 2>&1 || guard_error

# Read a repository executable once through a no-follow descriptor, bind those
# bytes to the exact Git blob id, and only then emit or evaluate the in-memory
# copy. The loader source is already resident in this validated helper, so a
# competing working-tree rewrite cannot replace policy/library code between
# the clean-tree check and a secret-bearing invocation.
validated_ruby_loader='
  path, expected_blob, operation, *remaining = ARGV
  raise unless path.start_with?(File::SEPARATOR) &&
    expected_blob.match?(/\A[0-9a-f]{40}\z/) && File.const_defined?(:NOFOLLOW)
  identity = lambda do |stat|
    [stat.dev, stat.ino, stat.mode, stat.uid, stat.nlink, stat.size,
     stat.mtime.to_r, stat.ctime.to_r]
  end
  validate = lambda do |stat|
    raise unless stat.file? && !stat.symlink? && stat.uid == Process.euid &&
      stat.nlink == 1 && (stat.mode & 0o022).zero? && (stat.mode & 0o100) == 0o100 &&
      stat.size.between?(1, 1_048_576)
  end
  before_path = File.lstat(path)
  validate.call(before_path)
  bytes = nil
  opened_identity = nil
  File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
    file.binmode
    before = file.stat
    validate.call(before)
    raise unless [before.dev, before.ino] == [before_path.dev, before_path.ino]
    before_identity = identity.call(before)
    bytes = file.read(1_048_577)
    after = file.stat
    opened_identity = identity.call(after)
    raise unless opened_identity == before_identity && bytes.bytesize == before.size
  end
  after_path = File.lstat(path)
  validate.call(after_path)
  raise unless identity.call(after_path) == opened_identity && !bytes.include?("\0")
  actual_blob = Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes)
  raise unless actual_blob == expected_blob
  case operation
  when "identify"
    STDOUT.write(actual_blob + "\n")
  when "emit"
    STDOUT.binmode
    STDOUT.write(bytes)
  when "eval"
    ARGV.replace(remaining)
    eval(bytes, TOPLEVEL_BINDING, path, 1)
  else
    raise
  end
'
readonly validated_ruby_loader

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
    working_blob="$(ruby -rdigest/sha1 -e "$validated_ruby_loader" \
        "$ROOT_DIR/$relative_path" "$tree_blob" identify 2>/dev/null)" \
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
validated_common_source="$(ruby -rdigest/sha1 -e "$validated_ruby_loader" \
    "$ROOT_DIR/scripts/lib/common.sh" "$common_library_blob" emit 2>/dev/null)" \
    || guard_error
common_source_status=0
eval "$validated_common_source" || common_source_status=$?
validated_common_source=""
[[ "$common_source_status" -eq 0 ]] || guard_error
unset common_source_status

intercepted_common_path="$SCRIPT_DIR/../lib/common.sh"
source() {
    [[ "$#" -eq 1 && "$1" == "$intercepted_common_path" ]] || return 1
    return 0
}
validated_release_source="$(ruby -rdigest/sha1 -e "$validated_ruby_loader" \
    "$ROOT_DIR/scripts/release/lib.sh" "$library_blob" emit 2>/dev/null)" \
    || guard_error
release_source_status=0
eval "$validated_release_source" || release_source_status=$?
validated_release_source=""
unset -f source
unset intercepted_common_path
[[ "$release_source_status" -eq 0 ]] || guard_error
unset release_source_status

run_policy() {
    ruby -rdigest/sha1 -e "$validated_ruby_loader" \
        "$POLICY" "$validator_blob" eval "$@"
}

release_tracked_signal_exit_status_override=""
gh_command="$(command -v gh 2>/dev/null)" || api_error
[[ "$gh_command" == /* && "$gh_command" != *$'\n'* && "$gh_command" != *$'\r'* ]] \
    || api_error
gh_executable="$(run_policy validate-remote-executable "$gh_command" 2>/dev/null)" \
    || api_error
[[ "$gh_executable" == /* ]] || api_error
unset gh_command
gh_config_directory="$(run_policy validate-remote-config-directory /var/empty 2>/dev/null)" \
    || api_error
[[ "$gh_config_directory" == /private/var/empty ]] || api_error
run_policy validate-output "$receipt_output" "$ROOT_DIR" >/dev/null 2>&1 \
    || guard_error

temporary_parent="$(run_policy validate-temporary-parent "${TMPDIR:-/tmp}" \
    2>/dev/null)" || guard_error
temporary_root="$(mktemp -d "$temporary_parent/desk-setup-legacy-workflow-containment.XXXXXX" \
    2>/dev/null)" || guard_error
chmod 0700 "$temporary_root" >/dev/null 2>&1 || {
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
    guard_error
}
temporary_root="$(cd "$temporary_root" && pwd -P)" || guard_error
run_policy validate-temporary-root "$temporary_root" "$temporary_parent" \
    >/dev/null 2>&1 || {
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
    guard_error
}
RUNNER_TEMP="$temporary_root/tracked-runner"
mkdir -m 0700 "$RUNNER_TEMP" >/dev/null 2>&1 || guard_error
cleanup() {
    trap '' HUP INT QUIT TERM
    release_stop_active_child || true
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
}
trap cleanup EXIT
release_install_exit_signal_traps

capture_sha256=""
capture_remote_operation() {
    local operation="$1"
    local output="$2"
    local attestation capture_key capture_authorization
    local authorization_plan_receipt="-" authorization_plan_digest="-"
    local secret_bundle
    local capture_status=0
    capture_sha256=""
    attestation="$output.attestation"
    capture_key="$(ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))' \
        2>/dev/null)" || return 1
    [[ "$capture_key" =~ ^[0-9a-f]{64}$ ]] || return 1
    capture_authorization="READ ONLY"
    if [[ "$operation" == disable-workflow ]]; then
        authorization_plan_receipt="$plan_receipt"
        authorization_plan_digest="$plan_digest"
        capture_authorization="DISABLE WORKFLOW $WORKFLOW_ID AT $expected_master USING PLAN $plan_digest"
    fi
    secret_bundle="$github_token"$'\t'"$capture_key"$'\t'"$capture_authorization"

    if release_run_tracked_secret_stdin_timeout \
        "$secret_bundle" "$API_TIMEOUT_SECONDS" \
        ruby -rdigest/sha1 -e "$validated_ruby_loader" \
        "$POLICY" "$validator_blob" eval capture-remote-operation \
        "$operation" "$output" "$attestation" "$expected_master" \
        "$temporary_root" "$gh_config_directory" "$gh_executable" \
        "$authorization_plan_receipt" "$authorization_plan_digest" \
        >/dev/null 2>&1; then
        capture_status=0
    else
        capture_status=$?
    fi
    secret_bundle=""
    capture_authorization=""
    if [[ "$capture_status" -eq 0 ]]; then
        capture_sha256="$(printf '%s\n' "$capture_key" | \
            run_policy verify-remote-capture \
                "$operation" "$output" "$attestation" 2>/dev/null)" \
            || capture_status=$?
        [[ "$capture_sha256" =~ ^[0-9a-f]{64}$ ]] || capture_status=1
    fi
    capture_key=""
    return "$capture_status"
}

# GitHub CLI 2.95 rejects --slurp together with --jq/--template. Keep the
# projection at the CLI boundary so unneeded response fields never reach disk,
# but emit one JSON-encoded value per line and let the strict Ruby policy join
# the complete paginated stream into one closed-schema document.
api_get_paginated_items() {
    local operation="$1"
    local output="$2"
    local lines="$output.lines"
    local input_sha256
    capture_remote_operation "$operation" "$lines" || return 1
    input_sha256="$capture_sha256"
    capture_sha256="$(run_policy normalize-json-line-item-pages \
        "$lines" "$output" "$input_sha256" 2>/dev/null)" || return 1
    [[ "$capture_sha256" =~ ^[0-9a-f]{64}$ ]]
}

api_get_paginated_run_pages() {
    local output="$1"
    local lines="$output.lines"
    local input_sha256
    capture_remote_operation workflow-runs "$lines" || return 1
    input_sha256="$capture_sha256"
    capture_sha256="$(run_policy normalize-workflow-run-pages \
        "$lines" "$output" "$input_sha256" 2>/dev/null)" || return 1
    [[ "$capture_sha256" =~ ^[0-9a-f]{64}$ ]]
}

collect_observation() {
    local snapshot="$1"
    local output="$2"
    local anchor_start_ref_sha256 anchor_start_workflow_sha256
    local anchor_start_content_sha256 viewer_sha256 repository_sha256
    local tags_sha256 releases_sha256 runs_sha256 anchor_end_ref_sha256
    local anchor_end_workflow_sha256 anchor_end_content_sha256
    mkdir -m 0700 "$snapshot" >/dev/null 2>&1 || return 1
    capture_remote_operation anchor-ref \
        "$snapshot/anchor-start-ref.json" || return 1
    anchor_start_ref_sha256="$capture_sha256"
    capture_remote_operation workflow \
        "$snapshot/anchor-start-workflow.json" || return 1
    anchor_start_workflow_sha256="$capture_sha256"
    capture_remote_operation workflow-content \
        "$snapshot/anchor-start-content.json" || return 1
    anchor_start_content_sha256="$capture_sha256"
    capture_remote_operation viewer "$snapshot/viewer.json" || return 1
    viewer_sha256="$capture_sha256"
    capture_remote_operation repository "$snapshot/repository.json" || return 1
    repository_sha256="$capture_sha256"
    api_get_paginated_items v-tag-refs "$snapshot/v-tag-refs.json" || return 1
    tags_sha256="$capture_sha256"
    api_get_paginated_items releases "$snapshot/releases.json" || return 1
    releases_sha256="$capture_sha256"
    api_get_paginated_run_pages "$snapshot/workflow-runs.json" || return 1
    runs_sha256="$capture_sha256"
    capture_remote_operation anchor-ref \
        "$snapshot/anchor-end-ref.json" || return 1
    anchor_end_ref_sha256="$capture_sha256"
    capture_remote_operation workflow \
        "$snapshot/anchor-end-workflow.json" || return 1
    anchor_end_workflow_sha256="$capture_sha256"
    capture_remote_operation workflow-content \
        "$snapshot/anchor-end-content.json" || return 1
    anchor_end_content_sha256="$capture_sha256"

    normalized_observation_sha256="$(run_policy normalize-observation \
        "$snapshot" "$expected_master" "$output" \
        "$anchor_start_ref_sha256" \
        "$anchor_start_workflow_sha256" \
        "$anchor_start_content_sha256" \
        "$viewer_sha256" \
        "$repository_sha256" \
        "$tags_sha256" \
        "$releases_sha256" \
        "$runs_sha256" \
        "$anchor_end_ref_sha256" \
        "$anchor_end_workflow_sha256" \
        "$anchor_end_content_sha256" 2>/dev/null)" || return 1
    [[ "$normalized_observation_sha256" =~ ^[0-9a-f]{64}$ ]]
}

normalized_observation_sha256=""
pair_first_sha256=""
pair_second_sha256=""
collect_pair() {
    local prefix="$1"
    collect_observation \
        "$temporary_root/$prefix-1" "$temporary_root/$prefix-1.json" || return 1
    pair_first_sha256="$normalized_observation_sha256"
    collect_observation \
        "$temporary_root/$prefix-2" "$temporary_root/$prefix-2.json" || return 1
    pair_second_sha256="$normalized_observation_sha256"
}

if [[ "$mode" == plan ]]; then
    collect_pair plan || api_error
    generated_digest="$(run_policy create-plan \
        "$temporary_root/plan-1.json" \
        "$pair_first_sha256" \
        "$temporary_root/plan-2.json" \
        "$pair_second_sha256" \
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

planned_state="$(run_policy validate-plan \
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
pre_first_sha256="$pair_first_sha256"
pre_second_sha256="$pair_second_sha256"
current_state="$(run_policy validate-pre \
    "$plan_receipt" \
    "$plan_digest" \
    "$expected_master" \
    "$temporary_root/pre-apply-1.json" \
    "$pre_first_sha256" \
    "$temporary_root/pre-apply-2.json" \
    "$pre_second_sha256" 2>/dev/null)" || guard_error
[[ "$current_state" == active || "$current_state" == disabled_manually ]] || guard_error

mutation_attempted=false
if [[ "$current_state" == active ]]; then
    # From the first byte of the sole mutation attempt onward, cancellation and
    # every uncertain response/postcondition are exit 75. This helper never
    # sends an enable request and never retries the disable request. The closed
    # capture policy owns the fixed bodyless PUT and includes its response
    # headers so the validator can require the documented 204/empty response.
    trap 'release_terminate_with_child 75' HUP INT QUIT TERM
    mutation_attempted=true
    mutation_response="$temporary_root/mutation-response"
    release_tracked_signal_exit_status_override=75
    if ! capture_remote_operation disable-workflow "$mutation_response"; then
        ambiguous_error
    fi
    mutation_response_sha256="$capture_sha256"
    run_policy validate-put-response \
        "$mutation_response" "$mutation_response_sha256" >/dev/null 2>&1 \
        || ambiguous_error
fi

collect_pair post-apply || ambiguous_error
post_first_sha256="$pair_first_sha256"
post_second_sha256="$pair_second_sha256"
run_policy validate-post \
    "$temporary_root/pre-apply-1.json" \
    "$pre_first_sha256" \
    "$temporary_root/pre-apply-2.json" \
    "$pre_second_sha256" \
    "$temporary_root/post-apply-1.json" \
    "$post_first_sha256" \
    "$temporary_root/post-apply-2.json" \
    "$post_second_sha256" >/dev/null 2>&1 || ambiguous_error

result_digest="$(run_policy create-success \
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
    "$pre_first_sha256" \
    "$temporary_root/pre-apply-2.json" \
    "$pre_second_sha256" \
    "$temporary_root/post-apply-1.json" \
    "$post_first_sha256" \
    "$temporary_root/post-apply-2.json" \
    "$post_second_sha256" \
    "$mutation_attempted" \
    "$receipt_output" 2>/dev/null)" || ambiguous_error
[[ "$result_digest" =~ ^[0-9a-f]{64}$ ]] || ambiguous_error
printf 'Legacy workflow containment result digest: %s\n' "$result_digest"
