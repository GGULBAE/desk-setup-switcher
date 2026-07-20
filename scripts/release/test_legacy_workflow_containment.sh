#!/usr/bin/env bash

set -euo pipefail
set +x
source "$(dirname "$0")/lib.sh"

cd "$ROOT_DIR"
assertions=0
pass() {
    assertions=$((assertions + 1))
}
fail() {
    release_die "$1"
}
assert_status() {
    local expected="$1"
    local actual="$2"
    [[ "$actual" == "$expected" ]] || fail "Unexpected containment status: expected $expected, got $actual."
    pass
}
assert_absent() {
    [[ ! -e "$1" && ! -L "$1" ]] || fail "Containment output unexpectedly exists."
    pass
}
assert_file() {
    [[ -f "$1" && ! -L "$1" ]] || fail "Expected containment receipt is absent."
    pass
}
assert_no_leak() {
    local path
    for path in "$@"; do
        if grep -F -q -- "$runtime_token" "$path" \
            || grep -F -q -- "$runtime_alias_token" "$path" \
            || grep -F -q -- "$temporary_root" "$path"; then
            fail "Containment output leaked a credential or private path."
        fi
    done
    pass
}
put_count() {
    grep -c '^PUT ' "$1" 2>/dev/null || true
}

temporary_parent="${TMPDIR:-/tmp}"
temporary_parent="${temporary_parent%/}"
temporary_root="$(mktemp -d "$temporary_parent/desk-setup-containment-tests.XXXXXX")"
chmod 0700 "$temporary_root"
cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT

mock_bin="$temporary_root/mock-bin"
mkdir -m 0700 "$mock_bin"
runtime_token="$(ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_alias_token="$(ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_token_sha256="$(printf '%s' "$runtime_token" | shasum -a 256 | awk '{print $1}')"
expected_master='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
local_head='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
helper_blob='bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'
validator_blob='cccccccccccccccccccccccccccccccccccccccc'
library_blob='dddddddddddddddddddddddddddddddddddddddd'
common_library_blob='abababababababababababababababababababab'

cat >"$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -C && "$#" -ge 3 ]] || exit 91
shift 2
printf '%q ' "$@" >>"$MOCK_GIT_LOG"
printf '\n' >>"$MOCK_GIT_LOG"
case "${1:-}" in
    rev-parse)
        case "${2:-}" in
            --verify)
                [[ "${3:-}" == 'HEAD^{commit}' && "$#" == 3 ]] || exit 92
                printf '%s\n' aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
                ;;
            --is-shallow-repository)
                [[ "$#" == 2 ]] || exit 92
                if [[ "${MOCK_LOCAL_SCENARIO:-}" == shallow ]]; then
                    printf 'true\n'
                else
                    printf 'false\n'
                fi
                ;;
            *) exit 92 ;;
        esac
        ;;
    status)
        [[ "$#" == 3 && "$2" == --porcelain=v1 && "$3" == --untracked-files=all ]] || exit 93
        [[ "${MOCK_LOCAL_SCENARIO:-}" != dirty ]] || printf ' M private-path\n'
        ;;
    remote)
        [[ "$#" == 3 && "$2" == get-url && "$3" == origin ]] || exit 94
        if [[ "${MOCK_LOCAL_SCENARIO:-}" == wrong-origin ]]; then
            printf 'https://example.invalid/private-path.git\n'
        else
            printf 'https://github.com/GGULBAE/desk-setup-switcher.git\n'
        fi
        ;;
    ls-tree)
        [[ "$#" == 4 && "$2" == HEAD && "$3" == -- ]] || exit 95
        case "$4" in
            scripts/release/contain-legacy-release-workflow.sh)
                blob=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb ;;
            scripts/release/legacy_workflow_containment_policy.rb)
                blob=cccccccccccccccccccccccccccccccccccccccc ;;
            scripts/release/lib.sh)
                blob=dddddddddddddddddddddddddddddddddddddddd ;;
            scripts/lib/common.sh)
                blob=abababababababababababababababababababab ;;
            *) exit 95 ;;
        esac
        printf '100755 blob %s\t%s\n' "$blob" "$4"
        ;;
    hash-object)
        [[ "$#" == 3 && "$2" == -- ]] || exit 96
        case "$3" in
            scripts/release/contain-legacy-release-workflow.sh)
                if [[ "${MOCK_LOCAL_SCENARIO:-}" == tool-drift ]]; then
                    printf '9999999999999999999999999999999999999999\n'
                else
                    printf 'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\n'
                fi
                ;;
            scripts/release/legacy_workflow_containment_policy.rb)
                printf 'cccccccccccccccccccccccccccccccccccccccc\n' ;;
            scripts/release/lib.sh)
                if [[ "${MOCK_LOCAL_SCENARIO:-}" == library-drift ]]; then
                    printf '9999999999999999999999999999999999999999\n'
                else
                    printf 'dddddddddddddddddddddddddddddddddddddddd\n'
                fi
                ;;
            scripts/lib/common.sh)
                if [[ "${MOCK_LOCAL_SCENARIO:-}" == common-library-drift ]]; then
                    printf '9999999999999999999999999999999999999999\n'
                else
                    printf 'abababababababababababababababababababab\n'
                fi
                ;;
            *) exit 96 ;;
        esac
        ;;
    *) exit 97 ;;
