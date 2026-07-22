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
    local protected_environment="${1:-release-candidate}"
    [[ "$protected_environment" == release-candidate \
        || "$protected_environment" == release-publication ]] || {
        release_die "Unexpected protected release environment policy."
    }
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
    [[ "${RELEASE_PROTECTED_ENVIRONMENT:-}" == "$protected_environment" ]] || {
        release_die "The protected release environment marker is missing or incorrect."
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

release_verify_first_parent_commit_once() {
    local repository="$1"
    local history_tip="$2"
    local expected_commit="$3"

    [[ -d "$repository" && ! -L "$repository" \
        && "$history_tip" =~ ^[0-9a-f]{40}$ \
        && "$expected_commit" =~ ^[0-9a-f]{40}$ ]] || return 1
    git -C "$repository" rev-list --first-parent "$history_tip" 2>/dev/null \
        | ruby -e '
          expected = ARGV.fetch(0)
          rows = STDIN.each_line(chomp: true).to_a
          raise unless rows.count(expected) == 1
        ' "$expected_commit" >/dev/null 2>&1
}

release_verify_predecessor_pre_tag_evidence_chain() {
    local release_tag="$1"
    local tag_commit="$2"
    local tag_object="$3"
    local history_tip="$4"
    local evidence_path introduction_commits introduction_commit parent_row
    local introduction_diff introduction_tree tip_tree evidence_digest
    local critical_path tag_tree tip_critical_tree
    local candidate_workflow_blob ci_workflow_blob publication_workflow_blob legacy_workflow_blob
    local repository_root validation_parent validation_root validation_status
    evidence_path="docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json"

    [[ "$release_tag" == v0.0.9 && "$tag_commit" =~ ^[0-9a-f]{40}$ \
        && "$tag_object" =~ ^[0-9a-f]{40}$ && "$history_tip" =~ ^[0-9a-f]{40}$ ]] \
        || return 1
    repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
    [[ "$(git rev-parse "refs/tags/$release_tag" 2>/dev/null)" == "$tag_object" \
        && "$(git cat-file -t "$tag_object" 2>/dev/null)" == tag \
        && "$(git rev-parse "refs/tags/$release_tag^{commit}" 2>/dev/null)" == "$tag_commit" ]] \
        || return 1
    git merge-base --is-ancestor "$tag_commit" "$history_tip" || return 1
    introduction_commits="$(git log --full-history --format=%H --reverse \
        "$tag_commit..$history_tip" -- "$evidence_path")" || return 1
    introduction_commit="$(ruby -e '
      rows = ARGV.fetch(0).split("\n", -1)
      rows.pop if rows.last == ""
      raise unless rows.length == 1 && rows.fetch(0).match?(/\A[0-9a-f]{40}\z/)
      puts rows.fetch(0)
    ' "$introduction_commits" 2>/dev/null)" || return 1
    parent_row="$(git rev-list --parents -n 1 "$introduction_commit")" || return 1
    [[ "$parent_row" == "$introduction_commit $tag_commit" ]] || return 1
    release_verify_first_parent_commit_once \
        "$repository_root" "$history_tip" "$introduction_commit" || return 1
    introduction_diff="$(git diff-tree --no-commit-id --name-status -r \
        "$tag_commit" "$introduction_commit")" || return 1
    [[ "$introduction_diff" == $'A\t'"$evidence_path" ]] || return 1
    introduction_tree="$(git ls-tree "$introduction_commit" -- "$evidence_path")" || return 1
    [[ "$introduction_tree" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' \
        && "${introduction_tree#*$'\t'}" == "$evidence_path" ]] || return 1
    tip_tree="$(git ls-tree "$history_tip" -- "$evidence_path")" || return 1
    [[ "$tip_tree" == "$introduction_tree" ]] || return 1
    for critical_path in .github/workflows scripts/release; do
        tag_tree="$(git rev-parse "$tag_commit:$critical_path")" || return 1
        tip_critical_tree="$(git rev-parse "$history_tip:$critical_path")" || return 1
        [[ "$tag_tree" =~ ^[0-9a-f]{40}$ && "$tip_critical_tree" == "$tag_tree" ]] \
            || return 1
    done
    evidence_digest="$(git show "$introduction_commit:$evidence_path" \
        | shasum -a 256 | awk '{print $1}')" || return 1
    [[ "$evidence_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    git cat-file -p "$tag_object" | ruby -e '
      digest = ARGV.fetch(0)
      _headers, separator, message = STDIN.read.partition("\n\n")
      expected = "remote-controls-predecessor-pre-tag-sha256: #{digest}\n"
      raise unless separator == "\n\n" && message == expected
    ' "$evidence_digest" >/dev/null 2>&1 || return 1

    candidate_workflow_blob="$(git rev-parse \
        "$tag_commit:.github/workflows/signed-release-candidate.yml")" || return 1
    ci_workflow_blob="$(git rev-parse "$tag_commit:.github/workflows/ci.yml")" || return 1
    publication_workflow_blob="$(git rev-parse \
        "$tag_commit:.github/workflows/publish-release.yml")" || return 1
    legacy_workflow_blob="$(git rev-parse \
        "$tag_commit:.github/workflows/release.yml")" || return 1
    [[ "$candidate_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$ci_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$publication_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$legacy_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || return 1

    validation_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    [[ -d "$validation_parent" && ! -L "$validation_parent" ]] || return 1
    validation_root="$(mktemp -d \
        "$validation_parent/desk-setup-predecessor-evidence-validation.XXXXXX")" || return 1
    chmod 0700 "$validation_root" || {
        rm -rf -- "$validation_root" >/dev/null 2>&1 || true
        return 1
    }
    validation_status=0
    git show "$tag_commit:scripts/release/remote_controls_policy.rb" \
        >"$validation_root/remote_controls_policy.rb" || validation_status=1
    git show "$tag_commit:scripts/release/release_policy.rb" \
        >"$validation_root/release_policy.rb" || validation_status=1
    git show "$tag_commit:scripts/release/remote-controls-policy.json" \
        >"$validation_root/policy.json" || validation_status=1
    git show "$introduction_commit:$evidence_path" \
        >"$validation_root/evidence.json" || validation_status=1
    if [[ "$validation_status" == 0 ]]; then
        ruby "$validation_root/remote_controls_policy.rb" \
            --policy "$validation_root/policy.json" \
            --evidence "$validation_root/evidence.json" \
            --expected-phase predecessor-pre-tag \
            --expected-commit "$tag_commit" \
            --expected-workflow-blob "$candidate_workflow_blob" \
            --expected-ci-workflow-blob "$ci_workflow_blob" \
            --expected-publication-workflow-blob "$publication_workflow_blob" \
            --expected-legacy-workflow-blob "$legacy_workflow_blob" \
            >/dev/null 2>&1 || validation_status=1
    fi
    rm -rf -- "$validation_root" >/dev/null 2>&1 || validation_status=1
    [[ "$validation_status" == 0 ]]
}

release_verify_final_pre_tag_evidence_chain() {
    local release_tag="$1"
    local tag_commit="$2"
    local tag_object="$3"
    local history_tip="$4"
    local evidence_path introduction_commits introduction_commit parent_row
    local introduction_diff introduction_tree tip_tree evidence_digest
    local critical_path tag_tree tip_critical_tree predecessor_critical_tree
    local candidate_workflow_blob ci_workflow_blob publication_workflow_blob
    local legacy_workflow_blob predecessor_workflow_blob predecessor_ci_workflow_blob
    local predecessor_publication_workflow_blob predecessor_legacy_workflow_blob
    local predecessor_tag predecessor_tag_object predecessor_commit predecessor_evidence_path
    local predecessor_evidence_digest predecessor_introduction_commits
    local predecessor_introduction_commit predecessor_parent_row predecessor_introduction_diff
    local predecessor_introduction_tree predecessor_tag_tree predecessor_tip_tree
    local repository_root validation_parent validation_root validation_status
    local candidate_manual_path publication_manual_path manual_path manual_tree
    local manual_contract_fields manual_operator_id manual_operator_login manual_collected_at

    if [[ "$release_tag" == v0.0.9 ]]; then
        release_verify_predecessor_pre_tag_evidence_chain \
            "$release_tag" "$tag_commit" "$tag_object" "$history_tip"
        return $?
    fi

    evidence_path="docs/evidence/releases/$release_tag/remote-controls-final-pre-tag.json"
    predecessor_tag="v0.0.9"
    predecessor_evidence_path="docs/evidence/releases/$release_tag/remote-controls-predecessor-pre-tag.json"
    candidate_manual_path="docs/evidence/releases/$release_tag/release-candidate-admin-bypass.json"
    publication_manual_path="docs/evidence/releases/$release_tag/release-publication-admin-token-scope.json"

    [[ "$release_tag" == v0.1.0 && "$tag_commit" =~ ^[0-9a-f]{40}$ \
        && "$tag_object" =~ ^[0-9a-f]{40}$ && "$history_tip" =~ ^[0-9a-f]{40}$ ]] || return 1
    repository_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
    git merge-base --is-ancestor "$tag_commit" "$history_tip" || return 1
    predecessor_tag_object="$(git rev-parse "refs/tags/$predecessor_tag")" || return 1
    [[ "$predecessor_tag_object" =~ ^[0-9a-f]{40}$ \
        && "$(git cat-file -t "$predecessor_tag_object")" == tag ]] || return 1
    predecessor_commit="$(git rev-parse "refs/tags/$predecessor_tag^{commit}")" || return 1
    [[ "$predecessor_commit" =~ ^[0-9a-f]{40}$ ]] || return 1
    git merge-base --is-ancestor "$predecessor_commit" "$tag_commit" || return 1
    predecessor_introduction_commits="$(git log --full-history --format=%H --reverse \
        "$predecessor_commit..$tag_commit" -- "$predecessor_evidence_path")" || return 1
    predecessor_introduction_commit="$(ruby -e '
      rows = ARGV.fetch(0).split("\n", -1)
      rows.pop if rows.last == ""
      raise unless rows.length == 1 && rows.fetch(0).match?(/\A[0-9a-f]{40}\z/)
      puts rows.fetch(0)
    ' "$predecessor_introduction_commits" 2>/dev/null)" || return 1
    predecessor_parent_row="$(git rev-list --parents -n 1 "$predecessor_introduction_commit")" \
        || return 1
    [[ "$predecessor_parent_row" == \
        "$predecessor_introduction_commit $predecessor_commit" ]] || return 1
    release_verify_first_parent_commit_once \
        "$repository_root" "$tag_commit" "$predecessor_introduction_commit" || return 1
    predecessor_introduction_diff="$(git diff-tree --no-commit-id --name-status -r \
        "$predecessor_commit" "$predecessor_introduction_commit")" || return 1
    [[ "$predecessor_introduction_diff" == $'A\t'"$predecessor_evidence_path" ]] || return 1
    predecessor_introduction_tree="$(git ls-tree "$predecessor_introduction_commit" -- \
        "$predecessor_evidence_path")" || return 1
    [[ "$predecessor_introduction_tree" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' ]] || return 1
    predecessor_tag_tree="$(git ls-tree "$tag_commit" -- "$predecessor_evidence_path")" || return 1
    [[ "$predecessor_tag_tree" == "$predecessor_introduction_tree" ]] || return 1
    predecessor_tip_tree="$(git ls-tree "$history_tip" -- "$predecessor_evidence_path")" || return 1
    [[ "$predecessor_tip_tree" == "$predecessor_introduction_tree" ]] || return 1
    predecessor_evidence_digest="$(git show \
        "$predecessor_introduction_commit:$predecessor_evidence_path" \
        | shasum -a 256 | awk '{print $1}')" || return 1
    [[ "$predecessor_evidence_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    git cat-file -p "$predecessor_tag_object" | ruby -e '
      digest = ARGV.fetch(0)
      _headers, separator, message = STDIN.read.partition("\n\n")
      expected = "remote-controls-predecessor-pre-tag-sha256: #{digest}\n"
      raise unless separator == "\n\n" && message == expected
    ' "$predecessor_evidence_digest" >/dev/null 2>&1 || return 1
    introduction_commits="$(git log --full-history --format=%H --reverse \
        "$tag_commit..$history_tip" -- "$evidence_path")" || return 1
    introduction_commit="$(ruby -e '
      rows = ARGV.fetch(0).split("\n", -1)
      rows.pop if rows.last == ""
      raise unless rows.length == 1 && rows.fetch(0).match?(/\A[0-9a-f]{40}\z/)
      puts rows.fetch(0)
    ' "$introduction_commits" 2>/dev/null)" || return 1
    parent_row="$(git rev-list --parents -n 1 "$introduction_commit")" || return 1
    [[ "$parent_row" == "$introduction_commit $tag_commit" ]] || return 1
    release_verify_first_parent_commit_once \
        "$repository_root" "$history_tip" "$introduction_commit" || return 1
    introduction_diff="$(git diff-tree --no-commit-id --name-status -r \
        "$tag_commit" "$introduction_commit")" || return 1
    [[ "$introduction_diff" == $'A\t'"$evidence_path" ]] || return 1
    introduction_tree="$(git ls-tree "$introduction_commit" -- "$evidence_path")" || return 1
    [[ "$introduction_tree" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' ]] || return 1
    [[ "${introduction_tree#*$'\t'}" == "$evidence_path" ]] || return 1
    tip_tree="$(git ls-tree "$history_tip" -- "$evidence_path")" || return 1
    [[ "$tip_tree" == "$introduction_tree" ]] || return 1
    for critical_path in .github/workflows scripts/release; do
        tag_tree="$(git rev-parse "$tag_commit:$critical_path")" || return 1
        tip_critical_tree="$(git rev-parse "$history_tip:$critical_path")" || return 1
        predecessor_critical_tree="$(git rev-parse "$predecessor_commit:$critical_path")" \
            || return 1
        [[ "$tag_tree" =~ ^[0-9a-f]{40}$ && "$tip_critical_tree" == "$tag_tree" \
            && "$predecessor_critical_tree" == "$tag_tree" ]] || return 1
    done
    evidence_digest="$(git show "$introduction_commit:$evidence_path" \
        | shasum -a 256 | awk '{print $1}')" || return 1
    [[ "$evidence_digest" =~ ^[0-9a-f]{64}$ ]] || return 1
    git cat-file -p "$tag_object" | ruby -e '
      digest = ARGV.fetch(0)
      _headers, separator, message = STDIN.read.partition("\n\n")
      expected = "remote-controls-final-pre-tag-sha256: #{digest}\n"
      raise unless separator == "\n\n" && message == expected
    ' "$evidence_digest" >/dev/null 2>&1 || return 1

    candidate_workflow_blob="$(git rev-parse \
        "$tag_commit:.github/workflows/signed-release-candidate.yml")" || return 1
    ci_workflow_blob="$(git rev-parse "$tag_commit:.github/workflows/ci.yml")" || return 1
    publication_workflow_blob="$(git rev-parse \
        "$tag_commit:.github/workflows/publish-release.yml")" || return 1
    legacy_workflow_blob="$(git rev-parse \
        "$tag_commit:.github/workflows/release.yml")" || return 1
    predecessor_workflow_blob="$(git rev-parse \
        "$predecessor_commit:.github/workflows/signed-release-candidate.yml")" || return 1
    predecessor_ci_workflow_blob="$(git rev-parse \
        "$predecessor_commit:.github/workflows/ci.yml")" || return 1
    predecessor_publication_workflow_blob="$(git rev-parse \
        "$predecessor_commit:.github/workflows/publish-release.yml")" || return 1
    predecessor_legacy_workflow_blob="$(git rev-parse \
        "$predecessor_commit:.github/workflows/release.yml")" || return 1
    [[ "$candidate_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$ci_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$publication_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$legacy_workflow_blob" =~ ^[0-9a-f]{40}$ \
        && "$predecessor_workflow_blob" == "$candidate_workflow_blob" \
        && "$predecessor_ci_workflow_blob" == "$ci_workflow_blob" \
        && "$predecessor_publication_workflow_blob" == "$publication_workflow_blob" \
        && "$predecessor_legacy_workflow_blob" == "$legacy_workflow_blob" ]] || return 1

    validation_parent="${RUNNER_TEMP:-${TMPDIR:-/tmp}}"
    [[ -d "$validation_parent" && ! -L "$validation_parent" ]] || return 1
    validation_root="$(mktemp -d \
        "$validation_parent/desk-setup-final-evidence-validation.XXXXXX")" || return 1
    chmod 0700 "$validation_root" || {
        rm -rf -- "$validation_root" >/dev/null 2>&1 || true
        return 1
    }
    validation_status=0
    git show "$tag_commit:scripts/release/remote_controls_policy.rb" \
        >"$validation_root/remote_controls_policy.rb" || validation_status=1
    git show "$tag_commit:scripts/release/release_policy.rb" \
        >"$validation_root/release_policy.rb" || validation_status=1
    git show "$tag_commit:scripts/release/collect_remote_controls_evidence.rb" \
        >"$validation_root/collect_remote_controls_evidence.rb" || validation_status=1
    git show "$tag_commit:scripts/release/remote-controls-policy.json" \
        >"$validation_root/policy.json" || validation_status=1
    git show "$introduction_commit:$evidence_path" \
        >"$validation_root/evidence.json" || validation_status=1
    git show "$predecessor_introduction_commit:$predecessor_evidence_path" \
        >"$validation_root/predecessor-evidence.json" || validation_status=1
    for manual_path in "$candidate_manual_path" "$publication_manual_path"; do
        manual_tree="$(git ls-tree "$tag_commit" -- "$manual_path")" || validation_status=1
        [[ "$manual_tree" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' \
            && "${manual_tree#*$'\t'}" == "$manual_path" ]] || validation_status=1
    done
    git show "$tag_commit:$candidate_manual_path" \
        >"$validation_root/candidate-manual.json" || validation_status=1
    git show "$tag_commit:$publication_manual_path" \
        >"$validation_root/publication-manual.json" || validation_status=1
    if [[ "$validation_status" == 0 ]]; then
        ruby "$validation_root/remote_controls_policy.rb" \
            --policy "$validation_root/policy.json" \
            --evidence "$validation_root/predecessor-evidence.json" \
            --expected-phase predecessor-pre-tag \
            --expected-commit "$predecessor_commit" \
            --expected-workflow-blob "$predecessor_workflow_blob" \
            --expected-ci-workflow-blob "$predecessor_ci_workflow_blob" \
            --expected-publication-workflow-blob "$predecessor_publication_workflow_blob" \
            --expected-legacy-workflow-blob "$predecessor_legacy_workflow_blob" \
            >/dev/null 2>&1 || validation_status=1
    fi
    if [[ "$validation_status" == 0 ]]; then
        ruby "$validation_root/remote_controls_policy.rb" \
            --policy "$validation_root/policy.json" \
            --evidence "$validation_root/evidence.json" \
            --expected-phase final-pre-tag \
            --expected-commit "$tag_commit" \
            --expected-workflow-blob "$candidate_workflow_blob" \
            --expected-ci-workflow-blob "$ci_workflow_blob" \
            --expected-publication-workflow-blob "$publication_workflow_blob" \
            --expected-legacy-workflow-blob "$legacy_workflow_blob" \
            --expected-predecessor-commit "$predecessor_commit" \
            --expected-predecessor-tag-object "$predecessor_tag_object" \
            --expected-predecessor-pre-tag-evidence-sha256 "$predecessor_evidence_digest" \
            >/dev/null 2>&1 || validation_status=1
    fi
    if [[ "$validation_status" == 0 ]]; then
        ruby "$validation_root/remote_controls_policy.rb" \
            --publication-approval-contract "$validation_root/policy.json" \
            >"$validation_root/publication-contract.json" 2>/dev/null || validation_status=1
        manual_contract_fields="$(ruby -rjson -rtime -e '
          contract_path, evidence_path = ARGV
          contract = JSON.parse(File.binread(contract_path), allow_nan: false, create_additions: false)
          evidence = JSON.parse(File.binread(evidence_path), allow_nan: false, create_additions: false)
          operator = contract.fetch("operator")
          collected_text = evidence.fetch("collectedAt")
          collected = Time.iso8601(collected_text)
          raise unless collected_text == collected.utc.iso8601
          fields = [operator.fetch("id"), operator.fetch("login"), collected_text]
          raise if fields.any? { |field| field.to_s.match?(/[\t\r\n]/) }
          puts fields.join("\t")
        ' "$validation_root/publication-contract.json" "$validation_root/evidence.json" \
            2>/dev/null)" || validation_status=1
    fi
    if [[ "$validation_status" == 0 ]]; then
        IFS=$'\t' read -r manual_operator_id manual_operator_login manual_collected_at \
            <<<"$manual_contract_fields"
        ruby "$validation_root/collect_remote_controls_evidence.rb" manual-evidence \
            --input "$validation_root/candidate-manual.json" \
            --control release-candidate-administrator-bypass-disabled \
            --permission-profile candidate \
            --actor-id "$manual_operator_id" \
            --actor-login "$manual_operator_login" \
            --verified-at "$manual_collected_at" \
            --phase final-pre-tag \
            --freshness-mode current \
            >"$validation_root/candidate-result.json" 2>/dev/null || validation_status=1
        ruby "$validation_root/collect_remote_controls_evidence.rb" manual-evidence \
            --input "$validation_root/publication-manual.json" \
            --control release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope \
            --permission-profile publication \
            --actor-id "$manual_operator_id" \
            --actor-login "$manual_operator_login" \
            --verified-at "$manual_collected_at" \
            --phase final-pre-tag \
            --freshness-mode current \
            >"$validation_root/publication-result.json" 2>/dev/null || validation_status=1
    fi
    if [[ "$validation_status" == 0 ]]; then
        ruby -rjson -e '
          evidence_path, *result_paths = ARGV
          evidence = JSON.parse(File.binread(evidence_path), allow_nan: false, create_additions: false)
          expected = evidence.fetch("manualEvidence").fetch("items")
          actual = result_paths.map do |path|
            JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
          end
          raise unless actual.map { |row| row.fetch("control") } ==
            expected.map { |row| row.fetch("control") }
          raise unless actual.map { |row| row.fetch("sha256") } ==
            expected.map { |row| row.fetch("sha256") }
          raise unless actual.map { |row| row.fetch("sourceArtifactSHA256") }.uniq.length == 2
        ' "$validation_root/evidence.json" "$validation_root/candidate-result.json" \
            "$validation_root/publication-result.json" >/dev/null 2>&1 || validation_status=1
    fi
    rm -rf -- "$validation_root" >/dev/null 2>&1 || validation_status=1
    [[ "$validation_status" == 0 ]]
}

release_active_child_pid=""
release_active_launch_root=""

release_cleanup_active_launch_root() {
    local launch_root="${release_active_launch_root:-}"
    local cleanup_status=0
    [[ -n "$launch_root" ]] || return 0
    case "$launch_root" in
        "$RUNNER_TEMP"/desk-setup-tracked-launch.*) ;;
        *) return 1 ;;
    esac
    rm -f -- "$launch_root/go" >/dev/null 2>&1 || cleanup_status=1
    if ! rmdir "$launch_root" >/dev/null 2>&1; then
        # A tracked command must never add another entry here. Remove the
        # already-private, prefix-validated root without following an entry
        # symlink, but retain a failure result so the attempt is not trusted.
        rm -rf -- "$launch_root" >/dev/null 2>&1 || cleanup_status=1
        cleanup_status=1
    fi
    if [[ -e "$launch_root" || -L "$launch_root" ]]; then
        return 1
    fi
    release_active_launch_root=""
    return "$cleanup_status"
}

release_process_tree_alive() {
    local child_pid="$1"
    kill -0 -- "-$child_pid" >/dev/null 2>&1 \
        || kill -0 "$child_pid" >/dev/null 2>&1
}

release_process_group_alive() {
    local child_pid="$1"
    kill -0 -- "-$child_pid" >/dev/null 2>&1
}

release_stop_lingering_group() {
    local child_pid="$1"
    local _attempt
    release_process_group_alive "$child_pid" || return 0
    kill -TERM -- "-$child_pid" >/dev/null 2>&1 || true
    for _attempt in {1..20}; do
        release_process_group_alive "$child_pid" || return 0
        sleep 0.05
    done
    kill -KILL -- "-$child_pid" >/dev/null 2>&1 || true
    for _attempt in {1..20}; do
        release_process_group_alive "$child_pid" || return 0
        sleep 0.05
    done
    return 1
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
    if [[ -z "$child_pid" ]]; then
        release_cleanup_active_launch_root
        return $?
    fi

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
    release_cleanup_active_launch_root
}

release_terminate_with_child() {
    local exit_status="$1"
    trap '' HUP INT QUIT TERM
    release_stop_active_child || true
    exit "$exit_status"
}

release_install_exit_signal_traps() {
    trap 'release_terminate_with_child 129' HUP
    trap 'release_terminate_with_child 130' INT
    trap 'release_terminate_with_child 131' QUIT
    trap 'release_terminate_with_child 143' TERM
}

release_restore_signal_trap() {
    local signal_name="$1"
    local saved_trap="$2"
    if [[ -n "$saved_trap" ]]; then
        eval "$saved_trap"
    else
        trap - "$signal_name"
    fi
}

release_restore_signal_traps() {
    release_restore_signal_trap HUP "$1"
    release_restore_signal_trap INT "$2"
    release_restore_signal_trap QUIT "$3"
    release_restore_signal_trap TERM "$4"
}

release_run_tracked_internal() {
    local secret_transport="$1"
    local environment_name="$2"
    local secret_value="$3"
    local timeout_seconds="$4"
    local launch_root launch_gate child_status child_pid parent_pid cleanup_status
    local saved_hup_trap saved_int_trap saved_quit_trap saved_term_trap
    local tracked_hup_status=129 tracked_int_status=130
    local tracked_quit_status=131 tracked_term_status=143
    local signal_status_override="${release_tracked_signal_exit_status_override:-}"
    local deferred_signal_status=0
    shift 4
    [[ -n "${RUNNER_TEMP:-}" && -d "$RUNNER_TEMP" && ! -L "$RUNNER_TEMP" ]] || return 70
    [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -le 3600 ]] || return 70
    parent_pid="${BASHPID:-$$}"
    [[ "$parent_pid" =~ ^[1-9][0-9]*$ ]] || return 70
    case "$secret_transport" in
        none)
            [[ -z "$environment_name" && -z "$secret_value" ]] || return 70
            ;;
        environment)
            [[ "$environment_name" =~ ^[A-Z_][A-Z0-9_]*$ \
                && -n "$secret_value" ]] || return 70
            ;;
        stdin)
            [[ -z "$environment_name" && -n "$secret_value" ]] || return 70
            ;;
        *) return 70 ;;
    esac
    case "$signal_status_override" in
        "") ;;
        75)
            tracked_hup_status=75
            tracked_int_status=75
            tracked_quit_status=75
            tracked_term_status=75
            ;;
        *) return 70 ;;
    esac

    # Defer catchable cancellation while the launch directory and launcher PID
    # become one tracked unit. Without this narrow critical section, a signal
    # can land after mktemp creates the directory but before its path reaches
    # release_active_launch_root, leaving untracked private launch state.
    saved_hup_trap="$(trap -p HUP)"
    saved_int_trap="$(trap -p INT)"
    saved_quit_trap="$(trap -p QUIT)"
    saved_term_trap="$(trap -p TERM)"
    trap '[[ "$deferred_signal_status" -ne 0 ]] || deferred_signal_status=$tracked_hup_status' HUP
    trap '[[ "$deferred_signal_status" -ne 0 ]] || deferred_signal_status=$tracked_int_status' INT
    trap '[[ "$deferred_signal_status" -ne 0 ]] || deferred_signal_status=$tracked_quit_status' QUIT
    trap '[[ "$deferred_signal_status" -ne 0 ]] || deferred_signal_status=$tracked_term_status' TERM

    if ! launch_root="$(mktemp -d "$RUNNER_TEMP/desk-setup-tracked-launch.XXXXXX")"; then
        release_restore_signal_traps \
            "$saved_hup_trap" "$saved_int_trap" "$saved_quit_trap" "$saved_term_trap"
        [[ "$deferred_signal_status" -eq 0 ]] || release_terminate_with_child "$deferred_signal_status"
        return 70
    fi
    release_active_launch_root="$launch_root"
    if [[ "$deferred_signal_status" -ne 0 ]]; then
        release_terminate_with_child "$deferred_signal_status"
    fi
    chmod 0700 "$launch_root" || {
        release_cleanup_active_launch_root || true
        if [[ "$deferred_signal_status" -ne 0 ]]; then
            release_terminate_with_child "$deferred_signal_status"
        fi
        release_restore_signal_traps \
            "$saved_hup_trap" "$saved_int_trap" "$saved_quit_trap" "$saved_term_trap"
        return 70
    }
    launch_gate="$launch_root/go"
    [[ ! -e "$launch_gate" && ! -L "$launch_gate" ]] || {
        release_cleanup_active_launch_root || true
        if [[ "$deferred_signal_status" -ne 0 ]]; then
            release_terminate_with_child "$deferred_signal_status"
        fi
        release_restore_signal_traps \
            "$saved_hup_trap" "$saved_int_trap" "$saved_quit_trap" "$saved_term_trap"
        return 70
    }

    if [[ "$secret_transport" != none ]]; then
        # The left side is a shell builtin writing to an anonymous pipe. This
        # keeps the secret out of argv, exported environment, and filesystem
        # storage while preserving `$!` as the Ruby launcher's exact PID.
        { printf '%s\n' "$secret_value"; } | ruby -e '
          gate, expected_parent_text, timeout_text, secret_transport,
            environment_name, *command = ARGV
          expected_parent = Integer(expected_parent_text, 10)
          timeout_seconds = Integer(timeout_text, 10)
          raise unless %w[environment stdin].include?(secret_transport) &&
            timeout_seconds.between?(0, 3_600) && !command.empty?
          if secret_transport == "environment"
            raise unless environment_name.match?(/\A[A-Z_][A-Z0-9_]*\z/)
          else
            raise unless environment_name.empty?
          end
          secret = $stdin.read
          raise unless secret.end_with?("\n")
          secret = secret.delete_suffix("\n")
          raise if secret.empty? || secret.include?("\n") || secret.include?("\r")
          $stdin.reopen(File::NULL, "r")
          directory = File.lstat(File.dirname(gate))
          raise unless directory.directory? && !directory.symlink? &&
            directory.uid == Process.euid && (directory.mode & 0o777) == 0o700
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
          loop do
            exit!(75) unless Process.ppid == expected_parent
            begin
              Process.kill(0, expected_parent)
              stat = File.lstat(gate)
              bytes = File.binread(gate)
              expected = "#{expected_parent}\t#{Process.pid}\n"
              if stat.file? && !stat.symlink? && stat.nlink == 1 &&
                 stat.uid == Process.euid && (stat.mode & 0o777) == 0o600 && bytes == expected
                File.delete(gate)
                break
              end
              exit!(75)
            rescue Errno::ENOENT
              exit!(75) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              sleep 0.005
            rescue Errno::ESRCH
              exit!(75)
            end
          end
          exit!(75) unless Process.ppid == expected_parent
          Process.setsid
          if secret_transport == "environment"
            exec({ environment_name => secret }, *command) if timeout_seconds.zero?
            child_environment = { environment_name => secret }
            child = Process.spawn(child_environment, *command)
          else
            input_reader, input_writer = IO.pipe
            child_environment = {}
            child = Process.spawn(*command, in: input_reader)
            input_reader.close
            input_writer.write(secret + "\n")
            input_writer.close
          end
          secret.clear
          child_environment.clear
          if timeout_seconds.zero?
            status = Process.waitpid2(child).fetch(1)
            exit!(status.exitstatus || 128 + status.termsig)
          end
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
          loop do
            waited = Process.waitpid2(child, Process::WNOHANG)
            if waited
              status = waited.fetch(1)
              exit!(status.exitstatus || 128 + status.termsig)
            end
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 0.05
          end
          begin
            Process.kill("TERM", child)
          rescue Errno::ESRCH
          end
          20.times do
            waited = Process.waitpid2(child, Process::WNOHANG)
            exit!(124) if waited
            sleep 0.05
          end
          begin
            Process.kill("KILL", child)
          rescue Errno::ESRCH
          end
          begin
            Process.waitpid(child)
          rescue Errno::ECHILD
          end
          exit!(124)
        ' "$launch_gate" "$parent_pid" "$timeout_seconds" "$secret_transport" \
            "$environment_name" "$@" &
    else
        ruby -e '
          gate, expected_parent_text, timeout_text, *command = ARGV
          expected_parent = Integer(expected_parent_text, 10)
          timeout_seconds = Integer(timeout_text, 10)
          raise unless timeout_seconds.between?(0, 3_600) && !command.empty?
          directory = File.lstat(File.dirname(gate))
          raise unless directory.directory? && !directory.symlink? &&
            directory.uid == Process.euid && (directory.mode & 0o777) == 0o700
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
          loop do
            exit!(75) unless Process.ppid == expected_parent
            begin
              Process.kill(0, expected_parent)
              stat = File.lstat(gate)
              bytes = File.binread(gate)
              expected = "#{expected_parent}\t#{Process.pid}\n"
              if stat.file? && !stat.symlink? && stat.nlink == 1 &&
                 stat.uid == Process.euid && (stat.mode & 0o777) == 0o600 && bytes == expected
                File.delete(gate)
                break
              end
              exit!(75)
            rescue Errno::ENOENT
              exit!(75) if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              sleep 0.005
            rescue Errno::ESRCH
              exit!(75)
            end
          end
          exit!(75) unless Process.ppid == expected_parent
          Process.setsid
          exec(*command) if timeout_seconds.zero?
          child = Process.spawn(*command)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout_seconds
          loop do
            waited = Process.waitpid2(child, Process::WNOHANG)
            if waited
              status = waited.fetch(1)
              exit!(status.exitstatus || 128 + status.termsig)
            end
            break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
            sleep 0.05
          end
          begin
            Process.kill("TERM", child)
          rescue Errno::ESRCH
          end
          20.times do
            waited = Process.waitpid2(child, Process::WNOHANG)
            exit!(124) if waited
            sleep 0.05
          end
          begin
            Process.kill("KILL", child)
          rescue Errno::ESRCH
          end
          begin
            Process.waitpid(child)
          rescue Errno::ECHILD
          end
          exit!(124)
        ' "$launch_gate" "$parent_pid" "$timeout_seconds" "$@" &
    fi
    child_pid=$!
    release_active_child_pid="$child_pid"
    # While any launcher or launch root remains live, this helper owns
    # catchable cancellation even if its caller had a default, ignored, or
    # custom disposition. Caller dispositions are restored only after the
    # process tree and private launch state are fully gone.
    trap 'release_terminate_with_child "$tracked_hup_status"' HUP
    trap 'release_terminate_with_child "$tracked_int_status"' INT
    trap 'release_terminate_with_child "$tracked_quit_status"' QUIT
    trap 'release_terminate_with_child "$tracked_term_status"' TERM
    [[ "$deferred_signal_status" -eq 0 ]] || release_terminate_with_child "$deferred_signal_status"
    if ! (umask 077; set -o noclobber; printf '%s\t%s\n' "$parent_pid" "$child_pid" >"$launch_gate"); then
        release_stop_active_child || true
        if [[ -z "${release_active_child_pid:-}" && -z "${release_active_launch_root:-}" ]]; then
            release_restore_signal_traps \
                "$saved_hup_trap" "$saved_int_trap" "$saved_quit_trap" "$saved_term_trap"
        fi
        return 70
    fi
    if wait "$child_pid"; then
        child_status=0
    else
        child_status=$?
    fi
    if release_process_group_alive "$child_pid"; then
        if ! release_stop_lingering_group "$child_pid"; then
            return 70
        fi
        release_active_child_pid=""
        release_cleanup_active_launch_root || true
        release_restore_signal_traps \
            "$saved_hup_trap" "$saved_int_trap" "$saved_quit_trap" "$saved_term_trap"
        return 70
    fi
    release_active_child_pid=""
    cleanup_status=0
    release_cleanup_active_launch_root || cleanup_status=$?
    release_restore_signal_traps \
        "$saved_hup_trap" "$saved_int_trap" "$saved_quit_trap" "$saved_term_trap"
    [[ "$cleanup_status" -eq 0 ]] || return 70
    return "$child_status"
}

release_run_tracked() {
    release_run_tracked_internal none "" "" 0 "$@"
}

release_run_tracked_timeout() {
    local timeout_seconds="$1"
    shift
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ && "$timeout_seconds" -le 3600 ]] || return 70
    release_run_tracked_internal none "" "" "$timeout_seconds" "$@"
}

# Keep the secret out of the launcher's argv/environment. It crosses a private
# stream, is installed only after the parent publishes the PID-bound go gate,
# and the stream is replaced with /dev/null before the final exec.
release_run_tracked_secret_env() {
    local environment_name="$1"
    local secret_value="$2"
    shift 2
    release_run_tracked_internal environment "$environment_name" "$secret_value" 0 "$@"
}

release_run_tracked_secret_env_timeout() {
    local environment_name="$1"
    local secret_value="$2"
    local timeout_seconds="$3"
    shift 3
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ && "$timeout_seconds" -le 3600 ]] || return 70
    release_run_tracked_internal environment "$environment_name" "$secret_value" \
        "$timeout_seconds" "$@"
}

# Deliver a secret over an anonymous pipe to the tracked command's standard
# input. Unlike an environment transport, this does not place the value in the
# command's launch environment as reported by macOS process inspection.
release_run_tracked_secret_stdin() {
    local secret_value="$1"
    shift
    release_run_tracked_internal stdin "" "$secret_value" 0 "$@"
}

release_run_tracked_secret_stdin_timeout() {
    local secret_value="$1"
    local timeout_seconds="$2"
    shift 2
    [[ "$timeout_seconds" =~ ^[1-9][0-9]*$ && "$timeout_seconds" -le 3600 ]] || return 70
    release_run_tracked_internal stdin "" "$secret_value" "$timeout_seconds" "$@"
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
