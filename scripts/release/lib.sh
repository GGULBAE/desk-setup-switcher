#!/usr/bin/env bash

set -euo pipefail

RELEASE_SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$RELEASE_SCRIPTS_DIR/../lib/common.sh"

release_die() {
    printf 'Release tooling error: %s\n' "$1" >&2
    exit 1
}

release_require_command() {
    command -v "$1" >/dev/null 2>&1 || release_die "Required command is unavailable: $1"
}

release_require_env() {
    local name="$1"
    [[ -n "${!name:-}" ]] || release_die "Required release input is missing: $name"
}

release_require_single_line() {
    local name="$1"
    local value="${!name:-}"
    [[ -n "$value" && "$value" != *$'\n'* && "$value" != *$'\r'* ]] || {
        release_die "$name must be a non-empty single-line value."
    }
}

release_sha256() {
    shasum -a 256 "$1" | awk '{print $1}'
}

release_require_execution_context() {
    [[ "${DESK_SETUP_RELEASE_MUTATIONS:-}" == 1 ]] || {
        release_die "Release mutations require DESK_SETUP_RELEASE_MUTATIONS=1."
    }
    [[ "${GITHUB_ACTIONS:-}" == true ]] || {
        release_die "Identity signing and notarization are restricted to GitHub Actions."
    }
    [[ "${GITHUB_EVENT_NAME:-}" == workflow_dispatch ]] || {
        release_die "Release candidates require a reviewed workflow_dispatch run."
    }
    [[ "${GITHUB_REF_TYPE:-}" == tag ]] || {
        release_die "Release candidates must run from an existing tag ref."
    }
    [[ "${RELEASE_PROTECTED_ENVIRONMENT:-}" == release-candidate ]] || {
        release_die "The release-candidate environment marker is missing."
    }
    [[ "${GITHUB_REPOSITORY:-}" == GGULBAE/desk-setup-switcher ]] || {
        release_die "Unexpected GitHub repository identity."
    }
    release_require_env RUNNER_TEMP
    release_require_env GITHUB_RUN_ID
}

release_require_path_within() {
    local path="$1"
    local parent="$2"
    local resolved_parent resolved_path
    resolved_parent="$(cd "$parent" && pwd -P)"
    resolved_path="$(cd "$(dirname "$path")" && pwd -P)/$(basename "$path")"
    case "$resolved_path" in
        "$resolved_parent"/*) ;;
        *) release_die "Release path escapes its allowed directory." ;;
    esac
}

release_require_absent_path() {
    local path="$1"
    [[ ! -e "$path" && ! -L "$path" ]] || {
        release_die "Release output path already exists."
    }
}

release_active_child_pid=""

release_process_tree_alive() {
    local child_pid="$1"
    kill -0 -- "-$child_pid" >/dev/null 2>&1 \
        || kill -0 "$child_pid" >/dev/null 2>&1
}

release_signal_process_tree() {
    local signal_name="$1"
    local child_pid="$2"
    kill -"$signal_name" -- "-$child_pid" >/dev/null 2>&1 \
        || kill -"$signal_name" "$child_pid" >/dev/null 2>&1 \
        || true
}

release_stop_active_child() {
    local child_pid="${release_active_child_pid:-}"
    local _attempt
    [[ -n "$child_pid" ]] || return 0

    release_signal_process_tree TERM "$child_pid"
    for _attempt in {1..20}; do
        release_process_tree_alive "$child_pid" || break
        sleep 0.05
    done
    if release_process_tree_alive "$child_pid"; then
        release_signal_process_tree KILL "$child_pid"
    fi
    wait "$child_pid" >/dev/null 2>&1 || true
    for _attempt in {1..20}; do
        release_process_tree_alive "$child_pid" || break
        sleep 0.05
    done
    if release_process_tree_alive "$child_pid"; then
        return 1
    fi
    release_active_child_pid=""
}

release_terminate_with_child() {
    local exit_status="$1"
    trap - INT TERM
    release_stop_active_child || true
    exit "$exit_status"
}

release_install_exit_signal_traps() {
    trap 'release_terminate_with_child 130' INT
    trap 'release_terminate_with_child 143' TERM
}

release_run_tracked() {
    local child_status child_pid
    ruby -e 'Process.setsid; exec(*ARGV)' "$@" &
    child_pid=$!
    release_active_child_pid="$child_pid"
    if wait "$child_pid"; then
        child_status=0
    else
        child_status=$?
    fi
    release_active_child_pid=""
    return "$child_status"
}

release_sanitize_json() {
    local input="$1"
    local output="$2"
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" sanitize-json \
        --json "$input" \
        --output "$output" \
        --repository "$ROOT_DIR" \
        --home "${HOME:-}" \
        --runner-temp "${RUNNER_TEMP:-}" >/dev/null
}

release_sanitize_text() {
    local input="$1"
    local output="$2"
    ruby -e '
      input, output, root, home, runner_temp = ARGV
      text = File.read(input)
      replacements = [[root, "$REPOSITORY"], [home, "$HOME"], [runner_temp, "$RUNNER_TEMP"]]
        .select { |from, _to| !from.nil? && !from.empty? }
        .each_with_index
        .sort_by { |((from, _to), index)| [-from.bytesize, index] }
        .map(&:first)
      replacements.each do |from, to|
        text = text.gsub(from, to) unless from.nil? || from.empty?
      end
      File.write(output, text.end_with?("\n") ? text : text + "\n", mode: "w", perm: 0o644)
    ' "$input" "$output" "$ROOT_DIR" "${HOME:-}" "${RUNNER_TEMP:-}"
}
