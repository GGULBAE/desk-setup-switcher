#!/usr/bin/env bash

set -euo pipefail
set +x
umask 077

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd -P)"
assertions=0
real_ruby="$(command -v ruby)" || {
    printf 'Remote controls collector test failed: ruby unavailable\n' >&2
    exit 1
}

pass() {
    assertions=$((assertions + 1))
}

fail() {
    printf 'Remote controls collector test failed: %s\n' "$1" >&2
    exit 1
}

assert_equal() {
    local expected="$1"
    local actual="$2"
    local label="$3"
    [[ "$actual" == "$expected" ]] || fail "$label"
    pass
}

assert_empty() {
    local path="$1"
    [[ ! -s "$path" ]] || fail "Expected empty output."
    pass
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-remote-controls-test.XXXXXX")"
chmod 0700 "$temporary_root"
cleanup() {
    rm -rf -- "$temporary_root"
}
trap cleanup EXIT

test_repository="$temporary_root/repository"
test_tmp="$temporary_root/runtime-tmp"
mock_bin="$temporary_root/mock-bin"
mkdir -p \
    "$test_repository/scripts/release/fixtures/remote-controls" \
    "$test_repository/.github/workflows" \
    "$test_tmp" \
    "$mock_bin"
chmod 0700 "$test_tmp"

cp "$SCRIPT_DIR/verify-remote-controls.sh" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/collect_remote_controls_evidence.rb" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/remote_controls_policy.rb" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/release_policy.rb" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/fixtures/remote-controls/policy-v1.json" \
    "$test_repository/scripts/release/fixtures/remote-controls/"
cp "$ROOT_DIR/.github/workflows/release.yml" "$test_repository/.github/workflows/release.yml"
cp "$ROOT_DIR/.github/workflows/ci.yml" "$test_repository/.github/workflows/ci.yml"
chmod 0755 \
    "$test_repository/scripts/release/verify-remote-controls.sh" \
    "$test_repository/scripts/release/collect_remote_controls_evidence.rb" \
    "$test_repository/scripts/release/remote_controls_policy.rb"

git -C "$test_repository" init -q
git -C "$test_repository" checkout -q -b master
git -C "$test_repository" config user.name 'Synthetic Collector Test'
git -C "$test_repository" config user.email 'collector@example.invalid'
workflow_blob="$(git -C "$test_repository" hash-object .github/workflows/release.yml)"
ci_workflow_blob="$(git -C "$test_repository" hash-object .github/workflows/ci.yml)"

ruby -rjson -e '
  source, output, blob, ci_blob = ARGV
  policy = JSON.parse(File.read(source))
  repository = policy.fetch("repository")
  repository["fullName"] = "GGULBAE/desk-setup-switcher"
  operator = policy.fetch("actors").fetch("operator")
  operator["login"] = "GGULBAE"
  policy.fetch("release").fetch("workflow")["blobSha"] = blob
  policy.fetch("release").fetch("ci").fetch("workflow")["blobSha"] = ci_blob
  File.write(output, JSON.pretty_generate(policy) + "\n", mode: "w", perm: 0o600)
' \
    "$test_repository/scripts/release/fixtures/remote-controls/policy-v1.json" \
    "$test_repository/scripts/release/remote-controls-policy.json" \
    "$workflow_blob" \
    "$ci_workflow_blob"

git -C "$test_repository" add -- .
git -C "$test_repository" commit -q -m 'Synthetic remote controls fixture'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"

cat >"$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "json"

abort "debug environment leaked" if ENV.key?("GH_DEBUG") || ENV.key?("DEBUG")
abort "not gh api" unless ARGV.first == "api"
method_indices = ARGV.each_index.select { |index| ARGV.fetch(index) == "-X" }
abort "method was not exactly GET" unless method_indices.length == 1 &&
  ARGV[method_indices.first + 1] == "GET"
abort "alternate method selector" if ARGV.any? do |argument|
  (argument.start_with?("-X") && argument != "-X") || argument.start_with?("--method")
end
abort "request body option" if ARGV.any? do |argument|
  argument == "-f" || argument.start_with?("-f") ||
    argument == "-F" || argument.start_with?("-F") ||
    argument == "--raw-field" || argument.start_with?("--raw-field=") ||
    argument == "--field" || argument.start_with?("--field=") ||
    argument == "--input" || argument.start_with?("--input=")
end
abort "unsafe output option" if ARGV.any? do |argument|
  argument == "-t" || argument.start_with?("-t") ||
    argument == "-i" || argument.start_with?("-i") ||
    argument == "--template" || argument.start_with?("--template=") ||
    argument == "--include" || argument.start_with?("--include=") ||
    argument == "--verbose" || argument.start_with?("--cache")
end

endpoint = ARGV.find { |argument| argument.start_with?("/") }
abort "missing endpoint" unless endpoint
log_path = ENV.fetch("MOCK_GH_LOG")
File.open(log_path, "a", 0o600) { |io| io.puts(JSON.generate(ARGV)) }
calls = File.readlines(log_path, chomp: true).map { |line| JSON.parse(line) }
occurrence = calls.count { |call| call.include?(endpoint) }

if ENV["MOCK_MODE"] == "api-failure" && endpoint.end_with?("/immutable-releases")
  warn "raw failure /repos/private-path #{ENV.fetch('RAW_VARIABLE_MARKER')}"
  exit 42
end
if ENV["MOCK_MODE"] == "collection-local-race" &&
   endpoint.end_with?("/actions/workflows/ci.yml") && occurrence == 2
  File.open(ENV.fetch("MOCK_CI_WORKFLOW_PATH"), "a", 0o600) { |io| io.puts("# collection race") }
end

commit = ENV.fetch("MOCK_COMMIT")
blob = ENV.fetch("MOCK_WORKFLOW_BLOB")
ci_blob = ENV.fetch("MOCK_CI_WORKFLOW_BLOB")
repository = "GGULBAE/desk-setup-switcher"
actor = { "id" => 1001, "login" => "GGULBAE", "type" => "User" }
reviewer = { "id" => 1002, "login" => "synthetic-reviewer", "type" => "User" }
ci_workflow_id = 7000
check_run_id = 11_001
check_suite_id = ENV["MOCK_MODE"] == "alternate-workflow-check" ? 90_002 : 90_001
workflow_run_id = 70_001
workflow_job_id = 10_001
workflow_run = lambda do |id, attempt, status, conclusion|
  {
    "id" => id,
    "workflow_id" => ci_workflow_id,
    "check_suite_id" => check_suite_id,
    "run_attempt" => attempt,
    "path" => ".github/workflows/ci.yml",
    "event" => "push",
    "head_branch" => "master",
    "head_sha" => commit,
    "status" => status,
    "conclusion" => conclusion
  }
end
workflow_job = lambda do |id, check_id, run_id, attempt, status, conclusion|
  {
    "id" => id,
    "run_id" => run_id,
    "run_attempt" => attempt,
    "name" => "Verify macOS app",
    "workflow_name" => "CI",
    "head_branch" => "master",
    "head_sha" => commit,
    "status" => status,
    "conclusion" => conclusion,
    "check_run_url" => "https://api.github.com/repos/GGULBAE/desk-setup-switcher/check-runs/#{check_id}"
  }
end

pull_request = {
  "type" => "pull_request",
  "parameters" => {
    "dismiss_stale_reviews_on_push" => true,
    "require_code_owner_review" => false,
    "require_last_push_approval" => true,
    "required_approving_review_count" => 1,
    "required_review_thread_resolution" => true
  }
}
status_checks = {
  "type" => "required_status_checks",
  "parameters" => {
    "strict_required_status_checks_policy" => true,
    "do_not_enforce_on_create" => false,
    "required_status_checks" => [
      { "context" => "Verify macOS app", "integration_id" => 15_368 }
    ]
  }
}
master_rules = [
  { "type" => "deletion" },
  { "type" => "non_fast_forward" },
  pull_request,
  status_checks
]

rulesets = {
  101 => {
    "id" => 101,
    "name" => "Protect master",
    "target" => "branch",
    "enforcement" => "active",
    "source_type" => "Repository",
    "source" => repository,
    "conditions" => { "ref_name" => { "include" => ["refs/heads/master"], "exclude" => [] } },
    "bypass_actors" => [],
    "rules" => master_rules
  },
  102 => {
    "id" => 102,
    "name" => "Release tag creation",
    "target" => "tag",
    "enforcement" => "active",
    "source_type" => "Repository",
    "source" => repository,
    "conditions" => { "ref_name" => { "include" => ["refs/tags/v*"], "exclude" => [] } },
    "bypass_actors" => [
      { "actor_id" => 1001, "actor_type" => "User", "bypass_mode" => "always" }
    ],
    "rules" => [{ "type" => "creation" }]
  },
  103 => {
    "id" => 103,
    "name" => "Release tag immutability",
    "target" => "tag",
    "enforcement" => "active",
    "source_type" => "Repository",
    "source" => repository,
    "conditions" => { "ref_name" => { "include" => ["refs/tags/v*"], "exclude" => [] } },
    "bypass_actors" => [],
    "rules" => [
      { "type" => "update", "parameters" => { "update_allows_fetch_and_merge" => false } },
      { "type" => "deletion" }
    ]
  }
}

json = lambda { |value| puts JSON.generate(value) }

case endpoint
when "/user"
  json.call(actor)
when "/repos/GGULBAE/desk-setup-switcher"
  json.call(
    "id" => 424_242,
    "node_id" => "R_SYNTHETIC_DESK_SETUP_SWITCHER",
    "name" => "desk-setup-switcher",
    "full_name" => repository,
    "owner" => actor,
    "private" => false,
    "visibility" => "public",
    "default_branch" => "master",
    "archived" => false,
    "disabled" => false,
    "has_discussions" => false,
    "description" => "Capture, edit, and safely apply local macOS desk setup profiles.",
    "homepage" => "https://example.invalid/desk-setup-switcher",
    "topics" => %w[macos menu-bar open-source swift swiftui]
  )
when "/repos/GGULBAE/desk-setup-switcher/collaborators/GGULBAE/permission"
  json.call("permission" => "admin", "user" => actor)
when "/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master"
  observed = if ENV["MOCK_MODE"] == "anchor-drift" && occurrence == 2
               "c" * 40
             else
               commit
             end
  json.call("ref" => "refs/heads/master", "object" => { "type" => "commit", "sha" => observed })
when %r{\A/repos/GGULBAE/desk-setup-switcher/contents/\.github/workflows/release\.yml\?ref=([0-9a-f]{40})\z}
  anchored_commit = Regexp.last_match(1)
  content = Base64.strict_encode64(File.binread(ENV.fetch("MOCK_WORKFLOW_PATH")))
  json.call(
    "commit_sha" => anchored_commit,
    "type" => "file",
    "path" => ".github/workflows/release.yml",
    "sha" => blob,
    "encoding" => "base64",
    "content" => content
  )
when "/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml"
  state = ENV["MOCK_MODE"] == "workflow-state-drift" && occurrence == 2 ? "disabled_manually" : "active"
  json.call(
    "id" => 7001,
    "name" => "Signed release candidate",
    "path" => ".github/workflows/release.yml",
    "state" => state
  )
when %r{\A/repos/GGULBAE/desk-setup-switcher/contents/\.github/workflows/ci\.yml\?ref=([0-9a-f]{40})\z}
  anchored_commit = Regexp.last_match(1)
  content = Base64.strict_encode64(File.binread(ENV.fetch("MOCK_CI_WORKFLOW_PATH")))
  json.call(
    "commit_sha" => anchored_commit,
    "type" => "file",
    "path" => ".github/workflows/ci.yml",
    "sha" => ci_blob,
    "encoding" => "base64",
    "content" => content
  )
when "/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml"
  json.call(
    "id" => ci_workflow_id,
    "name" => "CI",
    "path" => ".github/workflows/ci.yml",
    "state" => "active"
  )
when "/repos/GGULBAE/desk-setup-switcher/rulesets?includes_parents=false&per_page=100"
  rulesets.values.each do |ruleset|
    summary = ruleset.slice("id", "name", "target", "enforcement", "source_type", "source")
    if ENV["MOCK_MODE"] == "ruleset-list-detail-drift" && summary["id"] == 101
      summary["name"] = "Drifted list summary"
    end
    json.call(summary)
  end
when %r{\A/repos/GGULBAE/desk-setup-switcher/rulesets/(101|102|103)\?includes_parents=false\z}
  detail = rulesets.fetch(Regexp.last_match(1).to_i).dup
  detail.delete("bypass_actors") if ENV["MOCK_MODE"] == "missing-bypass" && detail["id"] == 101
  json.call(detail)
when "/repos/GGULBAE/desk-setup-switcher/rules/branches/master?per_page=30"
  master_rules.each do |rule|
    json.call(
      "ruleset_id" => 101,
      "ruleset_source_type" => "Repository",
      "ruleset_source" => repository,
      "rule" => rule
    )
  end
when "/repos/GGULBAE/desk-setup-switcher/environments/release-candidate"
  json.call(
    "name" => "release-candidate",
    "protection_rules" => [
      { "type" => "required_reviewers", "prevent_self_review" => true,
        "reviewers" => [{ "type" => "User", "reviewer" => reviewer }] },
      { "type" => "branch_policy" }
    ],
    "deployment_branch_policy" => { "protected_branches" => false, "custom_branch_policies" => true }
  )
when "/repos/GGULBAE/desk-setup-switcher/environments/release-candidate/deployment-branch-policies?per_page=30"
  json.call("total_count" => 1, "items" => [{ "name" => "v0.1.0", "type" => "tag" }])
when "/repos/GGULBAE/desk-setup-switcher/environments/release-candidate/secrets?per_page=30"
  json.call("total_count" => 3, "names" => ["APPLE_NOTARY_API_KEY_BASE64"])
  json.call("total_count" => 3, "names" => %w[DEVELOPER_ID_CERTIFICATE_BASE64 DEVELOPER_ID_CERTIFICATE_PASSWORD])
when "/repos/GGULBAE/desk-setup-switcher/environments/release-candidate/variables?per_page=30"
  if ARGV.include?("--jq")
    json.call("total_count" => 4, "names" => %w[APPLE_NOTARY_ISSUER_ID APPLE_NOTARY_KEY_ID])
    json.call("total_count" => 4, "names" => %w[APPLE_TEAM_ID DEVELOPER_ID_APPLICATION])
  else
    json.call("variables" => [{ "name" => "LEAK", "value" => ENV.fetch("RAW_VARIABLE_MARKER") }])
  end
when "/repos/GGULBAE/desk-setup-switcher/actions/secrets?per_page=30"
  json.call("total_count" => 0, "names" => [])
when "/repos/GGULBAE/desk-setup-switcher/actions/variables?per_page=30"
  if ARGV.include?("--jq")
    json.call("total_count" => 0, "names" => [])
  else
    json.call("variables" => [{ "name" => "LEAK", "value" => ENV.fetch("RAW_VARIABLE_MARKER") }])
  end
when "/repos/GGULBAE/desk-setup-switcher/private-vulnerability-reporting"
  json.call("enabled" => true)
when "/repos/GGULBAE/desk-setup-switcher/immutable-releases"
  enabled = !(ENV["MOCK_MODE"] == "mutable-control-drift" && occurrence == 2)
  json.call("enabled" => enabled, "enforced_by_owner" => false)
when "/repos/GGULBAE/desk-setup-switcher/actions/permissions"
  json.call("enabled" => true, "allowed_actions" => "selected", "sha_pinning_required" => true)
when "/repos/GGULBAE/desk-setup-switcher/actions/permissions/selected-actions"
  json.call("github_owned_allowed" => true, "verified_allowed" => false, "patterns_allowed" => [])
when "/repos/GGULBAE/desk-setup-switcher/actions/permissions/workflow"
  json.call("default_workflow_permissions" => "read", "can_approve_pull_request_reviews" => false)
when "/repos/GGULBAE/desk-setup-switcher/labels/needs-triage"
  json.call("name" => "needs-triage", "present" => true)
when "/repos/GGULBAE/desk-setup-switcher/git/matching-refs/tags/v"
  nil
when "/repos/GGULBAE/desk-setup-switcher/releases?per_page=30"
  nil
when %r{\A/repos/GGULBAE/desk-setup-switcher/commits/[0-9a-f]{40}/check-runs\?check_name=Verify%20macOS%20app&app_id=15368&filter=latest&per_page=100\z}
  failed = ENV["MOCK_MODE"] == "latest-rerun-failed"
  json.call(
    "total_count" => 1,
    "items" => [
      {
        "id" => check_run_id,
        "name" => "Verify macOS app",
        "app_id" => 15_368,
        "check_suite_id" => check_suite_id,
        "head_sha" => commit,
        "status" => "completed",
        "conclusion" => failed ? "failure" : "success"
      }
    ]
  )
when %r{\A/repos/GGULBAE/desk-setup-switcher/actions/workflows/(\d+)/runs\?check_suite_id=(\d+)&head_sha=([0-9a-f]{40})&event=push&per_page=100\z}
  observed_workflow_id = Regexp.last_match(1).to_i
  observed_suite_id = Regexp.last_match(2).to_i
  observed_commit = Regexp.last_match(3)
  abort "unanchored workflow run lookup" unless observed_workflow_id == ci_workflow_id &&
    observed_suite_id == check_suite_id && observed_commit == commit
  if ENV["MOCK_MODE"] == "alternate-workflow-check"
    json.call("total_count" => 0, "items" => [])
  elsif ENV["MOCK_MODE"] == "ambiguous-runs"
    json.call("total_count" => 2, "items" => [workflow_run.call(workflow_run_id, 2, "completed", "success")])
    json.call("total_count" => 2, "items" => [workflow_run.call(workflow_run_id + 1, 2, "completed", "success")])
  elsif ENV["MOCK_MODE"] == "runs-count-mismatch"
    json.call("total_count" => 3, "items" => [workflow_run.call(workflow_run_id, 1, "completed", "success")])
    json.call("total_count" => 3, "items" => [workflow_run.call(workflow_run_id, 2, "completed", "success")])
  elsif ENV["MOCK_MODE"] == "truncated-runs-page"
    json.call("total_count" => 2, "items" => [workflow_run.call(workflow_run_id, 1, "completed", "success")])
    puts '{"total_count":2,"items":'
  else
    latest_conclusion = ENV["MOCK_MODE"] == "latest-rerun-failed" ? "failure" : "success"
    json.call("total_count" => 2, "items" => [workflow_run.call(workflow_run_id, 1, "completed", "success")])
    json.call("total_count" => 2, "items" => [workflow_run.call(workflow_run_id, 2, "completed", latest_conclusion)])
  end
when %r{\A/repos/GGULBAE/desk-setup-switcher/actions/runs/(\d+)/attempts/(\d+)/jobs\?per_page=100\z}
  observed_run_id = Regexp.last_match(1).to_i
  observed_attempt = Regexp.last_match(2).to_i
  abort "unanchored workflow jobs lookup" unless observed_run_id == workflow_run_id && observed_attempt == 2
  failed = ENV["MOCK_MODE"] == "latest-rerun-failed"
  job = workflow_job.call(
    workflow_job_id,
    check_run_id,
    observed_run_id,
    observed_attempt,
    "completed",
    failed ? "failure" : "success"
  )
  if ENV["MOCK_MODE"] == "jobs-count-mismatch"
    json.call("total_count" => 2, "items" => [job])
  elsif ENV["MOCK_MODE"] == "ambiguous-jobs"
    json.call("total_count" => 2, "items" => [job])
    json.call(
      "total_count" => 2,
      "items" => [
        workflow_job.call(
          workflow_job_id + 1,
          check_run_id + 1,
          observed_run_id,
          observed_attempt,
          "completed",
          "success"
        )
      ]
    )
  else
    json.call("total_count" => 1, "items" => [job])
  end
else
  abort "unexpected endpoint"
end
MOCK_GH
cat >"$mock_bin/ruby" <<'MOCK_RUBY'
#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ge 1 && "$1" == */remote_controls_policy.rb ]]; then
    if [[ "${MOCK_MODE:-}" == policy-preflight-internal-error && " $* " == *' --check-policy '* ]]; then
        exit 70
    fi
    if [[ "${MOCK_MODE:-}" == policy-final-internal-error && " $* " == *' --policy '* ]]; then
        exit 70
    fi
    if [[ "${MOCK_MODE:-}" == policy-validator-local-race && " $* " == *' --policy '* ]]; then
        status=0
        "$MOCK_REAL_RUBY" "$@" || status=$?
        if [[ "$status" -eq 0 ]]; then
            printf '\n# validator race\n' >>"$MOCK_CI_WORKFLOW_PATH"
        fi
        exit "$status"
    fi
fi

exec "$MOCK_REAL_RUBY" "$@"
MOCK_RUBY
chmod 0755 "$mock_bin/gh" "$mock_bin/ruby"

mock_log="$temporary_root/gh-calls.jsonl"
raw_marker='SENSITIVE_REMOTE_VARIABLE_VALUE_83A971'
wrapper="$test_repository/scripts/release/verify-remote-controls.sh"
ci_workflow_backup="$temporary_root/ci-workflow.yml.backup"
cp "$test_repository/.github/workflows/ci.yml" "$ci_workflow_backup"
last_status=0

run_wrapper() {
    local mode="$1"
    local stdout_path="$2"
    local stderr_path="$3"
    : >"$mock_log"
    set +e
    env \
        "PATH=$mock_bin:$PATH" \
        "HOME=${HOME:-/tmp}" \
        "TMPDIR=$test_tmp" \
        "MOCK_GH_LOG=$mock_log" \
        "MOCK_MODE=$mode" \
        "MOCK_COMMIT=$expected_commit" \
        "MOCK_WORKFLOW_BLOB=$workflow_blob" \
        "MOCK_WORKFLOW_PATH=$test_repository/.github/workflows/release.yml" \
        "MOCK_CI_WORKFLOW_BLOB=$ci_workflow_blob" \
        "MOCK_CI_WORKFLOW_PATH=$test_repository/.github/workflows/ci.yml" \
        "MOCK_REAL_RUBY=$real_ruby" \
        "RAW_VARIABLE_MARKER=$raw_marker" \
        GH_DEBUG=api \
        DEBUG=1 \
        "$wrapper" >"$stdout_path" 2>"$stderr_path"
    last_status=$?
    set -e
}

assert_evidence_unavailable_mode() {
    local mode="$1"
    local label="$2"
    local stdout_path="$temporary_root/$mode.stdout"
    local stderr_path="$temporary_root/$mode.stderr"
    run_wrapper "$mode" "$stdout_path" "$stderr_path"
    assert_equal 70 "$last_status" "$label"
    assert_empty "$stdout_path"
    assert_equal 'ERROR: remote controls evidence unavailable' \
        "$(tr -d '\n' <"$stderr_path")" \
        "$label (stable error)"
}

success_stdout="$temporary_root/success.stdout"
success_stderr="$temporary_root/success.stderr"
run_wrapper success "$success_stdout" "$success_stderr"
assert_equal 0 "$last_status" \
    "Complete mock evidence did not pass (status=$last_status, stderr=$(tr -d '\n' <"$success_stderr"))."
assert_empty "$success_stderr"
expected_success="OK remote-controls final-pre-tag repository=GGULBAE/desk-setup-switcher commit=$expected_commit release_workflow_blob=$workflow_blob ci_workflow_blob=$ci_workflow_blob ci_run_id=70001 ci_run_attempt=2 ci_job_id=10001 checks=1 manual_gates=1"
assert_equal "$expected_success" "$(tr -d '\n' <"$success_stdout")" "Success summary was not exact."

ruby -rjson -e '
  calls = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
  raise unless calls.length == 60
  headers = [
    "Accept: application/vnd.github+json",
    "X-GitHub-Api-Version: 2026-03-10",
    "Cache-Control: no-cache"
  ]
  calls.each do |call|
    raise unless call.first == "api"
    method_indices = call.each_index.select { |index| call.fetch(index) == "-X" }
    raise unless method_indices.length == 1 && call[method_indices.first + 1] == "GET"
    raise if call.any? do |argument|
      (argument.start_with?("-X") && argument != "-X") || argument.start_with?("--method")
    end
    raise if call.any? do |argument|
      argument.start_with?("-f") || argument.start_with?("-F") ||
        argument == "--raw-field" || argument.start_with?("--raw-field=") ||
        argument == "--field" || argument.start_with?("--field=") ||
        argument == "--input" || argument.start_with?("--input=")
    end
    raise if call.any? do |argument|
      argument.start_with?("-t") || argument.start_with?("-i") ||
        argument == "--template" || argument.start_with?("--template=") ||
        argument == "--include" || argument.start_with?("--include=") ||
        argument == "--verbose" || argument.start_with?("--cache")
    end
    raise unless call.each_cons(2).any? { |left, right| left == "--hostname" && right == "github.com" }
    headers.each { |header| raise unless call.each_cons(2).any? { |left, right| left == "-H" && right == header } }
  end
  ordered_endpoints = calls.map { |call| call.find { |item| item.start_with?("/") } }
  raise unless ordered_endpoints.first == "/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master"
  raise unless ordered_endpoints[1].include?("/contents/.github/workflows/release.yml?ref=")
  raise unless ordered_endpoints[2] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml"
  raise unless ordered_endpoints[3].include?("/contents/.github/workflows/ci.yml?ref=")
  raise unless ordered_endpoints[4] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml"
  raise unless ordered_endpoints[-5] == "/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master"
  raise unless ordered_endpoints[-4].include?("/contents/.github/workflows/release.yml?ref=")
  raise unless ordered_endpoints[-3] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml"
  raise unless ordered_endpoints[-2].include?("/contents/.github/workflows/ci.yml?ref=")
  raise unless ordered_endpoints[-1] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml"
  raise unless ordered_endpoints[5, 25] == ordered_endpoints[30, 25]
  counts = ordered_endpoints.tally
  raise unless counts.values.all? { |count| count == 2 }
  endpoints = calls.to_h { |call| [call.find { |item| item.start_with?("/") }, call] }
  paginated = endpoints.select do |endpoint, _call|
    endpoint.include?("rulesets?") || endpoint.include?("/rules/branches/") ||
      endpoint.include?("deployment-branch-policies") || endpoint.include?("/secrets?") ||
      endpoint.include?("/variables?") || endpoint.include?("/releases?") ||
      endpoint.include?("/check-runs?") || endpoint.include?("/runs?") || endpoint.include?("/jobs?")
  end
  paginated.each_value { |call| raise unless call.include?("--paginate") }
  variable_calls = calls.select do |call|
    call.any? { |argument| argument.start_with?("/") && argument.include?("/variables?") }
  end
  raise unless variable_calls.length == 4
  expected_variable_jq = "{total_count: .total_count, names: (.variables | map(.name))}"
  variable_calls.each do |call|
    jq_index = call.index("--jq")
    raise unless call.count("--jq") == 1 && jq_index && call[jq_index + 1] == expected_variable_jq
  end
  master_calls = calls.select { |call| call.include?("/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master") }
  content_calls = calls.select do |call|
    call.any? { |item| item.include?("/contents/.github/workflows/") && item.include?("?ref=") }
  end
  raise unless master_calls.length == 2 && content_calls.length == 4
  content_calls.each do |call|
    endpoint = call.find { |item| item.start_with?("/") }
    raise unless endpoint.match?(/\?ref=[0-9a-f]{40}\z/)
  end
  run_calls = calls.select do |call|
    call.any? { |item| item.include?("/actions/workflows/7000/runs?") }
  end
  raise unless run_calls.length == 2
  run_calls.each do |call|
    endpoint = call.find { |item| item.start_with?("/") }
    raise unless endpoint.include?("check_suite_id=90001")
    raise unless endpoint.include?("head_sha=#{ARGV.fetch(1)}")
    raise unless endpoint.include?("event=push") && !endpoint.include?("status=")
  end
  job_calls = calls.select do |call|
    call.any? { |item| item.include?("/actions/runs/70001/attempts/2/jobs?per_page=100") }
  end
  raise unless job_calls.length == 2
' "$mock_log" "$expected_commit" || fail "gh request contract was incomplete."
pass

if grep -R -F -q -- "$raw_marker" \
    "$success_stdout" "$success_stderr" "$mock_log" "$test_tmp"; then
    fail "A raw variable value reached a file or process output."
fi
pass

drift_stdout="$temporary_root/drift.stdout"
drift_stderr="$temporary_root/drift.stderr"
run_wrapper anchor-drift "$drift_stdout" "$drift_stderr"
assert_equal 1 "$last_status" "Anchor drift did not use the policy-mismatch exit."
assert_empty "$drift_stdout"
assert_equal 'ERROR: remote controls policy mismatch' \
    "$(tr -d '\n' <"$drift_stderr")" \
    "Anchor drift exposed a non-generic error."

state_stdout="$temporary_root/state-drift.stdout"
state_stderr="$temporary_root/state-drift.stderr"
run_wrapper workflow-state-drift "$state_stdout" "$state_stderr"
assert_equal 1 "$last_status" "Workflow state drift did not fail closed."
assert_empty "$state_stdout"
assert_equal 'ERROR: remote controls policy mismatch' \
    "$(tr -d '\n' <"$state_stderr")" \
    "Workflow state drift exposed a non-generic error."

mutable_stdout="$temporary_root/mutable-drift.stdout"
mutable_stderr="$temporary_root/mutable-drift.stderr"
run_wrapper mutable-control-drift "$mutable_stdout" "$mutable_stderr"
assert_equal 70 "$last_status" "Mutable-control drift did not invalidate the snapshot."
assert_empty "$mutable_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
    "$(tr -d '\n' <"$mutable_stderr")" \
    "Mutable-control drift exposed observed values."

alternate_stdout="$temporary_root/alternate-workflow.stdout"
alternate_stderr="$temporary_root/alternate-workflow.stderr"
run_wrapper alternate-workflow-check "$alternate_stdout" "$alternate_stderr"
assert_equal 70 "$last_status" "A same-name check from another workflow was accepted."
assert_empty "$alternate_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
    "$(tr -d '\n' <"$alternate_stderr")" \
    "Alternate-workflow evidence exposed observed values."
ruby -rjson -e '
  calls = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
  endpoints = calls.map { |call| call.find { |argument| argument.start_with?("/") } }
  run_endpoints = endpoints.grep(%r{/actions/workflows/7000/runs\?})
  raise unless run_endpoints.length == 1
  raise unless run_endpoints.first.include?("check_suite_id=90002")
  raise if endpoints.any? { |endpoint| endpoint&.include?("/attempts/") }
' "$mock_log" || fail "Alternate-workflow check was not resolved through the authoritative CI workflow."
pass

ambiguous_runs_stdout="$temporary_root/ambiguous-runs.stdout"
ambiguous_runs_stderr="$temporary_root/ambiguous-runs.stderr"
run_wrapper ambiguous-runs "$ambiguous_runs_stdout" "$ambiguous_runs_stderr"
assert_equal 70 "$last_status" "Ambiguous latest workflow runs were accepted."
assert_empty "$ambiguous_runs_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
    "$(tr -d '\n' <"$ambiguous_runs_stderr")" \
    "Ambiguous workflow runs exposed observed values."

ambiguous_jobs_stdout="$temporary_root/ambiguous-jobs.stdout"
ambiguous_jobs_stderr="$temporary_root/ambiguous-jobs.stderr"
run_wrapper ambiguous-jobs "$ambiguous_jobs_stdout" "$ambiguous_jobs_stderr"
assert_equal 70 "$last_status" "Ambiguous workflow jobs were accepted."
assert_empty "$ambiguous_jobs_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
    "$(tr -d '\n' <"$ambiguous_jobs_stderr")" \
    "Ambiguous workflow jobs exposed observed values."

assert_evidence_unavailable_mode \
    runs-count-mismatch \
    "A paginated workflow-run total_count mismatch was accepted."
assert_evidence_unavailable_mode \
    jobs-count-mismatch \
    "A paginated workflow-job total_count mismatch was accepted."
assert_evidence_unavailable_mode \
    truncated-runs-page \
    "A truncated later workflow-run page was accepted."
assert_evidence_unavailable_mode \
    ruleset-list-detail-drift \
    "Ruleset list/detail drift was accepted."

failed_rerun_stdout="$temporary_root/failed-rerun.stdout"
failed_rerun_stderr="$temporary_root/failed-rerun.stderr"
run_wrapper latest-rerun-failed "$failed_rerun_stdout" "$failed_rerun_stderr"
assert_equal 1 "$last_status" "A failed latest CI rerun was accepted."
assert_empty "$failed_rerun_stdout"
assert_equal 'ERROR: remote controls policy mismatch' \
    "$(tr -d '\n' <"$failed_rerun_stderr")" \
    "A failed latest CI rerun did not reach the stable policy gate."

missing_stdout="$temporary_root/missing-bypass.stdout"
missing_stderr="$temporary_root/missing-bypass.stderr"
run_wrapper missing-bypass "$missing_stdout" "$missing_stderr"
assert_equal 70 "$last_status" "Omitted bypass_actors was not evidence-unavailable."
assert_empty "$missing_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
    "$(tr -d '\n' <"$missing_stderr")" \
    "Missing bypass evidence exposed response details."

api_stdout="$temporary_root/api.stdout"
api_stderr="$temporary_root/api.stderr"
run_wrapper api-failure "$api_stdout" "$api_stderr"
assert_equal 70 "$last_status" "API failure did not use exit 70."
assert_empty "$api_stdout"
assert_equal 'ERROR: remote controls API unavailable (endpoint S02)' \
    "$(tr -d '\n' <"$api_stderr")" \
    "API failure did not use its generic endpoint ID."
if grep -F -q -- '/repos/private-path' "$api_stderr" || grep -F -q -- "$raw_marker" "$api_stderr"; then
    fail "Raw API failure content reached stderr."
fi
pass

preflight_internal_stdout="$temporary_root/preflight-internal.stdout"
preflight_internal_stderr="$temporary_root/preflight-internal.stderr"
run_wrapper policy-preflight-internal-error "$preflight_internal_stdout" "$preflight_internal_stderr"
assert_equal 70 "$last_status" "A policy preflight internal error was misclassified."
assert_empty "$preflight_internal_stdout"
assert_equal 'ERROR: remote controls collection failed' \
    "$(tr -d '\n' <"$preflight_internal_stderr")" \
    "A policy preflight internal error was exposed or treated as mismatch."
assert_empty "$mock_log"

final_internal_stdout="$temporary_root/final-internal.stdout"
final_internal_stderr="$temporary_root/final-internal.stderr"
run_wrapper policy-final-internal-error "$final_internal_stdout" "$final_internal_stderr"
assert_equal 70 "$last_status" "A final policy validator internal error was misclassified."
assert_empty "$final_internal_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
    "$(tr -d '\n' <"$final_internal_stderr")" \
    "A final policy validator internal error was exposed or treated as mismatch."

dirty_path="$test_repository/untracked-local-state"
: >"$dirty_path"
dirty_stdout="$temporary_root/dirty.stdout"
dirty_stderr="$temporary_root/dirty.stderr"
run_wrapper success "$dirty_stdout" "$dirty_stderr"
assert_equal 1 "$last_status" "A dirty configured:true worktree reached remote collection."
assert_empty "$dirty_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$dirty_stderr")" \
    "A dirty worktree did not use the stable local-anchor error."
