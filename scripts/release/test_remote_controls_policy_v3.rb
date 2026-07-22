#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class RemoteControlsPolicyV3Test
  SCRIPT = File.join(__dir__, "remote_controls_policy.rb")
  FIXTURES = File.join(__dir__, "fixtures", "remote-controls")
  POLICY = File.join(FIXTURES, "policy-v3.json")
  BASE_EVIDENCE = File.join(FIXTURES, "evidence-v2-final-pre-tag.json")
  COMMIT = "a" * 40
  CANDIDATE_BLOB = "b" * 40
  CI_BLOB = "c" * 40
  PUBLICATION_BLOB = "d" * 40
  LEGACY_BLOB = "e" * 40
  PREDECESSOR_COMMIT = "7" * 40
  PREDECESSOR_TAG_OBJECT = "8" * 40
  RELEASE_COMMIT = "9" * 40
  RELEASE_TAG_OBJECT = "6" * 40
  PREDECESSOR_DIGEST = "1" * 64
  FINAL_DIGEST = "2" * 64
  RELEASE_ID = 12_345

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

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def predecessor_ref
    {
      "ref" => "refs/tags/v0.0.9",
      "objectType" => "tag",
      "objectSha" => PREDECESSOR_TAG_OBJECT,
      "commitSha" => PREDECESSOR_COMMIT
    }
  end

  def release_ref
    {
      "ref" => "refs/tags/v0.1.0",
      "objectType" => "tag",
      "objectSha" => RELEASE_TAG_OBJECT,
      "commitSha" => RELEASE_COMMIT
    }
  end

  def evidence_for(phase)
    evidence = JSON.parse(File.binread(BASE_EVIDENCE), create_additions: false)
    evidence["schemaVersion"] = "desk-setup-switcher.remote-release-controls-evidence/v3"
    evidence["phase"] = phase
    evidence["predecessorPreTagEvidenceSHA256"] = nil
    evidence["finalPreTagEvidenceSHA256"] = nil
    evidence.dig("environments", "releaseCandidate", "deployment", "policies").replace(
      [
        { "name" => "v0.0.9", "type" => "tag" },
        { "name" => "v0.1.0", "type" => "tag" }
      ]
    )
    case phase
    when "predecessor-pre-tag"
      evidence["releaseBoundary"] = {
        "vRefs" => { "complete" => true, "items" => [] },
        "releases" => { "complete" => true, "items" => [] }
      }
    when "final-pre-tag"
      evidence["predecessorPreTagEvidenceSHA256"] = PREDECESSOR_DIGEST
      evidence["releaseBoundary"] = {
        "vRefs" => { "complete" => true, "items" => [predecessor_ref] },
        "releases" => { "complete" => true, "items" => [] }
      }
    when "pre-publication"
      evidence["predecessorPreTagEvidenceSHA256"] = PREDECESSOR_DIGEST
      evidence["finalPreTagEvidenceSHA256"] = FINAL_DIGEST
      evidence["releaseBoundary"] = {
        "vRefs" => { "complete" => true, "items" => [predecessor_ref, release_ref] },
        "releases" => {
          "complete" => true,
          "items" => [
            { "id" => RELEASE_ID, "tag" => "v0.1.0", "draft" => true, "prerelease" => true }
          ]
        }
      }
    else
      raise "unknown phase"
    end
    evidence
  end

  def arguments(policy_path, evidence_path, phase)
    args = [
      "--policy", policy_path,
      "--evidence", evidence_path,
      "--expected-phase", phase,
      "--expected-commit", COMMIT,
      "--expected-workflow-blob", CANDIDATE_BLOB,
      "--expected-ci-workflow-blob", CI_BLOB,
      "--expected-publication-workflow-blob", PUBLICATION_BLOB,
      "--expected-legacy-workflow-blob", LEGACY_BLOB
    ]
    if %w[final-pre-tag pre-publication].include?(phase)
      args.concat(
        [
          "--expected-predecessor-commit", PREDECESSOR_COMMIT,
          "--expected-predecessor-tag-object", PREDECESSOR_TAG_OBJECT,
          "--expected-predecessor-pre-tag-evidence-sha256", PREDECESSOR_DIGEST
        ]
      )
    end
    if phase == "pre-publication"
      args.concat(
        [
          "--expected-release-commit", RELEASE_COMMIT,
          "--expected-release-id", RELEASE_ID.to_s,
          "--expected-release-tag-object", RELEASE_TAG_OBJECT,
          "--expected-final-pre-tag-evidence-sha256", FINAL_DIGEST
        ]
      )
    end
    args
  end

  def write_case(directory, policy, evidence)
    policy_path = File.join(directory, "policy.json")
    evidence_path = File.join(directory, "evidence.json")
    File.binwrite(policy_path, JSON.pretty_generate(policy) + "\n")
    File.binwrite(evidence_path, JSON.pretty_generate(evidence) + "\n")
    [policy_path, evidence_path]
  end

  def cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  def assert_success(*args, expected:)
    stdout, stderr, status = cli(*args)
    assert(status.success?, "expected success: #{stderr}")
    assert(stderr.empty?, "success wrote stderr")
    assert(stdout == expected, "unexpected success output: #{stdout.inspect}")
  end

  def assert_failure(*args)
    stdout, stderr, status = cli(*args)
    assert(!status.success?, "expected failure")
    assert(stdout.empty?, "failure wrote stdout")
    assert(
      stderr.match?(/\AERROR: [A-Za-z0-9 -]+(?: is invalid| is missing| are mutually exclusive)\n\z/),
      "failure was not stable: #{stderr.inspect}"
    )
  end

  def with_case(phase, policy_mutation: nil, evidence_mutation: nil)
    Dir.mktmpdir do |directory|
      policy = JSON.parse(File.binread(POLICY), create_additions: false)
      evidence = evidence_for(phase)
      policy_mutation&.call(policy)
      evidence_mutation&.call(evidence)
      policy_path, evidence_path = write_case(directory, policy, evidence)
      yield policy_path, evidence_path, evidence
    end
  end

  def mutation_failure(phase, policy: nil, evidence: nil)
    with_case(phase, policy_mutation: policy, evidence_mutation: evidence) do |policy_path, evidence_path|
      assert_failure(*arguments(policy_path, evidence_path, phase))
    end
  end

  def execute
    %w[predecessor-pre-tag final-pre-tag pre-publication].each do |phase|
      run("accepts the closed #{phase} lifecycle boundary") do
        with_case(phase) do |policy_path, evidence_path|
          assert_success(
            *arguments(policy_path, evidence_path, phase),
            expected: "OK remote-controls normalized-evidence phase=#{phase} manual_gates=2\n"
          )
        end
      end
    end

    run("final-pre-tag evidence is an authoritative predecessor release boundary") do
      with_case("final-pre-tag") do |_policy_path, _evidence_path, evidence|
        assert(evidence["schemaVersion"].end_with?("/v3"))
        assert(evidence["predecessorPreTagEvidenceSHA256"] == PREDECESSOR_DIGEST)
        assert(evidence["finalPreTagEvidenceSHA256"].nil?)
        assert(evidence.dig("releaseBoundary", "vRefs", "items") == [predecessor_ref])
        assert(evidence.dig("releaseBoundary", "releases", "items") == [])
      end
    end

    run("v3 evidence requires an independently supplied expected phase") do
      with_case("predecessor-pre-tag") do |policy_path, evidence_path|
        args = arguments(policy_path, evidence_path, "predecessor-pre-tag")
        index = args.index("--expected-phase")
        args.slice!(index, 2)
        assert_failure(*args)
      end
    end

    run("final-pre-tag requires every predecessor anchor") do
      with_case("final-pre-tag") do |policy_path, evidence_path|
        %w[
          --expected-predecessor-commit
          --expected-predecessor-tag-object
          --expected-predecessor-pre-tag-evidence-sha256
        ].each do |option|
          args = arguments(policy_path, evidence_path, "final-pre-tag")
          index = args.index(option)
          args.slice!(index, 2)
          assert_failure(*args)
        end
      end
    end

    run("pre-publication requires every current release anchor") do
      with_case("pre-publication") do |policy_path, evidence_path|
        %w[
          --expected-release-commit
          --expected-release-id
          --expected-release-tag-object
          --expected-final-pre-tag-evidence-sha256
        ].each do |option|
          args = arguments(policy_path, evidence_path, "pre-publication")
          index = args.index(option)
          args.slice!(index, 2)
          assert_failure(*args)
        end
      end
    end

    {
      "rejects a missing predecessor ref" => lambda do |value|
        value.dig("releaseBoundary", "vRefs", "items").clear
      end,
      "rejects an extra ref" => lambda do |value|
        value.dig("releaseBoundary", "vRefs", "items") << release_ref
      end,
      "rejects a lightweight predecessor ref" => lambda do |value|
        value.dig("releaseBoundary", "vRefs", "items", 0)["objectType"] = "commit"
      end,
      "rejects a moved predecessor commit" => lambda do |value|
        value.dig("releaseBoundary", "vRefs", "items", 0)["commitSha"] = "0" * 40
      end,
      "rejects a moved predecessor tag object" => lambda do |value|
        value.dig("releaseBoundary", "vRefs", "items", 0)["objectSha"] = "0" * 40
      end,
      "rejects any predecessor GitHub Release" => lambda do |value|
        value.dig("releaseBoundary", "releases", "items") << {
          "id" => 7_009, "tag" => "v0.0.9", "draft" => true, "prerelease" => true
        }
      end,
      "rejects the wrong predecessor evidence digest" => lambda do |value|
        value["predecessorPreTagEvidenceSHA256"] = "0" * 64
      end,
      "rejects an activated legacy workflow" => lambda do |value|
        value["legacyWorkflow"]["state"] = "active"
      end
    }.each do |name, mutation|
      run(name) { mutation_failure("final-pre-tag", evidence: mutation) }
    end

    run("rejects a missing current release ref") do
      mutation_failure(
        "pre-publication",
        evidence: lambda { |value| value.dig("releaseBoundary", "vRefs", "items").pop }
      )
    end

    run("rejects a v0.0.9 Release during pre-publication") do
      mutation_failure(
        "pre-publication",
        evidence: lambda do |value|
          value.dig("releaseBoundary", "releases", "items") << {
            "id" => 7_009, "tag" => "v0.0.9", "draft" => true, "prerelease" => true
          }
        end
      )
    end

    run("rejects the wrong final-pre-tag digest") do
      mutation_failure(
        "pre-publication",
        evidence: lambda { |value| value["finalPreTagEvidenceSHA256"] = "0" * 64 }
      )
    end

    run("rejects a phase substituted into otherwise predecessor-pre-tag evidence") do
      mutation_failure(
        "predecessor-pre-tag",
        evidence: lambda { |value| value["phase"] = "final-pre-tag" }
      )
    end

    {
      "requires both release-candidate deployment tags" => lambda do |value|
        value.dig("environments", "releaseCandidate", "deployment", "policies").shift
      end,
      "rejects an extra release-candidate deployment tag" => lambda do |value|
        value.dig("environments", "releaseCandidate", "deployment", "policies") << {
          "name" => "v0.2.0", "type" => "tag"
        }
      end,
      "keeps release-publication restricted to v0.1.0" => lambda do |value|
        value.dig("environments", "releasePublication", "deployment", "policies").unshift(
          { "name" => "v0.0.9", "type" => "tag" }
        )
      end
    }.each do |name, mutation|
      run(name) { mutation_failure("pre-publication", evidence: mutation) }
    end

    run("binds the predecessor tag in the v3 policy") do
      mutation_failure(
        "final-pre-tag",
        policy: lambda { |value| value["release"]["predecessorTag"] = "v0.0.8" }
      )
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

exit RemoteControlsPolicyV3Test.new.execute