esac
MOCK_GIT

cat >"$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
token="${GH_TOKEN:-}"
unset GH_TOKEN
actual_digest="$(printf '%s' "$token" | shasum -a 256 | awk '{print $1}')"
[[ "$actual_digest" == "$MOCK_TOKEN_SHA256" ]] || exit 81
[[ -z "${GITHUB_TOKEN+x}" && -z "${GH_DEBUG+x}" && -z "${DEBUG+x}" \
    && -z "${GH_ENTERPRISE_TOKEN+x}" && -z "${GITHUB_ENTERPRISE_TOKEN+x}" \
    && -z "${DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS+x}" \
    && -z "${DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION+x}" ]] || exit 82
[[ "${1:-}" == api ]] || exit 83
method=""
paginate=false
slurp=false
for ((index = 1; index <= $#; index++)); do
    argument="${!index}"
    case "$argument" in
        --method)
            next=$((index + 1))
            method="${!next}"
            ;;
        --paginate) paginate=true ;;
        --slurp) slurp=true ;;
    esac
done
endpoint="${!#}"
[[ "$method" == GET || "$method" == PUT ]] || exit 84
printf '%s %s paginate=%s slurp=%s\n' "$method" "$endpoint" "$paginate" "$slurp" \
    >>"$MOCK_COMMAND_LOG"

state_dir="$MOCK_STATE_DIR"
scenario="${MOCK_SCENARIO:-happy}"
counter() {
    local name="$1"
    local path="$state_dir/$name"
    local value=0
    [[ ! -f "$path" ]] || value="$(tr -d '\n' <"$path")"
    value=$((value + 1))
    printf '%s\n' "$value" >"$path"
    printf '%s\n' "$value"
}

if [[ "$method" == PUT ]]; then
    [[ "$endpoint" == '/repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable' ]] \
        || exit 85
    [[ "$scenario" != put-failure ]] || exit 86
    : >"$state_dir/disabled"
    if [[ -n "${MOCK_RACE_OUTPUT:-}" ]]; then
        printf 'attacker-owned-marker\n' >"$MOCK_RACE_OUTPUT"
        chmod 0600 "$MOCK_RACE_OUTPUT"
    fi
    case "$scenario" in
        put-bad-status) printf 'HTTP/2.0 200 OK\r\ncontent-length: 0\r\n\r\n' ;;
        put-body) printf 'HTTP/2.0 204 No Content\r\ncontent-length: 4\r\n\r\nBODY' ;;
        *) printf 'HTTP/2.0 204 No Content\r\ncontent-length: 0\r\n\r\n' ;;
    esac
    exit 0
fi

if [[ "$scenario" == api-failure && "$endpoint" == *'/releases?'* ]]; then
    exit 87
fi
if [[ "$scenario" == post-api-failure && -f "$state_dir/disabled" \
    && "$endpoint" == *'/releases?'* ]]; then
    exit 87
fi

