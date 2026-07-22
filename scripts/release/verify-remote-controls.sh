#!/usr/bin/env bash

set -euo pipefail
set +x
set +a
umask 077

github_token="${GH_TOKEN:-}"
export -n github_token 2>/dev/null || true
unset GH_TOKEN GITHUB_TOKEN GH_HOST GH_DEBUG DEBUG GH_ENTERPRISE_TOKEN \
    GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
source "$SCRIPT_DIR/lib.sh"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
POLICY_PATH="$SCRIPT_DIR/remote-controls-policy.json"
POLICY_VALIDATOR="$SCRIPT_DIR/remote_controls_policy.rb"
COLLECTOR="$SCRIPT_DIR/collect_remote_controls_evidence.rb"
WORKFLOW_PATH="$ROOT_DIR/.github/workflows/signed-release-candidate.yml"
LEGACY_WORKFLOW_PATH="$ROOT_DIR/.github/workflows/release.yml"
CI_WORKFLOW_PATH="$ROOT_DIR/.github/workflows/ci.yml"
PUBLICATION_WORKFLOW_PATH="$ROOT_DIR/.github/workflows/publish-release.yml"
REPOSITORY="GGULBAE/desk-setup-switcher"
PREDECESSOR_TAG="v0.0.9"
RELEASE_TAG="v0.1.0"
API_TIMEOUT_SECONDS=20
EVIDENCE_DIRECTORY="$ROOT_DIR/docs/evidence/releases/$RELEASE_TAG"
CANDIDATE_MANUAL_EVIDENCE="$EVIDENCE_DIRECTORY/release-candidate-admin-bypass.json"
PUBLICATION_MANUAL_EVIDENCE="$EVIDENCE_DIRECTORY/release-publication-admin-token-scope.json"
PRE_PUBLICATION_OUTPUT="$EVIDENCE_DIRECTORY/remote-controls-pre-publication.json"
PREDECESSOR_PRE_TAG_OUTPUT="$EVIDENCE_DIRECTORY/remote-controls-predecessor-pre-tag.json"
FINAL_PRE_TAG_OUTPUT="$EVIDENCE_DIRECTORY/remote-controls-final-pre-tag.json"

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

phase="final-pre-tag"
expected_predecessor_commit=""
expected_predecessor_tag_object=""
expected_release_commit=""
expected_release_id=""
expected_release_tag_object=""
evidence_output=""
show_usage() {
    cat <<'USAGE'
Usage:
  verify-remote-controls.sh --phase predecessor-pre-tag --evidence-output /absolute/private/remote-controls-predecessor-pre-tag.json
  verify-remote-controls.sh --phase final-pre-tag --predecessor-commit SHA --predecessor-tag-object SHA --evidence-output /absolute/private/remote-controls-final-pre-tag.json
  verify-remote-controls.sh --phase pre-publication --predecessor-commit SHA --predecessor-tag-object SHA --release-commit SHA --release-tag-object SHA --release-id ID

predecessor-pre-tag requires no v* ref or GitHub Release and produces the first
private chain link for a reviewed add-only commit. final-pre-tag requires only
the supplied immutable annotated v0.0.9 tag and no GitHub Release, binds that
committed first link, and preserves its normalized bytes outside the repository.
pre-publication requires the supplied annotated v0.0.9 and v0.1.0 refs plus the
sole draft prerelease v0.1.0, then writes the reviewed manifest at
docs/evidence/releases/v0.1.0/remote-controls-pre-publication.json.
Create publication-approval.json from that manifest digest and observed master,
then add only those two files in one direct-successor commit.
USAGE
}
while [[ "$#" -gt 0 ]]; do
    case "$1" in
        --phase)
            [[ "$#" -ge 2 ]] || policy_error
            phase="$2"
            shift 2
            ;;
        --release-commit)
            [[ "$#" -ge 2 && -z "$expected_release_commit" ]] || policy_error
            expected_release_commit="$2"
            shift 2
            ;;
        --predecessor-commit)
            [[ "$#" -ge 2 && -z "$expected_predecessor_commit" ]] || policy_error
            expected_predecessor_commit="$2"
            shift 2
            ;;
        --predecessor-tag-object)
            [[ "$#" -ge 2 && -z "$expected_predecessor_tag_object" ]] || policy_error
            expected_predecessor_tag_object="$2"
            shift 2
            ;;
        --release-tag-object)
            [[ "$#" -ge 2 && -z "$expected_release_tag_object" ]] || policy_error
            expected_release_tag_object="$2"
            shift 2
            ;;
        --release-id)
            [[ "$#" -ge 2 && -z "$expected_release_id" ]] || policy_error
            expected_release_id="$2"
            shift 2
            ;;
        --evidence-output)
            [[ "$#" -ge 2 && -z "$evidence_output" ]] || policy_error
            evidence_output="$2"
            shift 2
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *) policy_error ;;
    esac
