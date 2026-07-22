#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "optparse"
require "time"
require_relative "release_policy"

module DeskSetupExternalBetaPolicy
  REPORT_SCHEMA = "desk-setup-switcher.external-beta/v2"
  SET_SCHEMA = "desk-setup-switcher.external-beta-set/v2"
  INVENTORY_SCHEMA = "desk-setup-switcher.candidate-inventory/v1"
  LINEAGE_SCHEMA = "desk-setup-switcher.predecessor-lineage/v3"
  REMOTE_BOUNDARY_SCHEMA = "desk-setup-switcher.remote-release-controls-evidence/v3"
  CURRENT_VERSION = "0.1.0"
  CURRENT_TAG = "v0.1.0"
  CURRENT_BUILD_NUMBER = 2
  PREDECESSOR_VERSION = "0.0.9"
  PREDECESSOR_TAG = "v0.0.9"
  PREDECESSOR_BUILD_NUMBER = 1
  REPORT_CODES = %w[beta-01 beta-02 beta-03].freeze
  COVERAGE_ROLES = %w[sonoma-full-lifecycle additional-apple-silicon].freeze
  REJECTED_PLACEHOLDER_PREFIX = "<REJECTED_TEMPLATE:REPLACE_REQUIRED:".freeze
  SHA256 = /\A[0-9a-f]{64}\z/
  COMMIT = /\A[0-9a-f]{40}\z/
  VERSION = /\A(?:0|[1-9][0-9]*)(?:\.(?:0|[1-9][0-9]*)){2}\z/
  REPOSITORY = /\A[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+\z/
  MAX_JSON_BYTES = 262_144
  MAX_MANIFEST_BYTES = 16 * 1024 * 1024
  MAX_PROVENANCE_BYTES = 16 * 1024 * 1024
  MAX_REMOTE_BOUNDARY_BYTES = 4 * 1024 * 1024
  MAX_DMG_BYTES = 2 * 1024 * 1024 * 1024

  class PolicyError < StandardError; end

  module_function

  def fail_policy!(message)
    raise PolicyError, message
  end

  def exact_object(value, label, keys)
    fail_policy!("#{label} is not an object") unless value.is_a?(Hash)
    fail_policy!("#{label} has an unexpected schema") unless value.keys.sort == keys.sort
    value
  end

  def exact_array(value, label, length: nil)
    fail_policy!("#{label} is not an array") unless value.is_a?(Array)
    fail_policy!("#{label} has an unexpected length") if length && value.length != length
    value
  end

  def exact_string(value, label)
    unless value.is_a?(String) && !value.empty? && value.valid_encoding? &&
           !value.match?(/[\0\r\n]/)
      fail_policy!("#{label} is not a single-line string")
    end
    value
  end

  def exact_sha256(value, label)
    value = exact_string(value, label)
    fail_policy!("#{label} is not a lowercase SHA-256 digest") unless SHA256.match?(value)
    value
  end

  def exact_commit(value, label)
    value = exact_string(value, label)
    fail_policy!("#{label} is not a lowercase commit digest") unless COMMIT.match?(value)
    value
  end

  def exact_positive_integer(value, label)
    fail_policy!("#{label} is not a positive integer") unless value.is_a?(Integer) && value.positive?
    value
  end

  def exact_nonnegative_integer(value, label)
    fail_policy!("#{label} is not a nonnegative integer") unless value.is_a?(Integer) && value >= 0
    value
  end

  def parse_positive_integer(value, label)
    fail_policy!("#{label} is not a canonical positive integer") unless
      value.is_a?(String) && value.match?(/\A[1-9][0-9]*\z/)
    Integer(value, 10)
  end

  def exact_true(value, label)
    fail_policy!("#{label} is not true") unless value == true
    true
  end

  def exact_false(value, label)
    fail_policy!("#{label} is not false") unless value == false
    false
  end

  def exact_json_equal?(actual, expected)
    case expected
    when Hash
      return false unless actual.is_a?(Hash)

      actual.keys.sort == expected.keys.sort && expected.all? do |key, value|
        exact_json_equal?(actual.fetch(key), value)
      end
    when Array
      return false unless actual.is_a?(Array)

      actual.length == expected.length && actual.each_index.all? do |index|
        exact_json_equal?(actual.fetch(index), expected.fetch(index))
      end
    else
      actual.class == expected.class && actual == expected
    end
  end

  def exact_version(value, label)
    value = exact_string(value, label)
    fail_policy!("#{label} is not a canonical three-component version") unless VERSION.match?(value)
    value
  end

  def exact_timestamp(value, label)
    text = exact_string(value, label)
    time = Time.iso8601(text)
    fail_policy!("#{label} is not canonical UTC") unless text.end_with?("Z") && time.utc.iso8601 == text
    time
  rescue ArgumentError
    raise PolicyError, "#{label} is not a valid timestamp"
  end

  def exact_artifact_name(value, label, suffix: nil)
    value = exact_string(value, label)
    fail_policy!("#{label} is not a safe basename") unless
      File.basename(value) == value && !value.include?("\\") &&
      value.match?(/\A[A-Za-z0-9][A-Za-z0-9._+() -]*\z/)
    fail_policy!("#{label} has an unexpected suffix") if suffix && !value.end_with?(suffix)
    value
  end

  def descriptor_identity(stat)
    [stat.dev, stat.ino, stat.mode, stat.nlink, stat.size, stat.mtime.to_r, stat.ctime.to_r]
  end

  def read_exact_bytes(path, label, max_bytes:)
    path_stat = File.lstat(path)
    fail_policy!("#{label} is not a regular file") unless path_stat.file? && !path_stat.symlink?
    flags = File::RDONLY
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    bytes = nil
    opened_identity = nil
    File.open(path, flags) do |file|
      before = file.stat
      fail_policy!("#{label} descriptor is not a regular file") unless before.file?
      fail_policy!("#{label} has an unsafe link count") unless before.nlink == 1
      fail_policy!("#{label} path identity differs") unless
        [before.dev, before.ino] == [path_stat.dev, path_stat.ino]
      fail_policy!("#{label} is empty or too large") unless before.size.positive? && before.size <= max_bytes
      before_identity = descriptor_identity(before)
      bytes = file.read(max_bytes + 1)
      after = file.stat
      opened_identity = descriptor_identity(after)
      fail_policy!("#{label} changed during descriptor-bound read") unless opened_identity == before_identity
      fail_policy!("#{label} changed size during read") unless bytes.bytesize == before.size
    end
    after_path = File.lstat(path)
    fail_policy!("#{label} path changed during read") unless descriptor_identity(after_path) == opened_identity
    [bytes, Digest::SHA256.hexdigest(bytes)]
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP
    raise PolicyError, "#{label} is unavailable or invalid"
  end

  def read_exact_identity(path, label, max_bytes:)
    path_stat = File.lstat(path)
    fail_policy!("#{label} is not a regular file") unless path_stat.file? && !path_stat.symlink?
    flags = File::RDONLY
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    identity = nil
    opened_identity = nil
    File.open(path, flags) do |file|
      before = file.stat
      fail_policy!("#{label} descriptor is not a regular file") unless before.file?
      fail_policy!("#{label} has an unsafe link count") unless before.nlink == 1
      fail_policy!("#{label} path identity differs") unless
        [before.dev, before.ino] == [path_stat.dev, path_stat.ino]
      fail_policy!("#{label} is empty or too large") unless before.size.positive? && before.size <= max_bytes
      before_identity = descriptor_identity(before)
      digest = Digest::SHA256.new
      size = 0
      while (chunk = file.read(1024 * 1024))
        digest.update(chunk)
        size += chunk.bytesize
      end
      opened_identity = descriptor_identity(file.stat)
      fail_policy!("#{label} changed during descriptor-bound read") unless opened_identity == before_identity
      fail_policy!("#{label} changed size during read") unless size == before.size
      identity = { "sha256" => digest.hexdigest, "size" => size }
    end
    after_path = File.lstat(path)
    fail_policy!("#{label} path changed during read") unless descriptor_identity(after_path) == opened_identity
    identity
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP
    raise PolicyError, "#{label} is unavailable or invalid"
  end

  def read_strict_json(path, label, max_bytes: MAX_JSON_BYTES)
    bytes, digest = read_exact_bytes(path, label, max_bytes: max_bytes)
    text = bytes.dup.force_encoding(Encoding::UTF_8)
    fail_policy!("#{label} is not UTF-8") unless text.valid_encoding?
    fail_policy!("#{label} contains a null byte") if text.include?("\0")
    value = ReleasePolicy.parse_strict_json(text, label, max_nesting: 32)
    fail_policy!("#{label} contains rejected template placeholders") if rejected_placeholder?(value)
    [value, digest]
  rescue ReleasePolicy::PolicyError => error
    raise PolicyError, error.message
  end

  def rejected_placeholder?(value)
    case value
    when Hash
      value.any? { |key, item| rejected_placeholder?(key) || rejected_placeholder?(item) }
    when Array
      value.any? { |item| rejected_placeholder?(item) }
    when String
      value.start_with?(REJECTED_PLACEHOLDER_PREFIX)
    else
      false
    end
  end

  def validate_inventory_item(item)
    fail_policy!("candidate inventory item is not an object") unless item.is_a?(Hash)
    common = %w[
      outcome version buildNumber commit candidateOriginRunId
      candidateOriginRunAttempt runConclusion completedAt distributionState
    ]
    outcome = item["outcome"]
    case outcome
    when "retained"
      exact_object(
        item,
        "retained candidate inventory item",
        common + %w[candidateArtifactId candidateArtifactSHA256 finalDMGSHA256 releaseManifestSHA256]
      )
    when "not-retained"
      exact_object(item, "not-retained candidate inventory item", common + %w[reason])
    else
      fail_policy!("candidate inventory outcome is invalid")
    end

    exact_version(item["version"], "candidate inventory version")
    exact_positive_integer(item["buildNumber"], "candidate inventory build")
    exact_commit(item["commit"], "candidate inventory commit")
    exact_positive_integer(item["candidateOriginRunId"], "candidate inventory run ID")
    fail_policy!("candidate inventory origin attempt differs") unless
      item["candidateOriginRunAttempt"].is_a?(Integer) && item["candidateOriginRunAttempt"] == 1
    completed_at = exact_timestamp(item["completedAt"], "candidate inventory completion time")
    conclusion = exact_string(item["runConclusion"], "candidate inventory run conclusion")
    allowed_conclusions = %w[
      success failure cancelled timed_out action_required neutral skipped stale startup_failure
    ]
    fail_policy!("candidate inventory run conclusion is invalid") unless allowed_conclusions.include?(conclusion)

    distribution_state = exact_string(item["distributionState"], "candidate inventory distribution state")
    if outcome == "retained"
      fail_policy!("retained candidate did not complete successfully") unless conclusion == "success"
      exact_positive_integer(item["candidateArtifactId"], "candidate inventory artifact ID")
      %w[candidateArtifactSHA256 finalDMGSHA256 releaseManifestSHA256].each do |name|
        exact_sha256(item[name], "candidate inventory #{name}")
      end
      allowed_distribution = %w[not-distributed development-installed protected-beta published]
      fail_policy!("retained candidate distribution state is invalid") unless
        allowed_distribution.include?(distribution_state)
    else
      fail_policy!("a non-retained candidate was distributed") unless distribution_state == "not-distributed"
      reason = exact_string(item["reason"], "candidate inventory non-retention reason")
      allowed_reasons = %w[build-failed run-cancelled artifact-not-retained candidate-abandoned]
      fail_policy!("candidate inventory non-retention reason is invalid") unless allowed_reasons.include?(reason)
      if conclusion == "success"
        fail_policy!("successful non-retained candidate reason is invalid") unless
          %w[artifact-not-retained candidate-abandoned].include?(reason)
      elsif reason == "artifact-not-retained"
        fail_policy!("failed candidate cannot claim a missing retained artifact")
      end
    end
    { data: item, completed_at: completed_at, retained: outcome == "retained" }
  end

  def validate_inventory(inventory, expected, manifest_created_at)
    inventory = exact_object(
      inventory,
      "candidate inventory",
      %w[schemaVersion subject collection items]
    )
    fail_policy!("candidate inventory schema differs") unless inventory["schemaVersion"] == INVENTORY_SCHEMA
    candidate = expected.fetch(:candidate)
    expected_subject = {
      "repository" => candidate.fetch("repository"),
      "workflowPath" => ".github/workflows/signed-release-candidate.yml",
      "operation" => "build-candidate",
      "currentCandidateRunId" => candidate.fetch("candidateOriginRunId"),
      "currentCandidateBuildNumber" => candidate.fetch("buildNumber")
    }
    subject = exact_object(inventory["subject"], "candidate inventory subject", expected_subject.keys)
    fail_policy!("candidate inventory subject differs") unless exact_json_equal?(subject, expected_subject)

    collection = exact_object(
      inventory["collection"],
      "candidate inventory collection",
      %w[collectedAt reviewedAt reviewMode reviewerRole allPagesReviewed sourceEvidenceSHA256]
    )
    collected_at = exact_timestamp(collection["collectedAt"], "candidate inventory collection time")
    reviewed_at = exact_timestamp(collection["reviewedAt"], "candidate inventory review time")
    fail_policy!("candidate inventory predates the candidate") if collected_at < manifest_created_at
    fail_policy!("candidate inventory review predates collection") if reviewed_at < collected_at
    fail_policy!("candidate inventory review mode differs") unless
      collection["reviewMode"] == "protected-complete-history-review"
    fail_policy!("candidate inventory reviewer role differs") unless
      collection["reviewerRole"] == "release-approver"
    exact_true(collection["allPagesReviewed"], "candidate inventory completeness review")
    exact_sha256(collection["sourceEvidenceSHA256"], "candidate inventory source evidence digest")

    items = exact_array(inventory["items"], "candidate inventory items").map do |item|
      validate_inventory_item(item)
    end
    fail_policy!("candidate inventory contains an item that is not historical") unless
      items.all? { |item| item.fetch(:completed_at) < manifest_created_at }
    fail_policy!("candidate inventory contains an item after collection") unless
      items.all? { |item| item.fetch(:completed_at) <= collected_at }
    builds = items.map { |item| item.dig(:data, "buildNumber") }
    fail_policy!("candidate inventory is not strictly build-sorted") unless
      builds == builds.sort && builds.uniq == builds
    current_build = candidate.fetch("buildNumber")
    fail_policy!("current candidate version differs from the fixed public beta") unless
      candidate.fetch("version") == CURRENT_VERSION && candidate.fetch("tag") == CURRENT_TAG
    fail_policy!("current candidate build differs from the fixed public beta") unless
      current_build == CURRENT_BUILD_NUMBER
    fail_policy!("candidate inventory reuses or exceeds the current build") unless
      builds.all? { |build| build < current_build }
    run_ids = items.map { |item| item.dig(:data, "candidateOriginRunId") } +
      [candidate.fetch("candidateOriginRunId")]
    fail_policy!("candidate inventory reuses an origin run") unless run_ids.uniq.length == run_ids.length

    retained = items.select { |item| item.fetch(:retained) }
    unique_identity_fields = %w[
      candidateArtifactId candidateArtifactSHA256 finalDMGSHA256 releaseManifestSHA256
    ]
    unique_identity_fields.each do |name|
      identities = retained.map { |item| item.dig(:data, name) } + [candidate.fetch(name)]
      fail_policy!("candidate inventory reuses candidate identity") unless identities.uniq.length == identities.length
    end
    installable = retained.map { |item| item.fetch(:data) }.reject do |item|
      item.fetch("distributionState") == "not-distributed"
    end
    fail_policy!("the fixed public beta requires exactly one installable predecessor") unless
      installable.length == 1
    predecessor = installable.first
    fail_policy!("the fixed predecessor identity differs") unless
      predecessor.fetch("version") == PREDECESSOR_VERSION &&
      predecessor.fetch("buildNumber") == PREDECESSOR_BUILD_NUMBER &&
      predecessor.fetch("distributionState") == "protected-beta"
    {
      inventory: inventory,
      items: items,
      retained: retained,
      predecessor: predecessor,
      predecessor_completed_at: items.find do |item|
        item.fetch(:data).equal?(predecessor)
      end.fetch(:completed_at),
      reviewed_at: reviewed_at,
      current_build: current_build
    }
  end

  def validate_lineage(lineage, expected, inventory_result, inventory_sha256)
    lineage = exact_object(
      lineage,
      "predecessor lineage",
      %w[schemaVersion candidate candidateInventorySHA256 upgradePredecessor]
    )
    fail_policy!("predecessor lineage schema differs") unless lineage["schemaVersion"] == LINEAGE_SCHEMA

    candidate = exact_object(lineage["candidate"], "lineage candidate", expected.fetch(:candidate).keys)
    fail_policy!("lineage candidate differs from the restored candidate") unless
      exact_json_equal?(candidate, expected.fetch(:candidate))
    exact_sha256(lineage["candidateInventorySHA256"], "lineage candidate inventory digest")
    fail_policy!("lineage candidate inventory digest differs") unless
      lineage["candidateInventorySHA256"] == inventory_sha256

    upgrade = exact_object(
      lineage["upgradePredecessor"],
      "recorded upgrade predecessor",
      %w[
        state distributionKind bundleIdentifier version tag buildNumber profileSchemaVersion
        sourceCommit candidateOriginRunId candidateOriginRunAttempt candidateArtifactId
        candidateArtifactSHA256 artifactName finalDMGSHA256 releaseManifestSHA256
        provenanceBundleName provenanceBundleSHA256 provenanceSubjectSHA256
        releaseBoundaryEvidenceSHA256
      ]
    )
    fail_policy!("upgrade predecessor state differs") unless upgrade["state"] == "recorded"
    fail_policy!("upgrade predecessor distribution kind differs") unless
      upgrade["distributionKind"] == "protected-beta"
    fail_policy!("upgrade predecessor bundle identifier differs") unless
      upgrade["bundleIdentifier"] == expected.dig(:candidate, "bundleIdentifier")
    exact_version(upgrade["version"], "upgrade predecessor version")
    fail_policy!("upgrade predecessor version or tag differs") unless
      upgrade["version"] == PREDECESSOR_VERSION && upgrade["tag"] == PREDECESSOR_TAG
    predecessor_build = exact_positive_integer(upgrade["buildNumber"], "upgrade predecessor build")
    fail_policy!("upgrade predecessor build differs") unless predecessor_build == PREDECESSOR_BUILD_NUMBER
    exact_nonnegative_integer(upgrade["profileSchemaVersion"], "upgrade predecessor profile schema")
    exact_commit(upgrade["sourceCommit"], "upgrade predecessor source commit")
    exact_positive_integer(upgrade["candidateOriginRunId"], "upgrade predecessor run ID")
    fail_policy!("upgrade predecessor origin attempt differs") unless
      upgrade["candidateOriginRunAttempt"].is_a?(Integer) &&
      upgrade["candidateOriginRunAttempt"] == 1
    exact_positive_integer(upgrade["candidateArtifactId"], "upgrade predecessor artifact ID")
    artifact_name = exact_artifact_name(
      upgrade["artifactName"],
      "upgrade predecessor artifact",
      suffix: ".dmg"
    )
    fail_policy!("upgrade predecessor artifact name differs") unless
      artifact_name == "Desk-Setup-Switcher-#{PREDECESSOR_VERSION}.dmg"
    provenance_name = exact_artifact_name(
      upgrade["provenanceBundleName"],
      "upgrade predecessor provenance bundle",
      suffix: ".provenance.sigstore.json"
    )
    fail_policy!("upgrade predecessor provenance bundle name differs") unless
      provenance_name == "Desk-Setup-Switcher-#{PREDECESSOR_VERSION}.provenance.sigstore.json"
    %w[
      candidateArtifactSHA256 finalDMGSHA256 releaseManifestSHA256
      provenanceBundleSHA256 provenanceSubjectSHA256 releaseBoundaryEvidenceSHA256
    ].each do |name|
      exact_sha256(upgrade[name], "upgrade predecessor #{name}")
    end
    fail_policy!("upgrade predecessor provenance subject differs") unless
      upgrade["provenanceSubjectSHA256"] == upgrade["finalDMGSHA256"]

    predecessor = inventory_result.fetch(:predecessor)
    expected_inventory_fields = {
      "version" => "version",
      "buildNumber" => "buildNumber",
      "sourceCommit" => "commit",
      "candidateOriginRunId" => "candidateOriginRunId",
      "candidateOriginRunAttempt" => "candidateOriginRunAttempt",
      "candidateArtifactId" => "candidateArtifactId",
      "candidateArtifactSHA256" => "candidateArtifactSHA256",
      "finalDMGSHA256" => "finalDMGSHA256",
      "releaseManifestSHA256" => "releaseManifestSHA256"
    }
    fail_policy!("upgrade predecessor differs from the retained inventory item") unless
      expected_inventory_fields.all? do |lineage_name, inventory_name|
        upgrade.fetch(lineage_name) == predecessor.fetch(inventory_name)
      end

    {
      lineage: lineage,
      observed_at: inventory_result.fetch(:reviewed_at),
      upgrade: upgrade
    }
  end

  def validate_release_boundary(path, upgrade, expected_tag_object, expected_pre_tag_digest)
    boundary, digest = read_strict_json(
      path,
      "predecessor release boundary",
      max_bytes: MAX_REMOTE_BOUNDARY_BYTES
    )
    exact_object(
      boundary,
      "predecessor release boundary",
      %w[
        actions anchorReads authenticatedViewer candidateWorkflow ci ciWorkflow collectedAt
        environments finalPreTagEvidenceSHA256 labels legacyWorkflow manualEvidence phase
        predecessorPreTagEvidenceSHA256 publicationWorkflow releaseBoundary repository
        repositoryConfiguration rulesets schemaVersion security workflowInventory
      ]
    )
    fail_policy!("predecessor release boundary schema differs") unless
      boundary["schemaVersion"] == REMOTE_BOUNDARY_SCHEMA
    fail_policy!("predecessor release boundary phase differs") unless boundary["phase"] == "final-pre-tag"
    fail_policy!("predecessor release boundary has an unexpected final-pre-tag digest") unless
      boundary["finalPreTagEvidenceSHA256"].nil?
    fail_policy!("predecessor pre-tag evidence digest differs") unless
      boundary["predecessorPreTagEvidenceSHA256"] == expected_pre_tag_digest
    collected_at = exact_timestamp(boundary["collectedAt"], "predecessor release boundary collection time")
    release_boundary = exact_object(
      boundary["releaseBoundary"],
      "predecessor release boundary state",
      %w[releases vRefs]
    )
    refs = exact_object(
      release_boundary["vRefs"],
      "predecessor release boundary tag references",
      %w[complete items]
    )
    exact_true(refs["complete"], "predecessor release boundary tag completeness")
    ref = exact_array(refs["items"], "predecessor release boundary tag references", length: 1).first
    exact_object(ref, "predecessor release boundary tag reference", %w[commitSha objectSha objectType ref])
    exact_commit(ref["commitSha"], "predecessor release boundary peeled commit")
    exact_commit(ref["objectSha"], "predecessor release boundary tag object")
    fail_policy!("predecessor release boundary tag differs") unless ref == {
      "ref" => "refs/tags/#{PREDECESSOR_TAG}",
      "objectType" => "tag",
      "objectSha" => expected_tag_object,
      "commitSha" => upgrade.fetch("sourceCommit")
    }
    releases = exact_object(
      release_boundary["releases"],
      "predecessor GitHub Releases",
      %w[complete items]
    )
    exact_true(releases["complete"], "predecessor GitHub Release completeness")
    fail_policy!("a predecessor GitHub Release exists") unless
      exact_array(releases["items"], "predecessor GitHub Releases").empty?
    fail_policy!("predecessor release boundary digest differs") unless
      digest == upgrade.fetch("releaseBoundaryEvidenceSHA256")
    { digest: digest, collected_at: collected_at }
  end

  def validate_predecessor_materials(options, expected, inventory_result, lineage_result,
                                     boundary_result, current_manifest_created_at)
    manifest, manifest_sha256 = read_strict_json(
      options.fetch(:predecessor_release_manifest),
      "predecessor release manifest",
      max_bytes: MAX_MANIFEST_BYTES
    )
    begin
      ReleasePolicy.validate_release_manifest_data(manifest)
    rescue ReleasePolicy::PolicyError
      raise PolicyError, "predecessor release manifest is invalid"
    end
    upgrade = lineage_result.fetch(:upgrade)
    predecessor = inventory_result.fetch(:predecessor)
    fail_policy!("predecessor release manifest digest differs") unless
      manifest_sha256 == upgrade.fetch("releaseManifestSHA256") &&
      manifest_sha256 == predecessor.fetch("releaseManifestSHA256")

    release = manifest.fetch("release")
    repository = expected.dig(:candidate, "repository")
    expected_namespace =
      "https://github.com/#{repository}/release-evidence/#{PREDECESSOR_TAG}/#{upgrade.fetch('finalDMGSHA256')}"
    expected_run_url =
      "https://github.com/#{repository}/actions/runs/#{upgrade.fetch('candidateOriginRunId')}"
    fail_policy!("predecessor release manifest identity differs") unless
      release.fetch("version") == PREDECESSOR_VERSION &&
      release.fetch("tag") == PREDECESSOR_TAG &&
      release.fetch("commit") == upgrade.fetch("sourceCommit") &&
      release.fetch("buildNumber") == PREDECESSOR_BUILD_NUMBER.to_s &&
      release.fetch("namespace") == expected_namespace &&
      release.dig("run", "id") == upgrade.fetch("candidateOriginRunId") &&
      release.dig("run", "attempt") == 1 &&
      release.dig("run", "url") == expected_run_url
    fail_policy!("predecessor application bundle identifier differs") unless
      manifest.dig("application", "bundleIdentifier") == upgrade.fetch("bundleIdentifier")

    final_dmg = manifest.dig("lineage", "finalStapledDmg")
    fail_policy!("predecessor manifest final DMG differs") unless
      final_dmg.fetch("name") == upgrade.fetch("artifactName") &&
      final_dmg.fetch("sha256") == upgrade.fetch("finalDMGSHA256")
    dmg_identity = read_exact_identity(
      options.fetch(:predecessor_dmg),
      "predecessor final DMG",
      max_bytes: MAX_DMG_BYTES
    )
    fail_policy!("predecessor final DMG path name differs") unless
      File.basename(options.fetch(:predecessor_dmg)) == upgrade.fetch("artifactName")
    fail_policy!("predecessor final DMG bytes differ") unless
      dmg_identity["sha256"] == final_dmg.fetch("sha256") &&
      dmg_identity["size"] == final_dmg.fetch("size")

    provenance_identity = read_exact_identity(
      options.fetch(:predecessor_provenance_bundle),
      "predecessor final DMG provenance bundle",
      max_bytes: MAX_PROVENANCE_BYTES
    )
    fail_policy!("predecessor provenance bundle path name differs") unless
      File.basename(options.fetch(:predecessor_provenance_bundle)) == upgrade.fetch("provenanceBundleName")
    fail_policy!("predecessor provenance bundle bytes differ") unless
      provenance_identity["sha256"] == upgrade.fetch("provenanceBundleSHA256")
    fail_policy!("predecessor provenance subject differs") unless
      upgrade.fetch("provenanceSubjectSHA256") == dmg_identity["sha256"]

    predecessor_created_at = exact_timestamp(release.fetch("created"), "predecessor manifest creation time")
    boundary_time = boundary_result.fetch(:collected_at)
    fail_policy!("predecessor release boundary predates predecessor evidence") unless
      inventory_result.fetch(:predecessor_completed_at) <= boundary_time &&
      predecessor_created_at <= boundary_time
    fail_policy!("predecessor release boundary does not precede the final candidate") unless
      boundary_time < current_manifest_created_at
    {
      release_manifest_sha256: manifest_sha256,
      final_dmg_sha256: dmg_identity.fetch("sha256"),
      provenance_sha256: provenance_identity.fetch("sha256"),
      boundary_sha256: boundary_result.fetch(:digest)
    }
  end

  def validate_acquisition(acquisition, label)
    acquisition = exact_object(
      acquisition,
      label,
      %w[channel browserDownloaded normalArchiveExtraction quarantinePresent quarantineManufactured quarantineRemoved quarantineEvidenceSHA256 checksumPass provenancePass gatekeeperPass openAnywayUsed]
    )
    fail_policy!("#{label} channel differs") unless acquisition["channel"] == "protected-workflow-browser"
    %w[browserDownloaded normalArchiveExtraction quarantinePresent checksumPass provenancePass gatekeeperPass].each do |name|
      exact_true(acquisition[name], "#{label} #{name}")
    end
    %w[quarantineManufactured quarantineRemoved openAnywayUsed].each do |name|
      exact_false(acquisition[name], "#{label} #{name}")
    end
    exact_sha256(acquisition["quarantineEvidenceSHA256"], "#{label} quarantine evidence digest")
    acquisition
  end

  def validate_environment(environment)
    environment = exact_object(
      environment,
      "beta environment",
      %w[architecture macOSVersion hardwareClass cleanBasis coverageRole]
    )
    fail_policy!("beta architecture is unsupported") unless environment["architecture"] == "arm64"
    fail_policy!("beta hardware class is unsupported") unless environment["hardwareClass"] == "apple-silicon"
    unless %w[clean-local-account clean-mac].include?(environment["cleanBasis"])
      fail_policy!("beta clean basis is invalid")
    end
    version = exact_string(environment["macOSVersion"], "beta macOS version")
    match = version.match(/\A(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:\.(0|[1-9][0-9]*))?\z/)
    fail_policy!("beta macOS version is invalid") unless match
    major = Integer(match[1], 10)
    fail_policy!("beta macOS version is unsupported") if major < 14
    role = environment["coverageRole"]
    unless %w[sonoma-full-lifecycle additional-apple-silicon].include?(role)
      fail_policy!("beta coverage role is invalid")
    end
    fail_policy!("Sonoma coverage role is not macOS 14") if role == "sonoma-full-lifecycle" && major != 14
    [major, role]
  end

  def validate_report(report, expected, lineage_result, digest)
    report = exact_object(
      report,
      "external beta report",
      %w[schemaVersion report subject environment independence acquisition lifecycle issues attestation]
    )
    fail_policy!("external beta report schema differs") unless report["schemaVersion"] == REPORT_SCHEMA
    identity = exact_object(report["report"], "beta report identity", %w[reportCode startedAt completedAt])
    code = exact_string(identity["reportCode"], "beta report code")
    started_at = exact_timestamp(identity["startedAt"], "beta report start")
    completed_at = exact_timestamp(identity["completedAt"], "beta report completion")
    fail_policy!("beta report completion predates its start") if completed_at < started_at
    fail_policy!("beta report predates the candidate inventory") if started_at < lineage_result.fetch(:observed_at)

    subject = exact_object(report["subject"], "beta report subject", expected.fetch(:report_subject).keys)
    fail_policy!("beta report subject differs from the restored candidate") unless
      exact_json_equal?(subject, expected.fetch(:report_subject))
    major, role = validate_environment(report["environment"])

    independence = exact_object(
      report["independence"],
      "beta independence",
      %w[externalTester notReleaseOperator notReleaseApprover noRepositoryWriteAccess noReleaseSecretAccess]
    )
    independence.each { |name, value| exact_true(value, "beta independence #{name}") }

    validate_acquisition(report["acquisition"], "beta acquisition")

    lifecycle = exact_object(
      report["lifecycle"],
      "beta lifecycle",
      %w[firstLaunchPass loginItemDefaultOffPass threeStepFlowPass stoppedBeforeApply schema0MigrationPass backupRecoveryPass importExportPass diagnosticsPass uninstallPass localDataRemovalPass hardwareMutationPerformed upgrade]
    )
    %w[firstLaunchPass loginItemDefaultOffPass threeStepFlowPass stoppedBeforeApply schema0MigrationPass backupRecoveryPass importExportPass diagnosticsPass uninstallPass localDataRemovalPass].each do |name|
      exact_true(lifecycle[name], "beta lifecycle #{name}")
    end
    exact_false(lifecycle["hardwareMutationPerformed"], "beta lifecycle hardware mutation")
    upgrade = lifecycle["upgrade"]
    lineage_upgrade = lineage_result.fetch(:upgrade)
    exact_object(
      upgrade,
      "beta upgrade result",
      %w[
        state predecessorVersion predecessorBuildNumber predecessorFinalDMGSHA256
        predecessorReleaseManifestSHA256 predecessorProvenanceBundleSHA256
        predecessorAcquisition profilesPreserved settingsPreserved selectionPreserved
        backupsPreserved loginItemConsentPreserved
      ]
    )
    fail_policy!("beta upgrade did not pass") unless upgrade["state"] == "passed"
    exact_version(upgrade["predecessorVersion"], "beta upgrade predecessor version")
    exact_positive_integer(upgrade["predecessorBuildNumber"], "beta upgrade predecessor build")
    %w[
      predecessorFinalDMGSHA256 predecessorReleaseManifestSHA256
      predecessorProvenanceBundleSHA256
    ].each do |name|
      exact_sha256(upgrade[name], "beta upgrade #{name}")
    end
    fail_policy!("beta upgrade predecessor identity differs") unless
      upgrade["predecessorVersion"] == lineage_upgrade["version"] &&
      upgrade["predecessorBuildNumber"] == lineage_upgrade["buildNumber"] &&
      upgrade["predecessorFinalDMGSHA256"] == lineage_upgrade["finalDMGSHA256"] &&
      upgrade["predecessorReleaseManifestSHA256"] == lineage_upgrade["releaseManifestSHA256"] &&
      upgrade["predecessorProvenanceBundleSHA256"] == lineage_upgrade["provenanceBundleSHA256"]
    validate_acquisition(upgrade["predecessorAcquisition"], "beta predecessor acquisition")
    %w[profilesPreserved settingsPreserved selectionPreserved backupsPreserved loginItemConsentPreserved].each do |name|
      exact_true(upgrade[name], "beta upgrade #{name}")
    end

    issues = exact_object(
      report["issues"],
      "beta issues",
      %w[unresolvedP0 unresolvedP1 allFailuresTracked blockerEvidenceSHA256]
    )
    fail_policy!("beta report has an unresolved P0") unless
      issues["unresolvedP0"].is_a?(Integer) && issues["unresolvedP0"].zero?
    fail_policy!("beta report has an unresolved P1") unless
      issues["unresolvedP1"].is_a?(Integer) && issues["unresolvedP1"].zero?
    exact_true(issues["allFailuresTracked"], "beta issue tracking")
    exact_sha256(issues["blockerEvidenceSHA256"], "beta blocker evidence digest")

    attestation = exact_object(
      report["attestation"],
      "beta attestation",
      %w[candidateIdentityConfirmed privacyReviewed reportComplete testerAttested noHardwareMutationClaim]
    )
    attestation.each { |name, value| exact_true(value, "beta attestation #{name}") }

    {
      code: code,
      digest: digest,
      subject: subject,
      started_at: started_at,
      completed_at: completed_at,
      major: major,
      role: role
    }
  end

  def validate_set(set, expected, reports)
    set = exact_object(
      set,
      "external beta set",
      %w[schemaVersion subject reports independence coverage createdAt]
    )
    fail_policy!("external beta set schema differs") unless set["schemaVersion"] == SET_SCHEMA
    subject = exact_object(set["subject"], "external beta set subject", expected.fetch(:report_subject).keys)
    fail_policy!("external beta set subject differs") unless
      exact_json_equal?(subject, expected.fetch(:report_subject))

    report_entries = exact_array(set["reports"], "external beta set reports", length: 3)
    report_entries.each_with_index do |entry, index|
      entry = exact_object(entry, "external beta set report", %w[reportCode reportSHA256])
      exact_sha256(entry["reportSHA256"], "external beta set report digest")
      fail_policy!("external beta set report binding differs") unless
        entry == {
          "reportCode" => reports.fetch(index).fetch(:code),
          "reportSHA256" => reports.fetch(index).fetch(:digest)
        }
    end

    independence = exact_object(
      set["independence"],
      "external beta independence review",
      %w[reviewMode reviewerRole reviewedAt protectedReviewEvidenceSHA256 privateRosterBundleSHA256 bindings assertions]
    )
    fail_policy!("external beta review mode differs") unless independence["reviewMode"] == "protected-release-review"
    fail_policy!("external beta reviewer role differs") unless independence["reviewerRole"] == "release-approver"
    reviewed_at = exact_timestamp(independence["reviewedAt"], "external beta review time")
    fail_policy!("external beta review predates a report") unless
      reports.all? { |report| report.fetch(:completed_at) <= reviewed_at }
    exact_sha256(independence["protectedReviewEvidenceSHA256"], "protected beta review digest")
    exact_sha256(independence["privateRosterBundleSHA256"], "private roster bundle digest")
    bindings = exact_array(independence["bindings"], "external beta roster bindings", length: 3)
    commitments = bindings.each_with_index.map do |binding, index|
      binding = exact_object(
        binding,
        "external beta roster binding",
        %w[reportCode reportSHA256 privateRosterEntryCommitmentSHA256]
      )
      exact_sha256(binding["privateRosterEntryCommitmentSHA256"], "private roster commitment")
      fail_policy!("external beta roster report binding differs") unless
        binding["reportCode"] == reports.fetch(index).fetch(:code) &&
        binding["reportSHA256"] == reports.fetch(index).fetch(:digest)
      binding["privateRosterEntryCommitmentSHA256"]
    end
    fail_policy!("private roster commitments are not unique") unless commitments.uniq.length == commitments.length
    assertions = exact_object(
      independence["assertions"],
      "external beta independence assertions",
      %w[threeDistinctNaturalPersons allExternalToReleaseTeam noneIsReleaseOperator noneIsReleaseApprover noneHasPushReleaseEnvironmentOrSecretAccess]
    )
    assertions.each { |name, value| exact_true(value, "external beta independence assertion #{name}") }

    coverage = exact_object(
      set["coverage"],
      "external beta coverage",
      %w[acceptedReportCount sonomaGateReportCode allAppleSilicon allSupportedOS allMandatoryLifecyclePassed]
    )
    fail_policy!("external beta accepted report count differs") unless
      coverage["acceptedReportCount"].is_a?(Integer) && coverage["acceptedReportCount"] == 3
    %w[allAppleSilicon allSupportedOS allMandatoryLifecyclePassed].each do |name|
      exact_true(coverage[name], "external beta coverage #{name}")
    end
    sonoma_code = exact_string(coverage["sonomaGateReportCode"], "Sonoma gate report code")
    sonoma_report = reports.find { |report| report.fetch(:code) == sonoma_code }
    fail_policy!("Sonoma gate report is missing") unless sonoma_report
    fail_policy!("Sonoma gate report is not a full macOS 14 lifecycle") unless
      sonoma_report.fetch(:major) == 14 && sonoma_report.fetch(:role) == "sonoma-full-lifecycle"
    fail_policy!("the beta set has no Sonoma lifecycle report") unless
      reports.any? { |report| report.fetch(:major) == 14 && report.fetch(:role) == "sonoma-full-lifecycle" }

    created_at = exact_timestamp(set["createdAt"], "external beta set creation time")
    fail_policy!("external beta set predates its review") if created_at < reviewed_at
    { sonoma_code: sonoma_code, reviewed_at: reviewed_at, created_at: created_at }
  end

  def verify!(options)
    manifest, manifest_sha256 = read_strict_json(
      options.fetch(:release_manifest),
      "release manifest",
      max_bytes: MAX_MANIFEST_BYTES
    )
    begin
      ReleasePolicy.validate_release_manifest_data(manifest)
    rescue ReleasePolicy::PolicyError
      raise PolicyError, "release manifest is invalid"
    end
    provenance_bytes, provenance_sha256 = read_exact_bytes(
      options.fetch(:provenance_bundle),
      "final DMG provenance bundle",
      max_bytes: MAX_PROVENANCE_BYTES
    )
    fail_policy!("final DMG provenance bundle is empty") if provenance_bytes.empty?
    current_dmg_identity = read_exact_identity(
      options.fetch(:final_dmg),
      "final candidate DMG",
      max_bytes: MAX_DMG_BYTES
    )

    release = manifest.fetch("release")
    application = manifest.fetch("application")
    final_dmg = manifest.fetch("lineage").fetch("finalStapledDmg")
    fail_policy!("release manifest repository input is invalid") unless REPOSITORY.match?(options.fetch(:repository))
    repository_url = "https://github.com/#{options.fetch(:repository)}"
    expected_namespace = "#{repository_url}/release-evidence/#{options.fetch(:tag)}/#{options.fetch(:final_dmg_sha256)}"
    fail_policy!("release manifest namespace differs") unless release["namespace"] == expected_namespace
    fail_policy!("release manifest tag differs") unless release["tag"] == options.fetch(:tag)
    fail_policy!("release manifest commit differs") unless release["commit"] == options.fetch(:commit)
    fail_policy!("release manifest run differs") unless release.dig("run", "id") == options.fetch(:candidate_run_id)
    fail_policy!("release manifest origin attempt differs") unless release.dig("run", "attempt") == 1
    expected_run_url = "#{repository_url}/actions/runs/#{options.fetch(:candidate_run_id)}"
    fail_policy!("release manifest run URL differs") unless release.dig("run", "url") == expected_run_url
    fail_policy!("release manifest final DMG differs") unless final_dmg["sha256"] == options.fetch(:final_dmg_sha256)
    build_number = parse_positive_integer(release.fetch("buildNumber"), "release manifest build number")
    version = release.fetch("version")
    fail_policy!("release manifest does not identify the fixed public beta") unless
      version == CURRENT_VERSION && options.fetch(:tag) == CURRENT_TAG &&
      build_number == CURRENT_BUILD_NUMBER
    expected_dmg_name = "Desk-Setup-Switcher-#{version}.dmg"
    expected_provenance_name = "Desk-Setup-Switcher-#{version}.provenance.sigstore.json"
    fail_policy!("release manifest final DMG name differs") unless final_dmg["name"] == expected_dmg_name
    fail_policy!("final candidate DMG path name differs") unless
      File.basename(options.fetch(:final_dmg)) == expected_dmg_name
    fail_policy!("final candidate DMG bytes differ") unless
      current_dmg_identity["sha256"] == final_dmg["sha256"] &&
      current_dmg_identity["size"] == final_dmg["size"]
    manifest_created_at = exact_timestamp(release["created"], "release manifest creation time")

    candidate = {
      "repository" => options.fetch(:repository),
      "tag" => options.fetch(:tag),
      "commit" => options.fetch(:commit),
      "version" => version,
      "buildNumber" => build_number,
      "bundleIdentifier" => application.fetch("bundleIdentifier"),
      "profileSchemaVersion" => options.fetch(:profile_schema_version),
      "candidateOriginRunId" => options.fetch(:candidate_run_id),
      "candidateOriginRunAttempt" => 1,
      "candidateArtifactId" => options.fetch(:candidate_artifact_id),
      "candidateArtifactSHA256" => options.fetch(:candidate_artifact_sha256),
      "finalDMGSHA256" => options.fetch(:final_dmg_sha256),
      "releaseManifestSHA256" => manifest_sha256
    }
    expected = { candidate: candidate }
    inventory, inventory_sha256 = read_strict_json(
      options.fetch(:candidate_inventory),
      "candidate inventory"
    )
    inventory_result = validate_inventory(inventory, expected, manifest_created_at)
    lineage, lineage_sha256 = read_strict_json(options.fetch(:predecessor_lineage), "predecessor lineage")
    lineage_result = validate_lineage(lineage, expected, inventory_result, inventory_sha256)
    boundary_result = validate_release_boundary(
      options.fetch(:predecessor_release_boundary),
      lineage_result.fetch(:upgrade),
      options.fetch(:predecessor_tag_object),
      options.fetch(:predecessor_pre_tag_evidence_sha256)
    )
    predecessor_materials = validate_predecessor_materials(
      options,
      expected,
      inventory_result,
      lineage_result,
      boundary_result,
      manifest_created_at
    )
    report_subject = candidate.merge(
      "finalDMGName" => expected_dmg_name,
      "provenanceBundleName" => expected_provenance_name,
      "provenanceBundleSHA256" => provenance_sha256,
      "provenanceSubjectSHA256" => options.fetch(:final_dmg_sha256),
      "predecessorLineageSHA256" => lineage_sha256
    )
    expected[:report_subject] = report_subject

    reports = options.fetch(:reports).map do |path|
      report, digest = read_strict_json(path, "external beta report")
      validate_report(report, expected, lineage_result, digest)
    end
    fail_policy!("external beta report order differs") unless reports.map { |report| report.fetch(:code) } == REPORT_CODES
    fail_policy!("external beta report bytes are not unique") unless
      reports.map { |report| report.fetch(:digest) }.uniq.length == 3
    fail_policy!("external beta report subjects differ") unless
      reports.map { |report| report.fetch(:subject) }.uniq.length == 1

    set, set_sha256 = read_strict_json(options.fetch(:set_manifest), "external beta set")
    set_result = validate_set(set, expected, reports)
    {
      report_digests: reports.map { |report| report.fetch(:digest) },
      set_sha256: set_sha256,
      inventory_sha256: inventory_sha256,
      lineage_sha256: lineage_sha256,
      release_manifest_sha256: manifest_sha256,
      provenance_sha256: provenance_sha256,
      predecessor_release_manifest_sha256: predecessor_materials.fetch(:release_manifest_sha256),
      predecessor_final_dmg_sha256: predecessor_materials.fetch(:final_dmg_sha256),
      predecessor_provenance_sha256: predecessor_materials.fetch(:provenance_sha256),
      predecessor_release_boundary_sha256: predecessor_materials.fetch(:boundary_sha256),
      sonoma_code: set_result.fetch(:sonoma_code),
      set_created_at: set_result.fetch(:created_at).utc.iso8601,
      build_number: build_number
    }
  end

  def run_verify_set(argv)
    options = { reports: [], print_result_json: false }
    parser = OptionParser.new do |value|
      value.banner = "Usage: external_beta_policy.rb verify-set [options]"
      value.on("--release-manifest FILE") { |item| options[:release_manifest] = item }
      value.on("--final-dmg FILE") { |item| options[:final_dmg] = item }
      value.on("--provenance-bundle FILE") { |item| options[:provenance_bundle] = item }
      value.on("--predecessor-release-manifest FILE") { |item| options[:predecessor_release_manifest] = item }
      value.on("--predecessor-provenance-bundle FILE") { |item| options[:predecessor_provenance_bundle] = item }
      value.on("--predecessor-dmg FILE") { |item| options[:predecessor_dmg] = item }
      value.on("--predecessor-release-boundary FILE") { |item| options[:predecessor_release_boundary] = item }
      value.on("--predecessor-tag-object SHA") { |item| options[:predecessor_tag_object] = item }
      value.on("--predecessor-pre-tag-evidence-sha256 SHA") do |item|
        options[:predecessor_pre_tag_evidence_sha256] = item
      end
      value.on("--candidate-inventory FILE") { |item| options[:candidate_inventory] = item }
      value.on("--predecessor-lineage FILE") { |item| options[:predecessor_lineage] = item }
      value.on("--set-manifest FILE") { |item| options[:set_manifest] = item }
      value.on("--report FILE") { |item| options[:reports] << item }
      value.on("--repository NAME") { |item| options[:repository] = item }
      value.on("--tag TAG") { |item| options[:tag] = item }
      value.on("--commit SHA") { |item| options[:commit] = item }
      value.on("--candidate-run-id ID") { |item| options[:candidate_run_id] = item }
      value.on("--candidate-artifact-id ID") { |item| options[:candidate_artifact_id] = item }
      value.on("--candidate-artifact-sha256 SHA") { |item| options[:candidate_artifact_sha256] = item }
      value.on("--final-dmg-sha256 SHA") { |item| options[:final_dmg_sha256] = item }
      value.on("--profile-schema-version VERSION") { |item| options[:profile_schema_version] = item }
      value.on("--print-result-json") { options[:print_result_json] = true }
    end
    parser.parse!(argv)
    fail_policy!("unexpected arguments") unless argv.empty?
    required = %i[
      release_manifest final_dmg provenance_bundle predecessor_release_manifest
      predecessor_provenance_bundle predecessor_dmg predecessor_release_boundary
      predecessor_tag_object predecessor_pre_tag_evidence_sha256 candidate_inventory
      predecessor_lineage set_manifest repository tag commit
      candidate_run_id candidate_artifact_id candidate_artifact_sha256 final_dmg_sha256
      profile_schema_version
    ]
    fail_policy!("required external beta inputs are missing") unless required.all? { |name| options.key?(name) }
    fail_policy!("exactly three external beta reports are required") unless options.fetch(:reports).length == 3
    exact_string(options.fetch(:repository), "expected repository")
    fail_policy!("expected repository is invalid") unless REPOSITORY.match?(options.fetch(:repository))
    exact_string(options.fetch(:tag), "expected tag")
    exact_commit(options.fetch(:commit), "expected release commit")
    exact_commit(options.fetch(:predecessor_tag_object), "expected predecessor tag object")
    exact_sha256(
      options.fetch(:predecessor_pre_tag_evidence_sha256),
      "expected predecessor pre-tag evidence digest"
    )
    options[:candidate_run_id] = parse_positive_integer(options.fetch(:candidate_run_id), "expected candidate run ID")
    options[:candidate_artifact_id] = parse_positive_integer(options.fetch(:candidate_artifact_id), "expected candidate artifact ID")
    options[:profile_schema_version] = parse_positive_integer(options.fetch(:profile_schema_version), "expected profile schema version")
    exact_sha256(options.fetch(:candidate_artifact_sha256), "expected candidate artifact digest")
    exact_sha256(options.fetch(:final_dmg_sha256), "expected final DMG digest")

    result = verify!(options)
    if options.fetch(:print_result_json)
      sonoma_index = REPORT_CODES.index(result.fetch(:sonoma_code))
      puts JSON.generate(
        {
          "schemaVersion" => "desk-setup-switcher.external-beta-verification/v3",
          "releaseManifestSHA256" => result.fetch(:release_manifest_sha256),
          "finalDMGProvenanceSHA256" => result.fetch(:provenance_sha256),
          "candidateInventorySHA256" => result.fetch(:inventory_sha256),
          "predecessorLineageSHA256" => result.fetch(:lineage_sha256),
          "predecessorReleaseManifestSHA256" => result.fetch(:predecessor_release_manifest_sha256),
          "predecessorFinalDMGSHA256" => result.fetch(:predecessor_final_dmg_sha256),
          "predecessorFinalDMGProvenanceSHA256" => result.fetch(:predecessor_provenance_sha256),
          "predecessorReleaseBoundarySHA256" => result.fetch(:predecessor_release_boundary_sha256),
          "externalBetaSetSHA256" => result.fetch(:set_sha256),
          "externalBetaReportSHA256" => result.fetch(:report_digests),
          "sonomaGateReportCode" => result.fetch(:sonoma_code),
          "sonomaGateReportSHA256" => result.fetch(:report_digests).fetch(sonoma_index),
          "externalBetaSetCreatedAt" => result.fetch(:set_created_at),
          "buildNumber" => result.fetch(:build_number)
        }
      )
    else
      puts "OK external beta set reports=3 sonoma=#{result.fetch(:sonoma_code)} build=#{result.fetch(:build_number)}"
    end
  end

  def run(argv)
    command = argv.shift
    case command
    when "verify-set"
      run_verify_set(argv)
    else
      fail_policy!("expected verify-set")
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    DeskSetupExternalBetaPolicy.run(ARGV)
  rescue DeskSetupExternalBetaPolicy::PolicyError => error
    warn "External beta policy error: #{error.message}"
    exit 1
  rescue OptionParser::ParseError
    warn "External beta policy error: invalid command line."
    exit 1
  rescue StandardError
    warn "External beta policy error: evidence verification failed safely."
    exit 1
  end
end
