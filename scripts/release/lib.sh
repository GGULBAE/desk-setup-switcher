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

release_sanitize_json() {
    local input="$1"
    local output="$2"
    ruby "$RELEASE_SCRIPTS_DIR/release_policy.rb" verify-json --json "$input" >/dev/null || return 1
    ruby -rjson -e '
      input, output, root, home, runner_temp = ARGV
      value = JSON.parse(File.read(input))
      replacements = [
        [root, "$REPOSITORY"],
        [home, "$HOME"],
        [runner_temp, "$RUNNER_TEMP"],
      ].reject { |from, _| from.nil? || from.empty? }
      sanitize = lambda do |item|
        case item
        when Hash
          item.to_h { |key, child| [key, sanitize.call(child)] }
        when Array
          item.map { |child| sanitize.call(child) }
        when String
          replacements.reduce(item) { |text, (from, to)| text.gsub(from, to) }
        else
          item
        end
      end
      File.write(output, JSON.pretty_generate(sanitize.call(value)) + "\n", mode: "w", perm: 0o644)
    ' "$input" "$output" "$ROOT_DIR" "${HOME:-}" "${RUNNER_TEMP:-}"
}

release_sanitize_text() {
    local input="$1"
    local output="$2"
    ruby -e '
      input, output, root, home, runner_temp = ARGV
      text = File.read(input)
      [[root, "$REPOSITORY"], [home, "$HOME"], [runner_temp, "$RUNNER_TEMP"]].each do |from, to|
        text = text.gsub(from, to) unless from.nil? || from.empty?
      end
      File.write(output, text.end_with?("\n") ? text : text + "\n", mode: "w", perm: 0o644)
    ' "$input" "$output" "$ROOT_DIR" "${HOME:-}" "${RUNNER_TEMP:-}"
}