done
case "$phase" in
    predecessor-pre-tag|final-pre-tag)
        if [[ "$phase" == predecessor-pre-tag ]]; then
            [[ -z "$expected_predecessor_commit" && -z "$expected_predecessor_tag_object" ]] \
                || policy_error
        else
            [[ "$expected_predecessor_commit" =~ ^[0-9a-f]{40}$ \
                && "$expected_predecessor_tag_object" =~ ^[0-9a-f]{40}$ ]] || policy_error
        fi
        [[ -z "$expected_release_commit" && -z "$expected_release_tag_object" \
            && -z "$expected_release_id" ]] || policy_error
        case "$evidence_output" in
            /*)
                evidence_output="$(ruby -e '
                  source, repository = ARGV
                  expanded = File.expand_path(source)
                  raise unless source == expanded && !source.match?(/[\r\n]/)
                  parent = File.dirname(expanded)
                  parent_stat = File.lstat(parent)
                  repository = File.realpath(repository)
                  parent_real = File.realpath(parent)
                  real_destination = File.join(parent_real, File.basename(expanded))
                  raise unless parent_stat.directory? && !parent_stat.symlink? &&
                    parent_stat.uid == Process.euid && (parent_stat.mode & 0o777) == 0o700
                  raise if real_destination == repository ||
                    real_destination.start_with?("#{repository}/")
                  raise if File.exist?(expanded) || File.symlink?(expanded)
                  puts real_destination
                ' "$evidence_output" "$ROOT_DIR" 2>/dev/null)" || policy_error ;;
            *) policy_error ;;
        esac
        ;;
    pre-publication)
        [[ "$expected_predecessor_commit" =~ ^[0-9a-f]{40}$ ]] || policy_error
        [[ "$expected_predecessor_tag_object" =~ ^[0-9a-f]{40}$ ]] || policy_error
        [[ "$expected_release_commit" =~ ^[0-9a-f]{40}$ ]] || policy_error
        [[ "$expected_release_tag_object" =~ ^[0-9a-f]{40}$ ]] || policy_error
        [[ "$expected_release_id" =~ ^[1-9][0-9]*$ ]] || policy_error
        [[ -z "$evidence_output" ]] || policy_error
        ;;
    *) policy_error ;;
esac
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
command -v shasum >/dev/null 2>&1 || internal_error
command -v awk >/dev/null 2>&1 || internal_error

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-remote-controls.XXXXXX" 2>/dev/null)" \
    || internal_error
chmod 0700 "$temporary_root" >/dev/null 2>&1 || {
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
    internal_error
}
RUNNER_TEMP="$temporary_root/tracked-runner"
gh_config_directory="$temporary_root/gh-config"
cleanup() {
    trap '' HUP INT QUIT TERM
    release_stop_active_child || true
    rm -rf -- "$temporary_root" >/dev/null 2>&1 || :
}
trap cleanup EXIT
release_install_exit_signal_traps
mkdir -m 0700 "$RUNNER_TEMP" "$gh_config_directory" >/dev/null 2>&1 || internal_error

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
expected_workflow_blob="$(git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/signed-release-candidate.yml' 2>/dev/null)" \
    || local_anchor_error
[[ "$expected_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_ci_workflow_blob="$(git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/ci.yml' 2>/dev/null)" \
    || local_anchor_error
[[ "$expected_ci_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_publication_workflow_blob="$(
    git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/publish-release.yml' 2>/dev/null
)" || local_anchor_error
[[ "$expected_publication_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_legacy_workflow_blob="$(
    git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/release.yml' 2>/dev/null
)" || local_anchor_error
[[ "$expected_legacy_workflow_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
expected_policy_blob="$(
    git -C "$ROOT_DIR" rev-parse 'HEAD:scripts/release/remote-controls-policy.json' 2>/dev/null
)" || local_anchor_error
[[ "$expected_policy_blob" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
working_workflow_blob="$(git -C "$ROOT_DIR" hash-object -- "$WORKFLOW_PATH" 2>/dev/null)" \
    || local_anchor_error
working_ci_workflow_blob="$(git -C "$ROOT_DIR" hash-object -- "$CI_WORKFLOW_PATH" 2>/dev/null)" \
    || local_anchor_error
working_publication_workflow_blob="$(
    git -C "$ROOT_DIR" hash-object -- "$PUBLICATION_WORKFLOW_PATH" 2>/dev/null
)" || local_anchor_error
working_legacy_workflow_blob="$(
    git -C "$ROOT_DIR" hash-object -- "$LEGACY_WORKFLOW_PATH" 2>/dev/null
)" || local_anchor_error
working_policy_blob="$(git -C "$ROOT_DIR" hash-object -- "$POLICY_PATH" 2>/dev/null)" \
    || local_anchor_error
[[ "$working_workflow_blob" == "$expected_workflow_blob" ]] || local_anchor_error
[[ "$working_ci_workflow_blob" == "$expected_ci_workflow_blob" ]] || local_anchor_error
[[ "$working_publication_workflow_blob" == "$expected_publication_workflow_blob" ]] \
    || local_anchor_error
[[ "$working_legacy_workflow_blob" == "$expected_legacy_workflow_blob" ]] \
    || local_anchor_error
[[ "$working_policy_blob" == "$expected_policy_blob" ]] || local_anchor_error
unset working_workflow_blob working_ci_workflow_blob working_publication_workflow_blob
unset working_legacy_workflow_blob working_policy_blob

local_v_refs="$(git -C "$ROOT_DIR" for-each-ref --format='%(refname)' 'refs/tags/v*' 2>/dev/null)" \
    || local_anchor_error
local_predecessor_tag_object=""
local_release_tag_object=""
local_tag_matches() {
    local tag="$1"
    local expected_tag_commit="$2"
    local expected_tag_object="$3"
    local observed_tag_object observed_tag_commit
    observed_tag_object="$(git -C "$ROOT_DIR" rev-parse "refs/tags/$tag" 2>/dev/null)" || return 1
    observed_tag_commit="$(git -C "$ROOT_DIR" rev-parse "refs/tags/$tag^{commit}" 2>/dev/null)" \
        || return 1
    [[ "$observed_tag_object" == "$expected_tag_object" \
        && "$observed_tag_commit" == "$expected_tag_commit" ]] || return 1
    [[ "$(git -C "$ROOT_DIR" cat-file -t "$observed_tag_object" 2>/dev/null)" == tag ]] \
        || return 1
    git -C "$ROOT_DIR" merge-base --is-ancestor "$expected_tag_commit" "$expected_commit" \
        >/dev/null 2>&1
}
case "$phase" in
  predecessor-pre-tag)
    [[ -z "$local_v_refs" ]] || local_anchor_error
    [[ ! -e "$evidence_output" && ! -L "$evidence_output" ]] || local_anchor_error
    ;;
  final-pre-tag)
    [[ "$local_v_refs" == "refs/tags/$PREDECESSOR_TAG" ]] || local_anchor_error
    local_predecessor_tag_object="$expected_predecessor_tag_object"
    local_tag_matches "$PREDECESSOR_TAG" "$expected_predecessor_commit" \
        "$local_predecessor_tag_object" || local_anchor_error
    [[ ! -e "$evidence_output" && ! -L "$evidence_output" ]] || local_anchor_error
    predecessor_pre_tag_relative="${PREDECESSOR_PRE_TAG_OUTPUT#"$ROOT_DIR/"}"
    [[ -f "$PREDECESSOR_PRE_TAG_OUTPUT" && ! -L "$PREDECESSOR_PRE_TAG_OUTPUT" \
        && -s "$PREDECESSOR_PRE_TAG_OUTPUT" ]] || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" ls-files --error-unmatch -- \
        "$predecessor_pre_tag_relative" 2>/dev/null)" == "$predecessor_pre_tag_relative" ]] \
        || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" ls-tree "$expected_commit" -- \
        "$predecessor_pre_tag_relative" 2>/dev/null)" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' ]] \
        || local_anchor_error
    predecessor_evidence_introduction_commits="$(git -C "$ROOT_DIR" log \
        --full-history --format=%H --reverse "$expected_predecessor_commit..$expected_commit" \
        -- "$predecessor_pre_tag_relative" 2>/dev/null)" || local_anchor_error
    [[ "$predecessor_evidence_introduction_commits" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
    predecessor_evidence_introduction_commit="$predecessor_evidence_introduction_commits"
    [[ "$(git -C "$ROOT_DIR" rev-list --parents -n 1 \
        "$predecessor_evidence_introduction_commit" 2>/dev/null)" == \
        "$predecessor_evidence_introduction_commit $expected_predecessor_commit" ]] \
        || local_anchor_error
    release_verify_first_parent_commit_once \
        "$ROOT_DIR" "$expected_commit" "$predecessor_evidence_introduction_commit" \
        || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" diff-tree --no-commit-id --name-status -r \
        "$expected_predecessor_commit" "$predecessor_evidence_introduction_commit" \
        2>/dev/null)" == $'A\t'"$predecessor_pre_tag_relative" ]] || local_anchor_error
    (
        cd "$ROOT_DIR"
        release_verify_predecessor_pre_tag_evidence_chain \
            "$PREDECESSOR_TAG" "$expected_predecessor_commit" \
            "$expected_predecessor_tag_object" "$expected_commit"
    ) || local_anchor_error
    ;;
  pre-publication)
    [[ "$local_v_refs" == $'refs/tags/'"$PREDECESSOR_TAG"$'\nrefs/tags/'"$RELEASE_TAG" ]] \
        || local_anchor_error
    local_predecessor_tag_object="$expected_predecessor_tag_object"
    local_release_tag_object="$expected_release_tag_object"
    local_tag_matches "$PREDECESSOR_TAG" "$expected_predecessor_commit" \
        "$local_predecessor_tag_object" || local_anchor_error
    local_tag_matches "$RELEASE_TAG" "$expected_release_commit" "$local_release_tag_object" \
        || local_anchor_error
    [[ -d "$EVIDENCE_DIRECTORY" && ! -L "$EVIDENCE_DIRECTORY" ]] || local_anchor_error
    [[ ! -e "$PRE_PUBLICATION_OUTPUT" && ! -L "$PRE_PUBLICATION_OUTPUT" ]] || local_anchor_error
    final_pre_tag_relative="${FINAL_PRE_TAG_OUTPUT#"$ROOT_DIR/"}"
    [[ -f "$FINAL_PRE_TAG_OUTPUT" && ! -L "$FINAL_PRE_TAG_OUTPUT" && -s "$FINAL_PRE_TAG_OUTPUT" ]] \
        || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" ls-files --error-unmatch -- "$final_pre_tag_relative" 2>/dev/null)" == \
        "$final_pre_tag_relative" ]] || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" ls-tree "$expected_commit" -- "$final_pre_tag_relative" 2>/dev/null)" =~ \
        ^100644\ blob\ [0-9a-f]{40}$'\t' ]] || local_anchor_error
    final_evidence_introduction_commits="$(git -C "$ROOT_DIR" log --full-history --format=%H --reverse \
        "$expected_release_commit..$expected_commit" -- "$final_pre_tag_relative" 2>/dev/null)" \
        || local_anchor_error
    [[ "$final_evidence_introduction_commits" =~ ^[0-9a-f]{40}$ ]] || local_anchor_error
    final_evidence_introduction_commit="$final_evidence_introduction_commits"
    [[ "$(git -C "$ROOT_DIR" rev-list --parents -n 1 \
        "$final_evidence_introduction_commit" 2>/dev/null)" == \
        "$final_evidence_introduction_commit $expected_release_commit" ]] || local_anchor_error
    release_verify_first_parent_commit_once \
        "$ROOT_DIR" "$expected_commit" "$final_evidence_introduction_commit" \
        || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" diff-tree --no-commit-id --name-status -r \
        "$expected_release_commit" "$final_evidence_introduction_commit" 2>/dev/null)" == \
        $'A\t'"$final_pre_tag_relative" ]] || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" ls-tree "$final_evidence_introduction_commit" -- \
        "$final_pre_tag_relative" 2>/dev/null)" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' ]] \
        || local_anchor_error
    introduction_digest="$(git -C "$ROOT_DIR" show \
        "$final_evidence_introduction_commit:$final_pre_tag_relative" 2>/dev/null \
        | shasum -a 256 | awk '{print $1}')" || local_anchor_error
    [[ "$introduction_digest" == "$(shasum -a 256 "$FINAL_PRE_TAG_OUTPUT" | awk '{print $1}')" ]] \
        || local_anchor_error
    tag_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_release_commit:.github/workflows/signed-release-candidate.yml" 2>/dev/null)" || local_anchor_error
    tag_ci_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_release_commit:.github/workflows/ci.yml" 2>/dev/null)" || local_anchor_error
    tag_publication_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_release_commit:.github/workflows/publish-release.yml" 2>/dev/null)" || local_anchor_error
    tag_legacy_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_release_commit:.github/workflows/release.yml" 2>/dev/null)" || local_anchor_error
    tag_policy_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_release_commit:scripts/release/remote-controls-policy.json" 2>/dev/null)" \
        || local_anchor_error
    [[ "$tag_workflow_blob" == "$expected_workflow_blob" && \
        "$tag_ci_workflow_blob" == "$expected_ci_workflow_blob" && \
        "$tag_publication_workflow_blob" == "$expected_publication_workflow_blob" && \
        "$tag_legacy_workflow_blob" == "$expected_legacy_workflow_blob" && \
        "$tag_policy_blob" == "$expected_policy_blob" ]] || local_anchor_error
    (
        cd "$ROOT_DIR"
        release_verify_final_pre_tag_evidence_chain \
            "$RELEASE_TAG" "$expected_release_commit" \
            "$expected_release_tag_object" "$expected_commit"
    ) || local_anchor_error
    ;;
esac
unset local_v_refs

policy_contract="$(
    ruby "$POLICY_VALIDATOR" --publication-approval-contract "$POLICY_PATH" 2>/dev/null
)" || policy_error
policy_operator_fields="$(ruby -rjson -e '
  value = JSON.parse(ARGV.fetch(0), allow_nan: false, create_additions: false)
  raise unless value.is_a?(Hash) &&
    value.keys.sort == %w[approvalMode operator publisher reviewer schemaVersion]
  operator = value.fetch("operator")
  raise unless operator.is_a?(Hash) && operator.keys.sort == %w[id login type]
  raise unless operator.fetch("id").is_a?(Integer) && operator.fetch("id").positive?
  raise unless operator.fetch("login").is_a?(String) &&
    operator.fetch("login").match?(/\A(?!-)[A-Za-z0-9-]{1,39}(?<!-)\z/)
  raise unless operator.fetch("type") == "User"
  puts [operator.fetch("id"), operator.fetch("login")].join("\t")
' "$policy_contract" 2>/dev/null)" || policy_error
IFS=$'\t' read -r policy_operator_id policy_operator_login <<<"$policy_operator_fields"
[[ "$policy_operator_id" =~ ^[1-9][0-9]*$ && -n "$policy_operator_login" ]] || policy_error
manual_verified_at="$(ruby -rtime -e 'puts Time.now.utc.iso8601' 2>/dev/null)" \
    || internal_error
validate_manual_file() {
    local input_path="$1"
    local control="$2"
    local permission_profile="$3"
    local manual_arguments=(
        manual-evidence
        --input "$input_path"
        --control "$control"
        --permission-profile "$permission_profile"
        --actor-id "$policy_operator_id"
        --actor-login "$policy_operator_login"
        --verified-at "$manual_verified_at"
        --phase "$phase"
    )
    if [[ "$phase" == pre-publication ]]; then
        manual_arguments+=(
            --release-commit "$expected_release_commit"
            --release-id "$expected_release_id"
            --release-tag-object "$local_release_tag_object"
        )
    fi
    ruby "$COLLECTOR" "${manual_arguments[@]}" 2>/dev/null
}
for manual_path in "$CANDIDATE_MANUAL_EVIDENCE" "$PUBLICATION_MANUAL_EVIDENCE"; do
    [[ -f "$manual_path" && ! -L "$manual_path" && -s "$manual_path" ]] || local_anchor_error
    manual_relative="${manual_path#"$ROOT_DIR/"}"
    [[ "$(git -C "$ROOT_DIR" ls-files --error-unmatch -- "$manual_relative" 2>/dev/null)" == \
        "$manual_relative" ]] || local_anchor_error
    [[ "$(git -C "$ROOT_DIR" ls-tree "$expected_commit" -- "$manual_relative" 2>/dev/null)" =~ \
        ^100644\ blob\ [0-9a-f]{40}$'\t' ]] || local_anchor_error
done
candidate_manual_result="$(validate_manual_file \
    "$CANDIDATE_MANUAL_EVIDENCE" \
    release-candidate-administrator-bypass-disabled \
    candidate)" || local_anchor_error
publication_manual_result="$(validate_manual_file \
    "$PUBLICATION_MANUAL_EVIDENCE" \
    release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope \
    publication)" || local_anchor_error
manual_fields="$(ruby -rjson -e '
  rows = ARGV.map { |source| JSON.parse(source, allow_nan: false, create_additions: false) }
  rows.each do |row|
    raise unless row.is_a?(Hash) &&
      row.keys.sort == %w[control observedAt sha256 sourceArtifactSHA256]
    raise unless row.fetch("sha256").match?(/\A[0-9a-f]{64}\z/) &&
      row.fetch("sourceArtifactSHA256").match?(/\A[0-9a-f]{64}\z/)
  end
  raise unless rows.map { |row| row.fetch("sha256") }.uniq.length == 2
  raise unless rows.map { |row| row.fetch("sourceArtifactSHA256") }.uniq.length == 2
  puts [
    *rows.map { |row| row.fetch("sha256") },
    *rows.map { |row| row.fetch("sourceArtifactSHA256") }
  ].join("\t")
' "$candidate_manual_result" "$publication_manual_result" 2>/dev/null)" || local_anchor_error
IFS=$'\t' read -r candidate_manual_sha256 publication_manual_sha256 \
    candidate_manual_source_sha256 publication_manual_source_sha256 <<<"$manual_fields"
[[ "$candidate_manual_sha256" =~ ^[0-9a-f]{64}$ ]] || local_anchor_error
[[ "$publication_manual_sha256" =~ ^[0-9a-f]{64}$ ]] || local_anchor_error
[[ "$candidate_manual_source_sha256" =~ ^[0-9a-f]{64}$ ]] || local_anchor_error
[[ "$publication_manual_source_sha256" =~ ^[0-9a-f]{64}$ ]] || local_anchor_error
unset manual_path manual_relative manual_fields
unset policy_contract policy_operator_fields

predecessor_pre_tag_evidence_sha256=""
predecessor_pre_tag_collected_at=""
final_pre_tag_evidence_sha256=""
final_pre_tag_collected_at=""
if [[ "$phase" == final-pre-tag ]]; then
    predecessor_pre_tag_evidence_sha256="$(
        shasum -a 256 "$PREDECESSOR_PRE_TAG_OUTPUT" 2>/dev/null | awk '{print $1}'
    )" || local_anchor_error
    [[ "$predecessor_pre_tag_evidence_sha256" =~ ^[0-9a-f]{64}$ ]] || local_anchor_error
    predecessor_pre_tag_collected_at="$(ruby -rjson -rtime -e '
      value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
      text = value.fetch("collectedAt")
      time = Time.iso8601(text)
      raise unless value.fetch("schemaVersion") ==
        "desk-setup-switcher.remote-release-controls-evidence/v3"
      raise unless value.fetch("phase") == "predecessor-pre-tag"
      raise unless text == time.utc.iso8601
      puts text
    ' "$PREDECESSOR_PRE_TAG_OUTPUT" 2>/dev/null)" || local_anchor_error
    if ! git -C "$ROOT_DIR" cat-file -p "$expected_predecessor_tag_object" 2>/dev/null \
        | ruby -e '
          expected = "remote-controls-predecessor-pre-tag-sha256: #{ARGV.fetch(0)}\n"
          _headers, separator, message = STDIN.read.partition("\n\n")
          exit 1 unless separator == "\n\n" && message == expected
        ' "$predecessor_pre_tag_evidence_sha256"; then
        local_anchor_error
    fi
    predecessor_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_predecessor_commit:.github/workflows/signed-release-candidate.yml" 2>/dev/null)" \
        || local_anchor_error
    predecessor_ci_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_predecessor_commit:.github/workflows/ci.yml" 2>/dev/null)" || local_anchor_error
    predecessor_publication_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_predecessor_commit:.github/workflows/publish-release.yml" 2>/dev/null)" \
        || local_anchor_error
    predecessor_legacy_workflow_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_predecessor_commit:.github/workflows/release.yml" 2>/dev/null)" \
        || local_anchor_error
    predecessor_policy_blob="$(git -C "$ROOT_DIR" rev-parse \
        "$expected_predecessor_commit:scripts/release/remote-controls-policy.json" 2>/dev/null)" \
        || local_anchor_error
    [[ "$predecessor_workflow_blob" == "$expected_workflow_blob" \
        && "$predecessor_ci_workflow_blob" == "$expected_ci_workflow_blob" \
        && "$predecessor_publication_workflow_blob" == "$expected_publication_workflow_blob" \
        && "$predecessor_legacy_workflow_blob" == "$expected_legacy_workflow_blob" \
        && "$predecessor_policy_blob" == "$expected_policy_blob" ]] || local_anchor_error
    ruby "$POLICY_VALIDATOR" \
        --policy "$POLICY_PATH" \
        --evidence "$PREDECESSOR_PRE_TAG_OUTPUT" \
        --expected-phase predecessor-pre-tag \
        --expected-commit "$expected_predecessor_commit" \
        --expected-workflow-blob "$expected_workflow_blob" \
        --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
        --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
        --expected-legacy-workflow-blob "$expected_legacy_workflow_blob" \
        >/dev/null 2>&1 || local_anchor_error
elif [[ "$phase" == pre-publication ]]; then
    final_pre_tag_evidence_sha256="$(
        shasum -a 256 "$FINAL_PRE_TAG_OUTPUT" 2>/dev/null | awk '{print $1}'
    )" || local_anchor_error
    [[ "$final_pre_tag_evidence_sha256" =~ ^[0-9a-f]{64}$ ]] || local_anchor_error
    final_evidence_fields="$(ruby -rjson -rtime -e '
      value = JSON.parse(File.binread(ARGV.fetch(0)), allow_nan: false, create_additions: false)
      text = value.fetch("collectedAt")
      time = Time.iso8601(text)
      predecessor_digest = value.fetch("predecessorPreTagEvidenceSHA256")
      raise unless value.fetch("schemaVersion") ==
        "desk-setup-switcher.remote-release-controls-evidence/v3"
      raise unless value.fetch("phase") == "final-pre-tag"
      raise unless text == time.utc.iso8601 &&
        predecessor_digest.match?(/\A[0-9a-f]{64}\z/)
      puts [text, predecessor_digest].join("\t")
    ' "$FINAL_PRE_TAG_OUTPUT" 2>/dev/null)" || local_anchor_error
    IFS=$'\t' read -r final_pre_tag_collected_at predecessor_pre_tag_evidence_sha256 \
        <<<"$final_evidence_fields"
    ruby "$POLICY_VALIDATOR" \
        --policy "$POLICY_PATH" \
        --evidence "$FINAL_PRE_TAG_OUTPUT" \
        --expected-phase final-pre-tag \
        --expected-commit "$expected_release_commit" \
        --expected-workflow-blob "$expected_workflow_blob" \
        --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
        --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
        --expected-legacy-workflow-blob "$expected_legacy_workflow_blob" \
        --expected-predecessor-commit "$expected_predecessor_commit" \
        --expected-predecessor-tag-object "$expected_predecessor_tag_object" \
        --expected-predecessor-pre-tag-evidence-sha256 \
            "$predecessor_pre_tag_evidence_sha256" \
        >/dev/null 2>&1 || local_anchor_error
    if ! git -C "$ROOT_DIR" cat-file -p "$local_release_tag_object" 2>/dev/null \
        | ruby -e '
          expected = "remote-controls-final-pre-tag-sha256: #{ARGV.fetch(0)}\n"
          source = STDIN.read
          _headers, separator, message = source.partition("\n\n")
          exit 1 unless separator == "\n\n" && message == expected
        ' "$final_pre_tag_evidence_sha256"; then
        local_anchor_error
    fi
    unset final_evidence_fields
fi

policy_status=0
ci_workflow_id="$(
    ruby "$POLICY_VALIDATOR" \
        --ci-workflow-id "$POLICY_PATH" \
        --expected-workflow-blob "$expected_workflow_blob" \
        --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
        --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
        --expected-legacy-workflow-blob "$expected_legacy_workflow_blob" 2>/dev/null
)" || policy_status=$?
if [[ "$policy_status" -eq 1 ]]; then
    policy_error
elif [[ "$policy_status" -ne 0 ]]; then
    internal_error
fi
[[ "$ci_workflow_id" =~ ^[1-9][0-9]*$ ]] || policy_error
unset policy_status

policy_status=0
publication_workflow_id="$(
    ruby "$POLICY_VALIDATOR" \
        --publication-workflow-id "$POLICY_PATH" \
        --expected-workflow-blob "$expected_workflow_blob" \
        --expected-ci-workflow-blob "$expected_ci_workflow_blob" \
        --expected-publication-workflow-blob "$expected_publication_workflow_blob" \
        --expected-legacy-workflow-blob "$expected_legacy_workflow_blob" 2>/dev/null
)" || policy_status=$?
if [[ "$policy_status" -eq 1 ]]; then
    policy_error
elif [[ "$policy_status" -ne 0 ]]; then
    internal_error
fi
[[ "$publication_workflow_id" =~ ^[1-9][0-9]*$ ]] || policy_error
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
if ! local_candidate_security="$(
    ruby "$COLLECTOR" local-workflow-security --workflow "$WORKFLOW_PATH" 2>/dev/null
)"; then
    local_anchor_error
fi
[[ "$local_candidate_security" == '{"triggers":["workflow_dispatch"],"contentsWrite":true}' ]] \
    || local_anchor_error
if ! local_ci_security="$(
    ruby "$COLLECTOR" local-workflow-security --workflow "$CI_WORKFLOW_PATH" 2>/dev/null
)"; then
    local_anchor_error
fi
[[ "$local_ci_security" == '{"triggers":["pull_request","push","workflow_dispatch"],"contentsWrite":false}' ]] \
    || local_anchor_error
if ! local_publication_security="$(
    ruby "$COLLECTOR" local-workflow-security --workflow "$PUBLICATION_WORKFLOW_PATH" 2>/dev/null
)"; then
    local_anchor_error
fi
[[ "$local_publication_security" == '{"triggers":["workflow_dispatch"],"contentsWrite":true}' ]] \
    || local_anchor_error
if ! local_legacy_security="$(
    ruby "$COLLECTOR" local-workflow-security --workflow "$LEGACY_WORKFLOW_PATH" 2>/dev/null
)"; then
    local_anchor_error
fi
[[ "$local_legacy_security" == '{"triggers":["workflow_dispatch"],"contentsWrite":false}' ]] \
    || local_anchor_error

local_anchors_match() {
    local observed_root observed_shallow observed_commit
    local observed_workflow_blob observed_ci_workflow_blob observed_publication_workflow_blob
    local observed_legacy_workflow_blob
    local observed_policy_blob observed_workflow_worktree_blob observed_ci_workflow_worktree_blob
    local observed_publication_worktree_blob observed_legacy_worktree_blob
    local observed_policy_worktree_blob observed_status
    local observed_candidate_manual observed_publication_manual observed_v_refs
    local observed_final_pre_tag_evidence observed_predecessor_pre_tag_evidence

    [[ -f "$WORKFLOW_PATH" && ! -L "$WORKFLOW_PATH" ]] || return 1
    [[ -f "$CI_WORKFLOW_PATH" && ! -L "$CI_WORKFLOW_PATH" ]] || return 1
    [[ -f "$PUBLICATION_WORKFLOW_PATH" && ! -L "$PUBLICATION_WORKFLOW_PATH" ]] || return 1
    [[ -f "$LEGACY_WORKFLOW_PATH" && ! -L "$LEGACY_WORKFLOW_PATH" ]] || return 1
    [[ -f "$POLICY_PATH" && ! -L "$POLICY_PATH" ]] || return 1
    [[ -f "$CANDIDATE_MANUAL_EVIDENCE" && ! -L "$CANDIDATE_MANUAL_EVIDENCE" ]] || return 1
    [[ -f "$PUBLICATION_MANUAL_EVIDENCE" && ! -L "$PUBLICATION_MANUAL_EVIDENCE" ]] || return 1
    observed_root="$(git -C "$ROOT_DIR" rev-parse --show-toplevel 2>/dev/null)" || return 1
    observed_root="$(cd "$observed_root" 2>/dev/null && pwd -P)" || return 1
    observed_shallow="$(git -C "$ROOT_DIR" rev-parse --is-shallow-repository 2>/dev/null)" \
        || return 1
    observed_commit="$(git -C "$ROOT_DIR" rev-parse --verify HEAD 2>/dev/null)" || return 1
    observed_workflow_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/signed-release-candidate.yml' 2>/dev/null
    )" || return 1
    observed_ci_workflow_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/ci.yml' 2>/dev/null
    )" || return 1
    observed_publication_workflow_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/publish-release.yml' 2>/dev/null
    )" || return 1
    observed_legacy_workflow_blob="$(
        git -C "$ROOT_DIR" rev-parse 'HEAD:.github/workflows/release.yml' 2>/dev/null
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
    observed_publication_worktree_blob="$(
        git -C "$ROOT_DIR" hash-object -- "$PUBLICATION_WORKFLOW_PATH" 2>/dev/null
    )" || return 1
    observed_legacy_worktree_blob="$(
        git -C "$ROOT_DIR" hash-object -- "$LEGACY_WORKFLOW_PATH" 2>/dev/null
    )" || return 1
    observed_policy_worktree_blob="$(
        git -C "$ROOT_DIR" hash-object -- "$POLICY_PATH" 2>/dev/null
    )" || return 1
    observed_status="$(
        git -C "$ROOT_DIR" status --porcelain=v1 --untracked-files=all 2>/dev/null
    )" || return 1
    observed_candidate_manual="$(
        shasum -a 256 "$CANDIDATE_MANUAL_EVIDENCE" 2>/dev/null | awk '{print $1}'
    )" || return 1
    observed_publication_manual="$(
        shasum -a 256 "$PUBLICATION_MANUAL_EVIDENCE" 2>/dev/null | awk '{print $1}'
    )" || return 1
    observed_v_refs="$(
        git -C "$ROOT_DIR" for-each-ref --format='%(refname)' 'refs/tags/v*' 2>/dev/null
    )" || return 1

    [[ "$observed_root" == "$ROOT_DIR" ]] || return 1
    [[ "$observed_shallow" == false ]] || return 1
    [[ "$observed_commit" == "$expected_commit" ]] || return 1
    [[ "$observed_workflow_blob" == "$expected_workflow_blob" ]] || return 1
    [[ "$observed_ci_workflow_blob" == "$expected_ci_workflow_blob" ]] || return 1
    [[ "$observed_publication_workflow_blob" == "$expected_publication_workflow_blob" ]] \
        || return 1
    [[ "$observed_legacy_workflow_blob" == "$expected_legacy_workflow_blob" ]] || return 1
    [[ "$observed_policy_blob" == "$expected_policy_blob" ]] || return 1
    [[ "$observed_workflow_worktree_blob" == "$expected_workflow_blob" ]] || return 1
    [[ "$observed_ci_workflow_worktree_blob" == "$expected_ci_workflow_blob" ]] || return 1
    [[ "$observed_publication_worktree_blob" == "$expected_publication_workflow_blob" ]] \
        || return 1
    [[ "$observed_legacy_worktree_blob" == "$expected_legacy_workflow_blob" ]] || return 1
    [[ "$observed_policy_worktree_blob" == "$expected_policy_blob" ]] || return 1
    [[ "$observed_candidate_manual" == "$candidate_manual_sha256" ]] || return 1
    [[ "$observed_publication_manual" == "$publication_manual_sha256" ]] || return 1
    [[ -z "$observed_status" ]] || return 1
    case "$phase" in
      predecessor-pre-tag)
        [[ -z "$observed_v_refs" ]] || return 1
        [[ ! -e "$evidence_output" && ! -L "$evidence_output" ]] || return 1
        ;;
      final-pre-tag)
        [[ "$observed_v_refs" == "refs/tags/$PREDECESSOR_TAG" ]] || return 1
        local_tag_matches "$PREDECESSOR_TAG" "$expected_predecessor_commit" \
            "$expected_predecessor_tag_object" || return 1
        observed_predecessor_pre_tag_evidence="$(
            shasum -a 256 "$PREDECESSOR_PRE_TAG_OUTPUT" 2>/dev/null | awk '{print $1}'
        )" || return 1
        [[ "$observed_predecessor_pre_tag_evidence" == \
            "$predecessor_pre_tag_evidence_sha256" ]] || return 1
        [[ ! -e "$evidence_output" && ! -L "$evidence_output" ]] || return 1
        ;;
      pre-publication)
        [[ "$observed_v_refs" == $'refs/tags/'"$PREDECESSOR_TAG"$'\nrefs/tags/'"$RELEASE_TAG" ]] \
            || return 1
        local_tag_matches "$PREDECESSOR_TAG" "$expected_predecessor_commit" \
            "$expected_predecessor_tag_object" || return 1
        local_tag_matches "$RELEASE_TAG" "$expected_release_commit" \
            "$expected_release_tag_object" || return 1
        observed_final_pre_tag_evidence="$(
            shasum -a 256 "$FINAL_PRE_TAG_OUTPUT" 2>/dev/null | awk '{print $1}'
        )" || return 1
        [[ "$observed_final_pre_tag_evidence" == "$final_pre_tag_evidence_sha256" ]] || return 1
        [[ ! -e "$PRE_PUBLICATION_OUTPUT" && ! -L "$PRE_PUBLICATION_OUTPUT" ]] || return 1
        ;;
    esac
}

local_anchors_match || local_anchor_error

command -v gh >/dev/null 2>&1 || api_error G00
command -v cmp >/dev/null 2>&1 || internal_error
command -v cp >/dev/null 2>&1 || internal_error

run_tracked_with_timeout() {
    local timeout_seconds="$1"
    shift
    GH_CONFIG_DIR="$gh_config_directory" \
        release_run_tracked_secret_env_timeout GH_TOKEN "$github_token" \
        "$timeout_seconds" "$@"
}

snapshot_one="$temporary_root/snapshot-1"
snapshot_two="$temporary_root/snapshot-2"
mkdir "$snapshot_one" "$snapshot_two" >/dev/null 2>&1 || internal_error
chmod 0700 "$snapshot_one" "$snapshot_two" >/dev/null 2>&1 || internal_error

if [[ "$phase" == pre-publication ]]; then
    final_candidate_manual="$temporary_root/final-release-candidate-admin-bypass.json"
    final_publication_manual="$temporary_root/final-release-publication-admin-token-scope.json"
    for final_manual_spec in \
        "$CANDIDATE_MANUAL_EVIDENCE:$final_candidate_manual" \
        "$PUBLICATION_MANUAL_EVIDENCE:$final_publication_manual"; do
        final_source_path="${final_manual_spec%%:*}"
        final_destination="${final_manual_spec#*:}"
        final_relative="${final_source_path#"$ROOT_DIR/"}"
        final_tree="$(git -C "$ROOT_DIR" ls-tree "$expected_release_commit" -- \
            "$final_relative" 2>/dev/null)" || local_anchor_error
        [[ "$final_tree" =~ ^100644\ blob\ [0-9a-f]{40}$'\t' ]] || local_anchor_error
        git -C "$ROOT_DIR" show "$expected_release_commit:$final_relative" \
            >"$final_destination" 2>/dev/null || local_anchor_error
        chmod 0600 "$final_destination" >/dev/null 2>&1 || internal_error
    done
    final_candidate_result="$(ruby "$COLLECTOR" manual-evidence \
        --input "$final_candidate_manual" \
        --control release-candidate-administrator-bypass-disabled \
        --permission-profile candidate \
        --actor-id "$policy_operator_id" \
        --actor-login "$policy_operator_login" \
        --verified-at "$final_pre_tag_collected_at" \
        --phase final-pre-tag 2>/dev/null)" || local_anchor_error
    final_publication_result="$(ruby "$COLLECTOR" manual-evidence \
        --input "$final_publication_manual" \
        --control release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope \
        --permission-profile publication \
        --actor-id "$policy_operator_id" \
        --actor-login "$policy_operator_login" \
        --verified-at "$final_pre_tag_collected_at" \
        --phase final-pre-tag 2>/dev/null)" || local_anchor_error
    ruby -rjson -e '
      current_candidate, current_publication, final_candidate, final_publication = ARGV
      rows = [current_candidate, current_publication, final_candidate, final_publication].map do |source|
        value = JSON.parse(source, allow_nan: false, create_additions: false)
        raise unless value.is_a?(Hash) &&
          value.keys.sort == %w[control observedAt sha256 sourceArtifactSHA256]
        value
      end
      sources = rows.map { |row| row.fetch("sourceArtifactSHA256") }
      raise unless sources.all? { |digest| digest.match?(/\A[0-9a-f]{64}\z/) }
      raise unless sources.uniq.length == 4
    ' "$candidate_manual_result" "$publication_manual_result" \
        "$final_candidate_result" "$final_publication_result" 2>/dev/null || local_anchor_error
    unset final_manual_spec final_source_path final_destination final_relative final_tree
    unset final_candidate_result final_publication_result
fi

api_get() {
    local endpoint_id="$1"
    local endpoint="$2"
    local output="$3"
    shift 3
    if ! run_tracked_with_timeout "$API_TIMEOUT_SECONDS" gh api \
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
    api_get E05 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-publication' \
        "$snapshot/publication-environment.json" \
        --jq '{name: .name, protection_rules: [.protection_rules[] | if .type == "required_reviewers" then {type: .type, prevent_self_review: .prevent_self_review, reviewers: [.reviewers[] | {type: .type, reviewer: {id: .reviewer.id, login: .reviewer.login, type: .reviewer.type}}]} else {type: .type} end], deployment_branch_policy: {protected_branches: .deployment_branch_policy.protected_branches, custom_branch_policies: .deployment_branch_policy.custom_branch_policies}}'
    api_get E06 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-publication/deployment-branch-policies?per_page=30' \
        "$snapshot/publication-deployment-policies.json" \
        --paginate --jq '{total_count: .total_count, items: (.branch_policies | map({name: .name, type: .type}))}'
    api_get E07 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-publication/secrets?per_page=30' \
        "$snapshot/publication-environment-secrets.json" \
        --paginate --jq '{total_count: .total_count, names: (.secrets | map(.name))}'
    api_get E08 \
        '/repos/GGULBAE/desk-setup-switcher/environments/release-publication/variables?per_page=30' \
        "$snapshot/publication-environment-variable-names.json" \
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
    api_get W01 \
        '/repos/GGULBAE/desk-setup-switcher/actions/workflows?per_page=100' \
        "$snapshot/active-workflows.json" \
        --paginate --jq '{total_count: .total_count, items: (.workflows | map({id: .id, name: .name, path: .path, state: .state}))}'
    api_get B01 \
        '/repos/GGULBAE/desk-setup-switcher/git/matching-refs/tags/v?per_page=100' \
        "$snapshot/v-refs-raw.json" \
        --paginate --jq '.[] | {ref: .ref, object_type: .object.type, object_sha: .object.sha}'
    # Bash 3.2 treats an empty array expansion as unbound under `set -u`.
    # Keep one explicit sentinel for the zero-tag predecessor boundary.
    tag_projection_arguments=(__NO_TAG_PROJECTIONS__)
    if [[ "$phase" == final-pre-tag || "$phase" == pre-publication ]]; then
        tag_projection_arguments=()
        api_get B02P \
            "/repos/GGULBAE/desk-setup-switcher/commits/tags/$PREDECESSOR_TAG" \
            "$snapshot/predecessor-v-commit.json" --jq '{commit_sha: .sha}'
        api_get B04P \
            "/repos/GGULBAE/desk-setup-switcher/git/tags/$expected_predecessor_tag_object" \
            "$snapshot/predecessor-v-tag-object.json" \
            --jq '{tag_object_sha: .sha, tag: .tag, target_type: .object.type, target_sha: .object.sha}'
        tag_projection_arguments+=(
            "$PREDECESSOR_TAG" "$expected_predecessor_tag_object"
            "$snapshot/predecessor-v-commit.json" "$snapshot/predecessor-v-tag-object.json"
        )
    fi
    if [[ "$phase" == pre-publication ]]; then
        api_get B02R \
            "/repos/GGULBAE/desk-setup-switcher/commits/tags/$RELEASE_TAG" \
            "$snapshot/release-v-commit.json" --jq '{commit_sha: .sha}'
        api_get B04R \
            "/repos/GGULBAE/desk-setup-switcher/git/tags/$expected_release_tag_object" \
            "$snapshot/release-v-tag-object.json" \
            --jq '{tag_object_sha: .sha, tag: .tag, target_type: .object.type, target_sha: .object.sha}'
        tag_projection_arguments+=(
            "$RELEASE_TAG" "$expected_release_tag_object"
            "$snapshot/release-v-commit.json" "$snapshot/release-v-tag-object.json"
        )
    fi
    if ! ruby -rjson -e '
      refs_path, output_path, *specifications = ARGV
      specifications = [] if specifications == ["__NO_TAG_PROJECTIONS__"]
      raise unless (specifications.length % 4).zero?
      refs = File.readlines(refs_path, chomp: true).map do |line|
        value = JSON.parse(line, allow_nan: false, create_additions: false)
        raise unless value.is_a?(Hash) && value.keys.sort == %w[object_sha object_type ref]
        value
      end
      expected_refs = specifications.each_slice(4).map { |tag, *_| "refs/tags/#{tag}" }.sort
      raise unless refs.map { |ref| ref.fetch("ref") }.sort == expected_refs
      normalized = specifications.each_slice(4).map do |tag_name, expected_object, commit_path, tag_path|
        ref = refs.find { |candidate| candidate.fetch("ref") == "refs/tags/#{tag_name}" }
        commit = JSON.parse(File.binread(commit_path), allow_nan: false, create_additions: false)
        tag = JSON.parse(File.binread(tag_path), allow_nan: false, create_additions: false)
        raise unless commit.is_a?(Hash) && commit.keys == ["commit_sha"]
        raise unless tag.is_a?(Hash) &&
          tag.keys.sort == %w[tag tag_object_sha target_sha target_type]
        values = [ref.fetch("object_sha"), commit.fetch("commit_sha"),
          tag.fetch("tag_object_sha"), tag.fetch("target_sha"), expected_object]
        raise unless values.all? { |value| value.is_a?(String) && value.match?(/\A[0-9a-f]{40}\z/) }
        raise unless ref.fetch("object_type") == "tag" && ref.fetch("object_sha") == expected_object
        raise unless tag.fetch("tag_object_sha") == expected_object && tag.fetch("tag") == tag_name &&
          tag.fetch("target_type") == "commit" && tag.fetch("target_sha") == commit.fetch("commit_sha")
        ref.merge("commit_sha" => commit.fetch("commit_sha"))
      end.sort_by { |ref| ref.fetch("ref") }
      File.open(output_path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |io|
        normalized.each { |ref| io.puts(JSON.generate(ref)) }
      end
    ' "$snapshot/v-refs-raw.json" "$snapshot/v-refs.json" \
        "${tag_projection_arguments[@]}" >/dev/null 2>&1; then
        evidence_error
    fi
    rm -f -- "$snapshot/v-refs-raw.json" \
        "$snapshot/predecessor-v-commit.json" "$snapshot/predecessor-v-tag-object.json" \
        "$snapshot/release-v-commit.json" "$snapshot/release-v-tag-object.json" \
        >/dev/null 2>&1 || internal_error
    unset tag_projection_arguments
    api_get B03 \
        '/repos/GGULBAE/desk-setup-switcher/releases?per_page=100' \
        "$snapshot/releases.json" \
        --paginate --jq '.[] | {id: .id, tag_name: .tag_name, draft: .draft, prerelease: .prerelease}'
    api_get C03 \
        "/repos/GGULBAE/desk-setup-switcher/commits/$expected_commit/check-runs?app_id=15368&filter=latest&per_page=100" \
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
        actions-permissions.json active-workflows.json check-runs.json ci-workflow-content-1.json
        ci-workflow-content-2.json ci-workflow-metadata-1.json
        ci-workflow-metadata-2.json deployment-policies.json effective-master.json
        environment-secrets.json environment-variable-names.json environment.json
        immutable-releases.json label.json legacy-workflow-content-1.json
        legacy-workflow-content-2.json legacy-workflow-metadata-1.json
        legacy-workflow-metadata-2.json master-1.json master-2.json permission.json
        publication-deployment-policies.json publication-environment-secrets.json
        publication-environment-variable-names.json publication-environment.json
        publication-workflow-content-1.json publication-workflow-content-2.json
        publication-workflow-metadata-1.json publication-workflow-metadata-2.json
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
      path, phase, collected_at, commit, blob, ci_blob, publication_blob, legacy_blob,
        candidate_security_json, ci_security_json, publication_security_json, legacy_security_json,
        predecessor_commit, predecessor_tag_object, predecessor_pre_tag_evidence_sha256,
        release_commit, release_id_text, release_tag_object, final_pre_tag_evidence_sha256,
        candidate_manual_sha256, publication_manual_sha256, *files = ARGV
      security = lambda do |source, workflow_path, workflow_blob|
        value = JSON.parse(source, allow_nan: false, create_additions: false)
        raise unless value.is_a?(Hash) && value.keys.sort == %w[contentsWrite triggers]
        {
          "projection" => "strict-local-workflow-ast/v1",
          "workflowPath" => workflow_path,
          "workflowBlob" => workflow_blob,
          "triggers" => value.fetch("triggers"),
          "contentsWrite" => value.fetch("contentsWrite")
        }
      end
      expected_predecessor = if phase == "predecessor-pre-tag"
        raise unless predecessor_commit.empty? && predecessor_tag_object.empty? &&
          predecessor_pre_tag_evidence_sha256.empty?
        nil
      else
        {
          "commitSha" => predecessor_commit,
          "tagObjectSha" => predecessor_tag_object
        }
      end
      raise unless expected_predecessor.nil? ||
        expected_predecessor.values.all? { |item| item.match?(/\A[0-9a-f]{40}\z/) }
      expected_release = if phase == "pre-publication"
        raise unless release_commit.match?(/\A[0-9a-f]{40}\z/) &&
          release_id_text.match?(/\A[1-9][0-9]*\z/) &&
          release_tag_object.match?(/\A[0-9a-f]{40}\z/) &&
          final_pre_tag_evidence_sha256.match?(/\A[0-9a-f]{64}\z/)
        { "commitSha" => release_commit, "id" => Integer(release_id_text, 10),
          "tagObjectSha" => release_tag_object }
      else
        raise unless release_commit.empty? && release_id_text.empty? && release_tag_object.empty? &&
          final_pre_tag_evidence_sha256.empty?
        nil
      end
      predecessor_digest = predecessor_pre_tag_evidence_sha256.empty? ? nil :
        predecessor_pre_tag_evidence_sha256
      raise unless predecessor_digest.nil? || predecessor_digest.match?(/\A[0-9a-f]{64}\z/)
      value = {
        "schemaVersion" => "desk-setup-switcher.remote-release-controls-input/v3",
        "phase" => phase,
        "collectedAt" => collected_at,
        "expectedCommit" => commit,
        "expectedWorkflowBlob" => blob,
        "expectedCIWorkflowBlob" => ci_blob,
        "expectedPublicationWorkflowBlob" => publication_blob,
        "expectedLegacyWorkflowBlob" => legacy_blob,
        "expectedPredecessor" => expected_predecessor,
        "expectedRelease" => expected_release,
        "predecessorPreTagEvidenceSHA256" => predecessor_digest,
        "finalPreTagEvidenceSHA256" =>
          final_pre_tag_evidence_sha256.empty? ? nil : final_pre_tag_evidence_sha256,
        "localCandidateWorkflow" => security.call(
          candidate_security_json, ".github/workflows/signed-release-candidate.yml", blob
        ),
        "localCIWorkflow" => security.call(
          ci_security_json, ".github/workflows/ci.yml", ci_blob
        ),
        "localPublicationWorkflow" => security.call(
          publication_security_json, ".github/workflows/publish-release.yml", publication_blob
        ),
        "localLegacyWorkflow" => security.call(
          legacy_security_json, ".github/workflows/release.yml", legacy_blob
        ),
        "manualEvidence" => {
          "complete" => true,
          "items" => [
            {
              "control" => "release-candidate-administrator-bypass-disabled",
              "sha256" => candidate_manual_sha256
            },
            {
              "control" => "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
              "sha256" => publication_manual_sha256
            }
          ]
        },
        "files" => files.sort
      }
      raise unless value.fetch("files").uniq == value.fetch("files")
      File.open(path, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |io|
        io.write(JSON.generate(value))
        io.write("\n")
      end
    ' \
        "$snapshot/manifest.json" "$phase" "$collected_at" "$expected_commit" \
        "$expected_workflow_blob" \
        "$expected_ci_workflow_blob" "$expected_publication_workflow_blob" \
        "$expected_legacy_workflow_blob" \
        "$local_candidate_security" "$local_ci_security" "$local_publication_security" \
        "$local_legacy_security" \
        "$expected_predecessor_commit" "$expected_predecessor_tag_object" \
        "$predecessor_pre_tag_evidence_sha256" \
        "$expected_release_commit" "$expected_release_id" "$expected_release_tag_object" \
        "$final_pre_tag_evidence_sha256" \
        "$candidate_manual_sha256" "$publication_manual_sha256" \
        "${manifest_files[@]}" >/dev/null 2>&1; then
        evidence_error
    fi
}

# One outer code anchor brackets both complete mutable-control observations.
collection_started_at="$(ruby -rtime -e 'puts Time.now.utc.iso8601' 2>/dev/null)" \
    || internal_error
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
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/signed-release-candidate.yml?ref=$master_sha_1" \
    "$snapshot_one/workflow-content-1.json" \
    --jq "{commit_sha: \"$master_sha_1\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A03 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/signed-release-candidate.yml' \
    "$snapshot_one/workflow-metadata-1.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A03L \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/release.yml?ref=$master_sha_1" \
    "$snapshot_one/legacy-workflow-content-1.json" \
    --jq "{commit_sha: \"$master_sha_1\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A03M \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml' \
    "$snapshot_one/legacy-workflow-metadata-1.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A04 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/ci.yml?ref=$master_sha_1" \
    "$snapshot_one/ci-workflow-content-1.json" \
    --jq "{commit_sha: \"$master_sha_1\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A05 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml' \
    "$snapshot_one/ci-workflow-metadata-1.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A06 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/publish-release.yml?ref=$master_sha_1" \
    "$snapshot_one/publication-workflow-content-1.json" \
    --jq "{commit_sha: \"$master_sha_1\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A07 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/publish-release.yml' \
    "$snapshot_one/publication-workflow-metadata-1.json" \
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

api_get A08 \
    '/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master' \
    "$snapshot_two/master-2.json" \
    --jq '{ref: .ref, object: {type: .object.type, sha: .object.sha}}'
if ! master_sha_2="$(
    ruby "$COLLECTOR" master-sha --input "$snapshot_two/master-2.json" 2>/dev/null
)"; then
    evidence_error
fi
[[ "$master_sha_2" =~ ^[0-9a-f]{40}$ ]] || evidence_error
api_get A09 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/signed-release-candidate.yml?ref=$master_sha_2" \
    "$snapshot_two/workflow-content-2.json" \
    --jq "{commit_sha: \"$master_sha_2\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A10 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/signed-release-candidate.yml' \
    "$snapshot_two/workflow-metadata-2.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A10L \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/release.yml?ref=$master_sha_2" \
    "$snapshot_two/legacy-workflow-content-2.json" \
    --jq "{commit_sha: \"$master_sha_2\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A10M \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml' \
    "$snapshot_two/legacy-workflow-metadata-2.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A11 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/ci.yml?ref=$master_sha_2" \
    "$snapshot_two/ci-workflow-content-2.json" \
    --jq "{commit_sha: \"$master_sha_2\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A12 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml' \
    "$snapshot_two/ci-workflow-metadata-2.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'
api_get A13 \
    "/repos/GGULBAE/desk-setup-switcher/contents/.github/workflows/publish-release.yml?ref=$master_sha_2" \
    "$snapshot_two/publication-workflow-content-2.json" \
    --jq "{commit_sha: \"$master_sha_2\", type: .type, path: .path, sha: .sha, encoding: .encoding, content: .content}"
api_get A14 \
    '/repos/GGULBAE/desk-setup-switcher/actions/workflows/publish-release.yml' \
    "$snapshot_two/publication-workflow-metadata-2.json" \
    --jq '{id: .id, name: .name, path: .path, state: .state}'

for anchor_name in \
    master-1.json workflow-content-1.json workflow-metadata-1.json \
    legacy-workflow-content-1.json legacy-workflow-metadata-1.json \
    ci-workflow-content-1.json ci-workflow-metadata-1.json \
    publication-workflow-content-1.json publication-workflow-metadata-1.json; do
    copy_projection "$snapshot_one/$anchor_name" "$snapshot_two/$anchor_name"
done
for anchor_name in \
    master-2.json workflow-content-2.json workflow-metadata-2.json \
    legacy-workflow-content-2.json legacy-workflow-metadata-2.json \
    ci-workflow-content-2.json ci-workflow-metadata-2.json \
    publication-workflow-content-2.json publication-workflow-metadata-2.json; do
    copy_projection "$snapshot_two/$anchor_name" "$snapshot_one/$anchor_name"
done

local_anchors_match || local_anchor_error
collected_at="$(ruby -rtime -e 'puts Time.now.utc.iso8601' 2>/dev/null)" || internal_error
ruby -rtime -e '
  started = Time.iso8601(ARGV.fetch(0))
  collected = Time.iso8601(ARGV.fetch(1))
  raise unless ARGV.fetch(0) == started.utc.iso8601 &&
    ARGV.fetch(1) == collected.utc.iso8601 && started <= collected
' "$collection_started_at" "$collected_at" >/dev/null 2>&1 || internal_error
manual_verified_at="$collected_at"
candidate_manual_final_result="$(validate_manual_file \
    "$CANDIDATE_MANUAL_EVIDENCE" \
    release-candidate-administrator-bypass-disabled \
    candidate)" || local_anchor_error
publication_manual_final_result="$(validate_manual_file \
    "$PUBLICATION_MANUAL_EVIDENCE" \
    release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope \
    publication)" || local_anchor_error
[[ "$candidate_manual_final_result" == "$candidate_manual_result" && \
    "$publication_manual_final_result" == "$publication_manual_result" ]] || local_anchor_error
if [[ "$phase" == final-pre-tag || "$phase" == pre-publication ]]; then
    prior_collected_at="$predecessor_pre_tag_collected_at"
    if [[ "$phase" == pre-publication ]]; then
        prior_collected_at="$final_pre_tag_collected_at"
    fi
    ruby -rjson -rtime -e '
      prior_collected_text, current_collected_text, *manual_rows = ARGV
      prior_collected = Time.iso8601(prior_collected_text)
      current_collected = Time.iso8601(current_collected_text)
      raise unless prior_collected_text == prior_collected.utc.iso8601 &&
        current_collected_text == current_collected.utc.iso8601 &&
        prior_collected <= current_collected
      manual_rows.each do |source|
        observed_text = JSON.parse(source, allow_nan: false, create_additions: false)
          .fetch("observedAt")
        observed = Time.iso8601(observed_text)
        raise unless observed_text == observed.utc.iso8601 &&
          prior_collected <= observed && observed <= current_collected
      end
    ' "$prior_collected_at" "$collected_at" \
        "$candidate_manual_final_result" "$publication_manual_final_result" \
        >/dev/null 2>&1 || local_anchor_error
    unset prior_collected_at
fi
unset candidate_manual_result publication_manual_result

write_manifest "$snapshot_one" "$ruleset_count_one"
write_manifest "$snapshot_two" "$ruleset_count_two"
evidence_one="$temporary_root/evidence-1.json"
evidence_two="$temporary_root/evidence-2.json"
if ! checks_count_one="$(
    ruby "$COLLECTOR" collect-lifecycle \
        --input-dir "$snapshot_one" --output "$evidence_one" 2>/dev/null
)"; then
    evidence_error
fi
if ! checks_count_two="$(
    ruby "$COLLECTOR" collect-lifecycle \
        --input-dir "$snapshot_two" --output "$evidence_two" 2>/dev/null
)"; then
    evidence_error
fi
[[ "$checks_count_one" =~ ^[1-9][0-9]*$ ]] || evidence_error
[[ "$checks_count_two" == "$checks_count_one" ]] || evidence_error
cmp -s "$evidence_one" "$evidence_two" || evidence_error
checks_count="$checks_count_two"
evidence_path="$evidence_two"
if ! ruby -rjson -e '
  evidence_path, candidate_path, publication_path = ARGV
  evidence = JSON.parse(File.binread(evidence_path), allow_nan: false, create_additions: false)
  viewer = evidence.dig("authenticatedViewer", "actor")
  raise unless viewer.is_a?(Hash) && viewer.keys.sort == %w[id login type]
  source_digests = [candidate_path, publication_path].map do |path|
    manual = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
    observer = manual.fetch("observer")
    raise unless observer.fetch("id") == viewer.fetch("id")
    raise unless observer.fetch("type") == viewer.fetch("type")
    raise unless observer.fetch("login").casecmp?(viewer.fetch("login"))
    manual.fetch("sourceArtifactSHA256")
  end
  raise unless source_digests.uniq.length == source_digests.length
' "$evidence_path" "$CANDIDATE_MANUAL_EVIDENCE" "$PUBLICATION_MANUAL_EVIDENCE" \
    >/dev/null 2>&1; then
    evidence_error
fi

# Close local race windows as well as remote ones. A policy, workflow, HEAD, or
# worktree change during collection invalidates the trusted local authority.
local_anchors_match || local_anchor_error

policy_status=0
policy_arguments=(
    --policy "$POLICY_PATH"
    --evidence "$evidence_path"
    --expected-phase "$phase"
    --expected-commit "$expected_commit"
    --expected-workflow-blob "$expected_workflow_blob"
    --expected-ci-workflow-blob "$expected_ci_workflow_blob"
    --expected-publication-workflow-blob "$expected_publication_workflow_blob"
    --expected-legacy-workflow-blob "$expected_legacy_workflow_blob"
)
if [[ "$phase" == final-pre-tag || "$phase" == pre-publication ]]; then
    policy_arguments+=(
        --expected-predecessor-commit "$expected_predecessor_commit"
        --expected-predecessor-tag-object "$expected_predecessor_tag_object"
        --expected-predecessor-pre-tag-evidence-sha256
            "$predecessor_pre_tag_evidence_sha256"
    )
fi
if [[ "$phase" == pre-publication ]]; then
    policy_arguments+=(
        --expected-release-commit "$expected_release_commit"
        --expected-release-id "$expected_release_id"
        --expected-release-tag-object "$expected_release_tag_object"
        --expected-final-pre-tag-evidence-sha256 "$final_pre_tag_evidence_sha256"
    )
fi
ruby "$POLICY_VALIDATOR" "${policy_arguments[@]}" >/dev/null 2>&1 || policy_status=$?
if [[ "$policy_status" -eq 1 ]]; then
    policy_error
elif [[ "$policy_status" -ne 0 ]]; then
    evidence_error
fi
unset policy_status

# The validator itself is an external process. Recheck immediately after it
# returns so it cannot mutate or replace a trusted local anchor before output.
local_anchors_match || local_anchor_error

evidence_sha256="$(shasum -a 256 "$evidence_path" 2>/dev/null | awk '{print $1}')" \
    || internal_error
[[ "$evidence_sha256" =~ ^[0-9a-f]{64}$ ]] || internal_error
case "$phase" in
  predecessor-pre-tag)
    durable_evidence_output="$evidence_output"
    evidence_record="protected-external-output"
    durable_directory_policy="private"
    ;;
  final-pre-tag)
    durable_evidence_output="$evidence_output"
    evidence_record="protected-external-output"
    durable_directory_policy="private"
    ;;
  pre-publication)
    durable_evidence_output="$PRE_PUBLICATION_OUTPUT"
    evidence_record="docs/evidence/releases/$RELEASE_TAG/remote-controls-pre-publication.json"
    durable_directory_policy="repository"
    ;;
esac
durable_real_output="$(ruby -e '
  require "securerandom"
  source, destination, directory_policy, repository = ARGV
  directory = File.dirname(destination)
  directory_stat = File.lstat(directory)
  directory_real = File.realpath(directory)
  repository_real = File.realpath(repository)
  real_destination = File.join(directory_real, File.basename(destination))
  raise unless directory_stat.directory? && !directory_stat.symlink? &&
    directory_stat.uid == Process.euid
  case directory_policy
  when "private"
    raise unless (directory_stat.mode & 0o777) == 0o700
    raise if real_destination == repository_real ||
      real_destination.start_with?("#{repository_real}/")
  when "repository"
    raise unless (directory_stat.mode & 0o022).zero?
    raise unless real_destination.start_with?("#{repository_real}/")
  else
    raise
  end
  raise if File.exist?(real_destination) || File.symlink?(real_destination)
  bytes = File.binread(source)
  raise if bytes.empty?
  temporary = File.join(directory_real, ".remote-controls-evidence.#{Process.pid}.#{SecureRandom.hex(8)}")
  begin
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |io|
      io.write(bytes)
      io.flush
      io.fsync
    end
    File.link(temporary, real_destination)
    File.unlink(temporary)
    File.open(directory_real, File::RDONLY) { |io| io.fsync }
  ensure
    File.unlink(temporary) if File.exist?(temporary) || File.symlink?(temporary)
  end
  puts real_destination
' "$evidence_path" "$durable_evidence_output" "$durable_directory_policy" "$ROOT_DIR" \
    2>/dev/null)" || {
    internal_error
}
[[ -n "$durable_real_output" && "$durable_real_output" != *$'\n'* \
    && "$durable_real_output" != *$'\r'* ]] || internal_error
durable_evidence_output="$durable_real_output"
ruby -e '
  stat = File.lstat(ARGV.fetch(0))
  raise unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
    stat.uid == Process.euid && (stat.mode & 0o777) == 0o600
' "$durable_evidence_output" >/dev/null 2>&1 || internal_error
cmp -s "$evidence_path" "$durable_evidence_output" || internal_error

printf 'OK remote-controls phase=%s repository=%s observed_master=%s release_workflow_blob=%s ci_workflow_blob=%s publication_workflow_blob=%s legacy_workflow_blob=%s publication_workflow_id=%s ci_run_id=%s ci_run_attempt=%s ci_job_id=%s checks=%s manual_gates=2 evidence_sha256=%s evidence_record=%s\n' \
    "$phase" \
    "$REPOSITORY" \
    "$expected_commit" \
    "$expected_workflow_blob" \
    "$expected_ci_workflow_blob" \
    "$expected_publication_workflow_blob" \
    "$expected_legacy_workflow_blob" \
    "$publication_workflow_id" \
    "$ci_run_id_two" \
    "$ci_run_attempt_two" \
    "$ci_job_id_two" \
    "$checks_count" \
    "$evidence_sha256" \
    "$evidence_record"
