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
runtime_gh_token="$($real_ruby -rsecurerandom -e 'STDOUT.write(SecureRandom.hex(32))')"
runtime_gh_token_sha256="$(printf '%s' "$runtime_gh_token" | shasum -a 256 | awk '{print $1}')"
wrapper_timeout_seconds=90

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

assert_matches() {
    local pattern="$1"
    local actual="$2"
    local label="$3"
    [[ "$actual" =~ $pattern ]] || fail "$label"
    pass
}

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/desk-setup-remote-controls-test.XXXXXX")"
chmod 0700 "$temporary_root"
temporary_root="$(cd "$temporary_root" && pwd -P)"
cleanup() {
    if [[ "${KEEP_REMOTE_CONTROLS_TEST_TEMP:-}" == 1 ]]; then
        printf 'Preserved remote-controls test directory: %s\n' "$temporary_root" >&2
    else
        rm -rf -- "$temporary_root"
    fi
}
trap cleanup EXIT

test_repository="$temporary_root/repository"
test_tmp="$temporary_root/runtime-tmp"
mock_bin="$temporary_root/mock-bin"
mkdir -p \
    "$test_repository/scripts/release/fixtures/remote-controls" \
    "$test_repository/scripts/lib" \
    "$test_repository/.github/workflows" \
    "$test_repository/Config" \
    "$test_repository/docs/evidence/releases/v0.1.0" \
    "$test_tmp" \
    "$mock_bin"
chmod 0700 "$test_tmp"

cp "$SCRIPT_DIR/verify-remote-controls.sh" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/lib.sh" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/collect_remote_controls_evidence.rb" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/remote_controls_policy.rb" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/release_policy.rb" "$test_repository/scripts/release/"
cp "$SCRIPT_DIR/fixtures/remote-controls/policy-v3.json" \
    "$test_repository/scripts/release/fixtures/remote-controls/"
cp "$ROOT_DIR/.github/workflows/release.yml" "$test_repository/.github/workflows/release.yml"
cp "$ROOT_DIR/.github/workflows/signed-release-candidate.yml" \
    "$test_repository/.github/workflows/signed-release-candidate.yml"
cp "$ROOT_DIR/.github/workflows/ci.yml" "$test_repository/.github/workflows/ci.yml"
cp "$ROOT_DIR/.github/workflows/publish-release.yml" \
    "$test_repository/.github/workflows/publish-release.yml"
cp "$ROOT_DIR/scripts/lib/common.sh" "$test_repository/scripts/lib/common.sh"
cp "$ROOT_DIR/Config/Info.plist" "$test_repository/Config/Info.plist"
ruby -rjson -rtime -e '
  directory = ARGV.fetch(0)
  now = Time.now.utc
  base = {
    "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
    "phase" => "predecessor-pre-tag",
    "observedAt" => now.iso8601,
    "observer" => { "id" => 1001, "login" => "GGULBAE", "type" => "User" },
    "administratorBypassEnabled" => false,
    "sourceArtifactSHA256" => "1" * 64,
    "redactionReviewed" => true,
    "subject" => { "tag" => "v0.1.0" }
  }
  candidate = base.merge(
    "control" => "release-candidate-administrator-bypass-disabled",
    "token" => nil,
    "tokenPermissions" => []
  )
  publication = base.merge(
    "control" => "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
    "sourceArtifactSHA256" => "2" * 64,
    "token" => {
      "type" => "fine-grained-personal-access-token",
      "resourceOwner" => "GGULBAE",
      "repositorySelection" => ["GGULBAE/desk-setup-switcher"],
      "accountPermissions" => [],
      "organizationPermissions" => [],
      "issuedAt" => now.iso8601,
      "expiresAt" => (now + 30 * 86_400).iso8601
    },
    "tokenPermissions" => %w[
      actions:read administration:read attestations:read contents:read metadata:read
    ]
  )
  File.binwrite(File.join(directory, "release-candidate-admin-bypass.json"), JSON.generate(candidate) + "\n")
  File.binwrite(File.join(directory, "release-publication-admin-token-scope.json"), JSON.generate(publication) + "\n")
' "$test_repository/docs/evidence/releases/v0.1.0"
chmod 0755 \
    "$test_repository/scripts/release/verify-remote-controls.sh" \
    "$test_repository/scripts/release/collect_remote_controls_evidence.rb" \
    "$test_repository/scripts/release/remote_controls_policy.rb"

git -C "$test_repository" init -q
git -C "$test_repository" checkout -q -b master
git -C "$test_repository" config user.name 'Synthetic Collector Test'
git -C "$test_repository" config user.email 'collector@example.invalid'
workflow_blob="$(git -C "$test_repository" hash-object .github/workflows/signed-release-candidate.yml)"
legacy_workflow_blob="$(git -C "$test_repository" hash-object .github/workflows/release.yml)"
ci_workflow_blob="$(git -C "$test_repository" hash-object .github/workflows/ci.yml)"
publication_workflow_blob="$(
    git -C "$test_repository" hash-object .github/workflows/publish-release.yml
)"
ruby -rjson -e '
  source, output, blob, ci_blob, publication_blob, legacy_blob = ARGV
  policy = JSON.parse(File.read(source))
  repository = policy.fetch("repository")
  repository["fullName"] = "GGULBAE/desk-setup-switcher"
  operator = policy.fetch("actors").fetch("operator")
  operator["login"] = "GGULBAE"
  publisher = policy.fetch("actors").fetch("publisher")
  publisher["login"] = "ggulbae"
  policy.fetch("release").fetch("candidateWorkflow")["blobSha"] = blob
  policy.fetch("release").fetch("ci").fetch("workflow")["blobSha"] = ci_blob
  policy.fetch("release").fetch("publicationWorkflow")["blobSha"] = publication_blob
  policy.fetch("release").fetch("legacyWorkflow")["blobSha"] = legacy_blob
  File.write(output, JSON.pretty_generate(policy) + "\n", mode: "w", perm: 0o600)
' \
    "$test_repository/scripts/release/fixtures/remote-controls/policy-v3.json" \
    "$test_repository/scripts/release/remote-controls-policy.json" \
    "$workflow_blob" \
    "$ci_workflow_blob" \
    "$publication_workflow_blob" \
    "$legacy_workflow_blob"

