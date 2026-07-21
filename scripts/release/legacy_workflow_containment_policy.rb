#!/usr/bin/env ruby

require "digest"
require "json"
require "psych"
require "time"

class ContainmentPolicyError < StandardError; end

module LegacyWorkflowContainment
  module_function

  REPOSITORY = "GGULBAE/desk-setup-switcher"
  BRANCH = "master"
  ORIGIN = "https://github.com/GGULBAE/desk-setup-switcher.git"
  WORKFLOW_ID = 311_269_012
  WORKFLOW_NAME = "Release"
  WORKFLOW_PATH = ".github/workflows/release.yml"
  UNSAFE_WORKFLOW_BLOB = "0648b71f683fa0bdcc430d02a7e16d32e0ee0c42"
  OPERATION = "disable-legacy-release-workflow"
  RESULT_OPERATION = "legacy-release-workflow-containment-result"
  SCHEMA_VERSION = 1
  TOOL_PATHS = [
    "scripts/release/contain-legacy-release-workflow.sh",
    "scripts/release/legacy_workflow_containment_policy.rb",
    "scripts/release/lib.sh",
    "scripts/lib/common.sh"
  ].freeze
  SHA1 = /\A[0-9a-f]{40}\z/
  SHA256 = /\A[0-9a-f]{64}\z/
  MAX_JSON_BYTES = 16 * 1024 * 1024
  JSON_STRING_TOKEN = /"(?:[^"\\\x00-\x1f]|\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4}))*"/.freeze

  class DuplicateJSONKeyError < StandardError; end

  def fail_policy
    raise ContainmentPolicyError, "policy mismatch"
  end

  def exact_keys(value, keys)
    fail_policy unless value.is_a?(Hash) && value.keys.sort == keys.sort
    value
  end

  def reject_duplicate_json_keys!(node)
    case node
    when Psych::Nodes::Mapping
      seen = {}
      node.children.each_slice(2) do |key_node, value_node|
        fail_policy unless key_node.is_a?(Psych::Nodes::Scalar)
        raise DuplicateJSONKeyError if seen.key?(key_node.value)

        seen[key_node.value] = true
        reject_duplicate_json_keys!(value_node)
      end
    when Psych::Nodes::Sequence
      node.children.each { |child| reject_duplicate_json_keys!(child) }
    end
  end

  def parse_strict_json(source)
    text = source.dup.force_encoding(Encoding::UTF_8)
    fail_policy unless text.valid_encoding? && !text.include?("\0")
    value = JSON.parse(
      text,
      allow_nan: false,
      create_additions: false,
      max_nesting: 100
    )
    normalized_source = text.gsub(JSON_STRING_TOKEN) do |token|
      JSON.generate(JSON.parse(token, create_additions: false))
    end
    document = Psych.parse(normalized_source)
    fail_policy unless document&.root
    reject_duplicate_json_keys!(document.root)
    value
  rescue DuplicateJSONKeyError, JSON::ParserError, JSON::NestingError, Psych::SyntaxError
    fail_policy
  end

  def strict_json_file(path, secure: false)
    stat = File.lstat(path)
    if secure
      fail_policy unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
        stat.uid == Process.euid && (stat.mode & 0o777) == 0o600
    else
      fail_policy unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
        stat.uid == Process.euid && (stat.mode & 0o077) == 0
    end
    fail_policy unless stat.size.between?(1, MAX_JSON_BYTES)
    parse_strict_json(File.binread(path))
  rescue Errno::ENOENT, Errno::EACCES
    fail_policy
  end

  def canonical(value)
    case value
    when Hash
      value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
    when Array
      value.map { |item| canonical(item) }
    else
      value
    end
  end

  def digest(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
  end

  def validate_sha1(value)
    fail_policy unless value.is_a?(String) && value.match?(SHA1)
    value
  end

  def validate_sha256(value)
    fail_policy unless value.is_a?(String) && value.match?(SHA256)
    value
  end

  def validate_timestamp(value)
    fail_policy unless value.is_a?(String) && !value.empty? && value.bytesize <= 64
    parsed = Time.iso8601(value)
    fail_policy unless value == parsed.iso8601 || value == parsed.utc.iso8601
    value
  rescue ArgumentError
    fail_policy
  end

  def validate_anchor(value, expected_master)
    exact_keys(value, %w[object ref])
    fail_policy unless value.fetch("ref") == "refs/heads/master"
    object = exact_keys(value.fetch("object"), %w[sha type])
    fail_policy unless object.fetch("type") == "commit" &&
      validate_sha1(object.fetch("sha")) == expected_master
    expected_master
  end

  def validate_actor(value)
    exact_keys(value, %w[id login type])
    fail_policy unless value.fetch("id").is_a?(Integer) && value.fetch("id").positive? &&
      value.fetch("login").is_a?(String) &&
      value.fetch("login").match?(/\A[A-Za-z0-9](?:[A-Za-z0-9-]{0,37}[A-Za-z0-9])?\z/) &&
      value.fetch("type") == "User"
    value.to_h
  end

  def validate_repository(value)
    exact_keys(
      value,
      %w[archived default_branch disabled full_name id node_id owner permissions private visibility]
    )
    owner = exact_keys(value.fetch("owner"), %w[id login type])
    permissions = exact_keys(value.fetch("permissions"), %w[admin push])
    fail_policy unless value.fetch("id").is_a?(Integer) && value.fetch("id").positive? &&
      value.fetch("node_id").is_a?(String) && !value.fetch("node_id").empty? &&
      value.fetch("node_id").bytesize <= 128 &&
      value.fetch("node_id").match?(/\A[A-Za-z0-9_=-]+\z/) &&
      value.fetch("full_name") == REPOSITORY && value.fetch("private") == false &&
      value.fetch("visibility") == "public" && value.fetch("default_branch") == BRANCH &&
      value.fetch("archived") == false && value.fetch("disabled") == false &&
      owner.fetch("id").is_a?(Integer) && owner.fetch("id").positive? &&
      owner.fetch("login") == "GGULBAE" && owner.fetch("type") == "User" &&
      permissions.fetch("admin") == true && permissions.fetch("push") == true
    canonical(value.to_h)
  end

  def validate_workflow(value)
    exact_keys(value, %w[id name path state])
    fail_policy unless value.fetch("id") == WORKFLOW_ID &&
      value.fetch("name") == WORKFLOW_NAME &&
      value.fetch("path") == WORKFLOW_PATH &&
      %w[active disabled_manually].include?(value.fetch("state"))
    value.fetch("state")
  end

  def validate_workflow_content(value)
    exact_keys(value, %w[path sha type])
    fail_policy unless value.fetch("path") == WORKFLOW_PATH &&
      value.fetch("type") == "file" &&
      value.fetch("sha") == UNSAFE_WORKFLOW_BLOB
  end

  def validate_runs(value)
    exact_keys(value, %w[pageTotalCounts reportedTotalCount runs])
    reported_total = value.fetch("reportedTotalCount")
    page_totals = value.fetch("pageTotalCounts")
    runs = value.fetch("runs")
    fail_policy unless reported_total.is_a?(Integer) && reported_total >= 0 &&
      page_totals.is_a?(Array) && !page_totals.empty? &&
      page_totals.all? { |total| total == reported_total } && runs.is_a?(Array)
    normalized = runs.map do |run|
      exact_keys(
        run,
        %w[conclusion created_at event head_sha id run_attempt run_number status updated_at]
      )
      fail_policy unless run.fetch("id").is_a?(Integer) && run.fetch("id").positive? &&
        run.fetch("run_number").is_a?(Integer) && run.fetch("run_number").positive? &&
        run.fetch("run_attempt").is_a?(Integer) && run.fetch("run_attempt").positive? &&
        run.fetch("status") == "completed" &&
        run.fetch("conclusion").is_a?(String) && !run.fetch("conclusion").empty? &&
        run.fetch("conclusion").bytesize <= 64 &&
        validate_sha1(run.fetch("head_sha")) &&
        run.fetch("event").is_a?(String) && !run.fetch("event").empty? &&
        run.fetch("event").bytesize <= 64
      validate_timestamp(run.fetch("created_at"))
      validate_timestamp(run.fetch("updated_at"))
      run.to_h
    end
    fail_policy unless normalized.map { |run| run.fetch("id") }.uniq.length == normalized.length
    fail_policy unless normalized.length == reported_total
    normalized.sort_by { |run| run.fetch("id") }
  end

  def normalize_observation(snapshot, expected_master)
    validate_sha1(expected_master)
    start_anchor = strict_json_file(File.join(snapshot, "anchor-start-ref.json"))
    start_workflow = strict_json_file(File.join(snapshot, "anchor-start-workflow.json"))
    start_content = strict_json_file(File.join(snapshot, "anchor-start-content.json"))
    actor = strict_json_file(File.join(snapshot, "viewer.json"))
    repository = strict_json_file(File.join(snapshot, "repository.json"))
    tags = strict_json_file(File.join(snapshot, "v-tag-refs.json"))
    releases = strict_json_file(File.join(snapshot, "releases.json"))
    runs = strict_json_file(File.join(snapshot, "workflow-runs.json"))
    end_anchor = strict_json_file(File.join(snapshot, "anchor-end-ref.json"))
    end_workflow = strict_json_file(File.join(snapshot, "anchor-end-workflow.json"))
    end_content = strict_json_file(File.join(snapshot, "anchor-end-content.json"))

    validate_anchor(start_anchor, expected_master)
    state = validate_workflow(start_workflow)
    validate_workflow_content(start_content)
    normalized_actor = validate_actor(actor)
    normalized_repository = validate_repository(repository)
    fail_policy unless tags == [] && releases == []
    normalized_runs = validate_runs(runs)
    validate_anchor(end_anchor, expected_master)
    validate_workflow(end_workflow)
    validate_workflow_content(end_content)
    fail_policy unless start_anchor == end_anchor && start_workflow == end_workflow &&
      start_content == end_content

    {
      "masterSHA" => expected_master,
      "actor" => normalized_actor,
      "repository" => normalized_repository,
      "workflow" => {
        "id" => WORKFLOW_ID,
        "name" => WORKFLOW_NAME,
        "path" => WORKFLOW_PATH,
        "state" => state,
        "unsafeBlobSHA" => UNSAFE_WORKFLOW_BLOB
      },
      "vTagRefCount" => 0,
      "vTagRefSetSHA256" => digest(tags),
      "releaseCount" => 0,
      "releaseSetSHA256" => digest(releases),
      "workflowRunCount" => normalized_runs.length,
      "workflowRunSetSHA256" => digest(normalized_runs)
    }
  end

  def validate_observation(value)
    exact_keys(
      value,
      %w[actor masterSHA releaseCount releaseSetSHA256 repository vTagRefCount vTagRefSetSHA256 workflow workflowRunCount workflowRunSetSHA256]
    )
    validate_sha1(value.fetch("masterSHA"))
    validate_actor(value.fetch("actor"))
    validate_repository(value.fetch("repository"))
    workflow = exact_keys(value.fetch("workflow"), %w[id name path state unsafeBlobSHA])
    fail_policy unless workflow.fetch("id") == WORKFLOW_ID &&
      workflow.fetch("name") == WORKFLOW_NAME && workflow.fetch("path") == WORKFLOW_PATH &&
      workflow.fetch("unsafeBlobSHA") == UNSAFE_WORKFLOW_BLOB &&
      %w[active disabled_manually].include?(workflow.fetch("state"))
    fail_policy unless value.fetch("vTagRefCount") == 0 && value.fetch("releaseCount") == 0
    validate_sha256(value.fetch("vTagRefSetSHA256"))
    validate_sha256(value.fetch("releaseSetSHA256"))
    fail_policy unless value.fetch("workflowRunCount").is_a?(Integer) &&
      value.fetch("workflowRunCount") >= 0
    validate_sha256(value.fetch("workflowRunSetSHA256"))
    value
  end

  def read_observation(path)
    validate_observation(strict_json_file(path))
  end

  def same_observation_pair(first, second)
    fail_policy unless first == second
    first
  end

  def without_state(observation)
    value = Marshal.load(Marshal.dump(observation))
    value.fetch("workflow").delete("state")
    value
  end

  def validate_local_fields(
    head, helper_blob, validator_blob, library_blob, common_library_blob
  )
    validate_sha1(head)
    blobs = {
      TOOL_PATHS.fetch(0) => validate_sha1(helper_blob),
      TOOL_PATHS.fetch(1) => validate_sha1(validator_blob),
      TOOL_PATHS.fetch(2) => validate_sha1(library_blob),
      TOOL_PATHS.fetch(3) => validate_sha1(common_library_blob)
    }
    [head, blobs]
  end

  def secure_parent(path, repository_root, expect_absent:)
    fail_policy unless path.is_a?(String) && path == File.expand_path(path) &&
      !path.match?(/[\r\n]/)
    parent = File.dirname(path)
    parent_stat = File.lstat(parent)
    fail_policy unless parent_stat.directory? && !parent_stat.symlink? &&
      parent_stat.uid == Process.euid && (parent_stat.mode & 0o777) == 0o700
    repository = File.realpath(repository_root)
    parent_real = File.realpath(parent)
    destination = File.join(parent_real, File.basename(path))
    fail_policy if destination == repository || destination.start_with?(repository + File::SEPARATOR)
    if expect_absent
      begin
        File.lstat(destination)
        fail_policy
      rescue Errno::ENOENT
      end
    end
    destination
  rescue Errno::ENOENT, Errno::EACCES
    fail_policy
  end

  def write_receipt(path, repository_root, value)
    destination = secure_parent(path, repository_root, expect_absent: true)
    bytes = JSON.pretty_generate(value) + "\n"
    file = nil
    created_identity = nil
    succeeded = false
    begin
      file = File.open(destination, File::WRONLY | File::CREAT | File::EXCL, 0o600)
      created_stat = file.stat
      created_identity = [created_stat.dev, created_stat.ino]
      file.binmode
      file.write(bytes)
      file.flush
      file.fsync
      file.close
      file = nil
      stat = File.lstat(destination)
      fail_policy unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
        stat.uid == Process.euid && (stat.mode & 0o777) == 0o600 &&
        [stat.dev, stat.ino] == created_identity && File.binread(destination) == bytes
      succeeded = true
    ensure
      file&.close
      unless succeeded || created_identity.nil?
        begin
          current = File.lstat(destination)
          File.unlink(destination) if [current.dev, current.ino] == created_identity
        rescue Errno::ENOENT
        end
      end
    end
  rescue Errno::EEXIST, Errno::EACCES
    fail_policy
  end

  def plan_body(expected_master, local_head, tool_blobs, remote)
    {
      "schemaVersion" => SCHEMA_VERSION,
      "operation" => OPERATION,
      "repository" => REPOSITORY,
      "branch" => BRANCH,
      "expectedMasterSHA" => expected_master,
      "local" => {
        "headSHA" => local_head,
        "origin" => ORIGIN,
        "toolBlobs" => tool_blobs
      },
      "remote" => remote
    }
  end

  def validate_receipt(value, expected_master, expected_digest, local_head, tool_blobs)
    exact_keys(
      value,
      %w[branch expectedMasterSHA local operation planDigest remote repository schemaVersion]
    )
    fail_policy unless value.fetch("schemaVersion") == SCHEMA_VERSION &&
      value.fetch("operation") == OPERATION && value.fetch("repository") == REPOSITORY &&
      value.fetch("branch") == BRANCH && value.fetch("expectedMasterSHA") == expected_master
    local = exact_keys(value.fetch("local"), %w[headSHA origin toolBlobs])
    fail_policy unless local.fetch("headSHA") == local_head && local.fetch("origin") == ORIGIN
    receipt_blobs = exact_keys(local.fetch("toolBlobs"), TOOL_PATHS)
    fail_policy unless receipt_blobs == tool_blobs
    receipt_blobs.each_value { |blob| validate_sha1(blob) }
    remote = validate_observation(value.fetch("remote"))
    fail_policy unless remote.fetch("masterSHA") == expected_master
    supplied = validate_sha256(expected_digest)
    embedded = validate_sha256(value.fetch("planDigest"))
    body = value.reject { |key, _value| key == "planDigest" }
    actual = digest(body)
    fail_policy unless supplied == embedded && embedded == actual
    remote
  end

  def read_secure_receipt(path, repository_root)
    destination = secure_parent(path, repository_root, expect_absent: false)
    strict_json_file(destination, secure: true)
  end

  def validate_transition(before, after, mutation_attempted)
    fail_policy unless without_state(before) == without_state(after) &&
      after.fetch("workflow").fetch("state") == "disabled_manually"
    before_state = before.fetch("workflow").fetch("state")
    if mutation_attempted
      fail_policy unless before_state == "active"
    else
      fail_policy unless before_state == "disabled_manually"
    end
  end

  def validate_put_response(path)
    stat = File.lstat(path)
    fail_policy unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
      stat.uid == Process.euid && (stat.mode & 0o077) == 0 && stat.size.between?(1, 65_536)
    bytes = File.binread(path)
    status_and_headers, separator, body = bytes.partition(/\r?\n\r?\n/)
    first_line = status_and_headers.lines.first&.chomp&.delete_suffix("\r")
    fail_policy unless separator.match?(/\A\r?\n\r?\n\z/) && body.empty? &&
      first_line&.match?(/\AHTTP\/(?:1\.1|2(?:\.0)?) 204(?: No Content)?\z/)
  rescue Errno::ENOENT, Errno::EACCES
    fail_policy
  end

  def create_success_receipt(
    plan_receipt_path, expected_digest, expected_master, local_head, helper_blob,
    validator_blob, library_blob, common_library_blob, repository_root,
    pre_first_path, pre_second_path, post_first_path, post_second_path,
    mutation_attempted_text, output
  )
    _head, blobs = validate_local_fields(
      local_head, helper_blob, validator_blob, library_blob, common_library_blob
    )
    plan_receipt = read_secure_receipt(plan_receipt_path, repository_root)
    planned = validate_receipt(
      plan_receipt, expected_master, expected_digest, local_head, blobs
    )
    before = same_observation_pair(
      read_observation(pre_first_path), read_observation(pre_second_path)
    )
    after = same_observation_pair(
      read_observation(post_first_path), read_observation(post_second_path)
    )
    fail_policy unless without_state(before) == without_state(planned)
    planned_state = planned.fetch("workflow").fetch("state")
    fail_policy if planned_state == "disabled_manually" &&
      before.fetch("workflow").fetch("state") != "disabled_manually"
    mutation_attempted = case mutation_attempted_text
                         when "true" then true
                         when "false" then false
                         else fail_policy
                         end
    validate_transition(before, after, mutation_attempted)
    body = {
      "schemaVersion" => SCHEMA_VERSION,
      "operation" => RESULT_OPERATION,
      "repository" => REPOSITORY,
      "branch" => BRANCH,
      "expectedMasterSHA" => expected_master,
      "planDigest" => expected_digest,
      "local" => plan_receipt.fetch("local"),
      "actor" => after.fetch("actor"),
      "repositoryIdentity" => after.fetch("repository"),
      "preRemote" => before,
      "postRemote" => after,
      "mutationAttempted" => mutation_attempted,
      "result" => "disabled_manually"
    }
    result_digest = digest(body)
    write_receipt(output, repository_root, body.merge("resultDigest" => result_digest))
    result_digest
  end

  def main(argv)
    command = argv.shift
    case command
    when "validate-output"
      fail_policy unless argv.length == 2
      output, repository_root = argv
      secure_parent(output, repository_root, expect_absent: true)
    when "normalize-observation"
      fail_policy unless argv.length == 3
      snapshot, expected_master, output = argv
      normalized = normalize_observation(snapshot, expected_master)
      File.open(output, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(JSON.generate(canonical(normalized)) + "\n")
      end
    when "create-plan"
      fail_policy unless argv.length == 10
      first_path, second_path, expected_master, local_head, helper_blob,
        validator_blob, library_blob, common_library_blob, repository_root, output = argv
      first = read_observation(first_path)
      second = read_observation(second_path)
      remote = same_observation_pair(first, second)
      fail_policy unless remote.fetch("masterSHA") == expected_master
      head, blobs = validate_local_fields(
        local_head, helper_blob, validator_blob, library_blob, common_library_blob
      )
      body = plan_body(expected_master, head, blobs, remote)
      plan_digest = digest(body)
      receipt = body.merge("planDigest" => plan_digest)
      write_receipt(output, repository_root, receipt)
      STDOUT.write(plan_digest + "\n")
    when "validate-plan"
      fail_policy unless argv.length == 9
      receipt_path, expected_digest, expected_master, local_head, helper_blob,
        validator_blob, library_blob, common_library_blob, repository_root = argv
      _head, blobs = validate_local_fields(
        local_head, helper_blob, validator_blob, library_blob, common_library_blob
      )
      receipt = read_secure_receipt(receipt_path, repository_root)
      remote = validate_receipt(
        receipt, expected_master, expected_digest, local_head, blobs
      )
      STDOUT.write(remote.fetch("workflow").fetch("state") + "\n")
    when "validate-pre"
      fail_policy unless argv.length == 3
      receipt_path, first_path, second_path = argv
      receipt = strict_json_file(receipt_path, secure: true)
      first = read_observation(first_path)
      second = read_observation(second_path)
      current = same_observation_pair(first, second)
      planned = validate_observation(receipt.fetch("remote"))
      fail_policy unless without_state(current) == without_state(planned)
      planned_state = planned.fetch("workflow").fetch("state")
      current_state = current.fetch("workflow").fetch("state")
      fail_policy if planned_state == "disabled_manually" && current_state != "disabled_manually"
      STDOUT.write(current_state + "\n")
    when "validate-post"
      fail_policy unless argv.length == 4
      pre_first, pre_second, post_first, post_second = argv.map { |path| read_observation(path) }
      before = same_observation_pair(pre_first, pre_second)
      after = same_observation_pair(post_first, post_second)
      fail_policy unless without_state(before) == without_state(after) &&
        after.fetch("workflow").fetch("state") == "disabled_manually"
    when "validate-put-response"
      fail_policy unless argv.length == 1
      validate_put_response(argv.fetch(0))
    when "create-success"
      fail_policy unless argv.length == 15
      result_digest = create_success_receipt(*argv)
      STDOUT.write(result_digest + "\n")
    else
      fail_policy
    end
  end
end

begin
  LegacyWorkflowContainment.main(ARGV)
rescue ContainmentPolicyError, KeyError, TypeError, ArgumentError, IOError, SystemCallError
  warn "ERROR: legacy workflow containment policy mismatch"
  exit 1
end
