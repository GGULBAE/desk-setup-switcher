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
file_sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
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
mock_control="$temporary_root/mock-control"
mkdir -m 0700 "$mock_bin" "$mock_control"
runtime_token="$(ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_alias_token="$(ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_token_sha256="$(printf '%s' "$runtime_token" | shasum -a 256 | awk '{print $1}')"
expected_master='eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee'
local_head='aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
helper_blob="$(git hash-object "$RELEASE_SCRIPTS_DIR/contain-legacy-release-workflow.sh")"
validator_blob="$(git hash-object "$RELEASE_SCRIPTS_DIR/legacy_workflow_containment_policy.rb")"
library_blob="$(git hash-object "$RELEASE_SCRIPTS_DIR/lib.sh")"
common_library_blob="$(git hash-object "$ROOT_DIR/scripts/lib/common.sh")"

cat >"$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == -C && "$#" -ge 3 ]] || exit 91
repository_root="$2"
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
                blob="$MOCK_HELPER_BLOB"
                [[ "${MOCK_LOCAL_SCENARIO:-}" != tool-drift ]] || \
                    blob=9999999999999999999999999999999999999999
                ;;
            scripts/release/legacy_workflow_containment_policy.rb)
                blob="$MOCK_VALIDATOR_BLOB" ;;
            scripts/release/lib.sh)
                blob="$MOCK_LIBRARY_BLOB" ;;
            scripts/lib/common.sh)
                blob="$MOCK_COMMON_LIBRARY_BLOB"
                if [[ "${MOCK_LOCAL_SCENARIO:-}" == policy-after-validation-drift \
                    && ! -e "$MOCK_STATE_DIR/policy-after-validation-drift" ]]; then
                    : >"$MOCK_STATE_DIR/policy-after-validation-drift"
                    printf '\nFile.write(ENV.fetch("PRELOAD_MARKER"), "unexpected\\n")\n' \
                        >>"$repository_root/scripts/release/legacy_workflow_containment_policy.rb"
                fi
                ;;
            *) exit 95 ;;
        esac
        printf '100755 blob %s\t%s\n' "$blob" "$4"
        ;;
    hash-object)
        [[ "$#" == 3 && "$2" == -- ]] || exit 96
        case "$3" in
            scripts/release/contain-legacy-release-workflow.sh)
                printf '%s\n' "$MOCK_HELPER_BLOB"
                ;;
            scripts/release/legacy_workflow_containment_policy.rb)
                printf '%s\n' "$MOCK_VALIDATOR_BLOB" ;;
            scripts/release/lib.sh)
                printf '%s\n' "$MOCK_LIBRARY_BLOB"
                ;;
            scripts/lib/common.sh)
                printf '%s\n' "$MOCK_COMMON_LIBRARY_BLOB"
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
mock_control="$(cd "${0%/*}/../mock-control" && pwd -P)"
read_control() {
    local value=""
    IFS= read -r value <"$mock_control/$1" || [[ -z "$value" ]]
    printf '%s' "$value"
}
expected_token_sha256="$(read_control token-sha256)"
command_log="$(read_control command-log)"
state_dir="$(read_control state-dir)"
scenario="$(read_control scenario)"
noclobber_marker="$(read_control noclobber-marker)"
race_output="$(read_control race-output)"
helper_temp="$(read_control helper-temp)"
capture_roots=("$helper_temp"/desk-setup-legacy-workflow-containment.*)
[[ "${#capture_roots[@]}" == 1 && -d "${capture_roots[0]}" \
    && ! -L "${capture_roots[0]}" ]] || exit 80
capture_root="${capture_roots[0]}"
token="${GH_TOKEN:-}"
unset GH_TOKEN
actual_digest="$(printf '%s' "$token" | shasum -a 256 | awk '{print $1}')"
[[ "$actual_digest" == "$expected_token_sha256" ]] || exit 81
[[ -z "${GITHUB_TOKEN+x}" && -z "${GH_DEBUG+x}" && -z "${DEBUG+x}" \
    && -z "${GH_ENTERPRISE_TOKEN+x}" && -z "${GITHUB_ENTERPRISE_TOKEN+x}" \
    && -z "${DESK_SETUP_CAPTURE_SECRETS+x}" \
    && -z "${DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS+x}" \
    && -z "${DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION+x}" \
    && -z "${DESK_SETUP_CALLER_SENTINEL+x}" && -z "${HOME+x}" \
    && -z "${TMPDIR+x}" ]] || exit 82
[[ "$PATH" == /usr/bin:/bin:/usr/sbin:/sbin && "$LANG" == C \
    && "$LC_ALL" == C && "$GH_PROMPT_DISABLED" == 1 \
    && "$GH_NO_UPDATE_NOTIFIER" == 1 \
    && "$GH_TELEMETRY" == 0 && "$DO_NOT_TRACK" == 1 \
    && "$GH_CONFIG_DIR" == /private/var/empty ]] || exit 82
[[ "${1:-}" == api ]] || exit 83
method=""
paginate=false
slurp=false
jq_present=false
jq_expression=""
for ((index = 1; index <= $#; index++)); do
    argument="${!index}"
    case "$argument" in
        --method)
            next=$((index + 1))
            method="${!next}"
            ;;
        --paginate) paginate=true ;;
        --slurp) slurp=true ;;
        --jq)
            jq_present=true
            next=$((index + 1))
            jq_expression="${!next}"
            ;;
    esac
done
endpoint="${!#}"
[[ "$method" == GET || "$method" == PUT ]] || exit 84
[[ "$slurp" != true || "$jq_present" != true ]] || exit 89
printf '%s %s paginate=%s slurp=%s jq=%s\n' \
    "$method" "$endpoint" "$paginate" "$slurp" "$jq_present" \
    >>"$command_log"

counter() {
    local name="$1"
    local path="$state_dir/$name"
    local value=0
    [[ ! -f "$path" ]] || value="$(tr -d '\n' <"$path")"
    value=$((value + 1))
    printf '%s\n' "$value" >"$path"
    printf '%s\n' "$value"
}

install_race_link() {
    local target="$1"
    local marker="$noclobber_marker"
    [[ -n "$marker" && -f "$marker" && ! -e "$target" && ! -L "$target" ]] || exit 90
    ln -s "$marker" "$target"
}

rewrite_same_inode() {
    local target="$1"
    local expected_size="$2"
    local replacement="$3"
    local marker="$4"
    local size="" before_inode after_inode
    for _rewrite_wait in {1..2000}; do
        if [[ -f "$target" && ! -L "$target" ]]; then
            size="$(stat -f '%z' "$target")"
            [[ "$size" == "$expected_size" ]] && break
        fi
        sleep 0.001
    done
    [[ "$size" == "$expected_size" ]] || exit 94
    before_inode="$(stat -f '%i' "$target")"
    printf '%s' "$replacement" >"$target"
    after_inode="$(stat -f '%i' "$target")"
    [[ "$before_inode" == "$after_inode" ]] || exit 95
    printf '%s\t%s\n' "$before_inode" "$after_inode" >"$marker"
}

if [[ "$scenario" == noclobber-raw &&
    "$endpoint" == '/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master' &&
    ! -f "$state_dir/noclobber-installed" ]]; then
    : >"$state_dir/noclobber-installed"
    install_race_link \
        "$capture_root/plan-1/anchor-start-workflow.json"
elif [[ "$scenario" == noclobber-page &&
    "$endpoint" == '/repos/GGULBAE/desk-setup-switcher' &&
    ! -f "$state_dir/noclobber-installed" ]]; then
    : >"$state_dir/noclobber-installed"
    install_race_link \
        "$capture_root/plan-1/v-tag-refs.json.lines"
fi

if [[ "$method" == PUT ]]; then
    [[ "$endpoint" == '/repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable' ]] \
        || exit 85
    [[ "$scenario" != put-failure ]] || exit 86
    : >"$state_dir/disabled"
    if [[ -n "$race_output" ]]; then
        printf 'attacker-owned-marker\n' >"$race_output"
        chmod 0600 "$race_output"
    fi
    case "$scenario" in
        put-bad-status|same-inode-put)
            put_response=$'HTTP/2.0 200 OK\r\ncontent-length: 0\r\n\r\n' ;;
        put-body)
            put_response=$'HTTP/2.0 204 No Content\r\ncontent-length: 4\r\n\r\nBODY' ;;
        *)
            put_response=$'HTTP/2.0 204 No Content\r\ncontent-length: 0\r\n\r\n' ;;
    esac
    printf '%s' "$put_response"
    if [[ "$scenario" == same-inode-put ]]; then
        capture_path="$capture_root/mutation-response"
        replacement=$'HTTP/2.0 204 No Content\r\ncontent-length: 0\r\n\r\n'
        rewrite_same_inode "$capture_path" "${#put_response}" "$replacement" \
            "$state_dir/same-inode-put"
    fi
    if [[ "$scenario" == post-capture-put ]]; then
        capture_path="$capture_root/mutation-response"
        mv "$capture_path" "$capture_path.original"
        printf 'HTTP/2.0 204 No Content\r\ncontent-length: 0\r\n\r\n' >"$capture_path"
        chmod 0600 "$capture_path"
    fi
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
        elif [[ "$scenario" == same-inode-raw && "$ref_call" == 1 ]]; then
            sha=ffffffffffffffffffffffffffffffffffffffff
        fi
        ref_response="{\"ref\":\"refs/heads/master\",\"object\":{\"sha\":\"$sha\",\"type\":\"commit\"}}"$'\n'
        printf '%s' "$ref_response"
        if [[ "$scenario" == same-inode-raw && "$ref_call" == 1 ]]; then
            capture_path="$capture_root/plan-1/anchor-start-ref.json"
            replacement='{"ref":"refs/heads/master","object":{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","type":"commit"}}'$'\n'
            rewrite_same_inode "$capture_path" "${#ref_response}" "$replacement" \
                "$state_dir/same-inode-raw"
        fi
        if [[ "$scenario" == post-capture-raw && "$ref_call" == 1 ]]; then
            capture_path="$capture_root/plan-1/anchor-start-ref.json"
            mv "$capture_path" "$capture_path.original"
            printf '{"ref":"refs/heads/master","object":{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","type":"commit"}}\n' >"$capture_path"
            chmod 0600 "$capture_path"
        fi
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
        if [[ "$scenario" == noclobber-put && "$content_call" == 4 ]]; then
            install_race_link "$capture_root/mutation-response"
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
        expected_jq='if type == "array" then {items: [.[] | {ref: .ref, object: {sha: .object.sha, type: .object.type}}]} else error("unexpected page") end | @json'
        [[ "$jq_expression" == "$expected_jq" ]] || exit 91
        if [[ "$scenario" == zero-output-tags ]]; then
            :
        elif [[ "$scenario" == tag-present || "$scenario" == same-inode-page ]]; then
            printf '{"items":[{"ref":"refs/tags/v0.1.0","object":{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","type":"commit"}}]}\n'
        elif [[ "$scenario" == second-page-tag ]]; then
            printf '%s\n' \
                '{"items":[]}' \
                '{"items":[{"ref":"refs/tags/v0.1.0","object":{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","type":"commit"}}]}'
        elif [[ "$scenario" == malformed-tag-envelope ]]; then
            printf '{"items":[],"extra":true}\n'
        elif [[ "$scenario" == duplicate-tag-envelope-key ]]; then
            printf '{"items":[],"items":[]}\n'
        elif [[ "$scenario" == invalid-tag-items ]]; then
            printf '{"items":{}}\n'
        elif [[ "$scenario" == paginated-empty-boundaries ]]; then
            printf '%s\n' '{"items":[]}' '{"items":[]}'
        else
            printf '{"items":[]}\n'
        fi
        if [[ "$scenario" == same-inode-page ]]; then
            capture_path="$capture_root/plan-1/v-tag-refs.json.lines"
            original='{"items":[{"ref":"refs/tags/v0.1.0","object":{"sha":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee","type":"commit"}}]}'$'\n'
            replacement='{"items":[]}'$'\n'
            rewrite_same_inode "$capture_path" "${#original}" "$replacement" \
                "$state_dir/same-inode-page"
        fi
        if [[ "$scenario" == post-capture-page ]]; then
            capture_path="$capture_root/plan-1/v-tag-refs.json.lines"
            mv "$capture_path" "$capture_path.original"
            printf '{"items":[]}\n' >"$capture_path"
            chmod 0600 "$capture_path"
        fi
        ;;
    /repos/GGULBAE/desk-setup-switcher/releases\?per_page=100)
        expected_jq='if type == "array" then {items: [.[] | {id: .id, tag_name: .tag_name, draft: .draft, prerelease: .prerelease, target_commitish: .target_commitish}]} else error("unexpected page") end | @json'
        [[ "$jq_expression" == "$expected_jq" ]] || exit 92
        if [[ "$scenario" == zero-output-releases ]]; then
            :
        elif [[ "$scenario" == release-present ]]; then
            printf '{"items":[{"id":42,"tag_name":"v0.1.0","draft":true,"prerelease":true,"target_commitish":"master"}]}\n'
        elif [[ "$scenario" == second-page-release ]]; then
            printf '%s\n' \
                '{"items":[]}' \
                '{"items":[{"id":42,"tag_name":"v0.1.0","draft":true,"prerelease":true,"target_commitish":"master"}]}'
        elif [[ "$scenario" == paginated-empty-boundaries ]]; then
            printf '%s\n' '{"items":[]}' '{"items":[]}'
        else
            printf '{"items":[]}\n'
        fi
        ;;
    /repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/runs\?per_page=100)
        expected_jq='if type == "object" and (.total_count | type == "number") and (.workflow_runs | type == "array") then {reportedTotalCount: .total_count, runs: [.workflow_runs[] | {id: .id, run_number: .run_number, run_attempt: .run_attempt, status: .status, conclusion: .conclusion, head_sha: .head_sha, event: .event, created_at: .created_at, updated_at: .updated_at}]} else error("unexpected page") end | @json'
        [[ "$jq_expression" == "$expected_jq" ]] || exit 93
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
        if [[ "$scenario" == malformed-run-page ]]; then
            printf '%s\n' '{"reportedTotalCount":1'
        elif [[ "$scenario" == duplicate-run-page-key ]]; then
            printf '%s\n' \
                '{"reportedTotalCount":1,"reportedTotalCount":1,"runs":[]}'
        elif [[ "$scenario" == inconsistent-run-pages ]]; then
            printf '%s\n' \
                '{"reportedTotalCount":2,"runs":[{"id":501,"run_number":7,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","created_at":"2026-07-18T10:00:00Z","updated_at":"2026-07-18T10:01:00Z"}]}' \
                '{"reportedTotalCount":3,"runs":[{"id":502,"run_number":8,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","created_at":"2026-07-18T10:02:00Z","updated_at":"2026-07-18T10:03:00Z"}]}'
        elif [[ "$scenario" == paginated-runs ]]; then
            printf '%s\n' \
                '{"reportedTotalCount":2,"runs":[{"id":501,"run_number":7,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","created_at":"2026-07-18T10:00:00Z","updated_at":"2026-07-18T10:01:00Z"}]}' \
                '{"reportedTotalCount":2,"runs":[{"id":502,"run_number":8,"run_attempt":1,"status":"completed","conclusion":"success","head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","created_at":"2026-07-18T10:02:00Z","updated_at":"2026-07-18T10:03:00Z"}]}'
        else
            printf '{"reportedTotalCount":%s,"runs":[{"id":%s,"run_number":7,"run_attempt":1,"status":"%s","conclusion":%s,"head_sha":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","event":"workflow_dispatch","created_at":"2026-07-18T10:00:00Z","updated_at":"2026-07-18T10:01:00Z"}]}\n' \
                "$reported_total" "$run_id" "$status" "$conclusion"
        fi
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
    helper_temp="$case_root/helper-temp"
    mkdir -m 0700 "$state_dir" "$receipt_dir" "$helper_temp"
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
    local invocation_argument
    local mock_noclobber_marker=""
    local mock_race_output=""
    shift
    for invocation_argument in "$@"; do
        case "$invocation_argument" in
            MOCK_NOCLOBBER_MARKER=*)
                mock_noclobber_marker="${invocation_argument#*=}" ;;
            MOCK_RACE_OUTPUT=*)
                mock_race_output="${invocation_argument#*=}" ;;
        esac
    done
    printf '%s\n' "$runtime_token_sha256" >"$mock_control/token-sha256"
    printf '%s\n' "$command_log" >"$mock_control/command-log"
    printf '%s\n' "$state_dir" >"$mock_control/state-dir"
    printf '%s\n' "$scenario" >"$mock_control/scenario"
    printf '%s\n' "$mock_noclobber_marker" >"$mock_control/noclobber-marker"
    printf '%s\n' "$mock_race_output" >"$mock_control/race-output"
    printf '%s\n' "$helper_temp" >"$mock_control/helper-temp"
    chmod 0600 "$mock_control"/*
    set +e
    env \
        "PATH=$mock_bin:$PATH" \
        "TMPDIR=$helper_temp/" \
        "GH_TOKEN=$runtime_token" \
        'GH_DEBUG=api' \
        'DESK_SETUP_CALLER_SENTINEL=must-not-reach-gh' \
        "MOCK_TOKEN_SHA256=$runtime_token_sha256" \
        "MOCK_HELPER_BLOB=$helper_blob" \
        "MOCK_VALIDATOR_BLOB=$validator_blob" \
        "MOCK_LIBRARY_BLOB=$library_blob" \
        "MOCK_COMMON_LIBRARY_BLOB=$common_library_blob" \
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
    shift
    plan_receipt="$receipt_dir/plan.json"
    invoke "$scenario" "$@" "$helper" plan \
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
    shift 3
    result_receipt="$receipt_dir/result.json"
    invoke "$scenario" \
        "$@" \
        "DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS=1" \
        "DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION=DISABLE WORKFLOW 311269012 AT $expected_master" \
        "$helper" apply \
        --expected-master "$expected_master" \
        --plan-receipt "$source_plan" \
        --plan-digest "$digest" \
        --receipt-output "$result_receipt"
}

# Page normalization distinguishes a proven empty API page from absent output,
# preserves later pages, and refuses unsafe path shapes before observations are
# allowed to reach the receipt policy.
new_case
page_input="$case_root/item-pages.jsonl"
page_output="$case_root/items.json"
printf '%s\n' \
    '{"items":[{"page":1}]}' \
    '{"items":[]}' \
    '{"items":[{"page":2}]}' >"$page_input"
chmod 0600 "$page_input"
ruby "$policy" normalize-json-line-item-pages \
    "$page_input" "$page_output" "$(file_sha256 "$page_input")" \
    >"$stdout" 2>"$stderr"
assert_file "$page_output"
[[ "$(stat -f '%Lp' "$page_output")" == 600 ]] || fail "Normalized page mode differs."
pass
ruby -rjson -e '
  abort unless JSON.parse(File.binread(ARGV.fetch(0))) == [{"page" => 1}, {"page" => 2}]
' "$page_output"
pass

for invalid_page in zero malformed duplicate non-array null-item wrong-digest; do
    new_case
    page_input="$case_root/item-pages.jsonl"
    page_output="$case_root/items.json"
    case "$invalid_page" in
        zero) : >"$page_input" ;;
        malformed) printf '{"items":[],"extra":true}\n' >"$page_input" ;;
        duplicate) printf '{"items":[],"items":[]}\n' >"$page_input" ;;
        non-array) printf '{"items":{}}\n' >"$page_input" ;;
        null-item) printf '{"items":[null]}\n' >"$page_input" ;;
        wrong-digest) printf '{"items":[]}\n' >"$page_input" ;;
    esac
    chmod 0600 "$page_input"
    page_input_sha256="$(file_sha256 "$page_input")"
    [[ "$invalid_page" != wrong-digest ]] ||
        page_input_sha256='0000000000000000000000000000000000000000000000000000000000000000'
    set +e
    ruby "$policy" normalize-json-line-item-pages \
        "$page_input" "$page_output" "$page_input_sha256" \
        >"$stdout" 2>"$stderr"
    policy_status=$?
    set -e
    [[ "$policy_status" -ne 0 ]] || fail "Invalid item page was accepted: $invalid_page"
    pass
    assert_absent "$page_output"
done

new_case
page_target="$case_root/page-target.jsonl"
page_input="$case_root/item-pages.jsonl"
page_output="$case_root/items.json"
printf '{"items":[]}\n' >"$page_target"
chmod 0600 "$page_target"
ln -s "$page_target" "$page_input"
set +e
ruby "$policy" normalize-json-line-item-pages \
    "$page_input" "$page_output" "$(file_sha256 "$page_target")" \
    >"$stdout" 2>"$stderr"
policy_status=$?
set -e
[[ "$policy_status" -ne 0 ]] || fail "Symlink item-page input was accepted."
pass
assert_absent "$page_output"

new_case
page_input="$case_root/item-pages.jsonl"
page_peer="$case_root/item-pages-peer.jsonl"
page_output="$case_root/items.json"
printf '{"items":[]}\n' >"$page_input"
chmod 0600 "$page_input"
ln "$page_input" "$page_peer"
set +e
ruby "$policy" normalize-json-line-item-pages \
    "$page_input" "$page_output" "$(file_sha256 "$page_input")" \
    >"$stdout" 2>"$stderr"
policy_status=$?
set -e
[[ "$policy_status" -ne 0 ]] || fail "Hard-linked item-page input was accepted."
pass
assert_absent "$page_output"

for existing_output in symlink regular; do
    new_case
    page_input="$case_root/item-pages.jsonl"
    page_output="$case_root/items.json"
    output_marker="$case_root/output-marker"
    printf '{"items":[]}\n' >"$page_input"
    printf 'preserve-me\n' >"$output_marker"
    chmod 0600 "$page_input" "$output_marker"
    if [[ "$existing_output" == symlink ]]; then
        ln -s "$output_marker" "$page_output"
    else
        printf 'preserve-me\n' >"$page_output"
        chmod 0600 "$page_output"
    fi
    set +e
    ruby "$policy" normalize-json-line-item-pages \
        "$page_input" "$page_output" "$(file_sha256 "$page_input")" \
        >"$stdout" 2>"$stderr"
    policy_status=$?
    set -e
    [[ "$policy_status" -ne 0 ]] || fail "Existing normalizer output was overwritten: $existing_output"
    pass
    [[ "$(tr -d '\n' <"$output_marker")" == preserve-me ]] || fail "Output target changed."
    pass
    if [[ "$existing_output" == regular ]]; then
        [[ "$(tr -d '\n' <"$page_output")" == preserve-me ]] || fail "Existing output changed."
        pass
    fi
done

# A capture digest transported through a writable path is accepted only with a
# fresh caller-held HMAC key; a capture-path rewrite alone cannot forge it.
new_case
forged_capture="$case_root/capture.jsonl"
forged_attestation="$forged_capture.attestation"
printf '{"items":[]}\n' >"$forged_capture"
forged_capture_sha256="$(file_sha256 "$forged_capture")"
forged_capture_bytes="$(stat -f '%z' "$forged_capture")"
printf '%s\n' \
    "{\"schemaVersion\":1,\"operation\":\"v-tag-refs\",\"byteCount\":$forged_capture_bytes,\"sha256\":\"$forged_capture_sha256\",\"hmacSHA256\":\"0000000000000000000000000000000000000000000000000000000000000000\"}" \
    >"$forged_attestation"
chmod 0600 "$forged_capture" "$forged_attestation"
set +e
printf '%064d\n' 1 | ruby "$policy" verify-remote-capture \
    v-tag-refs "$forged_capture" "$forged_attestation" \
    >"$stdout" 2>"$stderr"
policy_status=$?
set -e
[[ "$policy_status" -ne 0 ]] || fail "Forged capture attestation was accepted."
pass

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
[[ "$(grep -c 'matching-refs/tags/v paginate=true slurp=false jq=true' "$command_log")" == 2 \
    && "$(grep -c '/releases?per_page=100 paginate=true slurp=false jq=true' "$command_log")" == 2 \
    && "$(grep -c '/runs?per_page=100 paginate=true slurp=false jq=true' "$command_log")" == 2 ]] \
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

# The mutation subcommand has an accidental-misuse guardrail in addition to the
# documented apply path: an unbound internal authorization string cannot spawn
# the remote child. This is not authentication against a token-holding caller.
new_case
direct_capture_root="$case_root/direct-capture"
direct_output="$direct_capture_root/mutation-response"
mkdir -m 0700 "$direct_capture_root"
direct_key='1111111111111111111111111111111111111111111111111111111111111111'
set +e
printf '%s\n' "$runtime_token"$'\t'"$direct_key"$'\t'"READ ONLY" | \
    ruby "$policy" capture-remote-operation \
        disable-workflow "$direct_output" "$direct_output.attestation" \
        "$expected_master" "$direct_capture_root" /private/var/empty "$mock_bin/gh" \
        "$happy_plan" "$happy_digest" \
        >"$stdout" 2>"$stderr"
policy_status=$?
set -e
[[ "$policy_status" -ne 0 ]] || fail "Unbound direct mutation authorization was accepted."
pass
assert_absent "$direct_output"
assert_absent "$direct_output.attestation"
[[ ! -s "$command_log" ]] || fail "Unbound direct mutation authorization contacted GitHub."
pass
assert_no_leak "$stdout" "$stderr"

# A real multi-page run response is joined without gh --slurp, while retaining
# every page total and every distinct projected run.
new_case
plan_case paginated-runs
assert_status 0 "$invoke_status"
assert_file "$plan_receipt"
[[ "$(put_count "$command_log")" == 0 ]] || fail "Paginated plan sent a mutation."
pass
ruby -rjson -e '
  value = JSON.parse(File.binread(ARGV.fetch(0)))
  abort unless value.fetch("remote").fetch("workflowRunCount") == 2
' "$plan_receipt"
pass
assert_no_leak "$stdout" "$stderr" "$plan_receipt"

# Empty tag and Release collections remain valid only when every observed page
# emits an explicit closed-schema envelope.
new_case
plan_case paginated-empty-boundaries
assert_status 0 "$invoke_status"
assert_file "$plan_receipt"
[[ "$(put_count "$command_log")" == 0 ]] || fail "Empty boundary pages sent a mutation."
pass
ruby -rjson -e '
  remote = JSON.parse(File.binread(ARGV.fetch(0))).fetch("remote")
  abort unless remote.fetch("vTagRefCount").zero? && remote.fetch("releaseCount").zero?
' "$plan_receipt"
pass
assert_no_leak "$stdout" "$stderr" "$plan_receipt"

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

new_case
plan_receipt="$receipt_dir/plan.json"
invoke happy \
    'DESK_SETUP_CAPTURE_SECRETS=caller-controlled' \
    "$helper" plan --expected-master "$expected_master" --receipt-output "$plan_receipt"
[[ "$invoke_status" -ne 0 ]] || fail "Caller-supplied capture secrets were accepted."
pass
assert_absent "$plan_receipt"
[[ ! -s "$command_log" ]] || fail "Caller-supplied capture secrets contacted GitHub."
pass
assert_no_leak "$stdout" "$stderr"

# Interpreter and loader injection variables are rejected before repository
# code is evaluated or the remote executable can be reached.
for injection_variable in \
    RUBYOPT RUBYLIB DYLD_INSERT_LIBRARIES DYLD_LIBRARY_PATH DYLD_FRAMEWORK_PATH; do
    new_case
    plan_receipt="$receipt_dir/plan.json"
    if [[ "$injection_variable" == DYLD_* ]]; then
        # macOS strips DYLD_* while launching protected binaries, so set it in
        # the already-running test shell immediately before loading the helper.
        invoke happy /bin/bash -c '
            injection_name="$1"
            injection_value="$2"
            helper_path="$3"
            shift 3
            export "$injection_name=$injection_value"
            set -- "$@"
            source "$helper_path"
        ' containment-runtime-injection \
            "$injection_variable" "$case_root" "$helper" \
            plan --expected-master "$expected_master" --receipt-output "$plan_receipt"
    else
        invoke happy \
            "$injection_variable=$case_root" \
            "$helper" plan --expected-master "$expected_master" --receipt-output "$plan_receipt"
    fi
    [[ "$invoke_status" -ne 0 ]] || \
        fail "Runtime injection variable was accepted: $injection_variable"
    pass
    assert_absent "$plan_receipt"
    [[ ! -s "$command_log" ]] || \
        fail "Runtime injection variable contacted GitHub: $injection_variable"
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

# Repository code is never evaluated from a pathname. Both a file that was
# already dirty and a policy replaced after its initial validation must fail
# its descriptor-bound Git-blob check before any side effect or remote call.
for preload_target in release-library common-library policy-after-validation; do
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
    elif [[ "$preload_target" == common-library ]]; then
        printf '\nprintf "unexpected preload\\n" >"${PRELOAD_MARKER:?}"\n' \
            >>"$preload_root/scripts/lib/common.sh"
        preload_scenario=common-library-drift
    else
        preload_scenario=policy-after-validation-drift
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

# Competing capture-path precreation cannot make the policy follow a symlink or
# truncate the external target under the trusted local-toolchain boundary.
for noclobber_scenario in noclobber-raw noclobber-page; do
    new_case
    noclobber_marker="$case_root/noclobber-marker"
    printf 'preserve-me\n' >"$noclobber_marker"
    chmod 0600 "$noclobber_marker"
    plan_case "$noclobber_scenario" "MOCK_NOCLOBBER_MARKER=$noclobber_marker"
    assert_status 70 "$invoke_status"
    assert_absent "$plan_receipt"
    [[ "$(tr -d '\n' <"$noclobber_marker")" == preserve-me ]] ||
        fail "GET capture followed a competing symlink: $noclobber_scenario"
    pass
    [[ "$(put_count "$command_log")" == 0 ]] || fail "Noclobber plan sent a mutation."
    pass
    assert_no_leak "$stdout" "$stderr" "$noclobber_marker"
done

# Every remote identity, boundary, and internal anchor drift blocks the plan
# without writing evidence or reaching a mutation callsite.
for remote_scenario in \
    anchor-drift workflow-anchor-drift blob-anchor-drift unstable-runs \
    tag-present release-present second-page-tag second-page-release \
    zero-output-tags zero-output-releases malformed-tag-envelope \
    duplicate-tag-envelope-key invalid-tag-items \
    post-capture-raw post-capture-page \
    insufficient-permission bad-viewer wrong-blob \
    workflow-identity-drift api-failure in-progress-run truncated-runs \
    private-repository malformed-run-page duplicate-run-page-key \
    inconsistent-run-pages; do
    new_case
    plan_case "$remote_scenario"
    [[ "$invoke_status" -ne 0 ]] || fail "Remote drift scenario was accepted: $remote_scenario"
    pass
    assert_absent "$plan_receipt"
    [[ "$(put_count "$command_log")" == 0 ]] || fail "Failed plan mutated GitHub."
    pass
    assert_no_leak "$stdout" "$stderr"
done

# A competing capture-path writer cannot turn streamed unsafe bytes into
# trusted input merely by truncating and rewriting the already-open inode.
# These two cases would pass if the digest began only after gh exited.
for same_inode_scenario in same-inode-raw same-inode-page; do
    new_case
    plan_case "$same_inode_scenario"
    [[ "$invoke_status" -ne 0 ]] || \
        fail "Same-inode GET rewrite was accepted: $same_inode_scenario"
    pass
    assert_absent "$plan_receipt"
    same_inode_marker="$state_dir/$same_inode_scenario"
    [[ -f "$same_inode_marker" && ! -L "$same_inode_marker" ]] || \
        fail "Same-inode marker is absent: $same_inode_scenario"
    pass
    IFS=$'\t' read -r before_inode after_inode <"$same_inode_marker"
    [[ "$before_inode" =~ ^[1-9][0-9]*$ && "$before_inode" == "$after_inode" ]] || \
        fail "GET rewrite did not preserve the capture inode: $same_inode_scenario"
    pass
    [[ "$(put_count "$command_log")" == 0 ]] || \
        fail "Same-inode GET rewrite reached PUT: $same_inode_scenario"
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

duplicate_plan="$temporary_root/duplicate-plan.json"
ruby -e '
  source = File.binread(ARGV.fetch(0))
  duplicate = source.sub(/\A\{/, %({"schemaVersion":0,))
  abort if duplicate == source
  File.binwrite(ARGV.fetch(1), duplicate)
' "$happy_plan" "$duplicate_plan"
chmod 0600 "$duplicate_plan"
new_case
result_receipt="$receipt_dir/result.json"
apply_case happy "$duplicate_plan" "$happy_digest"
[[ "$invoke_status" -ne 0 ]] || fail "Duplicate-key plan receipt was accepted."
[[ ! -e "$result_receipt" && ! -L "$result_receipt" ]] ||
    fail "Duplicate-key plan receipt produced a result."
[[ ! -s "$command_log" ]] || fail "Duplicate-key plan receipt contacted GitHub."
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

# Pre-creating the private PUT response path prevents the gh process from
# starting; the helper treats that boundary as ambiguous without issuing PUT.
new_case
noclobber_marker="$case_root/noclobber-marker"
printf 'preserve-me\n' >"$noclobber_marker"
chmod 0600 "$noclobber_marker"
apply_case noclobber-put "$happy_plan" "$happy_digest" \
    "MOCK_NOCLOBBER_MARKER=$noclobber_marker"
assert_status 75 "$invoke_status"
assert_absent "$result_receipt"
[[ "$(tr -d '\n' <"$noclobber_marker")" == preserve-me ]] ||
    fail "PUT capture followed a competing symlink."
pass
[[ "$(put_count "$command_log")" == 0 ]] || fail "Noclobber failure invoked PUT."
pass
assert_no_leak "$stdout" "$stderr" "$noclobber_marker"

# Once PUT is attempted, API ambiguity, wrong HTTP status/body, or any failed
# postcondition exits 75 and leaves the reserved success destination absent.
for apply_scenario in \
    put-failure put-bad-status put-body post-api-failure post-run-drift \
    post-capture-put; do
    new_case
    apply_case "$apply_scenario" "$happy_plan" "$happy_digest"
    assert_status 75 "$invoke_status"
    assert_absent "$result_receipt"
    [[ "$(put_count "$command_log")" == 1 ]] || fail "Ambiguous apply did not have one PUT: $apply_scenario"
    pass
    assert_no_leak "$stdout" "$stderr"
done

# The same stream binding applies to the sole mutation response: a real 200
# rewritten in place to an apparent 204 remains ambiguous and is never retried.
new_case
apply_case same-inode-put "$happy_plan" "$happy_digest"
assert_status 75 "$invoke_status"
assert_absent "$result_receipt"
same_inode_marker="$state_dir/same-inode-put"
assert_file "$same_inode_marker"
IFS=$'\t' read -r before_inode after_inode <"$same_inode_marker"
[[ "$before_inode" =~ ^[1-9][0-9]*$ && "$before_inode" == "$after_inode" ]] || \
    fail "PUT rewrite did not preserve the capture inode."
pass
[[ "$(put_count "$command_log")" == 1 ]] || \
    fail "Same-inode PUT rewrite did not have exactly one PUT."
pass
assert_no_leak "$stdout" "$stderr"

# A competing destination-path race after the sole PUT is never treated as success:
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
  abort if helper.match?(/--method\s+(?:GET|PUT|POST|PATCH|DELETE)\b/)
  abort unless helper.scan(/capture_remote_operation disable-workflow/).length == 1
  abort unless helper.scan(/release_run_tracked_secret_stdin_timeout/).length == 1
  abort if helper.match?(/release_run_tracked_secret_env_timeout\s+.*secret_bundle/)
  abort unless helper.include?(%q{API_TIMEOUT_SECONDS=20})
  abort unless helper.include?(%q{SecureRandom.hex(32)})
  abort unless helper.match?(/secret_bundle=.*github_token.*\\t.*capture_key/)
  abort unless helper.include?(%q{capture-remote-operation})
  abort unless helper.include?(%q{verify-remote-capture})
  abort if helper.include?(%q{source "$SCRIPT_DIR/lib.sh"})
  abort unless helper.include?(%q{Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes)})
  abort unless helper.include?(%q{eval(bytes, TOPLEVEL_BINDING, path, 1)})
  abort unless helper.include?(%q{File::RDONLY | File::NOFOLLOW})
  abort unless helper.include?(%q{capture_key=""}) && helper.include?(%q{secret_bundle=""})
  override = helper.index(%q{release_tracked_signal_exit_status_override=75})
  disable = helper.index(%q{capture_remote_operation disable-workflow})
  reset = helper.index(%q{release_tracked_signal_exit_status_override=""}, override)
  abort unless override && disable && override < disable && reset.nil?
  abort unless helper.include?(%q{normalize-json-line-item-pages})
  abort unless helper.include?(%q{normalize-workflow-run-pages})
  abort unless helper.include?(%q{input_sha256="$capture_sha256"})
  abort if helper.match?(/run_gh_to_new_file|digest-private-capture|CAPTURE_FD/)
  abort unless helper.include?(%q{temporary_root="$(cd "$temporary_root" && pwd -P)"})
' "$helper"
pass

ruby -e '
  policy = File.read(ARGV.fetch(0))
  remote = policy[/  def remote_operation_arguments\b.*?^  end\n/m]
  abort unless remote
  operations = remote.scan(/^    when "([^"]+)"/).flatten
  expected_operations = %w[anchor-ref workflow workflow-content viewer repository v-tag-refs releases workflow-runs disable-workflow]
  abort unless operations == expected_operations
  abort unless remote.scan(/"--method", "PUT"/).length == 1
  abort if remote.match?(/"--method", "(?:POST|PATCH|DELETE)"/)
  fixed = %q{/repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable}
  abort unless remote.scan(fixed).length == 1
  abort if remote.match?(%r{/enable\b|/dispatches\b|/cancel\b})
  put = remote.lines.each_index.find { |index| remote.lines[index].include?(%q{"--method", "PUT"}) }
  abort unless put
  put_window = remote.lines[put, 5].join
  abort unless put_window.include?(%q{"--include"}) && put_window.include?(fixed)
  abort if put_window.match?(/(?:--input|--field|--raw-field|"-f"|"-F")/)
  abort unless policy.include?(%q{API_VERSION = "2026-03-10"})
  abort unless remote.include?(%q{?ref=#{expected_master}})
  abort unless remote.scan(/"--paginate"/).length == 3
  abort unless remote.scan(/\| @json/).length == 3
  abort if policy.match?(/`[^`]*`|Open3|\bsystem\s*\(|\bexec\s*\(/)
  abort unless policy.scan(/Process\.spawn\(/).length == 1
  abort if policy.match?(/\bpgroup:|Process\.setsid/)
  abort unless policy.include?(%q{source = STDIN.read(8_386)})
  abort if policy.include?(%q{ENV.delete(CAPTURE_SECRET_ENVIRONMENT)})
  abort unless policy.include?(%q{OpenSSL::HMAC.hexdigest("SHA256", key, payload)})
  abort unless policy.include?(%q{CAPTURE_ATTESTATION_DOMAIN})
  abort unless policy.include?(%q{constant_time_equal?(supplied_mac, expected_mac)})
  abort unless policy.include?(%q{fail_policy unless argv.length == 9})
  abort unless policy.include?(%q{strict_json_file(plan_receipt_context, secure: true)})
  abort unless policy.include?(%q{validate_receipt_integrity(plan_receipt, expected_master, plan_digest_context)})
  abort unless policy.include?(%q{USING PLAN #{plan_digest_context}})
  abort unless policy.include?(%q{unsetenv_others: true})
  abort unless policy.include?(%q{"GH_PROMPT_DISABLED" => "1"})
  abort unless policy.include?(%q{"GH_NO_UPDATE_NOTIFIER" => "1"})
  abort unless policy.include?(%q{"GH_TELEMETRY" => "0"})
  abort unless policy.include?(%q{"DO_NOT_TRACK" => "1"})
  abort unless policy.include?(%q{"PATH" => "/usr/bin:/bin:/usr/sbin:/sbin"})
  abort unless policy.include?(%q{REMOTE_CONFIG_DIRECTORY = "/private/var/empty"})
  stream_hash = policy.index(%q{stream_digest.update(chunk)})
  stream_write = policy.index(%q{write_all(output_file, chunk)})
  attestation_write = policy.index(%q{write_private_json(attestation, body.merge("hmacSHA256" => mac))})
  readback_check = policy.index(%q{readback_digest.hexdigest == stream_sha256})
  abort unless stream_hash && stream_write && readback_check && attestation_write &&
    stream_hash < stream_write && stream_write < readback_check && readback_check < attestation_write
  abort unless policy.include?(%q{first_line&.match?(/\AHTTP\/(?:1\.1|2(?:\.0)?) 204(?: No Content)?\z/)})
  abort unless policy.include?(%q{separator.match?(/\A\r?\n\r?\n\z/) && body.empty?})
  abort unless policy.include?(%q{unless succeeded || created_identity.nil?})
  abort unless policy.include?(%q{File.unlink(path) if [current.dev, current.ino] == created_identity})
  abort unless policy.include?(%q{File::RDONLY | File::NOFOLLOW})
  abort unless policy.include?(%q{File::RDWR | File::CREAT | File::EXCL | File::NOFOLLOW})
  abort unless policy.include?(%q{[stat.dev, stat.ino, stat.mode, stat.nlink, stat.size, stat.mtime.to_r, stat.ctime.to_r]})
  abort unless policy.include?(%q{[stat.dev, stat.ino, stat.mode, stat.uid, stat.nlink]})
  abort unless policy.include?(%q{output_file.sync = true}) &&
    policy.include?(%q{output_file.fsync}) && policy.include?(%q{output_file.rewind})
  abort unless policy.include?(%q{Digest::SHA256.hexdigest(bytes) == validate_sha256(expected_sha256)})
  abort if policy.include?(%q{File.binread(path)})
  abort unless policy.include?(%q{fail_policy if pages.empty?})
  abort unless policy.include?(%q{exact_keys(page, %w[items])})
' "$policy"
pass

printf 'Legacy workflow containment checks passed: %d assertions.\n' "$assertions"
