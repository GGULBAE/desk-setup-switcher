#!/usr/bin/env ruby

require "json"
require "digest"
require "optparse"
require "time"

module DeskSetupPublicationPolicy
  SCHEMA = "desk-setup-switcher.publication-approval/v2"
  MAX_JSON_BYTES = 131_072
  MINIMUM_REMAINING_SECONDS = 300
  SHA256 = /\A[0-9a-f]{64}\z/
  COMMIT = /\A[0-9a-f]{40}\z/
  LOGIN = /\A(?!-)[A-Za-z0-9-]{1,39}(?<!-)\z/

  class PolicyError < StandardError; end
  class DuplicateKeyError < PolicyError; end

  class StrictObject < Hash
    def []=(key, value)
      raise DuplicateKeyError, "duplicate JSON key" if key?(key)

      super
    end
  end

  module_function

  def fail_policy!(message)
    raise PolicyError, message
  end

  def exact_object(value, label, keys)
    fail_policy!("#{label} is not an object") unless value.is_a?(Hash)
    fail_policy!("#{label} has an unexpected schema") unless value.keys.sort == keys.sort
    value
  end

  def exact_string(value, label)
    fail_policy!("#{label} is not a non-empty string") unless value.is_a?(String) && !value.empty?
    fail_policy!("#{label} is multiline") if value.include?("\n") || value.include?("\r")
    value
  end

  def exact_sha256(value, label)
    value = exact_string(value, label)
    fail_policy!("#{label} is not a lowercase SHA-256 digest") unless SHA256.match?(value)
    value
  end

  def exact_positive_integer(value, label)
    fail_policy!("#{label} is not a positive integer") unless value.is_a?(Integer) && value.positive?
    value
  end

  def exact_true(value, label)
    fail_policy!("#{label} is not true") unless value == true
    value
  end

  def read_strict_json(path)
    before_path = File.lstat(path)
    fail_policy!("approval record is not a regular file") unless before_path.file? && !before_path.symlink?
    bytes = nil
    descriptor_identity = nil
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      before = file.stat
      fail_policy!("approval record descriptor is not a regular file") unless before.file?
      fail_policy!("approval record has an unsafe link count") unless before.nlink == 1
      fail_policy!("approval record path identity differs") unless
        [before.dev, before.ino] == [before_path.dev, before_path.ino]
      fail_policy!("approval record is empty or too large") unless before.size.positive? && before.size <= MAX_JSON_BYTES

      bytes = file.read(MAX_JSON_BYTES + 1)
      after = file.stat
      descriptor_identity = [after.dev, after.ino, after.mode, after.nlink, after.size, after.mtime.to_r, after.ctime.to_r]
      before_identity = [before.dev, before.ino, before.mode, before.nlink, before.size, before.mtime.to_r, before.ctime.to_r]
      fail_policy!("approval record changed during descriptor-bound read") unless descriptor_identity == before_identity
      fail_policy!("approval record changed size during read") unless bytes.bytesize == before.size
    end
    after_path = File.lstat(path)
    after_path_identity = [
      after_path.dev, after_path.ino, after_path.mode, after_path.nlink,
      after_path.size, after_path.mtime.to_r, after_path.ctime.to_r
    ]
    fail_policy!("approval record path changed during read") unless after_path_identity == descriptor_identity

    text = bytes.force_encoding(Encoding::UTF_8)
    fail_policy!("approval record is not UTF-8") unless text.valid_encoding?
    parsed = JSON.parse(
      text,
      allow_nan: false,
      create_additions: false,
      max_nesting: 32,
      object_class: StrictObject
    )
    [parsed, Digest::SHA256.hexdigest(bytes)]
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP, JSON::ParserError, JSON::NestingError
    raise PolicyError, "approval record is unavailable or invalid"
  end

  def verify!(record, expected)
    record = exact_object(
      record,
      "approval record",
      %w[approval evidence gates schemaVersion subject]
    )
    fail_policy!("approval record schema differs") unless record["schemaVersion"] == SCHEMA

    subject = exact_object(
      record["subject"],
      "approval subject",
      %w[candidateArtifactId candidateArtifactSHA256 candidateOriginRunAttempt candidateOriginRunId commit finalDMGSHA256 releaseId remoteControlsObservedMasterCommit repository tag]
    )
    exact_positive_integer(subject["releaseId"], "release ID")
    exact_positive_integer(subject["candidateOriginRunId"], "candidate origin run ID")
    exact_positive_integer(subject["candidateArtifactId"], "candidate artifact ID")
    fail_policy!("candidate origin attempt differs") unless
      subject["candidateOriginRunAttempt"].is_a?(Integer) &&
      subject["candidateOriginRunAttempt"] == 1
    exact_sha256(subject["candidateArtifactSHA256"], "candidate artifact digest")
    exact_sha256(subject["finalDMGSHA256"], "final DMG digest")
    fail_policy!("repository identity differs") unless subject["repository"] == expected.fetch(:repository)
    fail_policy!("release tag differs") unless subject["tag"] == expected.fetch(:tag)
    fail_policy!("release commit differs") unless subject["commit"] == expected.fetch(:commit)
    observed_master = exact_string(subject["remoteControlsObservedMasterCommit"], "remote-controls observed master")
    fail_policy!("remote-controls observed master is invalid") unless COMMIT.match?(observed_master)
    fail_policy!("remote-controls observed master differs") unless
      observed_master == expected.fetch(:remote_controls_observed_master)
    fail_policy!("release ID differs") unless subject["releaseId"] == expected.fetch(:release_id)
    fail_policy!("candidate origin run differs") unless subject["candidateOriginRunId"] == expected.fetch(:candidate_run_id)
    fail_policy!("candidate artifact differs") unless subject["candidateArtifactId"] == expected.fetch(:candidate_artifact_id)
    fail_policy!("candidate artifact digest differs") unless subject["candidateArtifactSHA256"] == expected.fetch(:candidate_artifact_sha256)
    fail_policy!("final DMG digest differs") unless subject["finalDMGSHA256"] == expected.fetch(:final_dmg_sha256)

    gates = exact_object(
      record["gates"],
      "approval gates",
      %w[cleanQuarantinedLifecycle exactNineAssetsAndAttestations immutableReleases publicSurfaceReady remoteControlsStable signedNotarizedStapled threeExternalBetas zeroConfidentialP0P1 zeroPublicP0P1]
    )
    gates.each { |name, value| exact_true(value, "approval gate #{name}") }

    evidence = exact_object(
      record["evidence"],
      "approval evidence",
      %w[candidateInventorySHA256 cleanLifecycleSHA256 confidentialBlockerSignoffSHA256 externalBetaReportSHA256 externalBetaSetSHA256 finalDMGProvenanceSHA256 predecessorLineageSHA256 publicBlockerQuerySHA256 publicSurfaceSHA256 releaseEvidenceSHA256 releaseManifestSHA256 remoteControlsEvidenceSHA256]
    )
    %w[candidateInventorySHA256 cleanLifecycleSHA256 confidentialBlockerSignoffSHA256 externalBetaSetSHA256 finalDMGProvenanceSHA256 predecessorLineageSHA256 publicBlockerQuerySHA256 publicSurfaceSHA256 releaseEvidenceSHA256 releaseManifestSHA256 remoteControlsEvidenceSHA256].each do |name|
      exact_sha256(evidence[name], "approval evidence #{name}")
    end
    fail_policy!("candidate inventory digest differs") unless
      evidence["candidateInventorySHA256"] == expected.fetch(:candidate_inventory_sha256)
    fail_policy!("remote-controls manifest digest differs") unless
      evidence["remoteControlsEvidenceSHA256"] == expected.fetch(:remote_controls_manifest_sha256)
    fail_policy!("external beta set digest differs") unless
      evidence["externalBetaSetSHA256"] == expected.fetch(:external_beta_set_sha256)
    fail_policy!("final DMG provenance digest differs") unless
      evidence["finalDMGProvenanceSHA256"] == expected.fetch(:final_dmg_provenance_sha256)
    fail_policy!("predecessor lineage digest differs") unless
      evidence["predecessorLineageSHA256"] == expected.fetch(:predecessor_lineage_sha256)
    fail_policy!("release manifest digest differs") unless
      evidence["releaseManifestSHA256"] == expected.fetch(:release_manifest_sha256)
    beta_digests = evidence["externalBetaReportSHA256"]
    fail_policy!("exactly three external beta evidence digests are required") unless beta_digests.is_a?(Array) && beta_digests.length == 3
    beta_digests.each_with_index { |digest, index| exact_sha256(digest, "external beta digest #{index + 1}") }
    fail_policy!("external beta evidence digests are not unique") unless beta_digests.uniq.length == beta_digests.length
    fail_policy!("external beta evidence digests differ") unless
      beta_digests == expected.fetch(:external_beta_report_sha256)
    sonoma_digest = expected.fetch(:sonoma_beta_report_sha256)
    fail_policy!("clean lifecycle digest differs from the Sonoma beta report") unless
      evidence["cleanLifecycleSHA256"] == sonoma_digest
    fail_policy!("Sonoma beta report is not one of the external beta reports") unless
      beta_digests.include?(sonoma_digest)

    approval = exact_object(
      record["approval"],
      "publication approval",
      %w[approvalMode approvedAt approverLogin decision expiresAt publisherLogin releasePublication]
    )
    fail_policy!("publication decision is not approved") unless approval["decision"] == "approved"
    exact_true(approval["releasePublication"], "release publication approval")
    approver_login = exact_string(approval["approverLogin"], "approver login")
    publisher_login = exact_string(approval["publisherLogin"], "publisher login")
    fail_policy!("approver login has an invalid format") unless LOGIN.match?(approver_login)
    fail_policy!("publisher login has an invalid format") unless LOGIN.match?(publisher_login)
    fail_policy!("approver identity differs") unless approver_login.casecmp?(expected.fetch(:approver_login))
    fail_policy!("publisher identity differs") unless publisher_login.casecmp?(expected.fetch(:publisher_login))
    fail_policy!("publication approval mode differs") unless
      approval["approvalMode"] == expected.fetch(:approval_mode)
    case approval["approvalMode"]
    when "independent-review"
      fail_policy!("independent approval reuses the publisher identity") if approver_login.casecmp?(publisher_login)
    when "one-maintainer"
      fail_policy!("one-maintainer approval identities differ") unless approver_login.casecmp?(publisher_login)
    else
      fail_policy!("publication approval mode is invalid")
    end

    approved_at_text = exact_string(approval["approvedAt"], "approval timestamp")
    expires_at_text = exact_string(approval["expiresAt"], "approval expiration")
    approved_at = Time.iso8601(approved_at_text)
    expires_at = Time.iso8601(expires_at_text)
    verified_at = Time.iso8601(expected.fetch(:verified_at))
    fail_policy!("approval timestamp is not canonical UTC") unless approved_at_text.end_with?("Z") && approved_at.utc.iso8601 == approved_at_text
    fail_policy!("approval expiration is not canonical UTC") unless expires_at_text.end_with?("Z") && expires_at.utc.iso8601 == expires_at_text
    fail_policy!("publication verification timestamp is not canonical UTC") unless verified_at.utc.iso8601 == expected.fetch(:verified_at)
    fail_policy!("approval validity window is invalid") unless expires_at > approved_at && (expires_at - approved_at) <= 86_400
    fail_policy!("publication approval is not currently valid") unless approved_at <= verified_at && verified_at <= expires_at
    fail_policy!("publication approval has insufficient time remaining") unless
      (expires_at - verified_at) >= MINIMUM_REMAINING_SECONDS

    true
  rescue ArgumentError
    raise PolicyError, "approval timestamp is invalid"
  end

  def run(argv)
    command = argv.shift
    fail_policy!("expected verify-approval") unless command == "verify-approval"

    options = {}
    parser = OptionParser.new do |value|
      value.banner = "Usage: publication_policy.rb verify-approval [options]"
      value.on("--json FILE") { |item| options[:json] = item }
      value.on("--repository NAME") { |item| options[:repository] = item }
      value.on("--tag TAG") { |item| options[:tag] = item }
      value.on("--commit SHA") { |item| options[:commit] = item }
      value.on("--release-id ID") { |item| options[:release_id] = item }
      value.on("--candidate-run-id ID") { |item| options[:candidate_run_id] = item }
      value.on("--candidate-artifact-id ID") { |item| options[:candidate_artifact_id] = item }
      value.on("--candidate-artifact-sha256 SHA") { |item| options[:candidate_artifact_sha256] = item }
      value.on("--candidate-inventory-sha256 SHA") { |item| options[:candidate_inventory_sha256] = item }
      value.on("--final-dmg-sha256 SHA") { |item| options[:final_dmg_sha256] = item }
      value.on("--remote-controls-observed-master SHA") { |item| options[:remote_controls_observed_master] = item }
      value.on("--remote-controls-manifest-sha256 SHA") { |item| options[:remote_controls_manifest_sha256] = item }
      value.on("--external-beta-set-sha256 SHA") { |item| options[:external_beta_set_sha256] = item }
      value.on("--external-beta-report-sha256 SHA") do |item|
        (options[:external_beta_report_sha256] ||= []) << item
      end
      value.on("--sonoma-beta-report-sha256 SHA") { |item| options[:sonoma_beta_report_sha256] = item }
      value.on("--final-dmg-provenance-sha256 SHA") { |item| options[:final_dmg_provenance_sha256] = item }
      value.on("--predecessor-lineage-sha256 SHA") { |item| options[:predecessor_lineage_sha256] = item }
      value.on("--release-manifest-sha256 SHA") { |item| options[:release_manifest_sha256] = item }
      value.on("--approval-sha256 SHA") { |item| options[:approval_sha256] = item }
      value.on("--approver-login LOGIN") { |item| options[:approver_login] = item }
      value.on("--publisher-login LOGIN") { |item| options[:publisher_login] = item }
      value.on("--approval-mode MODE") { |item| options[:approval_mode] = item }
      value.on("--verified-at TIME") { |item| options[:verified_at] = item }
    end
    parser.parse!(argv)
    fail_policy!("unexpected arguments") unless argv.empty?

    required = %i[json repository tag commit release_id candidate_run_id candidate_artifact_id candidate_artifact_sha256 candidate_inventory_sha256 final_dmg_sha256 remote_controls_observed_master remote_controls_manifest_sha256 external_beta_set_sha256 external_beta_report_sha256 sonoma_beta_report_sha256 final_dmg_provenance_sha256 predecessor_lineage_sha256 release_manifest_sha256 approval_sha256 approver_login publisher_login approval_mode verified_at]
    missing = required.reject { |name| options.key?(name) }
    fail_policy!("required approval inputs are missing") unless missing.empty?
    fail_policy!("release commit is invalid") unless COMMIT.match?(options.fetch(:commit))
    %i[release_id candidate_run_id candidate_artifact_id].each do |name|
      text = options.fetch(name)
      fail_policy!("numeric publication input is invalid") unless text.match?(/\A[1-9][0-9]*\z/)
      options[name] = Integer(text, 10)
    end
    exact_sha256(options.fetch(:candidate_artifact_sha256), "expected candidate artifact digest")
    exact_sha256(options.fetch(:candidate_inventory_sha256), "expected candidate inventory digest")
    exact_sha256(options.fetch(:final_dmg_sha256), "expected final DMG digest")
    fail_policy!("expected remote-controls observed master is invalid") unless
      COMMIT.match?(options.fetch(:remote_controls_observed_master))
    exact_sha256(options.fetch(:remote_controls_manifest_sha256), "expected remote-controls manifest digest")
    exact_sha256(options.fetch(:external_beta_set_sha256), "expected external beta set digest")
    beta_digests = options.fetch(:external_beta_report_sha256)
    fail_policy!("exactly three expected external beta report digests are required") unless beta_digests.length == 3
    beta_digests.each_with_index do |digest, index|
      exact_sha256(digest, "expected external beta report digest #{index + 1}")
    end
    exact_sha256(options.fetch(:sonoma_beta_report_sha256), "expected Sonoma beta report digest")
    exact_sha256(options.fetch(:final_dmg_provenance_sha256), "expected final DMG provenance digest")
    exact_sha256(options.fetch(:predecessor_lineage_sha256), "expected predecessor lineage digest")
    exact_sha256(options.fetch(:release_manifest_sha256), "expected release manifest digest")
    exact_sha256(options.fetch(:approval_sha256), "expected approval record digest")
    exact_string(options.fetch(:approver_login), "expected approver login")
    exact_string(options.fetch(:publisher_login), "expected publisher login")
    fail_policy!("expected approval mode is invalid") unless
      %w[independent-review one-maintainer].include?(options.fetch(:approval_mode))

    record, approval_sha256 = read_strict_json(options.fetch(:json))
    fail_policy!("approval record digest differs") unless approval_sha256 == options.fetch(:approval_sha256)
    verify!(record, options)
    puts "OK publication approval"
  end
end

begin
  DeskSetupPublicationPolicy.run(ARGV)
rescue DeskSetupPublicationPolicy::PolicyError => error
  warn "Publication policy error: #{error.message}"
  exit 1
rescue OptionParser::ParseError
  warn "Publication policy error: invalid command line."
  exit 1
rescue StandardError
  # Keep unexpected filesystem/runtime failures value-free. In particular,
  # never let an approval path or raw parser/runtime detail reach CI output.
  warn "Publication policy error: approval verification failed safely."
  exit 1
end