git -C "$test_repository" add -- .
git -C "$test_repository" commit -q -m 'Synthetic remote controls fixture'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"
release_commit="$expected_commit"

cat >"$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "json"

abort "debug environment leaked" if ENV.key?("GH_DEBUG") || ENV.key?("DEBUG")
github_token = ENV.delete("GH_TOKEN")
abort "scoped GitHub token mismatch" unless github_token &&
  Digest::SHA256.hexdigest(github_token) == ENV.fetch("MOCK_GH_TOKEN_SHA256")
github_token = String.new(github_token)
github_token.clear
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

if ENV["MOCK_MODE"] == "signal-hang" &&
   endpoint.end_with?("/git/ref/heads/master")
  Signal.trap("TERM", "IGNORE")
  File.binwrite(ENV.fetch("MOCK_HANG_MARKER"), "#{Process.pid}\t#{Process.ppid}\n")
  loop { sleep 1 }
end

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
legacy_blob = ENV.fetch("MOCK_LEGACY_WORKFLOW_BLOB")
ci_blob = ENV.fetch("MOCK_CI_WORKFLOW_BLOB")
publication_blob = ENV.fetch("MOCK_PUBLICATION_WORKFLOW_BLOB")
release_tag_object = ENV.fetch("MOCK_RELEASE_TAG_OBJECT", "8" * 40)
predecessor_tag_object = ENV.fetch("MOCK_PREDECESSOR_TAG_OBJECT", "7" * 40)
predecessor_commit = ENV.fetch("MOCK_PREDECESSOR_COMMIT", commit)
repository = "GGULBAE/desk-setup-switcher"
actor = { "id" => 1001, "login" => "GGULBAE", "type" => "User" }
reviewer = { "id" => 1002, "login" => "synthetic-reviewer", "type" => "User" }
ci_workflow_id = 7000
publication_workflow_id = 7002
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
workflow_job = lambda do |id, check_id, name, run_id, attempt, status, conclusion|
  {
    "id" => id,
    "run_id" => run_id,
    "run_attempt" => attempt,
    "name" => name,
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
      { "context" => "Verify macOS app", "integration_id" => 15_368 },
      { "context" => "Verify public site and release assets", "integration_id" => 15_368 }
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
when %r{\A/repos/GGULBAE/desk-setup-switcher/contents/\.github/workflows/signed-release-candidate\.yml\?ref=([0-9a-f]{40})\z}
  anchored_commit = Regexp.last_match(1)
  content = Base64.strict_encode64(File.binread(ENV.fetch("MOCK_WORKFLOW_PATH")))
  json.call(
    "commit_sha" => anchored_commit,
    "type" => "file",
    "path" => ".github/workflows/signed-release-candidate.yml",
    "sha" => blob,
    "encoding" => "base64",
    "content" => content
  )
when "/repos/GGULBAE/desk-setup-switcher/actions/workflows/signed-release-candidate.yml"
  state = ENV["MOCK_MODE"] == "workflow-state-drift" && occurrence == 2 ? "disabled_manually" : "active"
  json.call(
    "id" => 7001,
    "name" => "Signed release candidate",
    "path" => ".github/workflows/signed-release-candidate.yml",
    "state" => state
  )
when %r{\A/repos/GGULBAE/desk-setup-switcher/contents/\.github/workflows/release\.yml\?ref=([0-9a-f]{40})\z}
  anchored_commit = Regexp.last_match(1)
  content = Base64.strict_encode64(File.binread(ENV.fetch("MOCK_LEGACY_WORKFLOW_PATH")))
  json.call(
    "commit_sha" => anchored_commit,
    "type" => "file",
    "path" => ".github/workflows/release.yml",
    "sha" => legacy_blob,
    "encoding" => "base64",
    "content" => content
  )
when "/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml"
  json.call(
    "id" => 7003,
    "name" => "Retired legacy release workflow",
    "path" => ".github/workflows/release.yml",
    "state" => "disabled_manually"
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
when %r{\A/repos/GGULBAE/desk-setup-switcher/contents/\.github/workflows/publish-release\.yml\?ref=([0-9a-f]{40})\z}
  anchored_commit = Regexp.last_match(1)
  content = Base64.strict_encode64(File.binread(ENV.fetch("MOCK_PUBLICATION_WORKFLOW_PATH")))
  json.call(
    "commit_sha" => anchored_commit,
    "type" => "file",
    "path" => ".github/workflows/publish-release.yml",
    "sha" => publication_blob,
    "encoding" => "base64",
    "content" => content
  )
when "/repos/GGULBAE/desk-setup-switcher/actions/workflows/publish-release.yml"
  json.call(
    "id" => publication_workflow_id,
    "name" => "Publish approved signed release",
    "path" => ".github/workflows/publish-release.yml",
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
  json.call(
    "total_count" => 2,
    "items" => [
      { "name" => "v0.0.9", "type" => "tag" },
      { "name" => "v0.1.0", "type" => "tag" }
    ]
  )
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
when "/repos/GGULBAE/desk-setup-switcher/environments/release-publication"
  json.call(
    "name" => "release-publication",
    "protection_rules" => [
      { "type" => "required_reviewers", "prevent_self_review" => true,
        "reviewers" => [{ "type" => "User", "reviewer" => reviewer }] },
      { "type" => "branch_policy" }
    ],
    "deployment_branch_policy" => { "protected_branches" => false, "custom_branch_policies" => true }
  )
when "/repos/GGULBAE/desk-setup-switcher/environments/release-publication/deployment-branch-policies?per_page=30"
  json.call("total_count" => 1, "items" => [{ "name" => "v0.1.0", "type" => "tag" }])
when "/repos/GGULBAE/desk-setup-switcher/environments/release-publication/secrets?per_page=30"
  json.call("total_count" => 1, "names" => ["RELEASE_ADMIN_READ_TOKEN"])
when "/repos/GGULBAE/desk-setup-switcher/environments/release-publication/variables?per_page=30"
  json.call("total_count" => 2, "names" => ["APPLE_TEAM_ID"])
  json.call("total_count" => 2, "names" => ["DEVELOPER_ID_APPLICATION"])
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
when "/repos/GGULBAE/desk-setup-switcher/actions/workflows?per_page=100"
  workflows = [
    { "id" => ci_workflow_id, "name" => "CI", "path" => ".github/workflows/ci.yml", "state" => "active" },
    { "id" => 7001, "name" => "Signed release candidate", "path" => ".github/workflows/signed-release-candidate.yml", "state" => "active" },
    { "id" => publication_workflow_id, "name" => "Publish approved signed release", "path" => ".github/workflows/publish-release.yml", "state" => "active" },
    { "id" => 7003, "name" => "Retired legacy release workflow", "path" => ".github/workflows/release.yml", "state" => "disabled_manually" }
  ]
  if ENV["MOCK_MODE"] == "workflow-inventory-drift" && occurrence == 2
    workflows.fetch(2)["state"] = "disabled_manually"
  elsif ENV["MOCK_MODE"] == "workflow-inventory-extra"
    workflows << { "id" => 7999, "name" => "Unexpected", "path" => ".github/workflows/unexpected.yml", "state" => "active" }
  elsif ENV["MOCK_MODE"] == "workflow-inventory-duplicate"
    workflows << workflows.first.dup
  end
  total = ENV["MOCK_MODE"] == "workflow-inventory-truncated" ? workflows.length + 1 : workflows.length
  json.call("total_count" => total, "items" => workflows.first(2))
  json.call("total_count" => total, "items" => workflows.drop(2)) unless ENV["MOCK_MODE"] == "workflow-inventory-truncated"
when "/repos/GGULBAE/desk-setup-switcher/git/matching-refs/tags/v?per_page=100"
  if %w[final-pre-tag pre-publication].include?(ENV.fetch("MOCK_PHASE"))
    json.call(
      "ref" => "refs/tags/v0.0.9",
      "object_type" => "tag",
      "object_sha" => predecessor_tag_object
    )
  end
  if ENV.fetch("MOCK_PHASE") == "pre-publication"
    json.call(
      "ref" => "refs/tags/v0.1.0",
      "object_type" => "tag",
      "object_sha" => release_tag_object
    )
  end
when "/repos/GGULBAE/desk-setup-switcher/commits/tags/v0.0.9"
  abort "predecessor commit requested before the tag exists" if
    ENV.fetch("MOCK_PHASE") == "predecessor-pre-tag"
  json.call("commit_sha" => predecessor_commit)
when "/repos/GGULBAE/desk-setup-switcher/git/tags/#{predecessor_tag_object}"
  abort "predecessor object requested before the tag exists" if
    ENV.fetch("MOCK_PHASE") == "predecessor-pre-tag"
  json.call(
    "tag_object_sha" => predecessor_tag_object,
    "tag" => "v0.0.9",
    "target_type" => "commit",
    "target_sha" => predecessor_commit
  )
when "/repos/GGULBAE/desk-setup-switcher/commits/tags/v0.1.0"
  abort "tag commit requested outside pre-publication" unless ENV.fetch("MOCK_PHASE") == "pre-publication"
  json.call("commit_sha" => ENV.fetch("MOCK_RELEASE_COMMIT"))
when "/repos/GGULBAE/desk-setup-switcher/git/tags/#{release_tag_object}"
  abort "tag object requested outside pre-publication" unless ENV.fetch("MOCK_PHASE") == "pre-publication"
  json.call(
    "tag_object_sha" => release_tag_object,
    "tag" => "v0.1.0",
    "target_type" => "commit",
    "target_sha" => ENV.fetch("MOCK_RELEASE_COMMIT")
  )
when "/repos/GGULBAE/desk-setup-switcher/releases?per_page=100"
  if ENV.fetch("MOCK_PHASE") == "pre-publication"
    release_id = ENV.fetch("MOCK_RELEASE_ID").to_i
    release_id += 1 if ENV["MOCK_MODE"] == "pre-publication-release-drift" && occurrence == 2
    json.call(
      "id" => release_id,
      "tag_name" => "v0.1.0",
      "draft" => true,
      "prerelease" => true
    )
  end
when %r{\A/repos/GGULBAE/desk-setup-switcher/commits/[0-9a-f]{40}/check-runs\?app_id=15368&filter=latest&per_page=100\z}
  primary_failed = ENV["MOCK_MODE"] == "latest-rerun-failed"
  public_failed = ENV["MOCK_MODE"] == "public-check-failed"
  checks = [
    {
      "id" => check_run_id,
      "name" => "Verify macOS app",
      "app_id" => 15_368,
      "check_suite_id" => check_suite_id,
      "head_sha" => commit,
      "status" => "completed",
      "conclusion" => primary_failed ? "failure" : "success"
    },
    {
      "id" => check_run_id + 1,
      "name" => "Verify public site and release assets",
      "app_id" => 15_368,
      "check_suite_id" => ENV["MOCK_MODE"] == "public-check-suite-drift" ? check_suite_id + 1 : check_suite_id,
      "head_sha" => commit,
      "status" => "completed",
      "conclusion" => public_failed ? "failure" : "success"
    }
  ]
  checks.pop if ENV["MOCK_MODE"] == "missing-public-check"
  json.call(
    "total_count" => checks.length,
    "items" => checks
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
  primary_failed = ENV["MOCK_MODE"] == "latest-rerun-failed"
  public_failed = ENV["MOCK_MODE"] == "public-job-failed"
  primary_job = workflow_job.call(
    workflow_job_id,
    check_run_id,
    "Verify macOS app",
    observed_run_id,
    observed_attempt,
    "completed",
    primary_failed ? "failure" : "success"
  )
  public_job = workflow_job.call(
    workflow_job_id + 1,
    check_run_id + 1,
    "Verify public site and release assets",
    observed_run_id,
    observed_attempt,
    "completed",
    public_failed ? "failure" : "success"
  )
  jobs = [primary_job, public_job]
  jobs.pop if ENV["MOCK_MODE"] == "missing-public-job"
  if ENV["MOCK_MODE"] == "jobs-count-mismatch"
    json.call("total_count" => 3, "items" => jobs)
  elsif ENV["MOCK_MODE"] == "ambiguous-jobs"
    json.call("total_count" => 3, "items" => jobs)
    json.call(
      "total_count" => 3,
      "items" => [
        workflow_job.call(
          workflow_job_id + 2,
          check_run_id + 2,
          "Verify macOS app",
          observed_run_id,
          observed_attempt,
          "completed",
          "success"
        )
      ]
    )
  else
    json.call("total_count" => jobs.length, "items" => jobs)
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
    if [[ "${MOCK_MODE:-}" == policy-final-internal-error \
        && " $* " == *' --evidence '*'/evidence-2.json '* ]]; then
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
    local mock_phase="final-pre-tag"
    local final_evidence_output="$temporary_root/$mode.final-pre-tag.json"
    local predecessor_evidence_output="$temporary_root/$mode.predecessor-pre-tag.json"
    local wrapper_pid_path="$temporary_root/$mode.wrapper.pid"
    shift 3
    if [[ " $* " == *' predecessor-pre-tag '* ]]; then
        mock_phase="predecessor-pre-tag"
        rm -f -- "$predecessor_evidence_output"
        set -- --phase predecessor-pre-tag --evidence-output "$predecessor_evidence_output"
    elif [[ " $* " == *' pre-publication '* ]]; then
        mock_phase="pre-publication"
        set -- --predecessor-commit "$predecessor_commit" \
            --predecessor-tag-object "$predecessor_tag_object" \
            --release-tag-object "$release_tag_object" "$@"
    else
        rm -f -- "$final_evidence_output"
        set -- --phase final-pre-tag \
            --predecessor-commit "$predecessor_commit" \
            --predecessor-tag-object "$predecessor_tag_object" \
            --evidence-output "$final_evidence_output" "$@"
    fi
    printf 'Remote controls collector scenario: %s (%s)\n' "$mode" "$mock_phase" >&2
    : >"$mock_log"
    rm -f -- "$wrapper_pid_path"
    set +e
    env \
        "PATH=$mock_bin:$PATH" \
        "HOME=${HOME:-/tmp}" \
        "TMPDIR=$test_tmp" \
        "MOCK_GH_LOG=$mock_log" \
        "MOCK_HANG_MARKER=$temporary_root/signal-hang.marker" \
        "MOCK_WRAPPER_PID_PATH=$wrapper_pid_path" \
        "MOCK_MODE=$mode" \
        "MOCK_PHASE=$mock_phase" \
        "MOCK_COMMIT=$expected_commit" \
        "MOCK_PREDECESSOR_COMMIT=${predecessor_commit:-$expected_commit}" \
        "MOCK_PREDECESSOR_TAG_OBJECT=${predecessor_tag_object:-7777777777777777777777777777777777777777}" \
        "MOCK_RELEASE_COMMIT=$release_commit" \
        "MOCK_RELEASE_TAG_OBJECT=${release_tag_object:-8888888888888888888888888888888888888888}" \
        "MOCK_RELEASE_ID=12345" \
        "MOCK_WORKFLOW_BLOB=$workflow_blob" \
        "MOCK_WORKFLOW_PATH=$test_repository/.github/workflows/signed-release-candidate.yml" \
        "MOCK_LEGACY_WORKFLOW_BLOB=$legacy_workflow_blob" \
        "MOCK_LEGACY_WORKFLOW_PATH=$test_repository/.github/workflows/release.yml" \
        "MOCK_CI_WORKFLOW_BLOB=$ci_workflow_blob" \
        "MOCK_CI_WORKFLOW_PATH=$test_repository/.github/workflows/ci.yml" \
        "MOCK_PUBLICATION_WORKFLOW_BLOB=$publication_workflow_blob" \
        "MOCK_PUBLICATION_WORKFLOW_PATH=$test_repository/.github/workflows/publish-release.yml" \
        "MOCK_REAL_RUBY=$real_ruby" \
        "MOCK_GH_TOKEN_SHA256=$runtime_gh_token_sha256" \
        "REMOTE_CONTROLS_TEST_WRAPPER_TIMEOUT_SECONDS=$wrapper_timeout_seconds" \
        "RAW_VARIABLE_MARKER=$raw_marker" \
        "GH_TOKEN=$runtime_gh_token" \
        GH_DEBUG=api \
        DEBUG=1 \
        "$real_ruby" -e '
          timeout = Integer(ENV.fetch("REMOTE_CONTROLS_TEST_WRAPPER_TIMEOUT_SECONDS"), 10)
          pid = Process.spawn(*ARGV, pgroup: true)
          File.write(ENV.fetch("MOCK_WRAPPER_PID_PATH"), "#{pid}\n", mode: "w", perm: 0o600)
          deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout
          loop do
            completed = Process.waitpid(pid, Process::WNOHANG)
            if completed
              status = $?
              exit(status.exitstatus || 128 + status.termsig)
            end
            if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
              begin
                Process.kill("TERM", -pid)
              rescue Errno::ESRCH
              end
              sleep 0.25
              begin
                Process.kill("KILL", -pid)
              rescue Errno::ESRCH
              end
              begin
                Process.waitpid(pid)
              rescue Errno::ECHILD
              end
              exit 124
            end
            sleep 0.05
          end
        ' "$wrapper" "$@" >"$stdout_path" 2>"$stderr_path"
    last_status=$?
    set -e
    printf '%s\n' "$last_status" >"$temporary_root/$mode.status"
}

assert_evidence_unavailable_mode() {
    local mode="$1"
    local label="$2"
    local stdout_path="$temporary_root/$mode.stdout"
    local stderr_path="$temporary_root/$mode.stderr"
    run_wrapper "$mode" "$stdout_path" "$stderr_path"
    if [[ "$last_status" == 124 ]]; then
        fail "Collector scenario $mode exceeded the ${wrapper_timeout_seconds}-second test timeout before a verdict."
    fi
    assert_equal 70 "$last_status" "$label"
    assert_empty "$stdout_path"
    assert_equal 'ERROR: remote controls evidence unavailable' \
        "$(tr -d '\n' <"$stderr_path")" \
        "$label (stable error)"
}

assert_policy_mismatch_mode() {
    local mode="$1"
    local label="$2"
    local stdout_path="$temporary_root/$mode.stdout"
    local stderr_path="$temporary_root/$mode.stderr"
    run_wrapper "$mode" "$stdout_path" "$stderr_path"
    assert_equal 1 "$last_status" "$label"
    assert_empty "$stdout_path"
    assert_equal 'ERROR: remote controls policy mismatch' \
        "$(tr -d '\n' <"$stderr_path")" \
        "$label (stable error)"
}

predecessor_stdout="$temporary_root/predecessor-success.stdout"
predecessor_stderr="$temporary_root/predecessor-success.stderr"
run_wrapper predecessor-success "$predecessor_stdout" "$predecessor_stderr" predecessor-pre-tag
assert_equal 0 "$last_status" \
    "Complete predecessor-pre-tag evidence did not pass (stderr=$(tr -d '\n' <"$predecessor_stderr"))."
assert_empty "$predecessor_stderr"
predecessor_external_output="$temporary_root/predecessor-success.predecessor-pre-tag.json"
[[ -f "$predecessor_external_output" && ! -L "$predecessor_external_output" && \
    "$(stat -f %Lp "$predecessor_external_output")" == 600 ]] || \
    fail "The protected predecessor-pre-tag output was not one mode-0600 file."
predecessor_external_sha256="$(shasum -a 256 "$predecessor_external_output" | awk '{print $1}')"
assert_matches '^[0-9a-f]{64}$' "$predecessor_external_sha256" \
    "The predecessor-pre-tag digest was invalid."
predecessor_commit="$expected_commit"
git -C "$test_repository" tag -a v0.0.9 \
    -m "remote-controls-predecessor-pre-tag-sha256: $predecessor_external_sha256" \
    "$predecessor_commit"
predecessor_tag_object="$(git -C "$test_repository" rev-parse refs/tags/v0.0.9)"
[[ "$(git -C "$test_repository" cat-file -t "$predecessor_tag_object")" == tag ]] || \
    fail "Synthetic predecessor tag is not annotated."
predecessor_tracked_output="$test_repository/docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json"
cp -- "$predecessor_external_output" "$predecessor_tracked_output"
chmod 0600 "$predecessor_tracked_output"
git -C "$test_repository" add -- \
    docs/evidence/releases/v0.1.0/remote-controls-predecessor-pre-tag.json
git -C "$test_repository" commit -q -m 'Record predecessor pre-tag controls evidence'
[[ "$(git -C "$test_repository" rev-parse HEAD^)" == "$predecessor_commit" ]] || \
    fail "Predecessor evidence is not the direct child of the predecessor tag commit."
ruby -rjson -rtime -e '
  directory = ARGV.fetch(0)
  %w[release-candidate-admin-bypass.json release-publication-admin-token-scope.json].each_with_index do |name, index|
    path = File.join(directory, name)
    value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
    observed = Time.now.utc
    value["phase"] = "final-pre-tag"
    value["observedAt"] = observed.iso8601
    value["sourceArtifactSHA256"] = (index + 3).to_s * 64
    if value["token"]
      value["token"]["issuedAt"] = (observed - 60).iso8601
      value["token"]["expiresAt"] = (observed + 29 * 86_400).iso8601
    end
    File.binwrite(path, JSON.generate(value) + "\n")
  end
' "$test_repository/docs/evidence/releases/v0.1.0"
git -C "$test_repository" add -- docs/evidence/releases/v0.1.0
git -C "$test_repository" commit -q -m 'Refresh final-pre-tag manual controls'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"
release_commit="$expected_commit"

success_stdout="$temporary_root/success.stdout"
success_stderr="$temporary_root/success.stderr"
run_wrapper success "$success_stdout" "$success_stderr"
assert_equal 0 "$last_status" \
    "Complete mock evidence did not pass (status=$last_status, stderr=$(tr -d '\n' <"$success_stderr"))."
assert_empty "$success_stderr"
expected_success_pattern="^OK remote-controls phase=final-pre-tag repository=GGULBAE/desk-setup-switcher observed_master=$expected_commit release_workflow_blob=$workflow_blob ci_workflow_blob=$ci_workflow_blob publication_workflow_blob=$publication_workflow_blob legacy_workflow_blob=$legacy_workflow_blob publication_workflow_id=7002 ci_run_id=70001 ci_run_attempt=2 ci_job_id=10001 checks=2 manual_gates=2 evidence_sha256=[0-9a-f]{64} evidence_record=protected-external-output$"
assert_matches "$expected_success_pattern" "$(tr -d '\n' <"$success_stdout")" \
    "Success summary was not exact."
final_pre_tag_external_output="$temporary_root/success.final-pre-tag.json"
[[ -f "$final_pre_tag_external_output" && ! -L "$final_pre_tag_external_output" && \
    "$(stat -f %Lp "$final_pre_tag_external_output")" == 600 ]] || \
    fail "The protected final-pre-tag evidence output was not one mode-0600 file."
final_pre_tag_external_sha256="$(shasum -a 256 "$final_pre_tag_external_output" | awk '{print $1}')"
assert_matches '^[0-9a-f]{64}$' "$final_pre_tag_external_sha256" \
    "The protected final-pre-tag evidence digest was invalid."
preserved_final_pre_tag_output="$temporary_root/preserved-final-pre-tag.json"
cp -- "$final_pre_tag_external_output" "$preserved_final_pre_tag_output"
chmod 0600 "$preserved_final_pre_tag_output"
success_mock_log="$temporary_root/success-gh-calls.jsonl"
cp -- "$mock_log" "$success_mock_log"

signal_stdout="$temporary_root/signal-hang.stdout"
signal_stderr="$temporary_root/signal-hang.stderr"
signal_marker="$temporary_root/signal-hang.marker"
signal_wrapper_pid_path="$temporary_root/signal-hang.wrapper.pid"
rm -f -- "$signal_marker" "$signal_wrapper_pid_path" "$temporary_root/signal-hang.status"
run_wrapper signal-hang "$signal_stdout" "$signal_stderr" &
signal_harness_pid=$!
for _signal_wait in {1..200}; do
    [[ -s "$signal_marker" && -s "$signal_wrapper_pid_path" ]] && break
    kill -0 "$signal_harness_pid" >/dev/null 2>&1 || break
    sleep 0.05
done
[[ -s "$signal_marker" && -s "$signal_wrapper_pid_path" ]] || \
    fail "The signal-cancellation mock did not start."
IFS=$'\t' read -r signal_gh_pid signal_launcher_pid <"$signal_marker"
signal_wrapper_pid="$(tr -d '\n' <"$signal_wrapper_pid_path")"
[[ "$signal_gh_pid" =~ ^[1-9][0-9]*$ && "$signal_launcher_pid" =~ ^[1-9][0-9]*$ \
    && "$signal_wrapper_pid" =~ ^[1-9][0-9]*$ ]] || \
    fail "The signal-cancellation process identities were malformed."
kill -TERM "$signal_wrapper_pid" >/dev/null 2>&1 || fail "The wrapper could not be terminated."
wait "$signal_harness_pid" || true
assert_equal 143 "$(tr -d '\n' <"$temporary_root/signal-hang.status")" \
    "SIGTERM did not produce the stable wrapper exit status."
assert_empty "$signal_stdout"
assert_empty "$signal_stderr"
if kill -0 "$signal_gh_pid" >/dev/null 2>&1; then
    fail "SIGTERM left the tracked gh process alive."
fi
pass
[[ -z "$(find "$test_tmp" -maxdepth 1 -type d -name 'desk-setup-remote-controls.*' -print -quit)" ]] || \
    fail "SIGTERM left a collection directory behind."
pass

ruby -rjson -e '
  calls = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
  raise unless calls.length == 82
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
  raise unless ordered_endpoints[1].include?("/contents/.github/workflows/signed-release-candidate.yml?ref=")
  raise unless ordered_endpoints[2] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/signed-release-candidate.yml"
  raise unless ordered_endpoints[3].include?("/contents/.github/workflows/release.yml?ref=")
  raise unless ordered_endpoints[4] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml"
  raise unless ordered_endpoints[5].include?("/contents/.github/workflows/ci.yml?ref=")
  raise unless ordered_endpoints[6] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml"
  raise unless ordered_endpoints[7].include?("/contents/.github/workflows/publish-release.yml?ref=")
  raise unless ordered_endpoints[8] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/publish-release.yml"
  raise unless ordered_endpoints[-9] == "/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master"
  raise unless ordered_endpoints[-8].include?("/contents/.github/workflows/signed-release-candidate.yml?ref=")
  raise unless ordered_endpoints[-7] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/signed-release-candidate.yml"
  raise unless ordered_endpoints[-6].include?("/contents/.github/workflows/release.yml?ref=")
  raise unless ordered_endpoints[-5] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/release.yml"
  raise unless ordered_endpoints[-4].include?("/contents/.github/workflows/ci.yml?ref=")
  raise unless ordered_endpoints[-3] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/ci.yml"
  raise unless ordered_endpoints[-2].include?("/contents/.github/workflows/publish-release.yml?ref=")
  raise unless ordered_endpoints[-1] == "/repos/GGULBAE/desk-setup-switcher/actions/workflows/publish-release.yml"
  raise unless ordered_endpoints[9, 32] == ordered_endpoints[41, 32]
  counts = ordered_endpoints.tally
  raise unless counts.values.all? { |count| count == 2 }
  endpoints = calls.to_h { |call| [call.find { |item| item.start_with?("/") }, call] }
  paginated = endpoints.select do |endpoint, _call|
    endpoint.include?("rulesets?") || endpoint.include?("/rules/branches/") ||
      endpoint.include?("deployment-branch-policies") || endpoint.include?("/secrets?") ||
      endpoint.include?("/variables?") || endpoint.include?("/releases?") ||
      endpoint.include?("/check-runs?") || endpoint.include?("/runs?") || endpoint.include?("/jobs?") ||
      endpoint.include?("/actions/workflows?")
  end
  paginated.each_value { |call| raise unless call.include?("--paginate") }
  variable_calls = calls.select do |call|
    call.any? { |argument| argument.start_with?("/") && argument.include?("/variables?") }
  end
  raise unless variable_calls.length == 6
  expected_variable_jq = "{total_count: .total_count, names: (.variables | map(.name))}"
  variable_calls.each do |call|
    jq_index = call.index("--jq")
    raise unless call.count("--jq") == 1 && jq_index && call[jq_index + 1] == expected_variable_jq
  end
  master_calls = calls.select { |call| call.include?("/repos/GGULBAE/desk-setup-switcher/git/ref/heads/master") }
  content_calls = calls.select do |call|
    call.any? { |item| item.include?("/contents/.github/workflows/") && item.include?("?ref=") }
  end
  raise unless master_calls.length == 2 && content_calls.length == 8
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
' "$success_mock_log" "$expected_commit" || fail "gh request contract was incomplete."
pass

if grep -R -F -q -- "$raw_marker" \
    "$success_stdout" "$success_stderr" "$success_mock_log" "$test_tmp" \
    || grep -R -F -q -- "$runtime_gh_token" \
        "$success_stdout" "$success_stderr" "$success_mock_log" "$test_tmp"; then
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
assert_equal 70 "$last_status" "Workflow state drift did not fail closed."
assert_empty "$state_stdout"
assert_equal 'ERROR: remote controls evidence unavailable' \
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

assert_evidence_unavailable_mode \
    public-check-suite-drift \
    "CI checks from different workflow suites were accepted."
assert_policy_mismatch_mode \
    missing-public-check \
    "The public-surface CI check was optional."
assert_policy_mismatch_mode \
    missing-public-job \
    "The public-surface CI job was optional."
assert_policy_mismatch_mode \
    public-check-failed \
    "A failed public-surface CI check was accepted."
assert_policy_mismatch_mode \
    public-job-failed \
    "A failed public-surface CI job was accepted."

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
assert_evidence_unavailable_mode \
    workflow-inventory-drift \
    "Active workflow inventory drift between complete reads was accepted."
assert_evidence_unavailable_mode \
    workflow-inventory-truncated \
    "A truncated active-workflow page set was accepted."
assert_evidence_unavailable_mode \
    workflow-inventory-extra \
    "An unexpected active workflow route was accepted."
assert_evidence_unavailable_mode \
    workflow-inventory-duplicate \
    "A duplicated active workflow identity was accepted."

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
if grep -F -q -- '/repos/private-path' "$api_stderr" \
    || grep -F -q -- "$raw_marker" "$api_stderr" \
    || grep -F -q -- "$runtime_gh_token" "$api_stderr"; then
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

git -C "$test_repository" tag -a v0.1.0 \
    -m "remote-controls-final-pre-tag-sha256: $final_pre_tag_external_sha256" \
    "$release_commit"
release_tag_object="$(git -C "$test_repository" rev-parse refs/tags/v0.1.0)"
[[ "$(git -C "$test_repository" cat-file -t "$release_tag_object")" == tag ]] || \
    fail "Synthetic release tag is not annotated."
final_pre_tag_tracked_output="$test_repository/docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json"
cp -- "$preserved_final_pre_tag_output" "$final_pre_tag_tracked_output"
chmod 0600 "$final_pre_tag_tracked_output"
git -C "$test_repository" add -- \
    docs/evidence/releases/v0.1.0/remote-controls-final-pre-tag.json
git -C "$test_repository" commit -q -m 'Record final pre-tag controls evidence'
final_pre_tag_introduction_commit="$(git -C "$test_repository" rev-parse HEAD)"
[[ "$(git -C "$test_repository" rev-parse "$final_pre_tag_introduction_commit^")" == \
    "$release_commit" ]] || fail "Final-pre-tag evidence commit is not tag commit A's direct child."
ruby -rjson -rtime -e '
  directory, release_commit, tag_object = ARGV
  %w[release-candidate-admin-bypass.json release-publication-admin-token-scope.json].each_with_index do |name, index|
    path = File.join(directory, name)
    value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
    value["phase"] = "pre-publication"
    value["observedAt"] = Time.now.utc.iso8601
    value["sourceArtifactSHA256"] = (index + 5).to_s * 64
    value["subject"] = {
      "peeledCommit" => release_commit,
      "releaseId" => 12_345,
      "tag" => "v0.1.0",
      "tagObjectSha" => tag_object
    }
    File.binwrite(path, JSON.generate(value) + "\n")
  end
' "$test_repository/docs/evidence/releases/v0.1.0" "$release_commit" "$release_tag_object"
git -C "$test_repository" add -- docs/evidence/releases/v0.1.0
git -C "$test_repository" commit -q -m 'Refresh pre-publication manual controls'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"
pre_publication_output="$test_repository/docs/evidence/releases/v0.1.0/remote-controls-pre-publication.json"

candidate_manual_path="$test_repository/docs/evidence/releases/v0.1.0/release-candidate-admin-bypass.json"
publication_manual_path="$test_repository/docs/evidence/releases/v0.1.0/release-publication-admin-token-scope.json"
candidate_manual_backup="$temporary_root/current-candidate-manual.backup.json"
publication_manual_backup="$temporary_root/current-publication-manual.backup.json"
cp -- "$candidate_manual_path" "$candidate_manual_backup"
cp -- "$publication_manual_path" "$publication_manual_backup"
ruby -rjson -rtime -e '
  final_path, candidate_path, publication_path = ARGV
  final_collected = Time.iso8601(
    JSON.parse(File.binread(final_path), allow_nan: false, create_additions: false)
      .fetch("collectedAt")
  )
  observed = final_collected - 60
  [candidate_path, publication_path].each do |path|
    value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
    value["observedAt"] = observed.iso8601
    if value["token"]
      value["token"]["issuedAt"] = (observed - 60).iso8601
      value["token"]["expiresAt"] = (observed + 29 * 86_400).iso8601
    end
    File.binwrite(path, JSON.generate(value) + "\n")
  end
' "$final_pre_tag_tracked_output" "$candidate_manual_path" "$publication_manual_path"
git -C "$test_repository" add -- docs/evidence/releases/v0.1.0
git -C "$test_repository" commit -q -m 'Backdate current manual controls before final evidence'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"
chronology_stdout="$temporary_root/pre-publication-chronology.stdout"
chronology_stderr="$temporary_root/pre-publication-chronology.stderr"
run_wrapper success "$chronology_stdout" "$chronology_stderr" \
    --phase pre-publication --release-commit "$release_commit" --release-id 12345
assert_equal 1 "$last_status" "A pre-publication manual observation predating final evidence was accepted."
assert_empty "$chronology_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$chronology_stderr")" \
    "Backdated pre-publication manual evidence did not fail before durable output."
[[ ! -e "$pre_publication_output" ]] || fail "Backdated manual evidence wrote a pre-publication manifest."
pass

cp -- "$candidate_manual_backup" "$candidate_manual_path"
cp -- "$publication_manual_backup" "$publication_manual_path"
git -C "$test_repository" add -- docs/evidence/releases/v0.1.0
git -C "$test_repository" commit -q -m 'Restore fresh pre-publication manual controls'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"
pre_drift_stdout="$temporary_root/pre-publication-drift.stdout"
pre_drift_stderr="$temporary_root/pre-publication-drift.stderr"
run_wrapper pre-publication-release-drift "$pre_drift_stdout" "$pre_drift_stderr" \
    --phase pre-publication --release-commit "$release_commit" --release-id 12345
[[ "$last_status" -eq 1 || "$last_status" -eq 70 ]] || \
    fail "Pre-publication Release drift was accepted."
pass
assert_empty "$pre_drift_stdout"
if [[ "$last_status" -eq 1 ]]; then
    assert_equal 'ERROR: remote controls policy mismatch' \
        "$(tr -d '\n' <"$pre_drift_stderr")" \
        "Pre-publication Release drift exposed observed values."
else
    assert_equal 'ERROR: remote controls evidence unavailable' \
        "$(tr -d '\n' <"$pre_drift_stderr")" \
        "Pre-publication Release drift exposed observed values."
fi
[[ ! -e "$pre_publication_output" ]] || fail "A failed pre-publication read wrote the manifest."
pass

ruby -rjson -rtime -e '
  directory = ARGV.fetch(0)
  %w[release-candidate-admin-bypass.json release-publication-admin-token-scope.json].each_with_index do |name, index|
    path = File.join(directory, name)
    value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
    value["observedAt"] = Time.now.utc.iso8601
    value["sourceArtifactSHA256"] = (index + 3).to_s * 64
    File.binwrite(path, JSON.generate(value) + "\n")
  end
' "$test_repository/docs/evidence/releases/v0.1.0"
git -C "$test_repository" add -- docs/evidence/releases/v0.1.0
git -C "$test_repository" commit -q -m 'Attempt to relabel final manual artifacts'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"
reuse_stdout="$temporary_root/pre-publication-source-reuse.stdout"
reuse_stderr="$temporary_root/pre-publication-source-reuse.stderr"
run_wrapper source-reuse "$reuse_stdout" "$reuse_stderr" \
    --phase pre-publication --release-commit "$release_commit" --release-id 12345
assert_equal 1 "$last_status" "Final-pre-tag source artifacts were reused as pre-publication evidence."
assert_empty "$reuse_stdout"
assert_equal 'ERROR: remote controls local anchor mismatch' \
    "$(tr -d '\n' <"$reuse_stderr")" \
    "Source-artifact reuse did not fail at the local evidence boundary."
assert_empty "$mock_log"

ruby -rjson -rtime -e '
  directory = ARGV.fetch(0)
  %w[release-candidate-admin-bypass.json release-publication-admin-token-scope.json].each_with_index do |name, index|
    path = File.join(directory, name)
    value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
    value["observedAt"] = Time.now.utc.iso8601
    value["sourceArtifactSHA256"] = (index + 5).to_s * 64
    File.binwrite(path, JSON.generate(value) + "\n")
  end
' "$test_repository/docs/evidence/releases/v0.1.0"
git -C "$test_repository" add -- docs/evidence/releases/v0.1.0
git -C "$test_repository" commit -q -m 'Record fresh pre-publication manual artifacts'
expected_commit="$(git -C "$test_repository" rev-parse HEAD)"

pre_success_stdout="$temporary_root/pre-publication-success.stdout"
pre_success_stderr="$temporary_root/pre-publication-success.stderr"
run_wrapper success "$pre_success_stdout" "$pre_success_stderr" \
    --phase pre-publication --release-commit "$release_commit" --release-id 12345
assert_equal 0 "$last_status" \
    "Complete pre-publication evidence did not pass (stderr=$(tr -d '\n' <"$pre_success_stderr"))."
assert_empty "$pre_success_stderr"
pre_success_pattern="^OK remote-controls phase=pre-publication repository=GGULBAE/desk-setup-switcher observed_master=$expected_commit release_workflow_blob=$workflow_blob ci_workflow_blob=$ci_workflow_blob publication_workflow_blob=$publication_workflow_blob legacy_workflow_blob=$legacy_workflow_blob publication_workflow_id=7002 ci_run_id=70001 ci_run_attempt=2 ci_job_id=10001 checks=2 manual_gates=2 evidence_sha256=[0-9a-f]{64} evidence_record=docs/evidence/releases/v0.1.0/remote-controls-pre-publication.json$"
assert_matches "$pre_success_pattern" "$(tr -d '\n' <"$pre_success_stdout")" \
    "Pre-publication success summary was not exact."
ruby -rjson -rdigest -e '
  path, expected_commit, predecessor_commit, predecessor_tag_object,
    release_commit, tag_object, predecessor_digest, final_digest, expected_digest = ARGV
  stat = File.lstat(path)
  raise unless stat.file? && !stat.symlink? && (stat.mode & 0o777) == 0o600
  value = JSON.parse(File.binread(path), allow_nan: false, create_additions: false)
  raise unless value.fetch("schemaVersion") == "desk-setup-switcher.remote-release-controls-evidence/v3"
  raise unless value.fetch("phase") == "pre-publication"
  raise unless value.fetch("predecessorPreTagEvidenceSHA256") == predecessor_digest
  raise unless value.fetch("finalPreTagEvidenceSHA256") == final_digest
  raise unless value.dig("anchorReads", 0, "master", "commitSha") == expected_commit
  raise unless value.dig("releaseBoundary", "vRefs", "items") == [
    {
      "ref" => "refs/tags/v0.0.9", "objectType" => "tag",
      "objectSha" => predecessor_tag_object, "commitSha" => predecessor_commit
    },
    {
      "ref" => "refs/tags/v0.1.0", "objectType" => "tag",
      "objectSha" => tag_object, "commitSha" => release_commit
    }
  ]
  raise unless value.dig("releaseBoundary", "releases", "items") == [{
    "id" => 12345, "tag" => "v0.1.0", "draft" => true, "prerelease" => true
  }]
  raise unless Digest::SHA256.file(path).hexdigest == expected_digest
' "$pre_publication_output" "$expected_commit" \
    "$predecessor_commit" "$predecessor_tag_object" \
    "$release_commit" "$release_tag_object" \
    "$predecessor_external_sha256" "$final_pre_tag_external_sha256" \
    "$(sed -n 's/.* evidence_sha256=\([0-9a-f]\{64\}\) .*/\1/p' "$pre_success_stdout")" \
    || fail "The persisted pre-publication manifest was not exact."
pass
ruby -rjson -e '
  calls = File.readlines(ARGV.fetch(0), chomp: true).map { |line| JSON.parse(line) }
  raise unless calls.length == 86
  endpoints = calls.map { |call| call.find { |item| item.start_with?("/") } }
  raise unless endpoints.count { |endpoint| endpoint.end_with?("/commits/tags/v0.0.9") } == 2
  raise unless endpoints.count { |endpoint| endpoint.end_with?("/commits/tags/v0.1.0") } == 2
  raise unless endpoints.count { |endpoint| endpoint.include?("/git/tags/") } == 4
  raise unless endpoints.count { |endpoint| endpoint.end_with?("/releases?per_page=100") } == 2
  raise unless endpoints.count { |endpoint| endpoint.end_with?("/actions/workflows?per_page=100") } == 2
' "$mock_log" || fail "Pre-publication did not execute two complete remote reads."
pass
rm -f -- "$pre_publication_output"

chmod 0500 "$test_tmp"
tmp_stdout="$temporary_root/tmp-failure.stdout"
tmp_stderr="$temporary_root/tmp-failure.stderr"
run_wrapper success "$tmp_stdout" "$tmp_stderr" \
    --phase pre-publication --release-commit "$release_commit" --release-id 12345
chmod 0700 "$test_tmp"
assert_equal 70 "$last_status" "A temporary-directory failure was misclassified."
assert_empty "$tmp_stdout"
assert_equal 'ERROR: remote controls collection failed' \
    "$(tr -d '\n' <"$tmp_stderr")" \
    "A temporary-directory failure leaked infrastructure details."
assert_empty "$mock_log"
git -C "$test_repository" tag -d v0.1.0 >/dev/null

# A configured:false operational policy must stop at the first preflight even
# if the worktree is dirty and a mock gh is available.
ruby -rjson -e '
  path = ARGV.fetch(0)
  value = {
    "schemaVersion" => "desk-setup-switcher.remote-release-controls-policy/v2",
    "phase" => "release-lifecycle",
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
