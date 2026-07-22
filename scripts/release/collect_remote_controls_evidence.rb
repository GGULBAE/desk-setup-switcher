#!/usr/bin/env ruby
# frozen_string_literal: true

require "base64"
require "digest"
require "digest/sha1"
require "json"
require "optparse"
require "psych"
require "tempfile"
require "time"
require_relative "release_policy"

# Normalizes fixed, value-minimized projections produced by the trusted
# verify-remote-controls wrapper. This file deliberately has no network or Git
# integration and accepts no endpoint or repository arguments.
module RemoteControlsCollector
  EVIDENCE_SCHEMA = "desk-setup-switcher.remote-release-controls-evidence/v1"
  INPUT_SCHEMA = "desk-setup-switcher.remote-release-controls-input/v1"
  EVIDENCE_SCHEMA_V2 = "desk-setup-switcher.remote-release-controls-evidence/v2"
  INPUT_SCHEMA_V2 = "desk-setup-switcher.remote-release-controls-input/v2"
  EVIDENCE_SCHEMA_V3 = "desk-setup-switcher.remote-release-controls-evidence/v3"
  INPUT_SCHEMA_V3 = "desk-setup-switcher.remote-release-controls-input/v3"
  PREDECESSOR_PRE_TAG_PHASE = "predecessor-pre-tag"
  PHASE = "final-pre-tag"
  PRE_PUBLICATION_PHASE = "pre-publication"
  MASTER_REF = "refs/heads/master"
  PREDECESSOR_TAG_REF = "refs/tags/v0.0.9"
  RELEASE_TAG_REF = "refs/tags/v0.1.0"
  RELEASE_WORKFLOW_PATH = ".github/workflows/signed-release-candidate.yml"
  LEGACY_WORKFLOW_PATH = ".github/workflows/release.yml"
  CI_WORKFLOW_PATH = ".github/workflows/ci.yml"
  PUBLICATION_WORKFLOW_PATH = ".github/workflows/publish-release.yml"
  PRIMARY_CI_JOB_NAME = "Verify macOS app"
  LOCAL_TRIGGER_PROJECTION = "strict-local-workflow-ast/v1"
  MANUAL_EVIDENCE_SCHEMA = "desk-setup-switcher.manual-release-control-evidence/v1"
  MANUAL_CONTROLS = {
    "candidate" => "release-candidate-administrator-bypass-disabled",
    "publication" =>
      "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope"
  }.freeze
  MANUAL_PERMISSION_PROFILES = {
    "candidate" => [],
    "publication" => %w[
      actions:read
      administration:read
      attestations:read
      contents:read
      metadata:read
    ]
  }.freeze

  MAX_MANIFEST_BYTES = 64 * 1024
  MAX_PROJECTION_BYTES = 2 * 1024 * 1024
  MAX_WORKFLOW_BYTES = 2 * 1024 * 1024
  MANUAL_TOKEN_MINIMUM_REMAINING_SECONDS = 2_700
  MANUAL_TOKEN_MAXIMUM_ISSUANCE_CAPTURE_SECONDS = 900
  MANUAL_TOKEN_MAXIMUM_LIFETIME_SECONDS = 30 * 86_400
  SHA = /\A[0-9a-f]{40}\z/
  NAME = /\A[A-Za-z_][A-Za-z0-9_]*\z/
  BASENAME = /\A[A-Za-z0-9][A-Za-z0-9.-]*\.json\z/
  TRIGGER = /\A[A-Za-z_][A-Za-z0-9_-]*\z/

  STATIC_INPUT_FILES = %w[
    actions-permissions.json
    check-runs.json
    ci-workflow-content-1.json
    ci-workflow-content-2.json
    ci-workflow-metadata-1.json
    ci-workflow-metadata-2.json
    deployment-policies.json
    effective-master.json
    environment-secrets.json
    environment-variable-names.json
    environment.json
    immutable-releases.json
    label.json
    master-1.json
    master-2.json
    permission.json
    private-vulnerability-reporting.json
    releases.json
    repository-secrets.json
    repository-variable-names.json
    repository.json
    ruleset-ids.json
    selected-actions.json
    v-refs.json
    viewer.json
    workflow-content-1.json
    workflow-content-2.json
    workflow-metadata-1.json
    workflow-metadata-2.json
    workflow-jobs.json
    workflow-permissions.json
    workflow-runs.json
  ].sort.freeze
  LIFECYCLE_EXTRA_INPUT_FILES = %w[
    active-workflows.json
    legacy-workflow-content-1.json
    legacy-workflow-content-2.json
    legacy-workflow-metadata-1.json
    legacy-workflow-metadata-2.json
    publication-deployment-policies.json
    publication-environment-secrets.json
    publication-environment-variable-names.json
    publication-environment.json
    publication-workflow-content-1.json
    publication-workflow-content-2.json
    publication-workflow-metadata-1.json
    publication-workflow-metadata-2.json
  ].sort.freeze

  KNOWN_RULE_TYPES = %w[
    creation
    deletion
    non_fast_forward
    pull_request
    required_status_checks
    update
  ].freeze

  class CollectionUnavailable < StandardError; end

  module_function

  def unavailable!
    raise CollectionUnavailable
  end

  def exact_object(value, keys)
    unavailable! unless value.is_a?(Hash) && value.keys.all? { |key| key.is_a?(String) }
    unavailable! unless value.keys.sort == keys.sort

    value
  end

  def exact_array(value, length: nil)
    unavailable! unless value.is_a?(Array)
    unavailable! if length && value.length != length

    value
  end

  def exact_string(value, allow_empty: false, max_bytes: 2048, pattern: nil)
    value = value.encode(Encoding::UTF_8) if value.is_a?(String) &&
                                                value.encoding == Encoding::US_ASCII
    unavailable! unless value.is_a?(String) && value.encoding == Encoding::UTF_8 && value.valid_encoding?
    unavailable! if !allow_empty && value.empty?
    unavailable! if value.bytesize > max_bytes || value.match?(/[\r\n\0]/)
    unavailable! if pattern && !value.match?(pattern)

    value
  end

  def nullable_string(value, max_bytes: 2048)
    return nil if value.nil?

    exact_string(value, allow_empty: true, max_bytes: max_bytes)
  end

  def exact_boolean(value)
    unavailable! unless value == true || value == false

    value
  end

  def nonnegative_integer(value)
    unavailable! unless value.is_a?(Integer) && value >= 0

    value
  end

  def positive_integer(value)
    unavailable! unless value.is_a?(Integer) && value.positive?

    value
  end

  def exact_sha(value)
    exact_string(value, pattern: SHA)
  end

  def canonical_strings(value, allow_empty: true, pattern: nil)
    items = exact_array(value).map { |item| exact_string(item, pattern: pattern) }
    unavailable! if !allow_empty && items.empty?
    unavailable! unless items == items.sort && items.uniq == items

    items
  end

  def actor(value)
    raw = exact_object(value, %w[id login type])
    {
      "id" => positive_integer(raw.fetch("id")),
      "login" => exact_string(raw.fetch("login"), max_bytes: 100),
      "type" => exact_string(raw.fetch("type"), max_bytes: 32)
    }
  rescue KeyError
    unavailable!
  end

  def require_secure_directory(path)
    unavailable! unless path.is_a?(String) && !path.empty?
    stat = File.lstat(path)
    unavailable! if stat.symlink? || !stat.directory?
    unavailable! unless stat.uid == Process.uid && (stat.mode & 0o777) == 0o700

    File.expand_path(path)
  rescue SystemCallError
    unavailable!
  end

  def projection_path(input_directory, name)
    unavailable! unless name.is_a?(String) && name.match?(BASENAME)

    File.join(input_directory, name)
  end

  def read_json(input_directory, name, max_bytes: MAX_PROJECTION_BYTES)
    ReleasePolicy.strict_json(
      projection_path(input_directory, name),
      "remote controls projection",
      max_bytes: max_bytes
    )
  rescue ReleasePolicy::PolicyError
    unavailable!
  end

  def strict_json_lines(path, allow_empty: false, max_bytes: MAX_PROJECTION_BYTES)
    source = ReleasePolicy.with_regular_file(path, "remote controls projection") do |io, stat|
      unavailable! if stat.size > max_bytes
      bytes = io.read(max_bytes + 1) || "".b
      unavailable! if bytes.bytesize > max_bytes
      bytes
    end
    source = source.force_encoding(Encoding::UTF_8)
    unavailable! unless source.valid_encoding? && !source.include?("\0")
    values = []
    source.each_line do |line|
      line = line.chomp
      unavailable! if line.empty?
      values << ReleasePolicy.parse_strict_json(line, "remote controls projection")
    end
    unavailable! if !allow_empty && values.empty?
    values
  rescue ReleasePolicy::PolicyError
    unavailable!
  end

  def read_json_lines(input_directory, name, allow_empty: false)
    strict_json_lines(projection_path(input_directory, name), allow_empty: allow_empty)
  end

  def yaml_scalar(node)
    unavailable! unless node.is_a?(Psych::Nodes::Scalar)

    exact_string(node.value, max_bytes: 256)
  end

  def yaml_mapping(node)
    unavailable! unless node.is_a?(Psych::Nodes::Mapping)
    result = {}
    node.children.each_slice(2) do |key_node, value_node|
      key = yaml_scalar(key_node)
      unavailable! if result.key?(key)
      result[key] = value_node
    end
    result
  end

  # Psych's object loader applies YAML 1.1 boolean coercion to the key `on`.
  # Inspecting the AST preserves the exact source spelling and lets us reject
  # duplicate top-level and trigger keys before extracting the trigger names.
  def workflow_triggers(source)
    document = Psych.parse(source)
    root = document&.root
    unavailable! unless root.is_a?(Psych::Nodes::Mapping)

    top_level = yaml_mapping(root)
    on_node = top_level.fetch("on")

    triggers = case on_node
               when Psych::Nodes::Mapping
                 seen = {}
                 on_node.children.each_slice(2) do |key_node, _value_node|
                   trigger = yaml_scalar(key_node)
                   unavailable! unless trigger.match?(TRIGGER)
                   unavailable! if seen.key?(trigger)
                   seen[trigger] = true
                 end
                 seen.keys
               when Psych::Nodes::Sequence
                 on_node.children.map do |node|
                   trigger = yaml_scalar(node)
                   unavailable! unless trigger.match?(TRIGGER)
                   trigger
                 end
               when Psych::Nodes::Scalar
                 trigger = yaml_scalar(on_node)
                 unavailable! unless trigger.match?(TRIGGER)
                 [trigger]
               else
                 unavailable!
               end
    triggers.sort!
    unavailable! if triggers.empty? || triggers.uniq != triggers
    triggers
  rescue KeyError, Psych::Exception
    unavailable!
  end

  def permissions_write_contents?(node)
    return false if node.nil?

    case node
    when Psych::Nodes::Mapping
      permissions = yaml_mapping(node)
      contents = permissions["contents"]
      return false unless contents

      yaml_scalar(contents) == "write"
    when Psych::Nodes::Scalar
      value = yaml_scalar(node)
      unavailable! unless %w[read-all write-all].include?(value)
      value == "write-all"
    else
      unavailable!
    end
  end

  # A workflow is a contents-write route when either workflow-level or any
  # job-level permissions can write repository contents. The projection is
  # source-derived from the exact blob and deliberately ignores step commands.
  def workflow_contents_write(source)
    document = Psych.parse(source)
    root = document&.root
    top_level = yaml_mapping(root)
    return true if permissions_write_contents?(top_level["permissions"])

    jobs_node = top_level.fetch("jobs")
    jobs = yaml_mapping(jobs_node)
    jobs.any? do |_name, job_node|
      job = yaml_mapping(job_node)
      permissions_write_contents?(job["permissions"])
    end
  rescue KeyError, Psych::Exception
    unavailable!
  end

  def local_workflow_security(path)
    source = ReleasePolicy.read_utf8(path, "release workflow", max_bytes: MAX_WORKFLOW_BYTES)
    {
      "triggers" => workflow_triggers(source),
      "contentsWrite" => workflow_contents_write(source)
    }
  rescue ReleasePolicy::PolicyError
    unavailable!
  end

  def local_triggers(path)
    source = ReleasePolicy.read_utf8(path, "release workflow", max_bytes: MAX_WORKFLOW_BYTES)
    workflow_triggers(source)
  rescue ReleasePolicy::PolicyError
    unavailable!
  end

  def workflow_blob_sha(bytes)
    Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes.b)
  end

  def master_anchor(value)
    raw = exact_object(value, %w[object ref])
    target = exact_object(raw.fetch("object"), %w[sha type])
    unavailable! unless target.fetch("type") == "commit"
    {
      "ref" => exact_string(raw.fetch("ref"), max_bytes: 256),
      "commitSha" => exact_sha(target.fetch("sha"))
    }
  rescue KeyError
    unavailable!
  end

  def decoded_workflow_content(value, master_commit, expected_path:)
    raw = exact_object(value, %w[commit_sha content encoding path sha type])
    unavailable! unless raw.fetch("type") == "file" && raw.fetch("path") == expected_path
    unavailable! unless exact_sha(raw.fetch("commit_sha")) == master_commit
    unavailable! unless raw.fetch("encoding") == "base64"

    encoded = raw.fetch("content")
    unavailable! unless encoded.is_a?(String) && encoded.bytesize <= MAX_WORKFLOW_BYTES * 2
    compact = encoded.delete("\n")
    unavailable! unless compact.match?(/\A[A-Za-z0-9+\/]*={0,2}\z/) && (compact.length % 4).zero?
    bytes = Base64.strict_decode64(compact)
    unavailable! if bytes.bytesize > MAX_WORKFLOW_BYTES

    blob_sha = exact_sha(raw.fetch("sha"))
    unavailable! unless workflow_blob_sha(bytes) == blob_sha
    source = bytes.dup.force_encoding(Encoding::UTF_8)
    unavailable! unless source.valid_encoding? && !source.include?("\0")

    {
      "blobSha" => blob_sha,
      "triggers" => workflow_triggers(source),
      "contentsWrite" => workflow_contents_write(source)
    }
  rescue ArgumentError, KeyError
    unavailable!
  end

  def workflow_metadata(value, content, expected_path:)
    raw = exact_object(value, %w[id name path state])
    path = exact_string(raw.fetch("path"), max_bytes: 256)
    unavailable! unless path == expected_path
    {
      "id" => positive_integer(raw.fetch("id")),
      "name" => exact_string(raw.fetch("name"), max_bytes: 100),
      "path" => path,
      "state" => exact_string(raw.fetch("state"), max_bytes: 64),
      "blobSha" => content.fetch("blobSha"),
      "triggers" => content.fetch("triggers")
    }
  rescue KeyError
    unavailable!
  end

  def normalize_repository(value)
    raw = exact_object(
      value,
      %w[archived default_branch description disabled full_name has_discussions homepage id name node_id owner private topics visibility]
    )
    topics = exact_array(raw.fetch("topics")).map { |topic| exact_string(topic, max_bytes: 50) }.sort
    unavailable! unless topics.uniq == topics
    {
      "id" => positive_integer(raw.fetch("id")),
      "nodeId" => exact_string(raw.fetch("node_id"), max_bytes: 256),
      "name" => exact_string(raw.fetch("name"), max_bytes: 100),
      "fullName" => exact_string(raw.fetch("full_name"), max_bytes: 256),
      "owner" => actor(raw.fetch("owner")),
      "private" => exact_boolean(raw.fetch("private")),
      "visibility" => exact_string(raw.fetch("visibility"), max_bytes: 32),
      "defaultBranch" => exact_string(raw.fetch("default_branch"), max_bytes: 256),
      "archived" => exact_boolean(raw.fetch("archived")),
      "disabled" => exact_boolean(raw.fetch("disabled")),
      "hasDiscussions" => exact_boolean(raw.fetch("has_discussions")),
      "description" => nullable_string(raw.fetch("description"), max_bytes: 512),
      "homepage" => nullable_string(raw.fetch("homepage"), max_bytes: 2048),
      "topics" => topics
    }
  rescue KeyError
    unavailable!
  end

  def authenticated_viewer(viewer_value, permission_value)
    viewer = actor(viewer_value)
    permission = exact_object(permission_value, %w[permission user])
    permission_actor = actor(permission.fetch("user"))
    unavailable! unless permission_actor == viewer
    {
      "actor" => viewer,
      "repositoryPermission" => exact_string(permission.fetch("permission"), max_bytes: 32)
    }
  rescue KeyError
    unavailable!
  end

  def normalize_local_trigger_projection(value, expected_path:, expected_blob:)
    local = exact_object(value, %w[projection triggers workflowBlob workflowPath])
    unavailable! unless local.fetch("projection") == LOCAL_TRIGGER_PROJECTION
    unavailable! unless local.fetch("workflowPath") == expected_path
    unavailable! unless exact_sha(local.fetch("workflowBlob")) == expected_blob
    canonical_strings(local.fetch("triggers"), allow_empty: false, pattern: TRIGGER)
  rescue KeyError
    unavailable!
  end

  def normalize_local_workflow_projection(value, expected_path:, expected_blob:)
    local = exact_object(value, %w[contentsWrite projection triggers workflowBlob workflowPath])
    unavailable! unless local.fetch("projection") == LOCAL_TRIGGER_PROJECTION
    unavailable! unless local.fetch("workflowPath") == expected_path
    unavailable! unless exact_sha(local.fetch("workflowBlob")) == expected_blob
    {
      "triggers" => canonical_strings(local.fetch("triggers"), allow_empty: false, pattern: TRIGGER),
      "contentsWrite" => exact_boolean(local.fetch("contentsWrite"))
    }
  rescue KeyError
    unavailable!
  end

  def normalize_manual_evidence_input(value)
    raw = exact_object(value, %w[complete items])
    unavailable! unless raw.fetch("complete") == true
    items = exact_array(raw.fetch("items"), length: 2).map do |item|
      entry = exact_object(item, %w[control sha256])
      {
        "control" => exact_string(entry.fetch("control"), max_bytes: 160),
        "sha256" => exact_string(entry.fetch("sha256"), pattern: /\A[0-9a-f]{64}\z/)
      }
    end
    unavailable! unless items.map { |item| item.fetch("control") }.uniq.length == items.length
    unavailable! unless items.map { |item| item.fetch("sha256") }.uniq.length == items.length
    { "complete" => true, "items" => items }
  rescue KeyError
    unavailable!
  end

  def manual_evidence(path:, expected_control:, permission_profile:, actor_id:, actor_login:,
                      verified_at:, phase:, release_commit: nil,
                      release_id: nil, release_tag_object: nil, freshness_mode: "current")
    unavailable! unless MANUAL_PERMISSION_PROFILES.key?(permission_profile)
    unavailable! unless MANUAL_CONTROLS.value?(expected_control)
    unavailable! unless MANUAL_CONTROLS.fetch(permission_profile) == expected_control
    positive_integer(actor_id)
    exact_string(actor_login, max_bytes: 39, pattern: /\A(?!-)[A-Za-z0-9-]+(?<!-)\z/)
    unavailable! unless [PREDECESSOR_PRE_TAG_PHASE, PHASE, PRE_PUBLICATION_PHASE].include?(phase)
    unavailable! unless %w[current historical].include?(freshness_mode)
    unavailable! if freshness_mode == "historical" && phase != PHASE

    expected_subject = if [PREDECESSOR_PRE_TAG_PHASE, PHASE].include?(phase)
      unavailable! if release_commit || release_id || release_tag_object
      { "tag" => "v0.1.0" }
    else
      exact_sha(release_commit)
      positive_integer(release_id)
      exact_sha(release_tag_object)
      {
        "peeledCommit" => release_commit,
        "releaseId" => release_id,
        "tag" => "v0.1.0",
        "tagObjectSha" => release_tag_object
      }
    end

    source = ReleasePolicy.with_regular_file(path, "manual release-control evidence") do |io, stat|
      unavailable! unless stat.nlink == 1 && stat.size.positive? && stat.size <= MAX_MANIFEST_BYTES
      bytes = io.read(MAX_MANIFEST_BYTES + 1) || "".b
      unavailable! if bytes.bytesize > MAX_MANIFEST_BYTES
      bytes
    end
    text = source.dup.force_encoding(Encoding::UTF_8)
    unavailable! unless text.valid_encoding? && !text.include?("\0")
    value = ReleasePolicy.parse_strict_json(text, "manual release-control evidence")
    raw = exact_object(
      value,
      %w[administratorBypassEnabled control observedAt observer phase redactionReviewed schemaVersion sourceArtifactSHA256 subject token tokenPermissions]
    )
    unavailable! unless raw.fetch("schemaVersion") == MANUAL_EVIDENCE_SCHEMA
    unavailable! unless raw.fetch("control") == expected_control && raw.fetch("phase") == phase
    unavailable! unless raw.fetch("administratorBypassEnabled") == false
    unavailable! unless raw.fetch("redactionReviewed") == true
    unavailable! unless raw.fetch("subject") == expected_subject

    observer = actor(raw.fetch("observer"))
    unavailable! unless observer.fetch("id") == actor_id && observer.fetch("type") == "User" &&
                        observer.fetch("login").casecmp?(actor_login)
    source_artifact = exact_string(
      raw.fetch("sourceArtifactSHA256"), pattern: /\A[0-9a-f]{64}\z/
    )
    unavailable! unless raw.fetch("tokenPermissions") ==
                        MANUAL_PERMISSION_PROFILES.fetch(permission_profile)

    observed_at = exact_string(raw.fetch("observedAt"), max_bytes: 32)
    verified_at = exact_string(verified_at.encode(Encoding::UTF_8), max_bytes: 32)
    observed_time = Time.iso8601(observed_at)
    verified_time = Time.iso8601(verified_at)
    unavailable! unless observed_at == observed_time.utc.iso8601 &&
                        verified_at == verified_time.utc.iso8601
    unavailable! unless observed_time <= verified_time
    unavailable! if freshness_mode == "current" && (verified_time - observed_time) > 86_400

    token = raw.fetch("token")
    if permission_profile == "candidate"
      unavailable! unless token.nil?
    else
      token = exact_object(
        token,
        %w[accountPermissions expiresAt issuedAt organizationPermissions repositorySelection resourceOwner type]
      )
      unavailable! unless token.fetch("type") == "fine-grained-personal-access-token"
      resource_owner = exact_string(token.fetch("resourceOwner"), max_bytes: 39)
      unavailable! unless resource_owner.casecmp?(actor_login)
      repositories = exact_array(token.fetch("repositorySelection"), length: 1)
      repository = exact_string(repositories.fetch(0), max_bytes: 141)
      unavailable! unless repository.casecmp?("#{actor_login}/desk-setup-switcher")
      unavailable! unless token.fetch("accountPermissions") == [] &&
                          token.fetch("organizationPermissions") == []
      issued_at = exact_string(token.fetch("issuedAt"), max_bytes: 32)
      expires_at = exact_string(token.fetch("expiresAt"), max_bytes: 32)
      issued_time = Time.iso8601(issued_at)
      expires_time = Time.iso8601(expires_at)
      unavailable! unless issued_at == issued_time.utc.iso8601 &&
                          expires_at == expires_time.utc.iso8601 &&
                          issued_time <= observed_time && observed_time < expires_time
      unavailable! if (observed_time - issued_time) > MANUAL_TOKEN_MAXIMUM_ISSUANCE_CAPTURE_SECONDS
      unavailable! if (expires_time - issued_time) > MANUAL_TOKEN_MAXIMUM_LIFETIME_SECONDS
      unavailable! if freshness_mode == "current" &&
                      (expires_time - verified_time) < MANUAL_TOKEN_MINIMUM_REMAINING_SECONDS
    end

    {
      "control" => expected_control,
      "observedAt" => observed_at,
      "sha256" => Digest::SHA256.hexdigest(source.b),
      "sourceArtifactSHA256" => source_artifact
    }
  rescue KeyError, ArgumentError
    unavailable!
  end

  def normalize_manifest_v2(value)
    raw = exact_object(
      value,
      %w[collectedAt expectedCIWorkflowBlob expectedCommit expectedLegacyWorkflowBlob expectedPublicationWorkflowBlob expectedRelease expectedWorkflowBlob files finalPreTagEvidenceSHA256 localCandidateWorkflow localCIWorkflow localLegacyWorkflow localPublicationWorkflow manualEvidence phase schemaVersion]
    )
    unavailable! unless raw.fetch("schemaVersion") == INPUT_SCHEMA_V2
    phase = exact_string(raw.fetch("phase"), max_bytes: 32)
    unavailable! unless [PHASE, PRE_PUBLICATION_PHASE].include?(phase)
    collected_at = exact_string(raw.fetch("collectedAt"), max_bytes: 32)
    collected_time = Time.iso8601(collected_at)
    unavailable! unless collected_at == collected_time.utc.iso8601
    expected_commit = exact_sha(raw.fetch("expectedCommit"))
    expected_blob = exact_sha(raw.fetch("expectedWorkflowBlob"))
    expected_ci_blob = exact_sha(raw.fetch("expectedCIWorkflowBlob"))
    expected_publication_blob = exact_sha(raw.fetch("expectedPublicationWorkflowBlob"))
    expected_legacy_blob = exact_sha(raw.fetch("expectedLegacyWorkflowBlob"))
    final_pre_tag_evidence_sha256 = raw.fetch("finalPreTagEvidenceSHA256")
    expected_release = raw.fetch("expectedRelease")
    if phase == PHASE
      unavailable! unless expected_release.nil? && final_pre_tag_evidence_sha256.nil?
    else
      final_pre_tag_evidence_sha256 = exact_string(
        final_pre_tag_evidence_sha256, pattern: /\A[0-9a-f]{64}\z/
      )
      release = exact_object(expected_release, %w[commitSha id tagObjectSha])
      expected_release = {
        "commitSha" => exact_sha(release.fetch("commitSha")),
        "id" => positive_integer(release.fetch("id")),
        "tagObjectSha" => exact_sha(release.fetch("tagObjectSha"))
      }
    end
    {
      "phase" => phase,
      "collectedAt" => collected_at,
      "expectedCommit" => expected_commit,
      "expectedWorkflowBlob" => expected_blob,
      "expectedCIWorkflowBlob" => expected_ci_blob,
      "expectedPublicationWorkflowBlob" => expected_publication_blob,
      "expectedLegacyWorkflowBlob" => expected_legacy_blob,
      "expectedRelease" => expected_release,
      "finalPreTagEvidenceSHA256" => final_pre_tag_evidence_sha256,
      "localCandidateWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localCandidateWorkflow"),
        expected_path: RELEASE_WORKFLOW_PATH,
        expected_blob: expected_blob
      ),
      "localCIWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localCIWorkflow"),
        expected_path: CI_WORKFLOW_PATH,
        expected_blob: expected_ci_blob
      ),
      "localPublicationWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localPublicationWorkflow"),
        expected_path: PUBLICATION_WORKFLOW_PATH,
        expected_blob: expected_publication_blob
      ),
      "localLegacyWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localLegacyWorkflow"),
        expected_path: LEGACY_WORKFLOW_PATH,
        expected_blob: expected_legacy_blob
      ),
      "manualEvidence" => normalize_manual_evidence_input(raw.fetch("manualEvidence")),
      "files" => canonical_strings(raw.fetch("files"), allow_empty: false, pattern: BASENAME)
    }
  rescue KeyError
    unavailable!
  end

  def normalize_manifest_v3(value)
    raw = exact_object(
      value,
      %w[collectedAt expectedCIWorkflowBlob expectedCommit expectedLegacyWorkflowBlob expectedPredecessor expectedPublicationWorkflowBlob expectedRelease expectedWorkflowBlob files finalPreTagEvidenceSHA256 localCandidateWorkflow localCIWorkflow localLegacyWorkflow localPublicationWorkflow manualEvidence phase predecessorPreTagEvidenceSHA256 schemaVersion]
    )
    unavailable! unless raw.fetch("schemaVersion") == INPUT_SCHEMA_V3
    phase = exact_string(raw.fetch("phase"), max_bytes: 32)
    phases = [PREDECESSOR_PRE_TAG_PHASE, PHASE, PRE_PUBLICATION_PHASE]
    unavailable! unless phases.include?(phase)
    collected_at = exact_string(raw.fetch("collectedAt"), max_bytes: 32)
    collected_time = Time.iso8601(collected_at)
    unavailable! unless collected_at == collected_time.utc.iso8601
    expected_commit = exact_sha(raw.fetch("expectedCommit"))
    expected_blob = exact_sha(raw.fetch("expectedWorkflowBlob"))
    expected_ci_blob = exact_sha(raw.fetch("expectedCIWorkflowBlob"))
    expected_publication_blob = exact_sha(raw.fetch("expectedPublicationWorkflowBlob"))
    expected_legacy_blob = exact_sha(raw.fetch("expectedLegacyWorkflowBlob"))
    predecessor_digest = raw.fetch("predecessorPreTagEvidenceSHA256")
    final_digest = raw.fetch("finalPreTagEvidenceSHA256")
    expected_predecessor = raw.fetch("expectedPredecessor")
    expected_release = raw.fetch("expectedRelease")
    case phase
    when PREDECESSOR_PRE_TAG_PHASE
      unavailable! unless expected_predecessor.nil? && expected_release.nil? &&
                          predecessor_digest.nil? && final_digest.nil?
    when PHASE
      predecessor = exact_object(expected_predecessor, %w[commitSha tagObjectSha])
      expected_predecessor = {
        "commitSha" => exact_sha(predecessor.fetch("commitSha")),
        "tagObjectSha" => exact_sha(predecessor.fetch("tagObjectSha"))
      }
      predecessor_digest = exact_string(predecessor_digest, pattern: /\A[0-9a-f]{64}\z/)
      unavailable! unless expected_release.nil? && final_digest.nil?
    when PRE_PUBLICATION_PHASE
      predecessor = exact_object(expected_predecessor, %w[commitSha tagObjectSha])
      expected_predecessor = {
        "commitSha" => exact_sha(predecessor.fetch("commitSha")),
        "tagObjectSha" => exact_sha(predecessor.fetch("tagObjectSha"))
      }
      release = exact_object(expected_release, %w[commitSha id tagObjectSha])
      expected_release = {
        "commitSha" => exact_sha(release.fetch("commitSha")),
        "id" => positive_integer(release.fetch("id")),
        "tagObjectSha" => exact_sha(release.fetch("tagObjectSha"))
      }
      predecessor_digest = exact_string(predecessor_digest, pattern: /\A[0-9a-f]{64}\z/)
      final_digest = exact_string(final_digest, pattern: /\A[0-9a-f]{64}\z/)
    end
    {
      "schemaVersion" => INPUT_SCHEMA_V3,
      "evidenceSchemaVersion" => EVIDENCE_SCHEMA_V3,
      "phase" => phase,
      "collectedAt" => collected_at,
      "expectedCommit" => expected_commit,
      "expectedWorkflowBlob" => expected_blob,
      "expectedCIWorkflowBlob" => expected_ci_blob,
      "expectedPublicationWorkflowBlob" => expected_publication_blob,
      "expectedLegacyWorkflowBlob" => expected_legacy_blob,
      "expectedPredecessor" => expected_predecessor,
      "expectedRelease" => expected_release,
      "predecessorPreTagEvidenceSHA256" => predecessor_digest,
      "finalPreTagEvidenceSHA256" => final_digest,
      "localCandidateWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localCandidateWorkflow"),
        expected_path: RELEASE_WORKFLOW_PATH,
        expected_blob: expected_blob
      ),
      "localCIWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localCIWorkflow"),
        expected_path: CI_WORKFLOW_PATH,
        expected_blob: expected_ci_blob
      ),
      "localPublicationWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localPublicationWorkflow"),
        expected_path: PUBLICATION_WORKFLOW_PATH,
        expected_blob: expected_publication_blob
      ),
      "localLegacyWorkflow" => normalize_local_workflow_projection(
        raw.fetch("localLegacyWorkflow"),
        expected_path: LEGACY_WORKFLOW_PATH,
        expected_blob: expected_legacy_blob
      ),
      "manualEvidence" => normalize_manual_evidence_input(raw.fetch("manualEvidence")),
      "files" => canonical_strings(raw.fetch("files"), allow_empty: false, pattern: BASENAME)
    }
  rescue KeyError
    unavailable!
  end

  def normalize_lifecycle_manifest(value)
    case value.is_a?(Hash) && value["schemaVersion"]
    when INPUT_SCHEMA_V3
      normalize_manifest_v3(value)
    when INPUT_SCHEMA_V2
      normalize_manifest_v2(value).merge(
        "schemaVersion" => INPUT_SCHEMA_V2,
        "evidenceSchemaVersion" => EVIDENCE_SCHEMA_V2
      )
    else
      unavailable!
    end
  end

  def normalize_manifest(value)
    raw = exact_object(
      value,
      %w[expectedCIWorkflowBlob expectedCommit expectedWorkflowBlob files localCITriggers localTriggers phase schemaVersion]
    )
    unavailable! unless raw.fetch("schemaVersion") == INPUT_SCHEMA && raw.fetch("phase") == PHASE
    expected_commit = exact_sha(raw.fetch("expectedCommit"))
    expected_blob = exact_sha(raw.fetch("expectedWorkflowBlob"))
    expected_ci_blob = exact_sha(raw.fetch("expectedCIWorkflowBlob"))
    triggers = normalize_local_trigger_projection(
      raw.fetch("localTriggers"),
      expected_path: RELEASE_WORKFLOW_PATH,
      expected_blob: expected_blob
    )
    ci_triggers = normalize_local_trigger_projection(
      raw.fetch("localCITriggers"),
      expected_path: CI_WORKFLOW_PATH,
      expected_blob: expected_ci_blob
    )
    files = canonical_strings(raw.fetch("files"), allow_empty: false, pattern: BASENAME)
    {
      "expectedCommit" => expected_commit,
      "expectedWorkflowBlob" => expected_blob,
      "expectedCIWorkflowBlob" => expected_ci_blob,
      "localTriggers" => triggers,
      "localCITriggers" => ci_triggers,
      "files" => files
    }
  rescue KeyError
    unavailable!
  end

  def normalize_ruleset_summary(value)
    raw = exact_object(value, %w[enforcement id name source source_type target])
    {
      "id" => positive_integer(raw.fetch("id")),
      "name" => exact_string(raw.fetch("name"), max_bytes: 100),
      "target" => exact_string(raw.fetch("target"), max_bytes: 32),
      "enforcement" => exact_string(raw.fetch("enforcement"), max_bytes: 32),
      "sourceType" => exact_string(raw.fetch("source_type"), max_bytes: 64),
      "source" => exact_string(raw.fetch("source"), max_bytes: 256)
    }
  rescue KeyError
    unavailable!
  end

  def ruleset_summaries(values)
    summaries = values.map { |value| normalize_ruleset_summary(value) }
    unavailable! unless summaries.map { |summary| summary.fetch("id") }.uniq.length == summaries.length
    summaries.sort_by { |summary| summary.fetch("id") }
  end

  def nullable_nonnegative_integer(value)
    return nil if value.nil?

    nonnegative_integer(value)
  end

  def normalize_rule(value)
    raw = value.is_a?(Hash) ? value : unavailable!
    unavailable! unless raw.keys.all? { |key| key.is_a?(String) }
    type = exact_string(raw.fetch("type"), max_bytes: 100)

    case type
    when "creation", "deletion", "non_fast_forward"
      exact_object(raw, %w[type])
      { "type" => type }
    when "update"
      exact_object(raw, %w[parameters type])
      parameters = exact_object(raw.fetch("parameters"), %w[update_allows_fetch_and_merge])
      {
        "type" => type,
        "parameters" => {
          "updateAllowsFetchAndMerge" => exact_boolean(parameters.fetch("update_allows_fetch_and_merge"))
        }
      }
    when "pull_request"
      exact_object(raw, %w[parameters type])
      parameters = exact_object(
        raw.fetch("parameters"),
        %w[dismiss_stale_reviews_on_push require_code_owner_review require_last_push_approval required_approving_review_count required_review_thread_resolution]
      )
      {
        "type" => type,
        "parameters" => {
          "dismissStaleReviewsOnPush" => exact_boolean(parameters.fetch("dismiss_stale_reviews_on_push")),
          "requireCodeOwnerReview" => exact_boolean(parameters.fetch("require_code_owner_review")),
          "requireLastPushApproval" => exact_boolean(parameters.fetch("require_last_push_approval")),
          "requiredApprovingReviewCount" => nonnegative_integer(parameters.fetch("required_approving_review_count")),
          "requiredReviewThreadResolution" => exact_boolean(parameters.fetch("required_review_thread_resolution"))
        }
      }
    when "required_status_checks"
      exact_object(raw, %w[parameters type])
      parameters = exact_object(
        raw.fetch("parameters"),
        %w[do_not_enforce_on_create required_status_checks strict_required_status_checks_policy]
      )
      checks = exact_array(parameters.fetch("required_status_checks")).map do |value|
        check = exact_object(value, %w[context integration_id])
        {
          "context" => exact_string(check.fetch("context"), max_bytes: 256),
          "integrationId" => nullable_nonnegative_integer(check.fetch("integration_id"))
        }
      end
      checks.sort_by! { |check| [check.fetch("context"), check.fetch("integrationId") || -1] }
      unavailable! unless checks.uniq == checks
      {
        "type" => type,
        "parameters" => {
          "strictRequiredStatusChecksPolicy" => exact_boolean(parameters.fetch("strict_required_status_checks_policy")),
          "doNotEnforceOnCreate" => exact_boolean(parameters.fetch("do_not_enforce_on_create")),
          "requiredStatusChecks" => checks
        }
      }
    else
      unavailable! unless [1, 2].include?(raw.length)
      unavailable! unless raw.keys.sort == %w[type] || raw.keys.sort == %w[parameters type]
      unavailable! if raw.key?("parameters") && !raw.fetch("parameters").is_a?(Hash)
      { "type" => type }
    end
  rescue KeyError
    unavailable!
  end

  def normalize_conditions(value)
    raw = exact_object(value, %w[ref_name])
    ref_name = exact_object(raw.fetch("ref_name"), %w[exclude include])
    includes = canonical_strings(ref_name.fetch("include"))
    excludes = canonical_strings(ref_name.fetch("exclude"))
    { "include" => includes, "exclude" => excludes }
  rescue KeyError
    unavailable!
  end

  def normalize_bypasses(value, known_actors)
    bypasses = exact_array(value).map do |entry|
      raw = exact_object(entry, %w[actor_id actor_type bypass_mode])
      actor_id = positive_integer(raw.fetch("actor_id"))
      actor_type = exact_string(raw.fetch("actor_type"), max_bytes: 64)
      resolved = known_actors.find do |candidate|
        candidate.fetch("id") == actor_id && candidate.fetch("type") == actor_type
      end
      unavailable! unless resolved
      {
        "actor" => resolved,
        "bypassMode" => exact_string(raw.fetch("bypass_mode"), max_bytes: 64)
      }
    end
    bypasses.sort_by! { |entry| [entry.dig("actor", "id"), entry.fetch("bypassMode")] }
    unavailable! unless bypasses.uniq == bypasses
    bypasses
  rescue KeyError
    unavailable!
  end

  def normalize_ruleset_detail(value, summary, known_actors)
    raw = exact_object(
      value,
      %w[bypass_actors conditions enforcement id name rules source source_type target]
    )
    identity = normalize_ruleset_summary(
      "id" => raw.fetch("id"),
      "name" => raw.fetch("name"),
      "target" => raw.fetch("target"),
      "enforcement" => raw.fetch("enforcement"),
      "source_type" => raw.fetch("source_type"),
      "source" => raw.fetch("source")
    )
    unavailable! unless identity == summary

    conditions = normalize_conditions(raw.fetch("conditions"))
    base = identity.merge("conditions" => conditions)
    relevant = ruleset_applies_to?(base, target: "branch", ref: MASTER_REF, default_branch: true) ||
               ruleset_applies_to?(base, target: "tag", ref: RELEASE_TAG_REF)

    # Every listed ruleset detail must be present and must explicitly carry the
    # bypass_actors field. Rules and bypass identities outside the release refs
    # are intentionally not interpreted: an unrelated future GitHub rule type
    # cannot make the release-control observation unavailable.
    unless relevant
      exact_array(raw.fetch("bypass_actors")).each do |entry|
        exact_object(entry, %w[actor_id actor_type bypass_mode])
      end
      exact_array(raw.fetch("rules")).each do |rule|
        unavailable! unless rule.is_a?(Hash) && rule.keys.all? { |key| key.is_a?(String) }
        unavailable! unless rule.key?("type")
        exact_string(rule.fetch("type"), max_bytes: 100)
      end
      return nil
    end

    rules = exact_array(raw.fetch("rules")).map { |rule| normalize_rule(rule) }
    rules.sort_by! { |rule| [rule.fetch("type"), JSON.generate(rule)] }
    identity.merge(
      "conditions" => conditions,
      "bypassActors" => normalize_bypasses(raw.fetch("bypass_actors"), known_actors),
      "rules" => rules
    )
  rescue KeyError
    unavailable!
  end

  def pattern_matches?(pattern, ref, default_branch: false)
    pattern == "~ALL" ||
      (default_branch && pattern == "~DEFAULT_BRANCH") ||
      File.fnmatch?(pattern, ref, File::FNM_PATHNAME)
  end

  def ruleset_applies_to?(ruleset, target:, ref:, default_branch: false)
    return false unless ruleset.fetch("target") == target

    includes = ruleset.dig("conditions", "include")
    excludes = ruleset.dig("conditions", "exclude")
    includes.any? { |pattern| pattern_matches?(pattern, ref, default_branch: default_branch) } &&
      excludes.none? { |pattern| pattern_matches?(pattern, ref, default_branch: default_branch) }
  end

  def classify_rulesets(rulesets)
    master = rulesets.select do |ruleset|
      ruleset_applies_to?(ruleset, target: "branch", ref: MASTER_REF, default_branch: true)
    end
    tags = rulesets.select do |ruleset|
      ruleset_applies_to?(ruleset, target: "tag", ref: RELEASE_TAG_REF)
    end
    [master.sort_by { |ruleset| ruleset.fetch("id") }, tags.sort_by { |ruleset| ruleset.fetch("id") }]
  end

  def normalize_effective_master(values)
    items = values.map do |value|
      raw = exact_object(value, %w[rule ruleset_id ruleset_source ruleset_source_type])
      {
        "rulesetId" => positive_integer(raw.fetch("ruleset_id")),
        "sourceType" => exact_string(raw.fetch("ruleset_source_type"), max_bytes: 64),
        "source" => exact_string(raw.fetch("ruleset_source"), max_bytes: 256),
        "rule" => normalize_rule(raw.fetch("rule"))
      }
    end
    items.sort_by! { |item| [item.fetch("rulesetId"), item.dig("rule", "type"), JSON.generate(item)] }
    unavailable! unless items.uniq == items
    { "complete" => true, "items" => items }
  rescue KeyError
    unavailable!
  end

  def normalize_environment(value)
    raw = exact_object(value, %w[deployment_branch_policy name protection_rules])
    protection_rules = exact_array(raw.fetch("protection_rules"))
    grouped = protection_rules.group_by do |rule|
      unavailable! unless rule.is_a?(Hash) && rule.keys.all? { |key| key.is_a?(String) }
      exact_string(rule.fetch("type"), max_bytes: 64)
    end
    unavailable! unless grouped.keys.sort == %w[branch_policy required_reviewers]
    unavailable! unless grouped.values.all? { |entries| entries.length == 1 }

    exact_object(grouped.fetch("branch_policy").first, %w[type])
    reviewer_rule = exact_object(
      grouped.fetch("required_reviewers").first,
      %w[prevent_self_review reviewers type]
    )
    reviewers = exact_array(reviewer_rule.fetch("reviewers")).map do |entry|
      reviewer = exact_object(entry, %w[reviewer type])
      unavailable! unless reviewer.fetch("type") == "User"
      actor(reviewer.fetch("reviewer"))
    end
    reviewers.sort_by! { |reviewer| [reviewer.fetch("id"), reviewer.fetch("login")] }
    unavailable! unless reviewers.uniq == reviewers

    deployment = exact_object(
      raw.fetch("deployment_branch_policy"),
      %w[custom_branch_policies protected_branches]
    )
    {
      "name" => exact_string(raw.fetch("name"), max_bytes: 255),
      "protection" => {
        "preventSelfReview" => exact_boolean(reviewer_rule.fetch("prevent_self_review")),
        "reviewers" => reviewers
      },
      "deployment" => {
        "protectedBranches" => exact_boolean(deployment.fetch("protected_branches")),
        "customBranchPolicies" => exact_boolean(deployment.fetch("custom_branch_policies"))
      }
    }
  rescue KeyError
    unavailable!
  end

  def paged_items(values)
    unavailable! if values.empty?
    total_count = nil
    items = []
    values.each do |value|
      page = exact_object(value, %w[items total_count])
      observed_total = nonnegative_integer(page.fetch("total_count"))
      total_count ||= observed_total
      unavailable! unless total_count == observed_total
      items.concat(exact_array(page.fetch("items")))
    end
    unavailable! unless items.length == total_count
    items
  rescue KeyError
    unavailable!
  end

  def normalize_active_workflow_inventory(values)
    workflows = paged_items(values).map do |value|
      raw = exact_object(value, %w[id name path state])
      {
        "id" => positive_integer(raw.fetch("id")),
        "name" => exact_string(raw.fetch("name"), max_bytes: 100),
        "path" => exact_string(raw.fetch("path"), max_bytes: 256),
        "state" => exact_string(raw.fetch("state"), max_bytes: 64)
      }
    end
    unavailable! unless workflows.map { |workflow| workflow["id"] }.uniq.length == workflows.length
    unavailable! unless workflows.map { |workflow| workflow["path"] }.uniq.length == workflows.length
    workflows.sort_by! { |workflow| workflow["path"] }
    { "complete" => true, "items" => workflows }
  rescue KeyError
    unavailable!
  end

  def normalize_pre_publication_refs(values)
    refs = values.map do |value|
      raw = exact_object(value, %w[commit_sha object_sha object_type ref])
      {
        "ref" => exact_string(raw.fetch("ref"), max_bytes: 256),
        "objectType" => exact_string(raw.fetch("object_type"), max_bytes: 32),
        "objectSha" => exact_sha(raw.fetch("object_sha")),
        "commitSha" => exact_sha(raw.fetch("commit_sha"))
      }
    end
    refs.sort_by! { |ref| ref["ref"] }
    unavailable! unless refs.map { |ref| ref["ref"] }.uniq.length == refs.length
    { "complete" => true, "items" => refs }
  rescue KeyError
    unavailable!
  end

  def normalize_pre_publication_releases(values)
    releases = values.map do |value|
      raw = exact_object(value, %w[draft id prerelease tag_name])
      {
        "id" => positive_integer(raw.fetch("id")),
        "tag" => exact_string(raw.fetch("tag_name"), max_bytes: 256),
        "draft" => exact_boolean(raw.fetch("draft")),
        "prerelease" => exact_boolean(raw.fetch("prerelease"))
      }
    end
    releases.sort_by! { |release| release["id"] }
    unavailable! unless releases.map { |release| release["id"] }.uniq.length == releases.length
    unavailable! unless releases.map { |release| release["tag"] }.uniq.length == releases.length
    { "complete" => true, "items" => releases }
  rescue KeyError
    unavailable!
  end

  def paged_names(values)
    unavailable! if values.empty?
    total_count = nil
    names = []
    values.each do |value|
      page = exact_object(value, %w[names total_count])
      observed_total = nonnegative_integer(page.fetch("total_count"))
      total_count ||= observed_total
      unavailable! unless total_count == observed_total
      names.concat(exact_array(page.fetch("names")).map { |name| exact_string(name, pattern: NAME) })
    end
    names.sort!
    unavailable! unless names.length == total_count && names.uniq == names
    names
  rescue KeyError
    unavailable!
  end

  def deployment_policies(values)
    policies = paged_items(values).map do |value|
      raw = exact_object(value, %w[name type])
      {
        "name" => exact_string(raw.fetch("name"), max_bytes: 256),
        "type" => exact_string(raw.fetch("type"), max_bytes: 32)
      }
    end
    policies.sort_by! { |policy| [policy.fetch("type"), policy.fetch("name")] }
    unavailable! unless policies.uniq == policies
    policies
  rescue KeyError
    unavailable!
  end

  def normalize_actions(input_directory)
    permissions = exact_object(
      read_json(input_directory, "actions-permissions.json"),
      %w[allowed_actions enabled sha_pinning_required]
    )
    selected = exact_object(
      read_json(input_directory, "selected-actions.json"),
      %w[github_owned_allowed patterns_allowed verified_allowed]
    )
    workflow = exact_object(
      read_json(input_directory, "workflow-permissions.json"),
      %w[can_approve_pull_request_reviews default_workflow_permissions]
    )
    patterns = exact_array(selected.fetch("patterns_allowed")).map do |pattern|
      exact_string(pattern, max_bytes: 256)
    end.sort
    unavailable! unless patterns.uniq == patterns
    {
      "enabled" => exact_boolean(permissions.fetch("enabled")),
      "allowedActions" => exact_string(permissions.fetch("allowed_actions"), max_bytes: 32),
      "shaPinningRequired" => exact_boolean(permissions.fetch("sha_pinning_required")),
      "selectedActions" => {
        "githubOwnedAllowed" => exact_boolean(selected.fetch("github_owned_allowed")),
        "verifiedAllowed" => exact_boolean(selected.fetch("verified_allowed")),
        "patternsAllowed" => patterns
      },
      "workflowPermissions" => {
        "defaultWorkflowPermissions" => exact_string(workflow.fetch("default_workflow_permissions"), max_bytes: 32),
        "canApprovePullRequestReviews" => exact_boolean(workflow.fetch("can_approve_pull_request_reviews"))
      }
    }
  rescue KeyError
    unavailable!
  end

  def normalize_check_runs(values)
    runs = paged_items(values).map do |value|
      raw = exact_object(value, %w[app_id check_suite_id conclusion head_sha id name status])
      {
        "id" => positive_integer(raw.fetch("id")),
        "name" => exact_string(raw.fetch("name"), max_bytes: 256),
        "appId" => positive_integer(raw.fetch("app_id")),
        "checkSuiteId" => positive_integer(raw.fetch("check_suite_id")),
        "headSha" => exact_sha(raw.fetch("head_sha")),
        "status" => exact_string(raw.fetch("status"), max_bytes: 32),
        "conclusion" => nullable_string(raw.fetch("conclusion"), max_bytes: 32)
      }
    end
    runs.sort_by! { |run| run.fetch("id") }
    unavailable! unless runs.map { |run| run.fetch("id") }.uniq.length == runs.length
    runs
  rescue KeyError
    unavailable!
  end

  def normalize_workflow_runs(values)
    runs = paged_items(values).map do |value|
      raw = exact_object(
        value,
        %w[check_suite_id conclusion event head_branch head_sha id path run_attempt status workflow_id]
      )
      {
        "id" => positive_integer(raw.fetch("id")),
        "workflowId" => positive_integer(raw.fetch("workflow_id")),
        "checkSuiteId" => positive_integer(raw.fetch("check_suite_id")),
        "path" => exact_string(raw.fetch("path"), max_bytes: 256),
        "event" => exact_string(raw.fetch("event"), max_bytes: 64),
        "headBranch" => exact_string(raw.fetch("head_branch"), max_bytes: 256),
        "headSha" => exact_sha(raw.fetch("head_sha")),
        "runAttempt" => positive_integer(raw.fetch("run_attempt")),
        "status" => exact_string(raw.fetch("status"), max_bytes: 32),
        "conclusion" => nullable_string(raw.fetch("conclusion"), max_bytes: 32)
      }
    end
    runs.sort_by! { |run| [run.fetch("runAttempt"), run.fetch("id")] }
    identities = runs.map { |run| [run.fetch("id"), run.fetch("runAttempt")] }
    unavailable! unless identities.uniq.length == identities.length
    runs
  rescue KeyError
    unavailable!
  end

  def latest_workflow_run(runs)
    unavailable! if runs.empty?
    unavailable! unless runs.map { |run| run.fetch("id") }.uniq.length == 1
    maximum_attempt = runs.map { |run| run.fetch("runAttempt") }.max
    latest = runs.select { |run| run.fetch("runAttempt") == maximum_attempt }
    unavailable! unless latest.length == 1
    latest.first
  rescue KeyError
    unavailable!
  end

  def check_run_id_from_url(value, repository_full_name = nil)
    url = exact_string(value, max_bytes: 2048)
    if repository_full_name
      prefix = "https://api.github.com/repos/#{repository_full_name}/check-runs/"
      unavailable! unless url.start_with?(prefix)
      suffix = url.delete_prefix(prefix)
    else
      match = url.match(
        %r{\Ahttps://api\.github\.com/repos/[A-Za-z0-9.-]+/[A-Za-z0-9_.-]+/check-runs/([1-9][0-9]*)\z}
      )
      unavailable! unless match
      suffix = match[1]
      prefix = url.delete_suffix(suffix)
    end
    unavailable! unless suffix.match?(/\A[1-9][0-9]*\z/)
    check_run_id = positive_integer(Integer(suffix, 10))
    unavailable! unless url == "#{prefix}#{check_run_id}"
    check_run_id
  rescue ArgumentError
    unavailable!
  end

  def normalize_workflow_jobs(values, repository_full_name = nil)
    jobs = paged_items(values).map do |value|
      raw = exact_object(
        value,
        %w[check_run_url conclusion head_branch head_sha id name run_attempt run_id status workflow_name]
      )
      id = positive_integer(raw.fetch("id"))
      check_run_id = check_run_id_from_url(raw.fetch("check_run_url"), repository_full_name)
      {
        "id" => id,
        "runId" => positive_integer(raw.fetch("run_id")),
        "runAttempt" => positive_integer(raw.fetch("run_attempt")),
        "checkRunId" => check_run_id,
        "name" => exact_string(raw.fetch("name"), max_bytes: 256),
        "workflowName" => exact_string(raw.fetch("workflow_name"), max_bytes: 100),
        "headBranch" => exact_string(raw.fetch("head_branch"), max_bytes: 256),
        "headSha" => exact_sha(raw.fetch("head_sha")),
        "status" => exact_string(raw.fetch("status"), max_bytes: 32),
        "conclusion" => nullable_string(raw.fetch("conclusion"), max_bytes: 32)
      }
    end
    jobs.sort_by! { |job| [job.fetch("runId"), job.fetch("runAttempt"), job.fetch("id")] }
    identities = jobs.map { |job| [job.fetch("runId"), job.fetch("runAttempt"), job.fetch("id")] }
    unavailable! unless identities.uniq.length == identities.length
    jobs
  rescue KeyError
    unavailable!
  end

  def boundary_refs(values)
    values.map do |value|
      raw = exact_object(value, %w[ref])
      exact_string(raw.fetch("ref"), max_bytes: 256)
      { "present" => true }
    end
  rescue KeyError
    unavailable!
  end

  def boundary_releases(values)
    values.map do |value|
      raw = exact_object(value, %w[id])
      positive_integer(raw.fetch("id"))
      { "present" => true }
    end
  rescue KeyError
    unavailable!
  end

  def normalize_security(input_directory)
    reporting = exact_object(
      read_json(input_directory, "private-vulnerability-reporting.json"),
      %w[enabled]
    )
    immutable = exact_object(
      read_json(input_directory, "immutable-releases.json"),
      %w[enabled enforced_by_owner]
    )
    {
      "privateVulnerabilityReporting" => exact_boolean(reporting.fetch("enabled")),
      "immutableReleases" => {
        "enabled" => exact_boolean(immutable.fetch("enabled")),
        "enforcedByOwner" => exact_boolean(immutable.fetch("enforced_by_owner"))
      }
    }
  rescue KeyError
    unavailable!
  end

  def manifest_detail_files(count)
    unavailable! unless count.is_a?(Integer) && count >= 0 && count <= 9999
    Array.new(count) { |index| format("ruleset-detail-%04d.json", index + 1) }
  end

  def verify_manifest_files(manifest, summaries)
    expected = (STATIC_INPUT_FILES + manifest_detail_files(summaries.length)).sort
    unavailable! unless manifest.fetch("files") == expected
    expected
  end

  def verify_manifest_files_v2(manifest, summaries)
    expected = (
      STATIC_INPUT_FILES + LIFECYCLE_EXTRA_INPUT_FILES + manifest_detail_files(summaries.length)
    ).sort
    unavailable! unless manifest.fetch("files") == expected
    expected
  end

  def normalize_scoped_environment(input_directory, prefix: "")
    environment = normalize_environment(read_json(input_directory, "#{prefix}environment.json"))
    environment.fetch("deployment")["policies"] = deployment_policies(
      read_json_lines(input_directory, "#{prefix}deployment-policies.json")
    )
    environment["secrets"] = {
      "complete" => true,
      "names" => paged_names(read_json_lines(input_directory, "#{prefix}environment-secrets.json"))
    }
    environment["variables"] = {
      "complete" => true,
      "names" => paged_names(
        read_json_lines(input_directory, "#{prefix}environment-variable-names.json")
      )
    }
    environment
  end

  def secure_atomic_write(path, bytes)
    unavailable! unless path.is_a?(String) && !path.empty?
    expanded = File.expand_path(path)
    directory = File.dirname(expanded)
    directory_stat = File.lstat(directory)
    unavailable! if directory_stat.symlink? || !directory_stat.directory?
    if File.exist?(expanded) || File.symlink?(expanded)
      current = File.lstat(expanded)
      unavailable! if current.symlink? || !current.file?
    end

    Tempfile.create([".remote-controls-evidence-", ".tmp"], directory) do |temp|
      temp.binmode
      temp.chmod(0o600)
      temp.write(bytes)
      temp.flush
      temp.fsync
      temp.close
      File.rename(temp.path, expanded)
    end
    written = File.lstat(expanded)
    unavailable! unless written.file? && !written.symlink? && (written.mode & 0o777) == 0o600
  rescue SystemCallError
    unavailable!
  end

  def emit_evidence(evidence, output_path)
    bytes = JSON.pretty_generate(evidence) << "\n"
    if output_path.nil? || output_path == "-"
      $stdout.write(bytes)
    else
      secure_atomic_write(output_path, bytes)
    end
  end

  def collect(input_directory:, output_path: nil)
    input_directory = require_secure_directory(input_directory)
    manifest = normalize_manifest(
      read_json(input_directory, "manifest.json", max_bytes: MAX_MANIFEST_BYTES)
    )

    repository = normalize_repository(read_json(input_directory, "repository.json"))
    viewer = authenticated_viewer(
      read_json(input_directory, "viewer.json"),
      read_json(input_directory, "permission.json")
    )

    anchors = [1, 2].map do |sequence|
      master = master_anchor(read_json(input_directory, "master-#{sequence}.json"))
      release_content = decoded_workflow_content(
        read_json(input_directory, "workflow-content-#{sequence}.json", max_bytes: MAX_WORKFLOW_BYTES * 2),
        master.fetch("commitSha"),
        expected_path: RELEASE_WORKFLOW_PATH
      )
      if release_content.fetch("blobSha") == manifest.fetch("expectedWorkflowBlob")
        unavailable! unless release_content.fetch("triggers") == manifest.fetch("localTriggers")
      end
      ci_content = decoded_workflow_content(
        read_json(input_directory, "ci-workflow-content-#{sequence}.json", max_bytes: MAX_WORKFLOW_BYTES * 2),
        master.fetch("commitSha"),
        expected_path: CI_WORKFLOW_PATH
      )
      if ci_content.fetch("blobSha") == manifest.fetch("expectedCIWorkflowBlob")
        unavailable! unless ci_content.fetch("triggers") == manifest.fetch("localCITriggers")
      end
      {
        "sequence" => sequence,
        "master" => master,
        "releaseWorkflow" => workflow_metadata(
          read_json(input_directory, "workflow-metadata-#{sequence}.json"),
          release_content,
          expected_path: RELEASE_WORKFLOW_PATH
        ),
        "ciWorkflow" => workflow_metadata(
          read_json(input_directory, "ci-workflow-metadata-#{sequence}.json"),
          ci_content,
          expected_path: CI_WORKFLOW_PATH
        )
      }
    end

    environment = normalize_environment(read_json(input_directory, "environment.json"))
    environment.fetch("deployment")["policies"] = deployment_policies(
      read_json_lines(input_directory, "deployment-policies.json")
    )
    environment["secrets"] = {
      "complete" => true,
      "names" => paged_names(read_json_lines(input_directory, "environment-secrets.json"))
    }
    environment["variables"] = {
      "complete" => true,
      "names" => paged_names(read_json_lines(input_directory, "environment-variable-names.json"))
    }

    summary_values = read_json_lines(input_directory, "ruleset-ids.json", allow_empty: true)
    summaries = ruleset_summaries(summary_values)
    input_files = verify_manifest_files(manifest, summaries)

    known_actors = [repository.fetch("owner"), viewer.fetch("actor")] +
                   environment.dig("protection", "reviewers")
    known_actors = known_actors.uniq
    grouped_ids = known_actors.group_by { |candidate| candidate.fetch("id") }
    unavailable! unless grouped_ids.values.all? { |actors| actors.uniq.length == 1 }

    rulesets = summaries.each_with_index.filter_map do |summary, index|
      filename = format("ruleset-detail-%04d.json", index + 1)
      normalize_ruleset_detail(read_json(input_directory, filename), summary, known_actors)
    end
    master_rulesets, tag_rulesets = classify_rulesets(rulesets)

    private_label = exact_object(read_json(input_directory, "label.json"), %w[name present])
    checks = normalize_check_runs(read_json_lines(input_directory, "check-runs.json"))
    workflow_runs = normalize_workflow_runs(read_json_lines(input_directory, "workflow-runs.json"))
    workflow_jobs = normalize_workflow_jobs(
      read_json_lines(input_directory, "workflow-jobs.json"),
      repository.fetch("fullName")
    )

    evidence = {
      "schemaVersion" => EVIDENCE_SCHEMA,
      "phase" => PHASE,
      "repository" => repository,
      "authenticatedViewer" => viewer,
      "anchorReads" => anchors,
      "workflow" => anchors.last.fetch("releaseWorkflow").merge(
        "commitSha" => anchors.last.dig("master", "commitSha")
      ),
      "ciWorkflow" => anchors.last.fetch("ciWorkflow").merge(
        "commitSha" => anchors.last.dig("master", "commitSha")
      ),
      "rulesets" => {
        "complete" => true,
        "master" => master_rulesets,
        "tags" => tag_rulesets,
        "effectiveMaster" => normalize_effective_master(
          read_json_lines(input_directory, "effective-master.json", allow_empty: true)
        )
      },
      "environment" => environment,
      "repositoryConfiguration" => {
        "secrets" => {
          "complete" => true,
          "names" => paged_names(read_json_lines(input_directory, "repository-secrets.json"))
        },
        "variables" => {
          "complete" => true,
          "names" => paged_names(read_json_lines(input_directory, "repository-variable-names.json"))
        }
      },
      "security" => normalize_security(input_directory),
      "actions" => normalize_actions(input_directory),
      "labels" => {
        "needsTriage" => {
          "name" => exact_string(private_label.fetch("name"), max_bytes: 100),
          "present" => exact_boolean(private_label.fetch("present"))
        }
      },
      "releaseBoundary" => {
        "vRefs" => {
          "complete" => true,
          "items" => boundary_refs(
            read_json_lines(input_directory, "v-refs.json", allow_empty: true)
          )
        },
        "releases" => {
          "complete" => true,
          "items" => boundary_releases(
            read_json_lines(input_directory, "releases.json", allow_empty: true)
          )
        }
      },
      "ci" => {
        "commitSha" => manifest.fetch("expectedCommit"),
        "workflowRuns" => { "complete" => true, "items" => workflow_runs },
        "jobs" => { "complete" => true, "items" => workflow_jobs },
        "checkRuns" => { "complete" => true, "items" => checks }
      }
    }

    if output_path && output_path != "-"
      expanded_output = File.expand_path(output_path)
      input_paths = (["manifest.json"] + input_files).map do |name|
        File.expand_path(File.join(input_directory, name))
      end
      unavailable! if input_paths.include?(expanded_output)
    end
    emit_evidence(evidence, output_path)
    checks.length
  rescue KeyError
    unavailable!
  end

  def collect_lifecycle(input_directory:, output_path: nil)
    input_directory = require_secure_directory(input_directory)
    manifest = normalize_lifecycle_manifest(
      read_json(input_directory, "manifest.json", max_bytes: MAX_MANIFEST_BYTES)
    )

    repository = normalize_repository(read_json(input_directory, "repository.json"))
    viewer = authenticated_viewer(
      read_json(input_directory, "viewer.json"),
      read_json(input_directory, "permission.json")
    )

    workflow_specs = {
      "candidateWorkflow" => {
        path: RELEASE_WORKFLOW_PATH,
        content: "workflow-content",
        metadata: "workflow-metadata",
        blob: manifest.fetch("expectedWorkflowBlob"),
        local: manifest.fetch("localCandidateWorkflow")
      },
      "ciWorkflow" => {
        path: CI_WORKFLOW_PATH,
        content: "ci-workflow-content",
        metadata: "ci-workflow-metadata",
        blob: manifest.fetch("expectedCIWorkflowBlob"),
        local: manifest.fetch("localCIWorkflow")
      },
      "publicationWorkflow" => {
        path: PUBLICATION_WORKFLOW_PATH,
        content: "publication-workflow-content",
        metadata: "publication-workflow-metadata",
        blob: manifest.fetch("expectedPublicationWorkflowBlob"),
        local: manifest.fetch("localPublicationWorkflow")
      },
      "legacyWorkflow" => {
        path: LEGACY_WORKFLOW_PATH,
        content: "legacy-workflow-content",
        metadata: "legacy-workflow-metadata",
        blob: manifest.fetch("expectedLegacyWorkflowBlob"),
        local: manifest.fetch("localLegacyWorkflow")
      }
    }.freeze

    anchors = [1, 2].map do |sequence|
      master = master_anchor(read_json(input_directory, "master-#{sequence}.json"))
      workflows = workflow_specs.to_h do |name, specification|
        content = decoded_workflow_content(
          read_json(
            input_directory,
            "#{specification.fetch(:content)}-#{sequence}.json",
            max_bytes: MAX_WORKFLOW_BYTES * 2
          ),
          master.fetch("commitSha"),
          expected_path: specification.fetch(:path)
        )
        unavailable! unless content.fetch("blobSha") == specification.fetch(:blob)
        unavailable! unless content.fetch("triggers") == specification.dig(:local, "triggers")
        unavailable! unless content.fetch("contentsWrite") == specification.dig(:local, "contentsWrite")
        metadata = workflow_metadata(
          read_json(input_directory, "#{specification.fetch(:metadata)}-#{sequence}.json"),
          content,
          expected_path: specification.fetch(:path)
        )
        [name, metadata]
      end
      { "sequence" => sequence, "master" => master }.merge(workflows)
    end

    candidate_environment = normalize_scoped_environment(input_directory)
    publication_environment = normalize_scoped_environment(input_directory, prefix: "publication-")
    summary_values = read_json_lines(input_directory, "ruleset-ids.json", allow_empty: true)
    summaries = ruleset_summaries(summary_values)
    input_files = verify_manifest_files_v2(manifest, summaries)

    known_actors = [repository.fetch("owner"), viewer.fetch("actor")] +
                   candidate_environment.dig("protection", "reviewers") +
                   publication_environment.dig("protection", "reviewers")
    known_actors = known_actors.uniq
    grouped_ids = known_actors.group_by { |candidate| candidate.fetch("id") }
    unavailable! unless grouped_ids.values.all? { |actors| actors.uniq.length == 1 }

    rulesets = summaries.each_with_index.filter_map do |summary, index|
      filename = format("ruleset-detail-%04d.json", index + 1)
      normalize_ruleset_detail(read_json(input_directory, filename), summary, known_actors)
    end
    master_rulesets, tag_rulesets = classify_rulesets(rulesets)

    latest_anchor = anchors.last
    full_workflows = workflow_specs.to_h do |name, specification|
      workflow = latest_anchor.fetch(name).merge(
        "commitSha" => latest_anchor.dig("master", "commitSha"),
        "contentsWrite" => specification.dig(:local, "contentsWrite")
      )
      [name, workflow]
    end
    raw_inventory = normalize_active_workflow_inventory(
      read_json_lines(input_directory, "active-workflows.json")
    )
    expected_inventory_identities = full_workflows.values.map do |workflow|
      workflow.slice("id", "name", "path", "state")
    end.sort_by { |workflow| workflow.fetch("path") }
    unavailable! unless raw_inventory.fetch("items") == expected_inventory_identities
    workflow_inventory = {
      "complete" => true,
      "items" => full_workflows.values.sort_by { |workflow| workflow.fetch("path") }
    }

    checks = normalize_check_runs(read_json_lines(input_directory, "check-runs.json"))
    workflow_runs = normalize_workflow_runs(read_json_lines(input_directory, "workflow-runs.json"))
    workflow_jobs = normalize_workflow_jobs(
      read_json_lines(input_directory, "workflow-jobs.json"),
      repository.fetch("fullName")
    )
    private_label = exact_object(read_json(input_directory, "label.json"), %w[name present])
    if manifest.fetch("schemaVersion") == INPUT_SCHEMA_V3
      boundary = {
        "vRefs" => normalize_pre_publication_refs(
          read_json_lines(input_directory, "v-refs.json", allow_empty: true)
        ),
        "releases" => normalize_pre_publication_releases(
          read_json_lines(input_directory, "releases.json", allow_empty: true)
        )
      }
    elsif manifest.fetch("phase") == PHASE
      boundary = {
        "vRefs" => {
          "complete" => true,
          "items" => boundary_refs(read_json_lines(input_directory, "v-refs.json", allow_empty: true))
        },
        "releases" => {
          "complete" => true,
          "items" => boundary_releases(
            read_json_lines(input_directory, "releases.json", allow_empty: true)
          )
        }
      }
    else
      boundary = {
        "vRefs" => normalize_pre_publication_refs(
          read_json_lines(input_directory, "v-refs.json", allow_empty: true)
        ),
        "releases" => normalize_pre_publication_releases(
          read_json_lines(input_directory, "releases.json", allow_empty: true)
        )
      }
    end

    evidence = {
      "schemaVersion" => manifest.fetch("evidenceSchemaVersion"),
      "phase" => manifest.fetch("phase"),
      "collectedAt" => manifest.fetch("collectedAt"),
      "repository" => repository,
      "authenticatedViewer" => viewer,
      "anchorReads" => anchors,
      "candidateWorkflow" => full_workflows.fetch("candidateWorkflow"),
      "ciWorkflow" => full_workflows.fetch("ciWorkflow"),
      "publicationWorkflow" => full_workflows.fetch("publicationWorkflow"),
      "legacyWorkflow" => full_workflows.fetch("legacyWorkflow"),
      "workflowInventory" => workflow_inventory,
      "rulesets" => {
        "complete" => true,
        "master" => master_rulesets,
        "tags" => tag_rulesets,
        "effectiveMaster" => normalize_effective_master(
          read_json_lines(input_directory, "effective-master.json", allow_empty: true)
        )
      },
      "environments" => {
        "releaseCandidate" => candidate_environment,
        "releasePublication" => publication_environment
      },
      "repositoryConfiguration" => {
        "secrets" => {
          "complete" => true,
          "names" => paged_names(read_json_lines(input_directory, "repository-secrets.json"))
        },
        "variables" => {
          "complete" => true,
          "names" => paged_names(read_json_lines(input_directory, "repository-variable-names.json"))
        }
      },
      "manualEvidence" => manifest.fetch("manualEvidence"),
      "security" => normalize_security(input_directory),
      "actions" => normalize_actions(input_directory),
      "labels" => {
        "needsTriage" => {
          "name" => exact_string(private_label.fetch("name"), max_bytes: 100),
          "present" => exact_boolean(private_label.fetch("present"))
        }
      },
      "releaseBoundary" => boundary,
      "ci" => {
        "commitSha" => manifest.fetch("expectedCommit"),
        "workflowRuns" => { "complete" => true, "items" => workflow_runs },
        "jobs" => { "complete" => true, "items" => workflow_jobs },
        "checkRuns" => { "complete" => true, "items" => checks }
      }
    }
    if manifest.fetch("schemaVersion") == INPUT_SCHEMA_V3
      evidence["predecessorPreTagEvidenceSHA256"] =
        manifest.fetch("predecessorPreTagEvidenceSHA256")
      evidence["finalPreTagEvidenceSHA256"] = manifest.fetch("finalPreTagEvidenceSHA256")
    else
      evidence["finalPreTagEvidenceSHA256"] = manifest.fetch("finalPreTagEvidenceSHA256")
    end

    if output_path && output_path != "-"
      expanded_output = File.expand_path(output_path)
      input_paths = (["manifest.json"] + input_files).map do |name|
        File.expand_path(File.join(input_directory, name))
      end
      unavailable! if input_paths.include?(expanded_output)
    end
    emit_evidence(evidence, output_path)
    checks.length
  rescue KeyError
    unavailable!
  end

  def parse_options(argv, allowed:, required:)
    options = {}
    seen = {}
    parser = OptionParser.new do |option|
      {
        "--input-dir DIR" => :input_directory,
        "--input FILE" => :input,
        "--workflow FILE" => :workflow_path,
        "--output FILE" => :output_path,
        "--control NAME" => :control,
        "--permission-profile NAME" => :permission_profile,
        "--actor-id ID" => :actor_id,
        "--actor-login LOGIN" => :actor_login,
        "--verified-at TIME" => :verified_at,
        "--phase PHASE" => :phase,
        "--freshness-mode MODE" => :freshness_mode,
        "--release-commit SHA" => :release_commit,
        "--release-id ID" => :release_id,
        "--release-tag-object SHA" => :release_tag_object
      }.each do |specification, key|
        option.on(specification) do |value|
          unavailable! if seen[key]
          seen[key] = true
          options[key] = value
        end
      end
    end
    parser.parse!(argv)
    unavailable! unless argv.empty?
    unavailable! unless options.keys.all? { |key| allowed.include?(key) }
    unavailable! unless required.all? { |key| options.key?(key) }
    options
  rescue OptionParser::ParseError
    unavailable!
  end

  def run_cli(argv)
    command = argv.shift
    case command
    when "local-triggers"
      options = parse_options(argv, allowed: %i[workflow_path], required: %i[workflow_path])
      puts JSON.generate(local_triggers(options.fetch(:workflow_path)))
    when "local-workflow-security"
      options = parse_options(argv, allowed: %i[workflow_path], required: %i[workflow_path])
      puts JSON.generate(local_workflow_security(options.fetch(:workflow_path)))
    when "master-sha"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      value = ReleasePolicy.strict_json(
        options.fetch(:input),
        "master projection",
        max_bytes: MAX_PROJECTION_BYTES
      )
      puts master_anchor(value).fetch("commitSha")
    when "ruleset-ids"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      summaries = ruleset_summaries(strict_json_lines(options.fetch(:input), allow_empty: true))
      summaries.each { |summary| puts summary.fetch("id") }
    when "check-suite-id"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      runs = normalize_check_runs(strict_json_lines(options.fetch(:input)))
      unavailable! if runs.empty?
      check_suite_ids = runs.map { |run| run.fetch("checkSuiteId") }.uniq
      puts exact_array(check_suite_ids, length: 1).first
    when "workflow-run-id", "workflow-run-attempt"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      run = latest_workflow_run(normalize_workflow_runs(strict_json_lines(options.fetch(:input))))
      key = command == "workflow-run-id" ? "id" : "runAttempt"
      puts run.fetch(key)
    when "workflow-job-id"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      jobs = normalize_workflow_jobs(strict_json_lines(options.fetch(:input)))
      primary = jobs.select { |job| job.fetch("name") == PRIMARY_CI_JOB_NAME }
      puts exact_array(primary, length: 1).first.fetch("id")
    when "active-workflow-inventory"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      value = normalize_active_workflow_inventory(strict_json_lines(options.fetch(:input)))
      puts JSON.generate(value)
    when "pre-publication-refs"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      value = normalize_pre_publication_refs(strict_json_lines(options.fetch(:input), allow_empty: true))
      puts JSON.generate(value)
    when "pre-publication-releases"
      options = parse_options(argv, allowed: %i[input], required: %i[input])
      value = normalize_pre_publication_releases(strict_json_lines(options.fetch(:input), allow_empty: true))
      puts JSON.generate(value)
    when "manual-evidence"
      options = parse_options(
        argv,
        allowed: %i[
          input control permission_profile actor_id actor_login verified_at phase release_commit
          release_id release_tag_object freshness_mode
        ],
        required: %i[
          input control permission_profile actor_id actor_login verified_at phase
        ]
      )
      actor_id = Integer(options.fetch(:actor_id), 10)
      release_id = options[:release_id]&.then { |value| Integer(value, 10) }
      value = manual_evidence(
        path: options.fetch(:input),
        expected_control: options.fetch(:control),
        permission_profile: options.fetch(:permission_profile),
        actor_id: actor_id,
        actor_login: options.fetch(:actor_login),
        verified_at: options.fetch(:verified_at),
        phase: options.fetch(:phase),
        release_commit: options[:release_commit],
        release_id: release_id,
        release_tag_object: options[:release_tag_object],
        freshness_mode: options.fetch(:freshness_mode, "current")
      )
      puts JSON.generate(value)
    when "collect", "collect-lifecycle"
      options = parse_options(
        argv,
        allowed: %i[input_directory output_path],
        required: %i[input_directory]
      )
      count = command == "collect" ? collect(**options) : collect_lifecycle(**options)
      puts count if options[:output_path] && options[:output_path] != "-"
    else
      unavailable!
    end
    0
  rescue ReleasePolicy::PolicyError
    unavailable!
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit RemoteControlsCollector.run_cli(ARGV.dup)
  rescue RemoteControlsCollector::CollectionUnavailable
    warn "ERROR: remote controls evidence unavailable"
    exit 70
  rescue StandardError
    warn "ERROR: remote controls evidence unavailable"
    exit 70
  end
end
