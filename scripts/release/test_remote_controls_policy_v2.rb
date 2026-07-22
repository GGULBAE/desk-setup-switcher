#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class RemoteControlsPolicyV2Test
  ROOT = File.expand_path("../..", __dir__)
  SCRIPT = File.join(__dir__, "remote_controls_policy.rb")
  FIXTURES = File.join(__dir__, "fixtures", "remote-controls")
  POLICY = File.join(FIXTURES, "policy-v2.json")
  PRE_TAG = File.join(FIXTURES, "evidence-v2-final-pre-tag.json")
  PRE_PUBLICATION = File.join(FIXTURES, "evidence-v2-pre-publication.json")
  ACTUAL_POLICY = File.join(__dir__, "remote-controls-policy.json")
  COMMIT = "a" * 40
  RELEASE_COMMIT = "9" * 40
  RELEASE_TAG_OBJECT = "8" * 40
  CANDIDATE_BLOB = "b" * 40
  CI_BLOB = "c" * 40
  PUBLICATION_BLOB = "d" * 40
  LEGACY_BLOB = "e" * 40

  def initialize
    @tests = 0
    @assertions = 0
    @failures = []
  end

  def assert(value, message = "assertion failed")
    @assertions += 1
    raise message unless value
  end

  def run(name)
    @tests += 1
    yield
    puts "ok #{@tests} - #{name}"
  rescue StandardError => error
    @failures << [name, error.message]
    puts "not ok #{@tests} - #{name}"
  end

  def arguments(policy, evidence, pre_publication: false)
    result = [
      "--policy", policy,
      "--evidence", evidence,
      "--expected-commit", COMMIT,
      "--expected-workflow-blob", CANDIDATE_BLOB,
      "--expected-ci-workflow-blob", CI_BLOB,
      "--expected-publication-workflow-blob", PUBLICATION_BLOB,
      "--expected-legacy-workflow-blob", LEGACY_BLOB
    ]
    if pre_publication
      result.concat(
        [
          "--expected-release-commit", RELEASE_COMMIT,
          "--expected-release-id", "12345",
          "--expected-release-tag-object", RELEASE_TAG_OBJECT
        ]
      )
    end
    result
  end

  def cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  def assert_success(*args, expected: nil)
    stdout, stderr, status = cli(*args)
    assert(status.success?, "expected success: #{stderr}")
    assert(stderr.empty?, "success wrote stderr")
    assert(stdout == expected, "unexpected success output") if expected
  end

  def assert_failure(*args, forbidden: [])
    stdout, stderr, status = cli(*args)
    assert(!status.success?, "expected failure")
    assert(stdout.empty?, "failure wrote stdout")
    assert(stderr.match?(/\AERROR: [A-Za-z0-9 -]+(?: is invalid| is missing| are mutually exclusive)\n\z/),
           "failure was not stable: #{stderr.inspect}")
    forbidden.each { |item| assert(!stderr.include?(item), "failure leaked input") }
  end

  def mutate(policy_fixture: POLICY, evidence_fixture: PRE_PUBLICATION)
    Dir.mktmpdir do |directory|
      policy = JSON.parse(File.binread(policy_fixture), create_additions: false)
      evidence = JSON.parse(File.binread(evidence_fixture), create_additions: false)
      yield policy, evidence
      policy_path = File.join(directory, "policy.json")
      evidence_path = File.join(directory, "evidence.json")
      File.binwrite(policy_path, JSON.pretty_generate(policy) + "\n")
      File.binwrite(evidence_path, JSON.pretty_generate(evidence) + "\n")
      yield policy_path, evidence_path, directory if block_given?
    end
  end

  def mutation_failure(policy_fixture: POLICY, evidence_fixture: PRE_PUBLICATION, policy: nil, evidence: nil)
    Dir.mktmpdir do |directory|
      policy_value = JSON.parse(File.binread(policy_fixture), create_additions: false)
      evidence_value = JSON.parse(File.binread(evidence_fixture), create_additions: false)
      policy&.call(policy_value)
      evidence&.call(evidence_value)
      policy_path = File.join(directory, "policy.json")
      evidence_path = File.join(directory, "evidence.json")
      File.binwrite(policy_path, JSON.pretty_generate(policy_value) + "\n")
      File.binwrite(evidence_path, JSON.pretty_generate(evidence_value) + "\n")
      assert_failure(*arguments(policy_path, evidence_path, pre_publication: evidence_fixture == PRE_PUBLICATION),
                     forbidden: [directory])
    end
  end

  def execute
    run("accepts the complete final-pre-tag lifecycle evidence") do
      assert_success(
        *arguments(POLICY, PRE_TAG),
        expected: "OK remote-controls normalized-evidence phase=final-pre-tag manual_gates=2\n"
      )
    end

    run("accepts the fresh pre-publication draft-bound lifecycle evidence") do
      assert_success(
        *arguments(POLICY, PRE_PUBLICATION, pre_publication: true),
        expected: "OK remote-controls normalized-evidence phase=pre-publication manual_gates=2\n"
      )
    end

    run("returns the reviewed publication workflow ID only with all four blobs") do
      assert_success(
        "--publication-workflow-id", POLICY,
        "--expected-workflow-blob", CANDIDATE_BLOB,
        "--expected-ci-workflow-blob", CI_BLOB,
        "--expected-publication-workflow-blob", PUBLICATION_BLOB,
        "--expected-legacy-workflow-blob", LEGACY_BLOB,
        expected: "7002\n"
      )
    end

    run("accepts ASCII-only CLI anchors under the C locale") do
      stdout, stderr, status = Open3.capture3(
        { "LC_ALL" => "C", "LANG" => "C" },
        RbConfig.ruby, SCRIPT,
        "--ci-workflow-id", POLICY,
        "--expected-workflow-blob", CANDIDATE_BLOB,
        "--expected-ci-workflow-blob", CI_BLOB,
        "--expected-publication-workflow-blob", PUBLICATION_BLOB,
        "--expected-legacy-workflow-blob", LEGACY_BLOB
      )
      assert(status.success?, "C-locale anchors failed: #{stderr}")
      assert(stderr.empty?, "C-locale success wrote stderr")
      assert(stdout == "7000\n", "C-locale workflow identity changed")
    end


    run("emits the policy-bound publication approval and actor contract") do
      expected = {
        "schemaVersion" => "desk-setup-switcher.publication-approval-contract/v1",
        "approvalMode" => "independent-review",
        "operator" => { "id" => 1001, "login" => "synthetic-operator", "type" => "User" },
        "reviewer" => { "id" => 1002, "login" => "synthetic-reviewer", "type" => "User" },
        "publisher" => { "id" => 1001, "login" => "SYNTHETIC-OPERATOR", "type" => "User" }
      }
      assert_success(
        "--publication-approval-contract", POLICY,
        expected: JSON.generate(expected) + "\n"
      )
    end

    run("actual operational policy remains fail-closed before collection") do
      assert_failure("--check-policy", ACTUAL_POLICY)
    end

    {
      "binds publication workflow name" => lambda { |v| v["release"]["publicationWorkflow"]["name"] = "Other" },
      "binds publication workflow path" => lambda { |v| v["release"]["publicationWorkflow"]["path"] = ".github/workflows/other.yml" },
      "binds publication workflow blob" => lambda { |v| v["release"]["publicationWorkflow"]["blobSha"] = "0" * 40 },
      "binds retired workflow name" => lambda { |v| v["release"]["legacyWorkflow"]["name"] = "Other" },
      "binds retired workflow path" => lambda { |v| v["release"]["legacyWorkflow"]["path"] = ".github/workflows/other.yml" },
      "binds retired workflow blob" => lambda { |v| v["release"]["legacyWorkflow"]["blobSha"] = "0" * 40 },
      "requires both reviewed CI checks" => lambda { |v| v["release"]["ci"]["checks"].pop },
      "binds the public-surface CI app" => lambda { |v| v["release"]["ci"]["checks"][1]["appId"] = 1 },
      "binds publisher numeric identity" => lambda { |v| v["actors"]["publisher"]["id"] = 9999 },
      "requires independent reviewer separation" => lambda { |v| v["actors"]["reviewer"] = v["actors"]["publisher"].dup },
      "requires exactly two manual controls" => lambda { |v| v["manualEvidence"]["items"].pop },
      "binds the manual evidence path contract" => lambda do |v|
        v["manualEvidence"]["items"][0]["path"] = "docs/other.json"
      end,
      "binds the manual evidence schema contract" => lambda do |v|
        v["manualEvidence"]["items"][0]["schemaVersion"] = "other/v1"
      end,
      "rejects unknown policy fields" => lambda { |v| v["unexpected"] = true }
    }.each do |name, mutation|
      run(name) { mutation_failure(policy: mutation) }
    end

    run("actor login comparison is case-insensitive but ID-bound") do
      mutation_failure(policy: lambda { |v| v["actors"]["publisher"]["login"] = "other-login" })
    end

    evidence_mutations = {
      "requires two publication workflow anchor reads" => lambda { |v| v["anchorReads"].pop },
      "rejects publication workflow anchor drift" => lambda { |v| v["anchorReads"][1]["publicationWorkflow"]["blobSha"] = "0" * 40 },
      "requires active publication workflow state" => lambda { |v| v["publicationWorkflow"]["state"] = "disabled_manually" },
      "requires manual-only publication trigger" => lambda { |v| v["publicationWorkflow"]["triggers"] << "push" },
      "requires publication contents-write route" => lambda { |v| v["publicationWorkflow"]["contentsWrite"] = false },
      "requires two retired workflow anchor reads" => lambda { |v| v["anchorReads"][0].delete("legacyWorkflow") },
      "rejects retired workflow anchor drift" => lambda { |v| v["anchorReads"][1]["legacyWorkflow"]["blobSha"] = "0" * 40 },
      "requires the retired workflow to remain disabled" => lambda { |v| v["legacyWorkflow"]["state"] = "active" },
      "requires manual-only retired workflow trigger" => lambda { |v| v["legacyWorkflow"]["triggers"] << "push" },
      "forbids contents-write on the retired workflow" => lambda { |v| v["legacyWorkflow"]["contentsWrite"] = true },
      "rejects any unexpected workflow" => lambda { |v| v["workflowInventory"]["items"] << v["ciWorkflow"].merge("id" => 7999, "name" => "Extra", "path" => ".github/workflows/extra.yml") },
      "requires exact publication environment reviewer" => lambda { |v| v["environments"]["releasePublication"]["protection"]["reviewers"][0]["id"] = 9999 },
      "requires exact publication tag deployment policy" => lambda { |v| v["environments"]["releasePublication"]["deployment"]["policies"][0]["name"] = "v0.1.1" },
      "separates publication secrets from signing secrets" => lambda { |v| v["environments"]["releasePublication"]["secrets"]["names"] << "DEVELOPER_ID_CERTIFICATE_BASE64" },
      "requires publication verification variables" => lambda { |v| v["environments"]["releasePublication"]["variables"]["names"].pop },
      "forbids repository admin-token shadowing" => lambda { |v| v["repositoryConfiguration"]["secrets"]["names"] = ["RELEASE_ADMIN_READ_TOKEN"] },
      "requires both master status checks" => lambda do |v|
        v["rulesets"]["master"][0]["rules"].find do |rule|
          rule["type"] == "required_status_checks"
        end["parameters"]["requiredStatusChecks"].pop
      end,
      "requires both completed CI jobs" => lambda { |v| v["ci"]["jobs"]["items"].pop },
      "requires the public-surface CI job to succeed" => lambda do |v|
        v["ci"]["jobs"]["items"][1]["conclusion"] = "failure"
      end,
      "requires both CI check runs" => lambda { |v| v["ci"]["checkRuns"]["items"].pop },
      "requires the public-surface GitHub Actions app" => lambda do |v|
        v["ci"]["checkRuns"]["items"][1]["appId"] = 1
      end,
      "binds both checks to one workflow suite" => lambda do |v|
        v["ci"]["checkRuns"]["items"][1]["checkSuiteId"] = 9002
      end,
      "cross-binds each CI job to its named check" => lambda do |v|
        v["ci"]["jobs"]["items"][1]["checkRunId"] = 11001
      end,
      "requires distinct manual evidence digests" => lambda do |v|
        v["manualEvidence"]["items"][0]["sha256"] =
          v["manualEvidence"]["items"][1]["sha256"]
      end,
      "binds the exact draft release ID" => lambda { |v| v["releaseBoundary"]["releases"]["items"][0]["id"] = 12346 },
      "binds the exact draft tag" => lambda { |v| v["releaseBoundary"]["releases"]["items"][0]["tag"] = "v0.1.1" },
      "requires the release to remain a draft prerelease" => lambda { |v| v["releaseBoundary"]["releases"]["items"][0]["draft"] = false },
      "rejects duplicate release records even with the exact ID" => lambda { |v| v["releaseBoundary"]["releases"]["items"] << v["releaseBoundary"]["releases"]["items"][0].dup },
      "binds the release tag commit" => lambda { |v| v["releaseBoundary"]["vRefs"]["items"][0]["commitSha"] = "0" * 40 },
      "binds the direct annotated release tag object" => lambda { |v| v["releaseBoundary"]["vRefs"]["items"][0]["objectSha"] = "7" * 40 },
      "rejects unknown evidence fields" => lambda { |v| v["publicationWorkflow"]["unexpected"] = true }
    }
    evidence_mutations.each do |name, mutation|
      run(name) { mutation_failure(evidence: mutation) }
    end

    run("pre-publication evidence requires explicit release anchors") do
      assert_failure(*arguments(POLICY, PRE_PUBLICATION))
    end

    run("final-pre-tag evidence rejects pre-publication anchors") do
      args = arguments(POLICY, PRE_TAG) + [
        "--expected-release-commit", RELEASE_COMMIT,
        "--expected-release-id", "12345",
        "--expected-release-tag-object", RELEASE_TAG_OBJECT
      ]
      assert_failure(*args)
    end

    run("one-maintainer mode binds all three numeric actors and both environments") do
      Dir.mktmpdir do |directory|
        policy = JSON.parse(File.binread(POLICY), create_additions: false)
        evidence = JSON.parse(File.binread(PRE_PUBLICATION), create_additions: false)
        operator = policy["actors"]["operator"].dup
        policy["actors"]["reviewer"] = operator.dup
        policy["actors"]["publisher"] = operator.merge("login" => operator["login"].upcase)
        policy["approval"] = { "mode" => "one-maintainer", "preventSelfReview" => false, "requiredApprovals" => 0 }
        observed = evidence["repository"]["owner"].dup
        evidence["environments"].each_value do |environment|
          environment["protection"]["reviewers"] = [observed]
          environment["protection"]["preventSelfReview"] = false
        end
        pr_rule = evidence["rulesets"]["master"][0]["rules"].find { |rule| rule["type"] == "pull_request" }
        effective = evidence["rulesets"]["effectiveMaster"]["items"].find { |item| item.dig("rule", "type") == "pull_request" }
        [pr_rule["parameters"], effective["rule"]["parameters"]].each do |parameters|
          parameters["requiredApprovingReviewCount"] = 0
          parameters["requireLastPushApproval"] = false
        end
        policy_path = File.join(directory, "policy.json")
        evidence_path = File.join(directory, "evidence.json")
        File.binwrite(policy_path, JSON.pretty_generate(policy) + "\n")
        File.binwrite(evidence_path, JSON.pretty_generate(evidence) + "\n")
        assert_success(*arguments(policy_path, evidence_path, pre_publication: true))
      end
    end

    if @failures.empty?
      puts "PASS: #{@tests} tests, #{@assertions} assertions"
      return 0
    end
    @failures.each { |name, message| warn "FAIL: #{name}: #{message}" }
    warn "FAIL: #{@failures.length} of #{@tests} tests failed"
    1
  end
end

exit RemoteControlsPolicyV2Test.new.execute
