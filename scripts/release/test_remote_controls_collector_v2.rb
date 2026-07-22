#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "collect_remote_controls_evidence"

class RemoteControlsCollectorV2Test
  SCRIPT = File.join(__dir__, "collect_remote_controls_evidence.rb")
  ROOT = File.expand_path("../..", __dir__)

  def initialize
    @tests = 0
    @assertions = 0
    @failures = []
  end

  def assert(value, message = "assertion failed")
    @assertions += 1
    raise message unless value
  end

  def equal(expected, actual)
    assert(expected == actual, "expected #{expected.inspect}, got #{actual.inspect}")
  end

  def run(name)
    @tests += 1
    yield
    puts "ok #{@tests} - #{name}"
  rescue StandardError => error
    @failures << [name, error.message]
    puts "not ok #{@tests} - #{name}"
  end

  def unavailable
    yield
    raise "expected unavailable"
  rescue RemoteControlsCollector::CollectionUnavailable
    @assertions += 1
  end

  def cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  def assert_cli_failure(*args, forbidden: [])
    stdout, stderr, status = cli(*args)
    equal(70, status.exitstatus)
    equal("", stdout)
    equal("ERROR: remote controls evidence unavailable\n", stderr)
    forbidden.each { |item| assert(!stderr.include?(item), "failure leaked input") }
  end

  def execute
    run("derives exact trigger and contents-write projections from all reviewed workflows") do
      expected = {
        ".github/workflows/ci.yml" => [["pull_request", "push", "workflow_dispatch"], false],
        ".github/workflows/release.yml" => [["workflow_dispatch"], false],
        ".github/workflows/signed-release-candidate.yml" => [["workflow_dispatch"], true],
        ".github/workflows/publish-release.yml" => [["workflow_dispatch"], true]
      }
      expected.each do |path, (triggers, contents_write)|
        projection = RemoteControlsCollector.local_workflow_security(File.join(ROOT, path))
        equal(triggers, projection["triggers"])
        equal(contents_write, projection["contentsWrite"])
      end
    end

    workflows = [
      { "id" => 7000, "name" => "CI", "path" => ".github/workflows/ci.yml", "state" => "active" },
      { "id" => 7001, "name" => "Signed release candidate", "path" => ".github/workflows/signed-release-candidate.yml", "state" => "active" },
      { "id" => 7002, "name" => "Publish approved signed release", "path" => ".github/workflows/publish-release.yml", "state" => "active" },
      { "id" => 7003, "name" => "Retired legacy release workflow", "path" => ".github/workflows/release.yml", "state" => "disabled_manually" }
    ]

    run("normalizes the complete paginated workflow inventory including the retired route") do
      pages = [
        { "total_count" => 4, "items" => workflows.first(2) },
        { "total_count" => 4, "items" => workflows.last(2) }
      ]
      inventory = RemoteControlsCollector.normalize_active_workflow_inventory(pages)
      equal(true, inventory["complete"])
      equal(workflows.map { |item| item["path"] }.sort, inventory["items"].map { |item| item["path"] })
    end

    run("rejects paginated workflow inventory truncation") do
      unavailable do
        RemoteControlsCollector.normalize_active_workflow_inventory(
          [{ "total_count" => 5, "items" => workflows }]
        )
      end
    end

    run("rejects duplicate workflow identity across pages") do
      unavailable do
        RemoteControlsCollector.normalize_active_workflow_inventory(
          [
            { "total_count" => 5, "items" => workflows.first(2) },
            { "total_count" => 5, "items" => [workflows.last, workflows.first.dup, workflows[2]] }
          ]
        )
      end
    end

    run("retains disabled routes while completing the full API inventory") do
      disabled = { "id" => 7999, "name" => "Old", "path" => ".github/workflows/old.yml", "state" => "disabled_manually" }
      inventory = RemoteControlsCollector.normalize_active_workflow_inventory(
        [{ "total_count" => 5, "items" => workflows + [disabled] }]
      )
      equal(5, inventory["items"].length)
      assert(inventory["items"].any? { |item| item["id"] == 7999 })
    end

    run("selects one suite and the primary job from the exact two-job CI") do
      Dir.mktmpdir do |directory|
        checks_path = File.join(directory, "checks.jsonl")
        jobs_path = File.join(directory, "jobs.jsonl")
        check_items = [
          {
            "id" => 11_001, "name" => "Verify macOS app", "app_id" => 15_368,
            "check_suite_id" => 9_001, "head_sha" => "a" * 40,
            "status" => "completed", "conclusion" => "success"
          },
          {
            "id" => 11_002, "name" => "Verify public site and release assets",
            "app_id" => 15_368, "check_suite_id" => 9_001, "head_sha" => "a" * 40,
            "status" => "completed", "conclusion" => "success"
          }
        ]
        job_items = [
          {
            "id" => 10_001, "run_id" => 8_001, "run_attempt" => 2,
            "name" => "Verify macOS app", "workflow_name" => "CI",
            "head_branch" => "master", "head_sha" => "a" * 40,
            "status" => "completed", "conclusion" => "success",
            "check_run_url" =>
              "https://api.github.com/repos/GGULBAE/desk-setup-switcher/check-runs/11001"
          },
          {
            "id" => 10_002, "run_id" => 8_001, "run_attempt" => 2,
            "name" => "Verify public site and release assets", "workflow_name" => "CI",
            "head_branch" => "master", "head_sha" => "a" * 40,
            "status" => "completed", "conclusion" => "success",
            "check_run_url" =>
              "https://api.github.com/repos/GGULBAE/desk-setup-switcher/check-runs/11002"
          }
        ]
        File.binwrite(checks_path, JSON.generate("total_count" => 2, "items" => check_items) + "\n")
        File.binwrite(jobs_path, JSON.generate("total_count" => 2, "items" => job_items) + "\n")

        stdout, stderr, status = cli("check-suite-id", "--input", checks_path)
        assert(status.success?)
        equal("9001\n", stdout)
        equal("", stderr)
        stdout, stderr, status = cli("workflow-job-id", "--input", jobs_path)
        assert(status.success?)
        equal("10001\n", stdout)
        equal("", stderr)

        check_items[1]["check_suite_id"] = 9_002
        File.binwrite(checks_path, JSON.generate("total_count" => 2, "items" => check_items) + "\n")
        assert_cli_failure("check-suite-id", "--input", checks_path, forbidden: [directory])
        job_items[1]["name"] = "Verify macOS app"
        File.binwrite(jobs_path, JSON.generate("total_count" => 2, "items" => job_items) + "\n")
        assert_cli_failure("workflow-job-id", "--input", jobs_path, forbidden: [directory])
      end
    end

    run("normalizes exact tag object/commit and rejects duplicate refs") do
      raw = {
        "ref" => "refs/tags/v0.1.0",
        "object_type" => "tag",
        "object_sha" => "8" * 40,
        "commit_sha" => "9" * 40
      }
      value = RemoteControlsCollector.normalize_pre_publication_refs([raw])
      equal("9" * 40, value.dig("items", 0, "commitSha"))
      equal("tag", value.dig("items", 0, "objectType"))
      unavailable { RemoteControlsCollector.normalize_pre_publication_refs([raw, raw.dup]) }
    end

    run("manual evidence is phase-bound, actor-bound, fresh, and digest-bearing") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "manual.json")
        observed_at = Time.now.utc.iso8601
        value = {
          "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
          "phase" => "pre-publication",
          "control" => "release-candidate-administrator-bypass-disabled",
          "administratorBypassEnabled" => false,
          "token" => nil,
          "tokenPermissions" => [],
          "observer" => { "id" => 1001, "login" => "synthetic-operator", "type" => "User" },
          "observedAt" => observed_at,
          "sourceArtifactSHA256" => "1" * 64,
          "redactionReviewed" => true,
          "subject" => {
            "peeledCommit" => "9" * 40,
            "releaseId" => 12_345,
            "tag" => "v0.1.0",
            "tagObjectSha" => "8" * 40
          }
        }
        File.binwrite(path, JSON.generate(value) + "\n")
        result = RemoteControlsCollector.manual_evidence(
          path: path,
          expected_control: "release-candidate-administrator-bypass-disabled",
          permission_profile: "candidate",
          actor_id: 1001,
          actor_login: "SYNTHETIC-OPERATOR",
          verified_at: observed_at,
          phase: "pre-publication",
          release_commit: "9" * 40,
          release_id: 12_345,
          release_tag_object: "8" * 40
        )
        equal(Digest::SHA256.file(path).hexdigest, result.fetch("sha256"))
        value["phase"] = "final-pre-tag"
        File.binwrite(path, JSON.generate(value) + "\n")
        unavailable do
          RemoteControlsCollector.manual_evidence(
            path: path,
            expected_control: "release-candidate-administrator-bypass-disabled",
            permission_profile: "candidate",
            actor_id: 1001,
            actor_login: "synthetic-operator",
            verified_at: observed_at,
            phase: "pre-publication",
            release_commit: "9" * 40,
            release_id: 12_345,
            release_tag_object: "8" * 40
          )
        end
      end
    end

    run("historical final evidence may age while current or pre-publication evidence may not") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "manual.json")
        verified_at = Time.now.utc
        stale_at = (verified_at - 86_401).iso8601
        value = {
          "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
          "phase" => "final-pre-tag",
          "control" => "release-candidate-administrator-bypass-disabled",
          "administratorBypassEnabled" => false,
          "token" => nil,
          "tokenPermissions" => [],
          "observer" => { "id" => 1001, "login" => "synthetic-operator", "type" => "User" },
          "observedAt" => stale_at,
          "sourceArtifactSHA256" => "1" * 64,
          "redactionReviewed" => true,
          "subject" => { "tag" => "v0.1.0" }
        }
        File.binwrite(path, JSON.generate(value) + "\n")
        base = {
          path: path,
          expected_control: "release-candidate-administrator-bypass-disabled",
          permission_profile: "candidate",
          actor_id: 1001,
          actor_login: "synthetic-operator",
          verified_at: verified_at.iso8601,
          phase: "final-pre-tag"
        }
        result = RemoteControlsCollector.manual_evidence(**base, freshness_mode: "historical")
        equal(stale_at, result.fetch("observedAt"))
        unavailable { RemoteControlsCollector.manual_evidence(**base, freshness_mode: "current") }

        value["phase"] = "pre-publication"
        value["subject"] = {
          "peeledCommit" => "9" * 40,
          "releaseId" => 12_345,
          "tag" => "v0.1.0",
          "tagObjectSha" => "8" * 40
        }
        File.binwrite(path, JSON.generate(value) + "\n")
        prepublication = base.merge(
          phase: "pre-publication",
          release_commit: "9" * 40,
          release_id: 12_345,
          release_tag_object: "8" * 40
        )
        unavailable do
          RemoteControlsCollector.manual_evidence(**prepublication, freshness_mode: "historical")
        end
        unavailable do
          RemoteControlsCollector.manual_evidence(**prepublication, freshness_mode: "current")
        end
      end
    end

    run("publication token evidence has a closed owner, repository, permission, and lifetime contract") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "manual.json")
        verified_time = Time.now.utc
        token = {
          "type" => "fine-grained-personal-access-token",
          "resourceOwner" => "synthetic-operator",
          "repositorySelection" => ["synthetic-operator/desk-setup-switcher"],
          "accountPermissions" => [],
          "organizationPermissions" => [],
          "issuedAt" => verified_time.iso8601,
          "expiresAt" => (verified_time + 30 * 86_400).iso8601
        }
        value = {
          "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
          "phase" => "pre-publication",
          "control" => "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
          "administratorBypassEnabled" => false,
          "token" => token,
          "tokenPermissions" =>
            %w[actions:read administration:read attestations:read contents:read metadata:read],
          "observer" => { "id" => 1001, "login" => "synthetic-operator", "type" => "User" },
          "observedAt" => verified_time.iso8601,
          "sourceArtifactSHA256" => "2" * 64,
          "redactionReviewed" => true,
          "subject" => {
            "peeledCommit" => "9" * 40,
            "releaseId" => 12_345,
            "tag" => "v0.1.0",
            "tagObjectSha" => "8" * 40
          }
        }
        arguments = {
          path: path,
          expected_control:
            "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
          permission_profile: "publication",
          actor_id: 1001,
          actor_login: "SYNTHETIC-OPERATOR",
          verified_at: verified_time.iso8601,
          phase: "pre-publication",
          release_commit: "9" * 40,
          release_id: 12_345,
          release_tag_object: "8" * 40
        }
        validate = lambda do |candidate, **overrides|
          File.binwrite(path, JSON.generate(candidate) + "\n")
          RemoteControlsCollector.manual_evidence(**arguments.merge(overrides))
        end
        deep_copy = ->(candidate) { JSON.parse(JSON.generate(candidate), create_additions: false) }

        result = validate.call(value)
        equal(Digest::SHA256.file(path).hexdigest, result.fetch("sha256"))

        issuance_boundary = deep_copy.call(value)
        issuance_boundary.fetch("token")["issuedAt"] = (verified_time - 900).iso8601
        issuance_boundary.fetch("token")["expiresAt"] =
          (verified_time - 900 + 30 * 86_400).iso8601
        equal(
          issuance_boundary.fetch("observedAt"),
          validate.call(issuance_boundary).fetch("observedAt")
        )

        boundary = deep_copy.call(value)
        boundary.fetch("token")["expiresAt"] = (verified_time + 2_700).iso8601
        equal(boundary.fetch("observedAt"), validate.call(boundary).fetch("observedAt"))

        invalid_mutations = [
          ->(candidate) { candidate.fetch("token")["type"] = "classic-personal-access-token" },
          ->(candidate) { candidate.fetch("token")["resourceOwner"] = "other-owner" },
          ->(candidate) { candidate.fetch("token")["repositorySelection"] << "synthetic-operator/other" },
          ->(candidate) { candidate.fetch("token")["accountPermissions"] = ["email:read"] },
          ->(candidate) { candidate.fetch("token")["organizationPermissions"] = ["members:read"] },
          ->(candidate) { candidate.fetch("token")["issuedAt"] = (verified_time + 1).iso8601 },
          ->(candidate) { candidate.fetch("token")["issuedAt"] = (verified_time - 901).iso8601 },
          ->(candidate) { candidate.fetch("token")["expiresAt"] = (verified_time + 2_699).iso8601 },
          ->(candidate) { candidate.fetch("token")["expiresAt"] = (verified_time + 30 * 86_400 + 1).iso8601 },
          ->(candidate) { candidate.fetch("token").delete("expiresAt") },
          ->(candidate) { candidate.fetch("token").delete("issuedAt") },
          ->(candidate) { candidate.fetch("token")["unexpected"] = true },
          ->(candidate) { candidate.delete("token") },
          ->(candidate) { candidate["unexpected"] = true }
        ]
        invalid_mutations.each do |mutation|
          candidate = deep_copy.call(value)
          mutation.call(candidate)
          unavailable { validate.call(candidate) }
        end

        candidate_profile = deep_copy.call(value)
        candidate_profile["control"] = "release-candidate-administrator-bypass-disabled"
        candidate_profile["tokenPermissions"] = []
        unavailable do
          validate.call(
            candidate_profile,
            expected_control: "release-candidate-administrator-bypass-disabled",
            permission_profile: "candidate"
          )
        end

        historical_observed = verified_time - 3 * 86_400
        historical = deep_copy.call(value)
        historical["phase"] = "final-pre-tag"
        historical["observedAt"] = historical_observed.iso8601
        historical["subject"] = { "tag" => "v0.1.0" }
        historical.fetch("token")["issuedAt"] = historical_observed.iso8601
        historical.fetch("token")["expiresAt"] = (historical_observed + 86_400).iso8601
        historical_arguments = {
          phase: "final-pre-tag",
          release_commit: nil,
          release_id: nil,
          release_tag_object: nil,
          freshness_mode: "historical"
        }
        equal(
          historical.fetch("observedAt"),
          validate.call(historical, **historical_arguments).fetch("observedAt")
        )
        overlong_historical = deep_copy.call(historical)
        overlong_historical.fetch("token")["expiresAt"] =
          (historical_observed + 30 * 86_400 + 1).iso8601
        unavailable { validate.call(overlong_historical, **historical_arguments) }
      end
    end

    run("manual evidence CLI accepts ASCII-only anchors under the C locale") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "manual.json")
        observed_at = Time.now.utc.iso8601
        value = {
          "schemaVersion" => "desk-setup-switcher.manual-release-control-evidence/v1",
          "phase" => "final-pre-tag",
          "control" => "release-candidate-administrator-bypass-disabled",
          "administratorBypassEnabled" => false,
          "token" => nil,
          "tokenPermissions" => [],
          "observer" => { "id" => 1001, "login" => "synthetic-operator", "type" => "User" },
          "observedAt" => observed_at,
          "sourceArtifactSHA256" => "1" * 64,
          "redactionReviewed" => true,
          "subject" => { "tag" => "v0.1.0" }
        }
        File.binwrite(path, JSON.generate(value) + "\n")
        stdout, stderr, status = Open3.capture3(
          { "LC_ALL" => "C", "LANG" => "C" },
          RbConfig.ruby, SCRIPT,
          "manual-evidence",
          "--input", path,
          "--control", "release-candidate-administrator-bypass-disabled",
          "--permission-profile", "candidate",
          "--actor-id", "1001",
          "--actor-login", "synthetic-operator",
          "--verified-at", observed_at,
          "--phase", "final-pre-tag"
        )
        assert(status.success?, "C-locale manual evidence failed: #{stderr}")
        equal("", stderr)
        result = JSON.parse(stdout, create_additions: false)
        equal(Digest::SHA256.file(path).hexdigest, result.fetch("sha256"))
      end
    end

    run("normalizes exact draft release and rejects duplicate tag routes") do
      raw = { "id" => 12345, "tag_name" => "v0.1.0", "draft" => true, "prerelease" => true }
      value = RemoteControlsCollector.normalize_pre_publication_releases([raw])
      equal(12345, value.dig("items", 0, "id"))
      duplicate = raw.merge("id" => 12346)
      unavailable { RemoteControlsCollector.normalize_pre_publication_releases([raw, duplicate]) }
    end

    run("CLI truncation failures remain value-free and stable") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "workflows.jsonl")
        File.binwrite(path, JSON.generate("total_count" => 5, "items" => workflows) + "\n")
        assert_cli_failure("active-workflow-inventory", "--input", path, forbidden: [directory, "7000"])
      end
    end

    run("workflow security projection rejects duplicate YAML permissions") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "workflow.yml")
        File.binwrite(path, "name: duplicate\non: workflow_dispatch\npermissions: {}\npermissions:\n  contents: write\njobs: {}\n")
        assert_cli_failure("local-workflow-security", "--workflow", path, forbidden: [directory])
      end
    end

    if @failures.empty?
      puts "PASS: #{@tests} tests, #{@assertions} assertions"
      return 0
    end
    @failures.each { |name, message| warn "FAIL: #{name}: #{message}" }
    1
  end
end

exit RemoteControlsCollectorV2Test.new.execute