assert_empty "$mock_log"
rm -f -- "$dirty_path"

shallow_path="$(git -C "$test_repository" rev-parse --absolute-git-dir)/shallow"
printf '%s\n' "$expected_commit" >"$shallow_path"
shallow_stdout="$temporary_root/shallow.stdout"
shallow_stderr="$temporary_root/shallow.stderr"
run_wrapper success "$shallow_stdout" "$shallow_stderr"
assert_equal 1 "$last_status" "A shallow repository reached remote collection."
assert_empty "$shallow_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$shallow_stderr")" \
    "A shallow repository did not use the stable local-anchor error."
assert_empty "$mock_log"
rm -f -- "$shallow_path"

git -C "$test_repository" update-index --assume-unchanged .github/workflows/ci.yml
printf '\n# local blob mismatch\n' >>"$test_repository/.github/workflows/ci.yml"
blob_stdout="$temporary_root/blob-mismatch.stdout"
blob_stderr="$temporary_root/blob-mismatch.stderr"
run_wrapper success "$blob_stdout" "$blob_stderr"
assert_equal 1 "$last_status" "A CI workflow worktree/blob mismatch reached remote collection."
assert_empty "$blob_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$blob_stderr")" \
    "A CI workflow blob mismatch did not use the stable local-anchor error."
