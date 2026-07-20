#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "time"
require "tmpdir"

class PublicationPolicyTestSuite
  SCRIPT = File.expand_path("publication_policy.rb", __dir__)
  REPOSITORY = "GGULBAE/desk-setup-switcher"
  TAG = "v0.1.0"
  COMMIT = "a" * 40
  RELEASE_ID = 7001
  RUN_ID = 8001
  ARTIFACT_ID = 9001
  ARTIFACT_SHA = "b" * 64
  CANDIDATE_INVENTORY_SHA = "a" * 64
  DMG_SHA = "c" * 64
  OBSERVED_MASTER = "7" * 40
  REMOTE_CONTROLS_SHA = "6" * 64
  EXTERNAL_BETA_SET_SHA = "2" * 64
  SONOMA_BETA_REPORT_SHA = "e" * 64
  EXTERNAL_BETA_REPORT_SHAS = [SONOMA_BETA_REPORT_SHA, "f" * 64, "1" * 64].freeze
  FINAL_DMG_PROVENANCE_SHA = "7" * 64
  PREDECESSOR_LINEAGE_SHA = "8" * 64
  RELEASE_MANIFEST_SHA = "9" * 64
  APPROVER = "release-reviewer"
  PUBLISHER = "release-publisher"

  class TestFailure < StandardError; end

  def initialize
    @tests = 0
    @assertions = 0
    @failures = []
  end

  def assert(value, message = "assertion failed")
    @assertions += 1
    raise TestFailure, message unless value
  end

  def assert_equal(expected, actual, message = "values differ")
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

  def record(mode: "independent-review", approver: APPROVER, publisher: PUBLISHER)
    now = Time.now.utc
    {
      "schemaVersion" => "desk-setup-switcher.publication-approval/v2",
      "subject" => {
        "repository" => REPOSITORY,
        "tag" => TAG,
        "commit" => COMMIT,
        "remoteControlsObservedMasterCommit" => OBSERVED_MASTER,
        "releaseId" => RELEASE_ID,
        "candidateOriginRunId" => RUN_ID,
        "candidateOriginRunAttempt" => 1,
        "candidateArtifactId" => ARTIFACT_ID,
        "candidateArtifactSHA256" => ARTIFACT_SHA,
        "finalDMGSHA256" => DMG_SHA
      },
      "gates" => {
        "remoteControlsStable" => true,
        "signedNotarizedStapled" => true,
        "exactNineAssetsAndAttestations" => true,
        "immutableReleases" => true,
        "cleanQuarantinedLifecycle" => true,
        "threeExternalBetas" => true,
        "zeroPublicP0P1" => true,
        "zeroConfidentialP0P1" => true,
        "publicSurfaceReady" => true
      },
      "evidence" => {
        "candidateInventorySHA256" => CANDIDATE_INVENTORY_SHA,
        "releaseEvidenceSHA256" => "d" * 64,
        "cleanLifecycleSHA256" => SONOMA_BETA_REPORT_SHA,
        "externalBetaSetSHA256" => EXTERNAL_BETA_SET_SHA,
        "externalBetaReportSHA256" => EXTERNAL_BETA_REPORT_SHAS.dup,
        "finalDMGProvenanceSHA256" => FINAL_DMG_PROVENANCE_SHA,
        "predecessorLineageSHA256" => PREDECESSOR_LINEAGE_SHA,
        "publicBlockerQuerySHA256" => "3" * 64,
        "confidentialBlockerSignoffSHA256" => "4" * 64,
        "publicSurfaceSHA256" => "5" * 64,
        "releaseManifestSHA256" => RELEASE_MANIFEST_SHA,
        "remoteControlsEvidenceSHA256" => REMOTE_CONTROLS_SHA
      },
      "approval" => {
        "decision" => "approved",
        "approvalMode" => mode,
        "approverLogin" => approver,
        "publisherLogin" => publisher,
        "approvedAt" => (now - 60).iso8601,
        "expiresAt" => (now + 3_600).iso8601,
        "releasePublication" => true
      }
    }
  end

  def write_record(directory, value = record, name: "approval.json")
    path = File.join(directory, name)
    File.binwrite(path, JSON.generate(value) + "\n")
    path
  end

  def arguments(path, value: nil, approver: APPROVER, publisher: PUBLISHER,
                approval_mode: "independent-review", verified_at: Time.now.utc.iso8601,
                external_beta_reports: EXTERNAL_BETA_REPORT_SHAS,
                sonoma_beta_report: SONOMA_BETA_REPORT_SHA)
    digest = value || Digest::SHA256.file(path).hexdigest
    [
      "verify-approval",
      "--json", path,
      "--repository", REPOSITORY,
      "--tag", TAG,
      "--commit", COMMIT,
      "--release-id", RELEASE_ID.to_s,
      "--candidate-run-id", RUN_ID.to_s,
      "--candidate-artifact-id", ARTIFACT_ID.to_s,
      "--candidate-artifact-sha256", ARTIFACT_SHA,
      "--candidate-inventory-sha256", CANDIDATE_INVENTORY_SHA,
      "--final-dmg-sha256", DMG_SHA,
      "--remote-controls-observed-master", OBSERVED_MASTER,
      "--remote-controls-manifest-sha256", REMOTE_CONTROLS_SHA,
      "--external-beta-set-sha256", EXTERNAL_BETA_SET_SHA,
      *external_beta_reports.flat_map { |sha| ["--external-beta-report-sha256", sha] },
      "--sonoma-beta-report-sha256", sonoma_beta_report,
      "--final-dmg-provenance-sha256", FINAL_DMG_PROVENANCE_SHA,
      "--predecessor-lineage-sha256", PREDECESSOR_LINEAGE_SHA,
      "--release-manifest-sha256", RELEASE_MANIFEST_SHA,
      "--approval-sha256", digest,
      "--approver-login", approver,
      "--publisher-login", publisher,
      "--approval-mode", approval_mode,
      "--verified-at", verified_at
    ]
  end

  def cli(*args)
    Open3.capture3(RbConfig.ruby, SCRIPT, *args)
  end

  def assert_success(*args)
    stdout, stderr, status = cli(*args)
    assert(status.success?, "expected success: #{stderr.inspect}")
    assert_equal("OK publication approval\n", stdout)
    assert(stderr.empty?, "success wrote stderr")
  end

  def assert_failure(*args, forbidden: [])
    stdout, stderr, status = cli(*args)
    assert(!status.success?, "expected failure")
    assert_equal(1, status.exitstatus)
    assert(stdout.empty?, "failure wrote stdout")
    assert(stderr.match?(/\APublication policy error: [A-Za-z0-9 .:-]+\n\z/), "failure output is unstable: #{stderr.inspect}")
    forbidden.each { |text| assert(!stderr.include?(text), "failure leaked input") }
  end

  def mutate
    value = record
    yield value
    Dir.mktmpdir do |directory|
      path = write_record(directory, value)
      assert_failure(*arguments(path), forbidden: [directory])
    end
  end

  def test_success
    run("accepts an exact v2 independent publication approval") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        assert_success(*arguments(path))
      end
    end

    run("accepts an explicitly declared one-maintainer approval") do
      Dir.mktmpdir do |directory|
        value = record(mode: "one-maintainer", approver: PUBLISHER, publisher: PUBLISHER)
        path = write_record(directory, value)
        assert_success(
          *arguments(
            path,
            approver: PUBLISHER,
            publisher: PUBLISHER,
            approval_mode: "one-maintainer"
          )
        )
      end
    end


    run("rejects an approval mode that differs from the policy-bound expectation") do
      Dir.mktmpdir do |directory|
        value = record(mode: "one-maintainer", approver: PUBLISHER, publisher: PUBLISHER)
        path = write_record(directory, value)
        assert_failure(
          *arguments(
            path,
            approver: PUBLISHER,
            publisher: PUBLISHER,
            approval_mode: "independent-review"
          )
        )
      end
    end
  end

  def test_subject_and_schema
    {
      "rejects unknown root keys" => ->(value) { value["extra"] = true },
      "rejects a missing root schema key" => ->(value) { value.delete("schemaVersion") },
      "rejects the v1 approval schema" => ->(value) { value["schemaVersion"] = "desk-setup-switcher.publication-approval/v1" },
      "rejects a missing v2 evidence schema key" => ->(value) { value["evidence"].delete("releaseManifestSHA256") },
      "rejects a missing candidate inventory evidence key" => ->(value) { value["evidence"].delete("candidateInventorySHA256") },
      "rejects an extra v2 evidence schema key" => ->(value) { value["evidence"]["unexpectedSHA256"] = "0" * 64 },
      "rejects a different repository" => ->(value) { value["subject"]["repository"] = "other/repository" },
      "rejects a different tag" => ->(value) { value["subject"]["tag"] = "v0.1.1" },
      "rejects a different commit" => ->(value) { value["subject"]["commit"] = "9" * 40 },
      "rejects a different remote-controls master" => ->(value) { value["subject"]["remoteControlsObservedMasterCommit"] = "8" * 40 },
      "rejects a different release ID" => ->(value) { value["subject"]["releaseId"] += 1 },
      "rejects a different candidate run" => ->(value) { value["subject"]["candidateOriginRunId"] += 1 },
      "rejects a rerun candidate attempt" => ->(value) { value["subject"]["candidateOriginRunAttempt"] = 2 },
      "rejects a floating-point candidate attempt" => ->(value) { value["subject"]["candidateOriginRunAttempt"] = 1.0 },
      "rejects a different artifact ID" => ->(value) { value["subject"]["candidateArtifactId"] += 1 },
      "rejects a different artifact digest" => ->(value) { value["subject"]["candidateArtifactSHA256"] = "8" * 64 },
      "rejects a different final DMG" => ->(value) { value["subject"]["finalDMGSHA256"] = "7" * 64 }
    }.each do |name, mutation|
      run(name) { mutate(&mutation) }
    end
  end

  def test_gates_and_evidence
    record.fetch("gates").keys.each do |gate|
      run("requires the #{gate} gate") do
        mutate { |value| value["gates"][gate] = false }
      end
    end

    run("requires exactly three external beta reports") do
      mutate { |value| value["evidence"]["externalBetaReportSHA256"].pop }
    end
    run("requires unique external beta reports") do
      mutate do |value|
        value["evidence"]["externalBetaReportSHA256"][2] = value["evidence"]["externalBetaReportSHA256"][1]
      end
    end
    run("requires evidence digests") do
      mutate { |value| value["evidence"]["cleanLifecycleSHA256"] = "not-a-digest" }
    end
    run("requires dedicated remote-controls evidence") do
      mutate { |value| value["evidence"]["remoteControlsEvidenceSHA256"] = "not-a-digest" }
    end
    run("binds the reviewed remote-controls manifest digest") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        args = arguments(path)
        index = args.index("--remote-controls-manifest-sha256")
        args[index + 1] = "8" * 64
        assert_failure(*args, forbidden: [directory])
      end
    end
  end

  def test_v2_evidence_bindings
    {
      "candidateInventorySHA256" => "candidate inventory",
      "externalBetaSetSHA256" => "external beta set",
      "finalDMGProvenanceSHA256" => "final DMG provenance",
      "predecessorLineageSHA256" => "predecessor lineage",
      "releaseManifestSHA256" => "release manifest"
    }.each do |field, label|
      run("binds the trusted #{label} digest") do
        mutate { |value| value["evidence"][field] = "0" * 64 }
      end
    end

    run("binds every ordered external beta report digest") do
      mutate { |value| value["evidence"]["externalBetaReportSHA256"][2] = "0" * 64 }
    end

    run("rejects reordered external beta report digests") do
      mutate { |value| value["evidence"]["externalBetaReportSHA256"].rotate! }
    end

    run("binds the clean lifecycle digest to the supplied Sonoma report") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        assert_failure(
          *arguments(path, sonoma_beta_report: EXTERNAL_BETA_REPORT_SHAS.fetch(1)),
          forbidden: [directory]
        )
      end
    end

    run("rejects a duplicated Sonoma beta report") do
      Dir.mktmpdir do |directory|
        value = record
        reports = [SONOMA_BETA_REPORT_SHA, SONOMA_BETA_REPORT_SHA, EXTERNAL_BETA_REPORT_SHAS.fetch(2)]
        value["evidence"]["externalBetaReportSHA256"] = reports
        path = write_record(directory, value)
        assert_failure(*arguments(path, external_beta_reports: reports), forbidden: [directory])
      end
    end

    run("rejects a foreign Sonoma digest outside the three beta reports") do
      Dir.mktmpdir do |directory|
        value = record
        reports = [EXTERNAL_BETA_REPORT_SHAS.fetch(1), EXTERNAL_BETA_REPORT_SHAS.fetch(2), "0" * 64]
        value["evidence"]["externalBetaReportSHA256"] = reports
        path = write_record(directory, value)
        assert_failure(*arguments(path, external_beta_reports: reports), forbidden: [directory])
      end
    end
  end

  def test_v2_cli_contract
    digest_options = {
      "--candidate-inventory-sha256" => "candidate inventory",
      "--external-beta-set-sha256" => "external beta set",
      "--external-beta-report-sha256" => "external beta report",
      "--sonoma-beta-report-sha256" => "Sonoma beta report",
      "--final-dmg-provenance-sha256" => "final DMG provenance",
      "--predecessor-lineage-sha256" => "predecessor lineage",
      "--release-manifest-sha256" => "release manifest"
    }
    digest_options.each do |option, label|
      run("validates the expected #{label} digest format") do
        Dir.mktmpdir do |directory|
          path = write_record(directory)
          args = arguments(path)
          args[args.index(option) + 1] = "not-a-digest"
          assert_failure(*args, forbidden: [directory, "not-a-digest"])
        end
      end
    end

    digest_options.each_key do |option|
      next if option == "--external-beta-report-sha256"

      run("requires the #{option} option") do
        Dir.mktmpdir do |directory|
          path = write_record(directory)
          args = arguments(path)
          args.slice!(args.index(option), 2)
          assert_failure(*args, forbidden: [directory])
        end
      end
    end

    run("rejects only two expected external beta report options") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        assert_failure(
          *arguments(path, external_beta_reports: EXTERNAL_BETA_REPORT_SHAS.first(2)),
          forbidden: [directory]
        )
      end
    end

    run("rejects four expected external beta report options") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        reports = EXTERNAL_BETA_REPORT_SHAS + ["0" * 64]
        assert_failure(*arguments(path, external_beta_reports: reports), forbidden: [directory])
      end
    end

    run("rejects an uppercase expected candidate inventory digest") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        args = arguments(path)
        args[args.index("--candidate-inventory-sha256") + 1] = CANDIDATE_INVENTORY_SHA.upcase
        assert_failure(*args, forbidden: [directory, CANDIDATE_INVENTORY_SHA.upcase])
      end
    end

    run("rejects an uppercase candidate inventory digest in the approval record") do
      mutate { |value| value["evidence"]["candidateInventorySHA256"] = CANDIDATE_INVENTORY_SHA.upcase }
    end
  end

  def test_approval_identity_and_time
    run("binds the explicit approver") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        assert_failure(*arguments(path, approver: "other-reviewer"), forbidden: [directory, "other-reviewer"])
      end
    end
    run("binds the explicit publisher") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        assert_failure(*arguments(path, publisher: "other-publisher"), forbidden: [directory, "other-publisher"])
      end
    end
    run("independent approval cannot reuse the publisher") do
      mutate do |value|
        value["approval"]["approverLogin"] = PUBLISHER
      end
    end
    run("independent approval cannot reuse a case-variant publisher") do
      Dir.mktmpdir do |directory|
        value = record(approver: "Release-Publisher", publisher: PUBLISHER)
        path = write_record(directory, value)
        assert_failure(
          *arguments(path, approver: "Release-Publisher", publisher: PUBLISHER),
          forbidden: [directory]
        )
      end
    end
    run("one-maintainer approval cannot name different actors") do
      mutate { |value| value["approval"]["approvalMode"] = "one-maintainer" }
    end
    run("one-maintainer recognizes a case-variant of the same account") do
      Dir.mktmpdir do |directory|
        value = record(mode: "one-maintainer", approver: "Release-Publisher", publisher: PUBLISHER)
        path = write_record(directory, value)
        assert_success(
          *arguments(
            path,
            approver: "Release-Publisher",
            publisher: PUBLISHER,
            approval_mode: "one-maintainer"
          )
        )
      end
    end
    run("requires an approved decision") do
      mutate { |value| value["approval"]["decision"] = "pending" }
    end
    run("requires release publication approval") do
      mutate { |value| value["approval"]["releasePublication"] = false }
    end
    run("release-only approval rejects a site publication field") do
      mutate { |value| value["approval"]["sitePublication"] = true }
    end
    run("rejects an expired approval") do
      value = record
      value["approval"]["approvedAt"] = (Time.now.utc - 7_200).iso8601
      value["approval"]["expiresAt"] = (Time.now.utc - 3_600).iso8601
      Dir.mktmpdir do |directory|
        path = write_record(directory, value)
        assert_failure(*arguments(path), forbidden: [directory])
      end
    end
    run("rejects an approval that is not active yet") do
      value = record
      value["approval"]["approvedAt"] = (Time.now.utc + 3_600).iso8601
      value["approval"]["expiresAt"] = (Time.now.utc + 7_200).iso8601
      Dir.mktmpdir do |directory|
        path = write_record(directory, value)
        assert_failure(*arguments(path), forbidden: [directory])
      end
    end
    run("caps approval validity at one day") do
      value = record
      value["approval"]["expiresAt"] = (Time.now.utc + 90_000).iso8601
      Dir.mktmpdir do |directory|
        path = write_record(directory, value)
        assert_failure(*arguments(path), forbidden: [directory])
      end
    end
    run("requires five minutes of approval validity to remain") do
      value = record
      value["approval"]["expiresAt"] = (Time.now.utc + 240).iso8601
      Dir.mktmpdir do |directory|
        path = write_record(directory, value)
        assert_failure(*arguments(path), forbidden: [directory])
      end
    end
  end

  def test_file_boundary
    run("binds the explicit approval-record SHA-256") do
      Dir.mktmpdir do |directory|
        path = write_record(directory)
        assert_failure(*arguments(path, value: "0" * 64), forbidden: [directory])
      end
    end

    run("rejects duplicate JSON keys") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "approval.json")
        File.binwrite(path, '{"schemaVersion":"one","schemaVersion":"two"}')
        assert_failure(*arguments(path), forbidden: [directory, "one", "two"])
      end
    end

    run("rejects symlink approval records") do
      Dir.mktmpdir do |directory|
        target = write_record(directory, record, name: "target.json")
        path = File.join(directory, "approval.json")
        File.symlink(target, path)
        assert_failure(*arguments(path, value: Digest::SHA256.file(target).hexdigest), forbidden: [directory])
      end
    end

    run("rejects multiply-linked approval records") do
      Dir.mktmpdir do |directory|
        target = write_record(directory, record, name: "target.json")
        path = File.join(directory, "approval.json")
        File.link(target, path)
        assert_failure(*arguments(path), forbidden: [directory])
      end
    end

    run("rejects oversized approval records") do
      Dir.mktmpdir do |directory|
        path = File.join(directory, "approval.json")
        File.binwrite(path, "x" * 131_073)
        assert_failure(*arguments(path), forbidden: [directory])
      end
    end

    run("sanitizes unexpected filesystem failures") do
      Dir.mktmpdir do |directory|
        parent = File.join(directory, "ordinary-file")
        File.binwrite(parent, "not a directory\n")
        path = File.join(parent, "approval.json")
        assert_failure(*arguments(path, value: "0" * 64), forbidden: [directory, parent, path])
      end
    end
  end

  def execute
    test_success
    test_subject_and_schema
    test_gates_and_evidence
    test_v2_evidence_bindings
    test_v2_cli_contract
    test_approval_identity_and_time
    test_file_boundary

    if @failures.empty?
      puts "PASS: #{@tests} tests, #{@assertions} assertions"
      return 0
    end

    @failures.each { |name, klass, message| warn "FAIL: #{name} (#{klass}: #{message})" }
    warn "FAIL: #{@failures.length} of #{@tests} tests failed after #{@assertions} assertions"
    1
  end
end

exit PublicationPolicyTestSuite.new.execute