case "$endpoint" in
    /repos/GGULBAE/desk-setup-switcher/git/ref/heads/master)
        ref_call="$(counter ref-calls)"
        sha=eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee
        if [[ "$scenario" == anchor-drift && "$ref_call" == 4 ]]; then
            sha=ffffffffffffffffffffffffffffffffffffffff
        fi
        printf '{"ref":"refs/heads/master","object":{"sha":"%s","type":"commit"}}\n' "$sha"
        ;;
    /repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012)
        workflow_call="$(counter workflow-calls)"
        state=active
        [[ ! -f "$state_dir/disabled" && "$scenario" != already-disabled ]] \
            || state=disabled_manually
        if [[ "$scenario" == workflow-anchor-drift && "$workflow_call" == 4 ]]; then
            state=disabled_manually
        fi
        name=Release
        [[ "$scenario" != workflow-identity-drift ]] || name=Unexpected
        printf '{"id":311269012,"name":"%s","path":".github/workflows/release.yml","state":"%s"}\n' \
            "$name" "$state"
        ;;
    /repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/release.yml\?ref=*)
        content_call="$(counter content-calls)"
        blob=0648b71f683fa0bdcc430d02a7e16d32e0ee0c42
        if [[ "$scenario" == blob-anchor-drift && "$content_call" == 4 ]]; then
            blob=1111111111111111111111111111111111111111
        elif [[ "$scenario" == wrong-blob ]]; then
            blob=1111111111111111111111111111111111111111
        fi
        printf '{"sha":"%s","path":".github/workflows/release.yml","type":"file"}\n' "$blob"
        ;;
    /user)
        if [[ "$scenario" == bad-viewer ]]; then
            printf '{"id":1002,"login":"synthetic-admin","type":"Bot"}\n'
        else
            printf '{"id":1002,"login":"synthetic-admin","type":"User"}\n'
        fi
        ;;
    /repos/GGULBAE/desk-setup-switcher)
        private=false
        visibility=public
        admin=true
        [[ "$scenario" != private-repository ]] || { private=true; visibility=private; }
        [[ "$scenario" != insufficient-permission ]] || admin=false
        printf '{"id":7654321,"node_id":"R_repoNode123","full_name":"GGULBAE/desk-setup-switcher","private":%s,"visibility":"%s","default_branch":"master","archived":false,"disabled":false,"owner":{"id":1001,"login":"GGULBAE","type":"User"},"permissions":{"admin":%s,"push":true}}\n' \
            "$private" "$visibility" "$admin"
        ;;
    /repos/GGULBAE/desk-setup-switcher/git/matching-refs/tags/v)
        if [[ "$scenario" == tag-present ]]; then
            printf '[{"ref":"refs/tags/v0.1.0","object":{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","type":"commit"}}]\n'
        else
            printf '[]\n'
        fi
        ;;
    /repos/GGULBAE/desk-setup-switcher/releases\?per_page=100)
        if [[ "$scenario" == release-present ]]; then
            printf '[{"id":42,"tag_name":"v0.1.0","draft":true,"prerelease":true,"target_commitish":"master"}]\n'
        else
            printf '[]\n'
        fi
        ;;
    /repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/runs\?per_page=100)
        ref_calls=1
        [[ ! -f "$state_dir/ref-calls" ]] || ref_calls="$(tr -d '\n' <"$state_dir/ref-calls")"
        observation=$(((ref_calls + 1) / 2))
        run_id=501
        if [[ "$scenario" == unstable-runs && $((observation % 2)) == 0 ]]; then
            run_id=502
        elif [[ "$scenario" == pre-run-drift ]]; then
            run_id=502
        elif [[ "$scenario" == post-run-drift && -f "$state_dir/disabled" ]]; then
            run_id=502
        fi
        if [[ "$scenario" == in-progress-run ]]; then
            status=queued
            conclusion=null
        else
            status=completed
            conclusion='"success"'
        fi
        reported_total=1
        [[ "$scenario" != truncated-runs ]] || reported_total=2
        printf '{"reportedTotalCount":%s,"pageTotalCounts":[%s],"runs":[{"id":%s,"run_number":7,"run_attempt":1,"status":"%s","conclusion":%s,"head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","created_at":"2026-07-18T10:00:00Z","updated_at":"2026-07-18T10:01:00Z"}]}\n' \
            "$reported_total" "$reported_total" "$run_id" "$status" "$conclusion"
        ;;
    *) exit 88 ;;
esac
MOCK_GH

chmod 0700 "$mock_bin/git" "$mock_bin/gh"

helper="$RELEASE_SCRIPTS_DIR/contain-legacy-release-workflow.sh"
policy="$RELEASE_SCRIPTS_DIR/legacy_workflow_containment_policy.rb"

