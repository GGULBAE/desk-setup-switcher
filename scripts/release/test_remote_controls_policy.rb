#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "collect_remote_controls_evidence"

class RemoteControlsPolicyTestSuite
  SCRIPT = File.expand_path("remote_controls_policy.rb", __dir__)
  COLLECTOR_SCRIPT = File.expand_path("collect_remote_controls_evidence.rb", __dir__)
  FIXTURES = File.expand_path("fixtures/remote-controls", __dir__)
  POLICY_FIXTURE = File.join(FIXTURES, "policy-v1.json")
  EVIDENCE_FIXTURE = File.join(FIXTURES, "evidence-v1.json")
  EXPECTED_COMMIT = "a" * 40
  EXPECTED_WORKFLOW_BLOB = "b" * 40
  EXPECTED_CI_WORKFLOW_BLOB = "c" * 40

  class TestFailure < StandardError; end

  def initialize
    @tests = 0
    @assertions = 0
    @failures = []
  end

  def assert(condition, message = "assertion failed")
    @assertions += 1
    raise TestFailure, message unless condition
  end

  def assert_equal(expected, actual, message = "values are not equal")
    assert(expected == actual, message)
  end

  def run(name)
    @tests += 1
    yield
    puts "ok #{@tests} - #{name}"
  rescue StandardError => error
    @failures << [name, error.class.name, error.message]
    puts "not ok #{@tests} - #{name}"
  end

  def cli(*arguments)
    Open3.capture3(RbConfig.ruby, SCRIPT, *arguments)
  end

  def collector_cli(*arguments)
    Open3.capture3(RbConfig.ruby, COLLECTOR_SCRIPT, *arguments)
  end

  def assert_collection_unavailable(message = "collector input was expected to be unavailable")
    @assertions += 1
    begin
      yield
    rescue RemoteControlsCollector::CollectionUnavailable
      return
    end
    raise TestFailure, message
  end

  def assert_collector_failure(*arguments, forbidden: [])
    stdout, stderr, status = collector_cli(*arguments)
    assert_equal(70, status.exitstatus, "collector rejection did not use the stable exit status")
    assert(stdout.empty?, "failed collector command wrote to stdout")
    assert_equal("ERROR: remote controls evidence unavailable\n", stderr)
    forbidden.each { |value| assert(!stderr.include?(value), "collector failure leaked an input value") }
  end

  def assert_success(*arguments, expected: "OK remote-controls normalized-evidence manual_gates=1\n")
    stdout, stderr, status = cli(*arguments)
    assert(status.success?, "command was expected to succeed: #{stderr.strip}")
    assert_equal(expected, stdout, "success output was not stable")
    assert(stderr.empty?, "successful command wrote to stderr")
    [stdout, stderr]
  end

  def assert_failure(*arguments, forbidden: [])
    stdout, stderr, status = cli(*arguments)
    assert(!status.success?, "command was expected to fail")
    assert_equal(1, status.exitstatus, "policy rejection did not use the stable exit status")
    assert(stdout.empty?, "failed command wrote to stdout")
    assert(stderr.match?(/\AERROR: [A-Za-z0-9 -]+(?: is invalid| is missing| is not valid JSON| contains duplicate JSON keys| must not be a symlink| must be a regular file| exceeds the size limit| are mutually exclusive| failed)\n\z/),
           "failure output was not stable and sanitized: #{stderr.inspect}")
    forbidden.each { |value| assert(!stderr.include?(value), "failure output leaked an input value") }
    [stdout, stderr]
  end

  def verification_arguments(policy = POLICY_FIXTURE, evidence = EVIDENCE_FIXTURE)
    [
      "--policy", policy,
      "--evidence", evidence,
      "--expected-commit", EXPECTED_COMMIT,
      "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
      "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB
    ]
  end

  def fixture_json(path)
    JSON.parse(File.binread(path), create_additions: false)
  end

  def write_json(path, value)
    File.binwrite(path, JSON.pretty_generate(value) + "\n")
    path
  end

  def mutated_pair(directory, policy_mutation: nil, evidence_mutation: nil)
    policy = fixture_json(POLICY_FIXTURE)
    evidence = fixture_json(EVIDENCE_FIXTURE)
    policy_mutation&.call(policy)
    evidence_mutation&.call(evidence)
    policy_path = write_json(File.join(directory, "policy.json"), policy)
    evidence_path = write_json(File.join(directory, "evidence.json"), evidence)
    [policy_path, evidence_path]
  end

  def assert_mutation_failure(policy_mutation: nil, evidence_mutation: nil)
    Dir.mktmpdir do |directory|
      policy, evidence = mutated_pair(
        directory,
        policy_mutation: policy_mutation,
        evidence_mutation: evidence_mutation
      )
      assert_failure(*verification_arguments(policy, evidence), forbidden: [directory])
    end
  end

  def test_positive_contract
    run("accepts the complete independent-review final-pre-tag fixture") do
      assert_success(*verification_arguments)
    end

    run("validates authoritative policy before any evidence collection") do
      assert_success(
        "--check-policy", POLICY_FIXTURE,
        expected: "OK remote-controls policy\n"
      )
    end

    run("binds policy preflight to both trusted local workflow blobs") do
      assert_success(
        "--check-policy", POLICY_FIXTURE,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB,
        expected: "OK remote-controls policy workflow-blobs-bound\n"
      )
    end

    run("returns the CI workflow ID only after strict policy and blob validation") do
      assert_success(
        "--ci-workflow-id", POLICY_FIXTURE,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB,
        expected: "7000\n"
      )
    end

    run("accepts the explicitly configured one-maintainer approval mode") do
      Dir.mktmpdir do |directory|
        policy, evidence = mutated_pair(
          directory,
          policy_mutation: lambda do |value|
            value["actors"]["reviewer"] = value["actors"]["operator"].dup
            value["approval"] = {
              "mode" => "one-maintainer",
              "requiredApprovals" => 0,
              "preventSelfReview" => false
            }
          end,
          evidence_mutation: lambda do |value|
            operator = value["repository"]["owner"].dup
            value["environment"]["protection"]["reviewers"] = [operator]
            value["environment"]["protection"]["preventSelfReview"] = false
            parameters = value["rulesets"]["master"][0]["rules"].find do |rule|
              rule["type"] == "pull_request"
            end.fetch("parameters")
            parameters["requiredApprovingReviewCount"] = 0
            parameters["requireLastPushApproval"] = false
            effective_parameters = value["rulesets"]["effectiveMaster"]["items"].find do |item|
              item["rule"]["type"] == "pull_request"
            end.fetch("rule").fetch("parameters")
            effective_parameters["requiredApprovingReviewCount"] = 0
            effective_parameters["requireLastPushApproval"] = false
          end
        )
        assert_success(*verification_arguments(policy, evidence))
      end
    end
  end

  def test_policy_boundaries
    mutations = {
      "requires root configured true" => lambda { |value| value["configured"] = false },
      "requires exact policy schema" => lambda { |value| value["schemaVersion"] = "future/v2" },
      "requires the final-pre-tag phase" => lambda { |value| value["phase"] = "post-tag" },
      "rejects unknown policy keys" => lambda { |value| value["unexpected"] = true },
      "requires an exact public repository identity" => lambda { |value| value["repository"]["fullName"] = "different/repository" },
      "requires canonical repository metadata" => lambda { |value| value["repository"]["topics"].reverse! },
      "requires the v0.1.0 release identity" => lambda { |value| value["release"]["tag"] = "v0.1.1" },
      "requires the reviewed workflow path" => lambda { |value| value["release"]["workflow"]["path"] = ".github/workflows/other.yml" },
      "requires the GitHub Actions CI app" => lambda { |value| value["release"]["ci"]["appId"] = 1 },
      "requires the authoritative CI workflow ID" => lambda { |value| value["release"]["ci"]["workflow"]["id"] = 1 },
      "requires the authoritative CI workflow name" => lambda { |value| value["release"]["ci"]["workflow"]["name"] = "Alternate CI" },
      "requires the authoritative CI workflow path" => lambda { |value| value["release"]["ci"]["workflow"]["path"] = ".github/workflows/alternate.yml" },
      "requires the authoritative CI workflow blob" => lambda { |value| value["release"]["ci"]["workflow"]["blobSha"] = "invalid" },
      "requires configured operator identity" => lambda { |value| value["actors"]["operator"]["configured"] = false },
      "requires configured reviewer identity" => lambda { |value| value["actors"]["reviewer"]["configured"] = false },
      "requires User actor types" => lambda { |value| value["actors"]["reviewer"]["type"] = "Team" },
      "requires exact approval-mode actor separation" => lambda { |value| value["actors"]["reviewer"] = value["actors"]["operator"].dup }
    }
    mutations.each do |name, mutation|
      run(name) { assert_mutation_failure(policy_mutation: mutation) }
    end

    run("unconfigured policy uses a minimal closed shape and fails before collection") do
      Dir.mktmpdir do |directory|
        path = write_json(
          File.join(directory, "policy.json"),
          {
            "schemaVersion" => "desk-setup-switcher.remote-release-controls-policy/v1",
            "phase" => "final-pre-tag",
            "configured" => false
          }
        )
        _stdout, stderr = assert_failure("--check-policy", path, forbidden: [directory])
        assert_equal("ERROR: remote controls policy configuration is invalid\n", stderr)
      end
    end

    run("policy check rejects malformed JSON") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "malformed.json")
        File.binwrite(path, "{\"configured\":true")
        assert_failure("--check-policy", path, forbidden: [directory])
      end
    end

    run("policy check rejects duplicate JSON keys") do
      Dir.mktmpdir do |directory|
        source = File.binread(POLICY_FIXTURE).sub(
          '"configured": true,',
          '"configured": true, "configured": false,'
        )
        path = File.join(directory, "duplicate.json")
        File.binwrite(path, source)
        assert_failure("--check-policy", path, forbidden: [directory])
      end
    end

    run("policy check rejects symlinks") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "policy-link.json")
        File.symlink(POLICY_FIXTURE, path)
        assert_failure("--check-policy", path, forbidden: [directory])
      end
    end
  end

  def test_observation_boundaries
    mutations = {
      "requires exact evidence schema" => lambda { |value| value["schemaVersion"] = "future/v2" },
      "rejects unknown evidence keys" => lambda { |value| value["workflow"]["unexpected"] = true },
      "requires exact repository metadata" => lambda { |value| value["repository"]["description"] = "different" },
      "rejects an archived repository" => lambda { |value| value["repository"]["archived"] = true },
      "rejects a disabled repository" => lambda { |value| value["repository"]["disabled"] = true },
      "requires Discussions to stay disabled" => lambda { |value| value["repository"]["hasDiscussions"] = true },
      "requires the exact repository owner" => lambda { |value| value["repository"]["owner"]["id"] = 9999 },
      "requires the authenticated viewer to be the operator" => lambda { |value| value["authenticatedViewer"]["actor"]["id"] = 9999 },
      "requires authenticated admin visibility" => lambda { |value| value["authenticatedViewer"]["repositoryPermission"] = "read" },
      "requires two anchor reads" => lambda { |value| value["anchorReads"].pop },
      "rejects master drift between anchor reads" => lambda { |value| value["anchorReads"][1]["master"]["commitSha"] = "c" * 40 },
      "rejects release-workflow drift between anchor reads" => lambda { |value| value["anchorReads"][1]["releaseWorkflow"]["blobSha"] = "d" * 40 },
      "rejects release-workflow state drift between anchor reads" => lambda { |value| value["anchorReads"][1]["releaseWorkflow"]["state"] = "disabled_manually" },
      "rejects CI-workflow drift between anchor reads" => lambda { |value| value["anchorReads"][1]["ciWorkflow"]["blobSha"] = "d" * 40 },
      "rejects CI-workflow metadata drift between anchor reads" => lambda { |value| value["anchorReads"][1]["ciWorkflow"]["id"] = 7999 },
      "requires the active workflow" => lambda { |value| value["workflow"]["state"] = "disabled_manually" },
      "requires workflow_dispatch as the only trigger" => lambda { |value| value["workflow"]["triggers"] << "push" },
      "requires the active authoritative CI workflow" => lambda { |value| value["ciWorkflow"]["state"] = "disabled_manually" },
      "requires the exact CI workflow triggers" => lambda { |value| value["ciWorkflow"]["triggers"].delete("push") },
      "requires a complete ruleset observation" => lambda { |value| value["rulesets"]["complete"] = false },
      "requires repository-scoped rulesets" => lambda { |value| value["rulesets"]["master"][0]["sourceType"] = "Organization" },
      "forbids master ruleset bypasses" => lambda do |value|
        value["rulesets"]["master"][0]["bypassActors"] = [
          { "actor" => value["repository"]["owner"].dup, "bypassMode" => "always" }
        ]
      end,
      "requires master deletion protection" => lambda do |value|
        value["rulesets"]["master"][0]["rules"].reject! { |rule| rule["type"] == "deletion" }
      end,
      "requires master non-fast-forward protection" => lambda do |value|
        value["rulesets"]["master"][0]["rules"].reject! { |rule| rule["type"] == "non_fast_forward" }
      end,
      "requires review-thread resolution" => lambda do |value|
        value["rulesets"]["master"][0]["rules"].find do |rule|
          rule["type"] == "pull_request"
        end["parameters"]["requiredReviewThreadResolution"] = false
      end,
      "requires the configured PR approval mode" => lambda do |value|
        value["rulesets"]["master"][0]["rules"].find do |rule|
          rule["type"] == "pull_request"
        end["parameters"]["requiredApprovingReviewCount"] = 0
      end,
      "requires the exact CI integration in the master ruleset" => lambda do |value|
        value["rulesets"]["master"][0]["rules"].find do |rule|
          rule["type"] == "required_status_checks"
        end["parameters"]["requiredStatusChecks"][0]["integrationId"] = 1
      end,
      "requires the effective master read" => lambda { |value| value["rulesets"]["effectiveMaster"]["complete"] = false },
      "binds effective master rules to the detail ruleset" => lambda do |value|
        value["rulesets"]["effectiveMaster"]["items"][0]["rulesetId"] = 9999
      end,
      "requires effective master parameters to match" => lambda do |value|
        value["rulesets"]["effectiveMaster"]["items"].find do |item|
          item["rule"]["type"] == "required_status_checks"
        end["rule"]["parameters"]["strictRequiredStatusChecksPolicy"] = false
      end,
      "requires exactly two tag rulesets" => lambda { |value| value["rulesets"]["tags"].pop },
      "requires one operator bypass for tag creation" => lambda { |value| value["rulesets"]["tags"][0]["bypassActors"] = [] },
      "requires the exact tag creation operator" => lambda do |value|
        value["rulesets"]["tags"][0]["bypassActors"][0]["actor"]["id"] = 9999
      end,
      "forbids an immutability bypass" => lambda do |value|
        value["rulesets"]["tags"][1]["bypassActors"] = value["rulesets"]["tags"][0]["bypassActors"]
      end,
      "requires tag update protection" => lambda do |value|
        value["rulesets"]["tags"][1]["rules"].reject! { |rule| rule["type"] == "update" }
      end,
      "forbids fetch-and-merge tag updates" => lambda do |value|
        value["rulesets"]["tags"][1]["rules"].find do |rule|
          rule["type"] == "update"
        end["parameters"]["updateAllowsFetchAndMerge"] = true
      end,
      "requires tag deletion protection" => lambda do |value|
        value["rulesets"]["tags"][1]["rules"].reject! { |rule| rule["type"] == "deletion" }
      end,
      "requires the exact environment reviewer" => lambda { |value| value["environment"]["protection"]["reviewers"][0]["id"] = 9999 },
      "requires the configured environment self-review policy" => lambda { |value| value["environment"]["protection"]["preventSelfReview"] = false },
      "forbids protected-branch-only deployment policy" => lambda { |value| value["environment"]["deployment"]["protectedBranches"] = true },
      "requires custom deployment policies" => lambda { |value| value["environment"]["deployment"]["customBranchPolicies"] = false },
      "requires the exact release tag deployment policy" => lambda { |value| value["environment"]["deployment"]["policies"][0]["name"] = "v0.1.1" },
      "requires the exact environment secret names" => lambda { |value| value["environment"]["secrets"]["names"].pop },
      "requires the exact environment variable names" => lambda { |value| value["environment"]["variables"]["names"].pop },
      "forbids repository secret shadowing" => lambda do |value|
        value["repositoryConfiguration"]["secrets"]["names"] = ["APPLE_NOTARY_API_KEY_BASE64"]
      end,
      "forbids repository variable shadowing" => lambda do |value|
        value["repositoryConfiguration"]["variables"]["names"] = ["APPLE_TEAM_ID"]
      end,
      "requires private vulnerability reporting" => lambda { |value| value["security"]["privateVulnerabilityReporting"] = false },
      "requires immutable releases" => lambda { |value| value["security"]["immutableReleases"]["enabled"] = false },
      "requires selected GitHub-owned Actions" => lambda { |value| value["actions"]["allowedActions"] = "all" },
      "requires full-SHA Actions enforcement" => lambda { |value| value["actions"]["shaPinningRequired"] = false },
      "requires GitHub-owned Actions to remain allowed" => lambda { |value| value["actions"]["selectedActions"]["githubOwnedAllowed"] = false },
      "forbids blanket verified-creator Actions" => lambda { |value| value["actions"]["selectedActions"]["verifiedAllowed"] = true },
      "forbids extra Actions patterns" => lambda { |value| value["actions"]["selectedActions"]["patternsAllowed"] = ["example/action@*"] },
      "forbids workflow write-token defaults" => lambda { |value| value["actions"]["workflowPermissions"]["defaultWorkflowPermissions"] = "write" },
      "forbids workflow PR-approval permission" => lambda { |value| value["actions"]["workflowPermissions"]["canApprovePullRequestReviews"] = true },
      "requires the needs-triage label" => lambda { |value| value["labels"]["needsTriage"]["present"] = false },
      "requires zero v tag refs" => lambda { |value| value["releaseBoundary"]["vRefs"]["items"] = ["refs/tags/v0.1.0"] },
      "requires zero GitHub Releases" => lambda { |value| value["releaseBoundary"]["releases"]["items"] = [{ "id" => 1 }] },
      "requires CI on the exact commit" => lambda { |value| value["ci"]["commitSha"] = "c" * 40 },
      "requires complete CI workflow runs" => lambda { |value| value["ci"]["workflowRuns"]["complete"] = false },
      "requires the authoritative CI workflow run" => lambda { |value| value["ci"]["workflowRuns"]["items"][0]["workflowId"] = 7002 },
      "binds the workflow run to the check suite" => lambda { |value| value["ci"]["workflowRuns"]["items"][0]["checkSuiteId"] = 9002 },
      "requires the exact CI workflow run path" => lambda { |value| value["ci"]["workflowRuns"]["items"][0]["path"] = ".github/workflows/alternate.yml" },
      "requires a push CI workflow run" => lambda { |value| value["ci"]["workflowRuns"]["items"][0]["event"] = "workflow_dispatch" },
      "requires the master CI workflow run" => lambda { |value| value["ci"]["workflowRuns"]["items"][0]["headBranch"] = "feature" },
      "requires the CI workflow run head" => lambda { |value| value["ci"]["workflowRuns"]["items"][0]["headSha"] = "d" * 40 },
      "rejects a failed latest rerun even when an older attempt succeeded" => lambda do |value|
        latest = value["ci"]["workflowRuns"]["items"][0]
        older = latest.dup
        older["runAttempt"] = 1
        latest["status"] = "completed"
        latest["conclusion"] = "failure"
        value["ci"]["workflowRuns"]["items"].unshift(older)
      end,
      "rejects ambiguous latest workflow run attempts" => lambda do |value|
        duplicate = value["ci"]["workflowRuns"]["items"][0].dup
        duplicate["id"] = 8002
        value["ci"]["workflowRuns"]["items"] << duplicate
      end,
      "requires complete CI jobs" => lambda { |value| value["ci"]["jobs"]["complete"] = false },
      "binds the CI job to the workflow run" => lambda { |value| value["ci"]["jobs"]["items"][0]["runId"] = 8002 },
      "binds the CI job to the latest run attempt" => lambda { |value| value["ci"]["jobs"]["items"][0]["runAttempt"] = 1 },
      "requires the exact CI workflow name on the job" => lambda { |value| value["ci"]["jobs"]["items"][0]["workflowName"] = "Alternate CI" },
      "requires the master CI job" => lambda { |value| value["ci"]["jobs"]["items"][0]["headBranch"] = "feature" },
      "requires the CI job head" => lambda { |value| value["ci"]["jobs"]["items"][0]["headSha"] = "d" * 40 },
      "requires the exact CI job name" => lambda { |value| value["ci"]["jobs"]["items"][0]["name"] = "Alternate job" },
      "requires a successful completed CI job" => lambda { |value| value["ci"]["jobs"]["items"][0]["conclusion"] = "failure" },
      "requires the exact CI check name" => lambda { |value| value["ci"]["checkRuns"]["items"][0]["name"] = "Different check" },
      "requires the exact CI check app" => lambda { |value| value["ci"]["checkRuns"]["items"][0]["appId"] = 1 },
      "requires the exact CI check head" => lambda { |value| value["ci"]["checkRuns"]["items"][0]["headSha"] = "c" * 40 },
      "requires completed CI status" => lambda { |value| value["ci"]["checkRuns"]["items"][0]["status"] = "in_progress" },
      "requires successful completed CI" => lambda { |value| value["ci"]["checkRuns"]["items"][0]["conclusion"] = "failure" },
      "rejects an alternate same-name Actions check from another workflow" => lambda do |value|
        value["ci"]["checkRuns"]["items"][0]["id"] = 11999
        value["ci"]["checkRuns"]["items"][0]["checkSuiteId"] = 9999
      end,
      "binds the check run URL identity through the CI job" => lambda { |value| value["ci"]["jobs"]["items"][0]["checkRunId"] = 11999 }
    }
    mutations.each do |name, mutation|
      run(name) { assert_mutation_failure(evidence_mutation: mutation) }
    end
  end

  def test_collector_strictness
    check = {
      "id" => 11_001,
      "name" => "Verify macOS app",
      "app_id" => 15_368,
      "check_suite_id" => 9_001,
      "head_sha" => EXPECTED_COMMIT,
      "status" => "completed",
      "conclusion" => "success"
    }
    workflow_run = {
      "id" => 8_001,
      "workflow_id" => 7_000,
      "check_suite_id" => 9_001,
      "path" => ".github/workflows/ci.yml",
      "event" => "push",
      "head_branch" => "master",
      "head_sha" => EXPECTED_COMMIT,
      "run_attempt" => 2,
      "status" => "completed",
      "conclusion" => "success"
    }
    workflow_job = {
      "id" => 10_001,
      "run_id" => 8_001,
      "run_attempt" => 2,
      "name" => "Verify macOS app",
      "workflow_name" => "CI",
      "head_branch" => "master",
      "head_sha" => EXPECTED_COMMIT,
      "status" => "completed",
      "conclusion" => "success",
      "check_run_url" => "https://api.github.com/repos/synthetic-operator/desk-setup-switcher/check-runs/11001"
    }

    run("collector enforces paged totals and duplicate names or IDs") do
      assert_collection_unavailable do
        RemoteControlsCollector.paged_names([{ "total_count" => 2, "names" => ["ONLY_ONE"] }])
      end
      assert_collection_unavailable do
        RemoteControlsCollector.paged_names(
          [
            { "total_count" => 2, "names" => ["DUPLICATE"] },
            { "total_count" => 2, "names" => ["DUPLICATE"] }
          ]
        )
      end
      assert_collection_unavailable do
        RemoteControlsCollector.normalize_check_runs(
          [{ "total_count" => 2, "items" => [check, check.dup] }]
        )
      end
      summary = {
        "id" => 101,
        "name" => "duplicate",
        "target" => "branch",
        "enforcement" => "active",
        "source_type" => "Repository",
        "source" => "synthetic-operator/desk-setup-switcher"
      }
      assert_collection_unavailable do
        RemoteControlsCollector.ruleset_summaries([summary, summary.dup])
      end
    end

    run("collector rejects a truncated later JSONL page with sanitized output") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "workflow-runs.json")
        first_page = { "total_count" => 2, "items" => [workflow_run] }
        File.binwrite(path, "#{JSON.generate(first_page)}\n{\"total_count\":")
        assert_collector_failure("workflow-run-id", "--input", path, forbidden: [directory, "total_count"])
      end
    end

    run("collector binds ruleset list identities to their detail projections") do
      summary = {
        "id" => 101,
        "name" => "master-controls",
        "target" => "branch",
        "enforcement" => "active",
        "sourceType" => "Repository",
        "source" => "synthetic-operator/desk-setup-switcher"
      }
      detail = {
        "id" => 102,
        "name" => "master-controls",
        "target" => "branch",
        "enforcement" => "active",
        "source_type" => "Repository",
        "source" => "synthetic-operator/desk-setup-switcher",
        "conditions" => {
          "ref_name" => { "include" => ["refs/heads/master"], "exclude" => [] }
        },
        "bypass_actors" => [],
        "rules" => [{ "type" => "deletion" }]
      }
      assert_collection_unavailable do
        RemoteControlsCollector.normalize_ruleset_detail(detail, summary, [])
      end
    end

    run("collector strictly completes and disambiguates CI workflow-run pages") do
      assert_collection_unavailable do
        RemoteControlsCollector.normalize_workflow_runs(
          [{ "total_count" => 2, "items" => [workflow_run] }]
        )
      end
      assert_collection_unavailable do
        RemoteControlsCollector.normalize_workflow_runs(
          [{ "total_count" => 2, "items" => [workflow_run, workflow_run.dup] }]
        )
      end
      ambiguous = workflow_run.merge("id" => 8_002)
      normalized = RemoteControlsCollector.normalize_workflow_runs(
        [{ "total_count" => 2, "items" => [workflow_run, ambiguous] }]
      )
      assert_collection_unavailable do
        RemoteControlsCollector.latest_workflow_run(normalized)
      end
      older = workflow_run.merge("run_attempt" => 1)
      normalized = RemoteControlsCollector.normalize_workflow_runs(
        [{ "total_count" => 2, "items" => [workflow_run, older] }]
      )
      assert_equal(2, RemoteControlsCollector.latest_workflow_run(normalized).fetch("runAttempt"))
    end

    run("collector strictly completes and deduplicates CI job pages") do
      assert_collection_unavailable do
        RemoteControlsCollector.normalize_workflow_jobs(
          [{ "total_count" => 2, "items" => [workflow_job] }],
          "synthetic-operator/desk-setup-switcher"
        )
      end
      assert_collection_unavailable do
        RemoteControlsCollector.normalize_workflow_jobs(
          [{ "total_count" => 2, "items" => [workflow_job, workflow_job.dup] }],
          "synthetic-operator/desk-setup-switcher"
        )
      end
      jobs = RemoteControlsCollector.normalize_workflow_jobs(
        [{ "total_count" => 1, "items" => [workflow_job] }],
        "synthetic-operator/desk-setup-switcher"
      )
      assert_equal(10_001, jobs.first.fetch("id"))
      assert_equal(11_001, jobs.first.fetch("checkRunId"))
    end

    run("collector uses slash-aware GitHub ruleset ref matching") do
      nested = "refs/heads/feature/nested"
      single_level = {
        "target" => "branch",
        "conditions" => { "include" => ["refs/heads/*"], "exclude" => [] }
      }
      recursive = {
        "target" => "branch",
        "conditions" => { "include" => ["refs/heads/**/*"], "exclude" => [] }
      }
      shallow_exclusion = {
        "target" => "branch",
        "conditions" => { "include" => ["~ALL"], "exclude" => ["refs/heads/*"] }
      }
      recursive_exclusion = {
        "target" => "branch",
        "conditions" => { "include" => ["~ALL"], "exclude" => ["refs/heads/**/*"] }
      }
      assert(!RemoteControlsCollector.ruleset_applies_to?(single_level, target: "branch", ref: nested))
      assert(RemoteControlsCollector.ruleset_applies_to?(recursive, target: "branch", ref: nested))
      assert(RemoteControlsCollector.ruleset_applies_to?(shallow_exclusion, target: "branch", ref: nested))
      assert(!RemoteControlsCollector.ruleset_applies_to?(recursive_exclusion, target: "branch", ref: nested))
    end
  end

  def test_input_safety_and_cli
    run("policy parser rejects files over its size limit") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "oversize-policy.json")
        File.binwrite(path, "")
        File.truncate(path, (1024 * 1024) + 1)
        assert_failure("--check-policy", path, forbidden: [directory])
      end
    end

    run("evidence parser rejects files over its size limit") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "oversize-evidence.json")
        File.binwrite(path, "")
        File.truncate(path, (4 * 1024 * 1024) + 1)
        assert_failure(*verification_arguments(POLICY_FIXTURE, path), forbidden: [directory])
      end
    end

    run("policy parser rejects missing and non-regular inputs") do
      Dir.mktmpdir do |directory|
        missing = File.join(directory, "missing-policy.json")
        assert_failure("--check-policy", missing, forbidden: [directory])
        assert_failure("--check-policy", directory, forbidden: [directory])
      end
    end

    run("evidence parser rejects missing and non-regular inputs") do
      Dir.mktmpdir do |directory|
        missing = File.join(directory, "missing-evidence.json")
        assert_failure(*verification_arguments(POLICY_FIXTURE, missing), forbidden: [directory])
        assert_failure(*verification_arguments(POLICY_FIXTURE, directory), forbidden: [directory])
      end
    end

    run("evidence parser rejects malformed JSON") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "evidence.json")
        File.binwrite(path, "{\"phase\":")
        assert_failure(*verification_arguments(POLICY_FIXTURE, path), forbidden: [directory])
      end
    end

    run("evidence parser rejects duplicate keys") do
      Dir.mktmpdir do |directory|
        source = File.binread(EVIDENCE_FIXTURE).sub(
          '"phase": "final-pre-tag",',
          '"phase": "final-pre-tag", "phase": "post-tag",'
        )
        path = File.join(directory, "evidence.json")
        File.binwrite(path, source)
        assert_failure(*verification_arguments(POLICY_FIXTURE, path), forbidden: [directory])
      end
    end

    run("evidence parser rejects symlinks") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "evidence-link.json")
        File.symlink(EVIDENCE_FIXTURE, path)
        assert_failure(*verification_arguments(POLICY_FIXTURE, path), forbidden: [directory])
      end
    end

    run("failure output does not echo actor IDs, logins, values, or paths") do
      Dir.mktmpdir do |directory|
        marker = "SENSITIVE_REMOTE_VALUE_MARKER"
        policy, evidence = mutated_pair(
          directory,
          evidence_mutation: lambda do |value|
            value["environment"]["protection"]["reviewers"][0]["login"] = marker
          end
        )
        assert_failure(
          *verification_arguments(policy, evidence),
          forbidden: [directory, marker, "1002"]
        )
      end
    end

    run("CLI rejects mixed policy-check and evidence modes") do
      assert_failure(
        "--check-policy", POLICY_FIXTURE,
        "--policy", POLICY_FIXTURE,
        "--evidence", EVIDENCE_FIXTURE,
        "--expected-commit", EXPECTED_COMMIT,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB
      )
    end

    run("policy preflight rejects a mismatched workflow blob anchor") do
      _stdout, stderr = assert_failure(
        "--check-policy", POLICY_FIXTURE,
        "--expected-workflow-blob", "d" * 40,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB
      )
      assert_equal("ERROR: expected workflow blob anchor is invalid\n", stderr)
    end

    run("policy preflight rejects a malformed workflow blob anchor") do
      marker = "MALFORMED_WORKFLOW_BLOB_MARKER"
      _stdout, stderr = assert_failure(
        "--check-policy", POLICY_FIXTURE,
        "--expected-workflow-blob", marker,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB,
        forbidden: [marker]
      )
      assert_equal("ERROR: expected workflow blob anchor is invalid\n", stderr)
    end


    run("policy preflight rejects a mismatched CI workflow blob anchor") do
      _stdout, stderr = assert_failure(
        "--check-policy", POLICY_FIXTURE,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", "d" * 40
      )
      assert_equal("ERROR: expected CI workflow blob anchor is invalid\n", stderr)
    end

    run("policy preflight rejects a malformed CI workflow blob anchor") do
      marker = "MALFORMED_CI_WORKFLOW_BLOB_MARKER"
      _stdout, stderr = assert_failure(
        "--check-policy", POLICY_FIXTURE,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", marker,
        forbidden: [marker]
      )
      assert_equal("ERROR: expected CI workflow blob anchor is invalid\n", stderr)
    end

    run("policy preflight rejects an expected commit even with a workflow anchor") do
      assert_failure(
        "--check-policy", POLICY_FIXTURE,
        "--expected-commit", EXPECTED_COMMIT,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB
      )
    end

    run("CLI help is side-effect-free and stable") do
      stdout, stderr, status = cli("--help")
      assert(status.success?, "help failed")
      assert(stderr.empty?, "help wrote to stderr")
      assert(stdout.include?("--check-policy FILE"), "help omitted policy preflight mode")
      assert(stdout.include?("--expected-commit SHA"), "help omitted trusted commit anchor")
      assert(stdout.include?("--expected-workflow-blob SHA"), "help omitted trusted workflow anchor")
      assert(stdout.include?("--expected-ci-workflow-blob SHA"), "help omitted trusted CI workflow anchor")
      assert(stdout.include?("--ci-workflow-id FILE"), "help omitted strict CI workflow ID mode")
    end


    run("trusted anchors must match the exact final observations") do
      assert_failure(
        "--policy", POLICY_FIXTURE,
        "--evidence", EVIDENCE_FIXTURE,
        "--expected-commit", "c" * 40,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB
      )
      assert_failure(
        "--policy", POLICY_FIXTURE,
        "--evidence", EVIDENCE_FIXTURE,
        "--expected-commit", EXPECTED_COMMIT,
        "--expected-workflow-blob", "d" * 40,
        "--expected-ci-workflow-blob", EXPECTED_CI_WORKFLOW_BLOB
      )
      assert_failure(
        "--policy", POLICY_FIXTURE,
        "--evidence", EVIDENCE_FIXTURE,
        "--expected-commit", EXPECTED_COMMIT,
        "--expected-workflow-blob", EXPECTED_WORKFLOW_BLOB,
        "--expected-ci-workflow-blob", "d" * 40
      )
    end
  end

  def execute
    test_positive_contract
    test_policy_boundaries
    test_observation_boundaries
    test_collector_strictness
    test_input_safety_and_cli

    if @failures.empty?
      puts "PASS: #{@tests} tests, #{@assertions} assertions"
      return 0
    end

    @failures.each do |name, error_class, message|
      warn "FAIL: #{name} (#{error_class}: #{message})"
    end
    warn "FAIL: #{@failures.length} of #{@tests} tests failed after #{@assertions} assertions"
    1
  end
end

exit RemoteControlsPolicyTestSuite.new.execute