assert_empty "$mock_log"
cp "$ci_workflow_backup" "$test_repository/.github/workflows/ci.yml"
git -C "$test_repository" update-index --no-assume-unchanged .github/workflows/ci.yml

collection_race_stdout="$temporary_root/collection-race.stdout"
collection_race_stderr="$temporary_root/collection-race.stderr"
run_wrapper collection-local-race "$collection_race_stdout" "$collection_race_stderr"
assert_equal 1 "$last_status" "A collection-time local mutation was accepted."
assert_empty "$collection_race_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$collection_race_stderr")" \
    "A collection-time local mutation did not fail at the local anchor."
cp "$ci_workflow_backup" "$test_repository/.github/workflows/ci.yml"

validator_race_stdout="$temporary_root/validator-race.stdout"
validator_race_stderr="$temporary_root/validator-race.stderr"
run_wrapper policy-validator-local-race "$validator_race_stdout" "$validator_race_stderr"
assert_equal 1 "$last_status" "A policy-validator local mutation crossed the output boundary."
assert_empty "$validator_race_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$validator_race_stderr")" \
    "A policy-validator local mutation did not fail at the final local recheck."
cp "$ci_workflow_backup" "$test_repository/.github/workflows/ci.yml"

chmod 0500 "$test_tmp"
tmp_stdout="$temporary_root/tmp-failure.stdout"
tmp_stderr="$temporary_root/tmp-failure.stderr"
run_wrapper success "$tmp_stdout" "$tmp_stderr"
chmod 0700 "$test_tmp"
assert_equal 70 "$last_status" "A temporary-directory failure was misclassified."
assert_empty "$tmp_stdout"
assert_equal 'ERROR: remote controls collection failed' \
    "$(tr -d '\n' <"$tmp_stderr")" \
    "A temporary-directory failure leaked infrastructure details."
assert_empty "$mock_log"

# A configured:false operational policy must stop at the first preflight even
# if the worktree is dirty and a mock gh is available.
ruby -rjson -e '
  path = ARGV.fetch(0)
  value = {
    "schemaVersion" => "desk-setup-switcher.remote-release-controls-policy/v1",
    "phase" => "final-pre-tag",
    "configured" => false
  }
  File.write(path, JSON.pretty_generate(value) + "\n", mode: "w", perm: 0o600)
' "$test_repository/scripts/release/remote-controls-policy.json"
: >"$mock_log"
disabled_stdout="$temporary_root/disabled.stdout"
disabled_stderr="$temporary_root/disabled.stderr"
run_wrapper success "$disabled_stdout" "$disabled_stderr"
assert_equal 1 "$last_status" "configured:false did not fail."
assert_empty "$disabled_stdout"
assert_equal 'ERROR: remote controls policy mismatch' \
    "$(tr -d '\n' <"$disabled_stderr")" \
    "configured:false did not use the stable policy error."
assert_empty "$mock_log"

printf 'Remote controls collector tests passed: %d assertions\n' "$assertions"