new_case() {
    case_root="$(mktemp -d "$temporary_root/case.XXXXXX")"
    chmod 0700 "$case_root"
    state_dir="$case_root/state"
    receipt_dir="$case_root/receipts"
    mkdir -m 0700 "$state_dir" "$receipt_dir"
    command_log="$case_root/commands.log"
    git_log="$case_root/git.log"
    stdout="$case_root/stdout"
    stderr="$case_root/stderr"
    : >"$command_log"
    : >"$git_log"
    chmod 0600 "$command_log" "$git_log"
}

invoke() {
    local scenario="$1"
    shift
    set +e
    env \
        "PATH=$mock_bin:$PATH" \
        "GH_TOKEN=$runtime_token" \
        'GH_DEBUG=api' \
        "MOCK_TOKEN_SHA256=$runtime_token_sha256" \
        "MOCK_STATE_DIR=$state_dir" \
        "MOCK_COMMAND_LOG=$command_log" \
        "MOCK_GIT_LOG=$git_log" \
        "MOCK_SCENARIO=$scenario" \
        "$@" >"$stdout" 2>"$stderr"
    invoke_status=$?
    set -e
}

plan_case() {
    local scenario="$1"
    plan_receipt="$receipt_dir/plan.json"
    invoke "$scenario" "$helper" plan \
        --expected-master "$expected_master" \
        --receipt-output "$plan_receipt"
}

plan_digest_from() {
    ruby -rjson -e 'STDOUT.write(JSON.parse(File.binread(ARGV.fetch(0))).fetch("planDigest"))' "$1"
}

apply_case() {
    local scenario="$1"
    local source_plan="$2"
    local digest="$3"
    result_receipt="$receipt_dir/result.json"
    invoke "$scenario" \
        "DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1" \
        "DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION=DISABLE WORKFLOW 311269012 AT $expected_master" \
        "$helper" apply \
        --expected-master "$expected_master" \
        --plan-receipt "$source_plan" \
        --plan-digest "$digest" \
        --receipt-output "$result_receipt"
}

# Happy read-only plan: two complete anchored observations, no mutation, and a
# closed owner-only receipt that contains no raw secret or local path.
new_case
plan_case happy
assert_status 0 "$invoke_status"
assert_file "$plan_receipt"
[[ "$(stat -f '%Lp' "$plan_receipt")" == 600 ]] || fail "Plan receipt mode differs."
pass
[[ "$(put_count "$command_log")" == 0 ]] || fail "Plan sent a mutation."
pass
[[ "$(grep -c '^GET ' "$command_log")" == 22 ]] || fail "Plan did not perform two full observations."
pass
[[ "$(grep -c 'matching-refs/tags/v paginate=true slurp=true' "$command_log")" == 2 \
    && "$(grep -c '/releases?per_page=100 paginate=true slurp=true' "$command_log")" == 2 \
    && "$(grep -c '/runs?per_page=100 paginate=true slurp=true' "$command_log")" == 2 ]] \
    || fail "Plan did not exhaust all paginated boundary collections."
pass
[[ "$(grep -c '/git/ref/heads/master ' "$command_log")" == 4 \
    && "$(grep -c '/actions/workflows/311269012 ' "$command_log")" == 4 \
    && "$(grep -c "/contents/.github/workflows/release.yml?ref=$expected_master " "$command_log")" == 4 ]] \
    || fail "Plan did not bind both ends of both observations."
pass
assert_no_leak "$stdout" "$stderr" "$plan_receipt"
ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)))
  expected = %w[branch expectedMasterSHA local operation planDigest remote repository schemaVersion]
  abort unless value.keys.sort == expected.sort
  abort unless value.fetch("repository") == "GGULBAE/desk-setup-switcher"
  remote = value.fetch("remote")
  abort unless remote.fetch("actor") == {"id" => 1002, "login" => "synthetic-admin", "type" => "User"}
  repo = remote.fetch("repository")
  abort unless repo.fetch("id") == 7_654_321 && repo.fetch("permissions") == {"admin" => true, "push" => true}
  abort unless remote.fetch("workflowRunCount") == 1
' "$plan_receipt"
pass
happy_plan="$temporary_root/happy-plan.json"
cp "$plan_receipt" "$happy_plan"
chmod 0600 "$happy_plan"
happy_digest="$(plan_digest_from "$happy_plan")"

# Happy apply sends exactly the one fixed PUT, requires an exact 204/empty
# response, double-checks the post-state, and writes a closed success receipt.
: >"$command_log"
rm -f "$state_dir"/*
apply_case happy "$happy_plan" "$happy_digest"
assert_status 0 "$invoke_status"
assert_file "$result_receipt"
[[ "$(put_count "$command_log")" == 1 ]] || fail "Apply did not send exactly one mutation."
pass
assert_no_leak "$stdout" "$stderr" "$result_receipt"
ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)))
  expected = %w[actor branch expectedMasterSHA local mutationAttempted operation planDigest postRemote preRemote repository repositoryIdentity result resultDigest schemaVersion]
  abort unless value.keys.sort == expected.sort
  abort unless value.fetch("operation") == "legacy-release-workflow-containment-result"
  abort unless value.fetch("mutationAttempted") == true
  abort unless value.fetch("preRemote").fetch("workflow").fetch("state") == "active"
  abort unless value.fetch("postRemote").fetch("workflow").fetch("state") == "disabled_manually"
  abort unless value.fetch("planDigest") == ARGV.fetch(1)
' "$result_receipt" "$happy_digest"
pass

# An already-disabled workflow is still double-verified and receipted, but the
# mutation call count remains exactly zero.
new_case
plan_case already-disabled
assert_status 0 "$invoke_status"
disabled_digest="$(plan_digest_from "$plan_receipt")"
: >"$command_log"
rm -f "$state_dir"/ref-calls "$state_dir"/workflow-calls "$state_dir"/content-calls
apply_case already-disabled "$plan_receipt" "$disabled_digest"
assert_status 0 "$invoke_status"
[[ "$(put_count "$command_log")" == 0 ]] || fail "Idempotent apply sent a mutation."
pass
ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)))
  abort unless value.fetch("mutationAttempted") == false
  abort unless value.fetch("preRemote").fetch("workflow").fetch("state") == "disabled_manually"
  abort unless value.fetch("postRemote").fetch("workflow").fetch("state") == "disabled_manually"
' "$result_receipt"
pass

# Plan mode refuses mutation markers, even when they are set to empty strings.
new_case
plan_receipt="$receipt_dir/plan.json"
invoke happy \
    'DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=' \
    'DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION=' \
    "$helper" plan --expected-master "$expected_master" --receipt-output "$plan_receipt"
[[ "$invoke_status" -ne 0 ]] || fail "Plan accepted mutation markers."
pass
assert_absent "$plan_receipt"
[[ ! -s "$command_log" ]] || fail "Rejected plan contacted GitHub."
pass

# Competing GitHub token aliases are rejected rather than silently ignored.
for token_alias in GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN; do
    new_case
    plan_receipt="$receipt_dir/plan.json"
    invoke happy \
        "$token_alias=$runtime_alias_token" \
        "$helper" plan --expected-master "$expected_master" --receipt-output "$plan_receipt"
    [[ "$invoke_status" -ne 0 ]] || fail "Competing GitHub token alias was accepted."
    pass
    assert_absent "$plan_receipt"
    [[ ! -s "$command_log" ]] || fail "Competing token alias contacted GitHub."
    pass
    assert_no_leak "$stdout" "$stderr"
done

# Local anchors are fail-closed before any GitHub request.
for local_scenario in dirty shallow wrong-origin tool-drift; do
    new_case
    plan_receipt="$receipt_dir/plan.json"
    invoke happy "MOCK_LOCAL_SCENARIO=$local_scenario" \
        "$helper" plan --expected-master "$expected_master" --receipt-output "$plan_receipt"
    [[ "$invoke_status" -ne 0 ]] || fail "Local anchor scenario was accepted: $local_scenario"
    pass
    assert_absent "$plan_receipt"
    [[ ! -s "$command_log" ]] || fail "Local anchor failure contacted GitHub."
    pass
done

# Repository shell code is not sourced until every transitive library blob has
# passed the clean local-context check. A tampered library therefore cannot
# observe the captured token or perform a side effect before the guard exits.
for preload_target in release-library common-library; do
    new_case
    preload_root="$case_root/preload-repository"
    mkdir -p "$preload_root/scripts/release" "$preload_root/scripts/lib"
    cp "$helper" "$preload_root/scripts/release/contain-legacy-release-workflow.sh"
    cp "$policy" "$preload_root/scripts/release/legacy_workflow_containment_policy.rb"
    cp "$RELEASE_SCRIPTS_DIR/lib.sh" "$preload_root/scripts/release/lib.sh"
    cp "$ROOT_DIR/scripts/lib/common.sh" "$preload_root/scripts/lib/common.sh"
    chmod 0700 \
        "$preload_root/scripts/release/contain-legacy-release-workflow.sh" \
        "$preload_root/scripts/release/legacy_workflow_containment_policy.rb" \
        "$preload_root/scripts/release/lib.sh" \
        "$preload_root/scripts/lib/common.sh"
    preload_marker="$case_root/preload-marker"
    if [[ "$preload_target" == release-library ]]; then
        printf '\nprintf "unexpected preload\\n" >"${PRELOAD_MARKER:?}"\n' \
            >>"$preload_root/scripts/release/lib.sh"
        preload_scenario=library-drift
    else
        printf '\nprintf "unexpected preload\\n" >"${PRELOAD_MARKER:?}"\n' \
            >>"$preload_root/scripts/lib/common.sh"
        preload_scenario=common-library-drift
    fi
    plan_receipt="$receipt_dir/plan.json"
    invoke happy \
        "PRELOAD_MARKER=$preload_marker" \
        "MOCK_LOCAL_SCENARIO=$preload_scenario" \
        "$preload_root/scripts/release/contain-legacy-release-workflow.sh" plan \
        --expected-master "$expected_master" --receipt-output "$plan_receipt"
    [[ "$invoke_status" -ne 0 ]] || fail "Tampered library was accepted: $preload_target"
    pass
    assert_absent "$preload_marker"
    assert_absent "$plan_receipt"
    [[ ! -s "$command_log" ]] || fail "Tampered library contacted GitHub: $preload_target"
    pass
done

# Output must be an absent path under an external owner-0700 directory.
new_case
chmod 0755 "$receipt_dir"
plan_case happy
[[ "$invoke_status" -ne 0 ]] || fail "Public receipt parent was accepted."
pass
assert_absent "$plan_receipt"
[[ ! -s "$command_log" ]] || fail "Invalid receipt output contacted GitHub."
pass
new_case
plan_receipt="$receipt_dir/plan.json"
printf 'existing\n' >"$plan_receipt"
chmod 0600 "$plan_receipt"
plan_case happy
[[ "$invoke_status" -ne 0 ]] || fail "Existing plan receipt was overwritten."
pass
[[ "$(tr -d '\n' <"$plan_receipt")" == existing ]] || fail "Existing plan receipt changed."
pass

# Every remote identity, boundary, and internal anchor drift blocks the plan
# without writing evidence or reaching a mutation callsite.
for remote_scenario in \
    anchor-drift workflow-anchor-drift blob-anchor-drift unstable-runs \
    tag-present release-present insufficient-permission bad-viewer wrong-blob \
    workflow-identity-drift api-failure in-progress-run truncated-runs \
    private-repository; do
    new_case
    plan_case "$remote_scenario"
    [[ "$invoke_status" -ne 0 ]] || fail "Remote drift scenario was accepted: $remote_scenario"
    pass
    assert_absent "$plan_receipt"
    [[ "$(put_count "$command_log")" == 0 ]] || fail "Failed plan mutated GitHub."
    pass
    assert_no_leak "$stdout" "$stderr"
done

# Wrong approval material fails before remote apply observation or mutation.
new_case
result_receipt="$receipt_dir/result.json"
invoke happy \
    'DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1' \
    "DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION=DISABLE WORKFLOW 311269012 AT $expected_master" \
    "$helper" apply --expected-master "$expected_master" \
    --plan-receipt "$happy_plan" \
    --plan-digest '0000000000000000000000000000000000000000000000000000000000000000' \
    --receipt-output "$result_receipt"
[[ "$invoke_status" -ne 0 ]] || fail "Wrong plan digest was accepted."
pass
assert_absent "$result_receipt"
[[ ! -s "$command_log" ]] || fail "Wrong plan digest contacted GitHub."
pass

new_case
insecure_plan="$receipt_dir/insecure-plan.json"
cp "$happy_plan" "$insecure_plan"
chmod 0644 "$insecure_plan"
result_receipt="$receipt_dir/result.json"
invoke happy \
    'DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1' \
    "DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION=DISABLE WORKFLOW 311269012 AT $expected_master" \
    "$helper" apply --expected-master "$expected_master" \
    --plan-receipt "$insecure_plan" --plan-digest "$happy_digest" \
    --receipt-output "$result_receipt"
[[ "$invoke_status" -ne 0 ]] || fail "Non-0600 plan receipt was accepted."
pass
assert_absent "$result_receipt"
[[ ! -s "$command_log" ]] || fail "Non-0600 plan receipt contacted GitHub."
pass

new_case
result_receipt="$receipt_dir/result.json"
invoke happy \
    'DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1' \
    "$helper" apply --expected-master "$expected_master" \
    --plan-receipt "$happy_plan" --plan-digest "$happy_digest" \
    --receipt-output "$result_receipt"
[[ "$invoke_status" -ne 0 ]] || fail "Missing typed confirmation was accepted."
pass
assert_absent "$result_receipt"
[[ ! -s "$command_log" ]] || fail "Missing confirmation contacted GitHub."
pass

# Pre-write drift is detected after two fresh full observations and before PUT.
new_case
apply_case pre-run-drift "$happy_plan" "$happy_digest"
[[ "$invoke_status" -ne 0 && "$invoke_status" -ne 75 ]] \
    || fail "Pre-write run-set drift was not a guard failure."
pass
assert_absent "$result_receipt"
[[ "$(put_count "$command_log")" == 0 ]] || fail "Pre-write drift reached PUT."
pass

# Once PUT is attempted, API ambiguity, wrong HTTP status/body, or any failed
# postcondition exits 75 and leaves the reserved success destination absent.
for apply_scenario in put-failure put-bad-status put-body post-api-failure post-run-drift; do
    new_case
    apply_case "$apply_scenario" "$happy_plan" "$happy_digest"
    assert_status 75 "$invoke_status"
    assert_absent "$result_receipt"
    [[ "$(put_count "$command_log")" == 1 ]] || fail "Ambiguous apply did not have one PUT: $apply_scenario"
    pass
    assert_no_leak "$stdout" "$stderr"
done

# A same-UID destination race after the sole PUT is never treated as success:
# the helper preserves the competing file, emits no receipt, and exits with the
# incident-only ambiguity status.
new_case
result_receipt="$receipt_dir/result.json"
invoke happy \
    "MOCK_RACE_OUTPUT=$result_receipt" \
    'DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1' \
    "DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION=DISABLE WORKFLOW 311269012 AT $expected_master" \
    "$helper" apply --expected-master "$expected_master" \
    --plan-receipt "$happy_plan" --plan-digest "$happy_digest" \
    --receipt-output "$result_receipt"
assert_status 75 "$invoke_status"
[[ "$(tr -d '\n' <"$result_receipt")" == attacker-owned-marker ]] \
    || fail "Destination race evidence was overwritten or removed."
pass
[[ "$(put_count "$command_log")" == 1 ]] || fail "Destination race did not follow one PUT."
pass
assert_no_leak "$stdout" "$stderr" "$result_receipt"

# Structural guards keep the mutation surface fixed: one disable PUT, no body,
# and no enable/dispatch/cancel/tag/release mutation vocabulary.
ruby -e '
  helper = File.read(ARGV.fetch(0))
  abort unless helper.scan(/--method PUT/).length == 1
  abort if helper.match?(/--method (?:POST|PATCH|DELETE)\b/)
  fixed = %q{/repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable}
  abort unless helper.scan(fixed).length == 1
  abort if helper.match?(%r{/enable\b|/dispatches\b|/cancel\b})
  put = helper.lines.each_index.find { |index| helper.lines[index].include?("--method PUT") }
  abort unless put
  window = helper.lines[put, 10].join
  abort if window.match?(/(?:--input|-f|--field|-F|--raw-field)\b/)
  abort unless window.include?("--include") && window.include?(fixed)
  abort unless helper.include?("X-GitHub-Api-Version: $API_VERSION")
  abort unless helper.include?(%q{API_VERSION="2026-03-10"})
  abort unless helper.include?(%q{?ref=$expected_master})
' "$helper"
pass

ruby -e '
  policy = File.read(ARGV.fetch(0))
  abort unless policy.include?(%q{first_line&.match?(/\AHTTP\/(?:1\.1|2(?:\.0)?) 204(?: No Content)?\z/)})
  abort unless policy.include?(%q{separator.match?(/\A\r?\n\r?\n\z/) && body.empty?})
  abort unless policy.include?(%q{unless succeeded || created_identity.nil?})
  abort unless policy.include?(%q{File.unlink(destination) if [current.dev, current.ino] == created_identity})
' "$policy"
pass

printf 'Legacy workflow containment checks passed: %d assertions.\n' "$assertions"
