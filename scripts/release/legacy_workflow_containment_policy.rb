#!/usr/bin/env ruby

require "digest"
require "json"
require "openssl"
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
  API_VERSION = "2026-03-10"
  API_TIMEOUT_SECONDS = 20
  OPERATION = "disable-legacy-release-workflow"
  RESULT_OPERATION = "legacy-release-workflow-containment-result"
  SCHEMA_VERSION = 1
  TOOL_PATHS = [
    "scripts/release/contain-legacy-release-workflow.sh",
    "scripts/release/legacy_workflow_containment_policy.rb",
    "scripts/release/lib.sh",
    "scripts/lib/common.sh"
  ].freeze
  OBSERVATION_FILES = %w[
    anchor-start-ref.json
    anchor-start-workflow.json
    anchor-start-content.json
    viewer.json
    repository.json
    v-tag-refs.json
    releases.json
    workflow-runs.json
    anchor-end-ref.json
    anchor-end-workflow.json
    anchor-end-content.json
  ].freeze
  SHA1 = /\A[0-9a-f]{40}\z/
  SHA256 = /\A[0-9a-f]{64}\z/
  MAX_JSON_BYTES = 16 * 1024 * 1024
  JSON_STRING_TOKEN = /"(?:[^"\\\x00-\x1f]|\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4}))*"/.freeze
  FORBIDDEN_REMOTE_ENVIRONMENT = %w[
    GH_TOKEN
    GITHUB_TOKEN
    GH_HOST
    GH_CONFIG_DIR
    GH_DEBUG
    DEBUG
    GH_ENTERPRISE_TOKEN
    GITHUB_ENTERPRISE_TOKEN
    DESK_SETUP_REMOTE_CONTAINMENT_MUTATIONS
    DESK_SETUP_REMOTE_CONTAINMENT_CONFIRMATION
    DESK_SETUP_CAPTURE_SECRETS
  ].freeze
  CAPTURE_ATTESTATION_SCHEMA_VERSION = 1
  CAPTURE_ATTESTATION_DOMAIN = "desk-setup-legacy-workflow-capture-v1\0"
  REMOTE_CONFIG_DIRECTORY = "/private/var/empty"

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

  def descriptor_identity(stat)
    [stat.dev, stat.ino, stat.mode, stat.nlink, stat.size, stat.mtime.to_r, stat.ctime.to_r]
  end

  def directory_identity(stat)
    [stat.dev, stat.ino, stat.mode, stat.uid, stat.nlink]
  end

  def valid_directory_creation_transition?(before, after)
    before.fetch(0, 4) == after.fetch(0, 4) &&
      [before.fetch(4), before.fetch(4) + 1].include?(after.fetch(4))
  end

  def validate_private_file_stat(stat, secure:, allow_empty:, max_bytes:)
    fail_policy unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
      stat.uid == Process.euid
    if secure
      fail_policy unless (stat.mode & 0o777) == 0o600
    else
      fail_policy unless (stat.mode & 0o077) == 0
    end
    minimum = allow_empty ? 0 : 1
    fail_policy unless stat.size.between?(minimum, max_bytes)
  end

  def read_private_bytes(
    path, secure: false, allow_empty: false, max_bytes: MAX_JSON_BYTES,
    expected_sha256: nil
  )
    fail_policy unless File.const_defined?(:NOFOLLOW)
    before_path = File.lstat(path)
    validate_private_file_stat(
      before_path, secure: secure, allow_empty: allow_empty, max_bytes: max_bytes
    )
    bytes = nil
    opened_identity = nil
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      file.binmode
      before = file.stat
      validate_private_file_stat(
        before, secure: secure, allow_empty: allow_empty, max_bytes: max_bytes
      )
      fail_policy unless [before.dev, before.ino] == [before_path.dev, before_path.ino]
      before_identity = descriptor_identity(before)
      bytes = file.read(max_bytes + 1)
      after = file.stat
      opened_identity = descriptor_identity(after)
      fail_policy unless opened_identity == before_identity && bytes.bytesize == before.size
    end
    after_path = File.lstat(path)
    validate_private_file_stat(
      after_path, secure: secure, allow_empty: allow_empty, max_bytes: max_bytes
    )
    fail_policy unless descriptor_identity(after_path) == opened_identity
    unless expected_sha256.nil?
      fail_policy unless Digest::SHA256.hexdigest(bytes) == validate_sha256(expected_sha256)
    end
    bytes
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP, Errno::ENOTDIR
    fail_policy
  end

  def remote_operation_arguments(operation, expected_master)
    validate_sha1(expected_master)
    common = [
      "api",
      "--hostname", "github.com",
      "-H", "Accept: application/vnd.github+json",
      "-H", "X-GitHub-Api-Version: #{API_VERSION}"
    ]
    get = ["--method", "GET", "-H", "Cache-Control: no-cache"]
    case operation
    when "anchor-ref"
      common + get + [
        "--jq", "{ref: .ref, object: {sha: .object.sha, type: .object.type}}",
        "/repos/#{REPOSITORY}/git/ref/heads/#{BRANCH}"
      ]
    when "workflow"
      common + get + [
        "--jq", "{id: .id, name: .name, path: .path, state: .state}",
        "/repos/#{REPOSITORY}/actions/workflows/#{WORKFLOW_ID}"
      ]
    when "workflow-content"
      common + get + [
        "--jq", "{sha: .sha, path: .path, type: .type}",
        "/repos/#{REPOSITORY}/contents/#{WORKFLOW_PATH}?ref=#{expected_master}"
      ]
    when "viewer"
      common + get + ["--jq", "{id: .id, login: .login, type: .type}", "/user"]
    when "repository"
      projection = "{id: .id, node_id: .node_id, full_name: .full_name, " \
        "private: .private, visibility: .visibility, default_branch: .default_branch, " \
        "archived: .archived, disabled: .disabled, owner: {id: .owner.id, " \
        "login: .owner.login, type: .owner.type}, permissions: " \
        "{admin: .permissions.admin, push: .permissions.push}}"
      common + get + ["--jq", projection, "/repos/#{REPOSITORY}"]
    when "v-tag-refs"
      projection = "if type == \"array\" then {items: [.[] | {ref: .ref, " \
        "object: {sha: .object.sha, type: .object.type}}]} else " \
        "error(\"unexpected page\") end | @json"
      common + get + [
        "--paginate", "--jq", projection,
        "/repos/#{REPOSITORY}/git/matching-refs/tags/v"
      ]
    when "releases"
      projection = "if type == \"array\" then {items: [.[] | {id: .id, " \
        "tag_name: .tag_name, draft: .draft, prerelease: .prerelease, " \
        "target_commitish: .target_commitish}]} else error(\"unexpected page\") end | @json"
      common + get + [
        "--paginate", "--jq", projection,
        "/repos/#{REPOSITORY}/releases?per_page=100"
      ]
    when "workflow-runs"
      projection = "if type == \"object\" and (.total_count | type == \"number\") " \
        "and (.workflow_runs | type == \"array\") then " \
        "{reportedTotalCount: .total_count, runs: [.workflow_runs[] | " \
        "{id: .id, run_number: .run_number, run_attempt: .run_attempt, " \
        "status: .status, conclusion: .conclusion, head_sha: .head_sha, " \
        "event: .event, created_at: .created_at, updated_at: .updated_at}]} " \
        "else error(\"unexpected page\") end | @json"
      common + get + [
        "--paginate", "--jq", projection,
        "/repos/#{REPOSITORY}/actions/workflows/#{WORKFLOW_ID}/runs?per_page=100"
      ]
    when "disable-workflow"
      common + [
        "--method", "PUT", "--include",
        "/repos/GGULBAE/desk-setup-switcher/actions/workflows/311269012/disable"
      ]
    else
      fail_policy
    end
  end

  def canonical_remote_executable(path)
    fail_policy unless path.is_a?(String) && path.start_with?(File::SEPARATOR) &&
      !path.match?(/[\r\n]/) && File.const_defined?(:NOFOLLOW)
    resolved = File.realpath(path)
    fail_policy unless resolved == File.expand_path(resolved)
    before_path = File.lstat(resolved)
    validate = lambda do |stat|
      fail_policy unless stat.file? && !stat.symlink? && stat.nlink == 1 &&
        [0, Process.euid].include?(stat.uid) && (stat.mode & 0o022).zero? &&
        (stat.mode & 0o111).positive? && stat.size.positive?
    end
    validate.call(before_path)
    opened_identity = nil
    File.open(resolved, File::RDONLY | File::NOFOLLOW) do |file|
      before = file.stat
      validate.call(before)
      fail_policy unless [before.dev, before.ino] == [before_path.dev, before_path.ino]
      before_identity = descriptor_identity(before)
      after = file.stat
      opened_identity = descriptor_identity(after)
      fail_policy unless opened_identity == before_identity
    end
    after_path = File.lstat(resolved)
    validate.call(after_path)
    fail_policy unless descriptor_identity(after_path) == opened_identity
    resolved
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP, Errno::ENOTDIR
    fail_policy
  end

  def canonical_remote_config_directory(path)
    fail_policy unless path.is_a?(String) && path.start_with?(File::SEPARATOR) &&
      !path.match?(/[\r\n]/)
    resolved = File.realpath(path)
    fail_policy unless resolved == REMOTE_CONFIG_DIRECTORY &&
      resolved == File.expand_path(resolved)
    validate = lambda do |stat|
      fail_policy unless stat.directory? && !stat.symlink? && stat.uid.zero? &&
        (stat.mode & 0o022).zero?
    end
    stable_directory_stat(resolved, &validate)
    fail_policy unless Dir.children(resolved).empty?
    stable_directory_stat(resolved, &validate)
    resolved
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR
    fail_policy
  end

  def write_all(output, bytes)
    offset = 0
    while offset < bytes.bytesize
      written = output.write(bytes.byteslice(offset, bytes.bytesize - offset))
      fail_policy unless written.is_a?(Integer) && written.positive?
      offset += written
    end
  end

  def read_capture_secrets
    source = STDIN.read(8_386)
    fail_policy unless source.bytesize.between?(77, 8_385) && source.end_with?("\n") &&
      source.count("\n") == 1 && FORBIDDEN_REMOTE_ENVIRONMENT.none? { |name| ENV.key?(name) }
    bundle = source.delete_suffix("\n")
    source.clear
    STDIN.reopen(File::NULL, "r")
    fields = bundle.split("\t", -1)
    bundle.clear
    fail_policy unless fields.length == 3
    token, key_hex, authorization = fields
    fail_policy if token.empty? || token.bytesize > 8_191 ||
      token.match?(/[\t\r\n]/) || !key_hex.match?(/\A[0-9a-f]{64}\z/) ||
      authorization.empty? || authorization.bytesize > 512 || authorization.match?(/[\t\r\n]/)
    key = [key_hex].pack("H*")
    key_hex.clear
    [token, key, authorization]
  end

  def read_capture_mac_key
    source = STDIN.read(66)
    fail_policy unless source.bytesize == 65 && source.end_with?("\n")
    key_hex = source.delete_suffix("\n")
    fail_policy unless key_hex.match?(/\A[0-9a-f]{64}\z/)
    STDIN.reopen(File::NULL, "r")
    key = [key_hex].pack("H*")
    key_hex.clear
    key
  end

  def capture_limit(operation)
    operation == "disable-workflow" ? 65_536 : MAX_JSON_BYTES
  end

  def capture_attestation_body(operation, byte_count, sha256)
    {
      "schemaVersion" => CAPTURE_ATTESTATION_SCHEMA_VERSION,
      "operation" => operation,
      "byteCount" => byte_count,
      "sha256" => sha256
    }
  end

  def capture_attestation_mac(key, body)
    payload = CAPTURE_ATTESTATION_DOMAIN + JSON.generate(canonical(body))
    OpenSSL::HMAC.hexdigest("SHA256", key, payload)
  end

  def constant_time_equal?(left, right)
    return false unless left.is_a?(String) && right.is_a?(String) &&
      left.bytesize == right.bytesize

    difference = 0
    left.bytes.zip(right.bytes) { |left_byte, right_byte| difference |= left_byte ^ right_byte }
    difference.zero?
  end

  def stop_remote_child(pid)
    return if pid.nil?

    begin
      Process.kill("TERM", pid)
    rescue Errno::ESRCH
    end
    20.times do
      begin
        waited = Process.waitpid2(pid, Process::WNOHANG)
        return waited unless waited.nil?
      rescue Errno::ECHILD
        return nil
      end
      sleep 0.05
    end
    begin
      Process.kill("KILL", pid)
    rescue Errno::ESRCH
    end
    Process.waitpid2(pid)
  rescue Errno::ECHILD
    nil
  end

  def capture_remote_operation(
    operation, output, attestation, expected_master, temporary_root, config_directory,
    executable, plan_receipt_context, plan_digest_context
  )
    fail_policy unless File.const_defined?(:NOFOLLOW) && output.is_a?(String) &&
      output == File.expand_path(output) && !output.match?(/[\r\n]/) &&
      attestation.is_a?(String) && attestation == File.expand_path(attestation) &&
      !attestation.match?(/[\r\n]/) && attestation == "#{output}.attestation" &&
      config_directory.is_a?(String) && config_directory == File.expand_path(config_directory) &&
      !config_directory.match?(/[\r\n]/) && temporary_root.is_a?(String) &&
      temporary_root == File.expand_path(temporary_root) && !temporary_root.match?(/[\r\n]/)
    arguments = remote_operation_arguments(operation, expected_master)
    if operation == "disable-workflow"
      fail_policy unless plan_receipt_context.is_a?(String) &&
        plan_receipt_context.start_with?(File::SEPARATOR) &&
        !plan_receipt_context.match?(/[\r\n]/)
      plan_digest_context = validate_sha256(plan_digest_context)
      plan_receipt = strict_json_file(plan_receipt_context, secure: true)
      validate_receipt_integrity(plan_receipt, expected_master, plan_digest_context)
    else
      fail_policy unless plan_receipt_context == "-" && plan_digest_context == "-"
    end
    executable = canonical_remote_executable(executable)
    config_directory = canonical_remote_config_directory(config_directory)
    fail_policy unless File.realpath(temporary_root) == temporary_root &&
      output.start_with?(temporary_root + File::SEPARATOR)
    stable_directory_stat(temporary_root) { |stat| validate_private_directory_stat(stat) }

    token, mac_key, authorization = read_capture_secrets
    expected_authorization = if operation == "disable-workflow"
                               "DISABLE WORKFLOW #{WORKFLOW_ID} AT #{expected_master} " \
                                 "USING PLAN #{plan_digest_context}"
                             else
                               "READ ONLY"
                             end
    fail_policy unless authorization == expected_authorization
    parent = File.dirname(output)
    parent_path_stat = File.lstat(parent)
    validate_private_directory_stat(parent_path_stat)
    parent_file = nil
    output_file = nil
    reader = nil
    writer = nil
    child_pid = nil
    child_status = nil
    created_identity = nil
    succeeded = false
    stream_sha256 = nil
    begin
      parent_file = File.open(parent, File::RDONLY | File::NOFOLLOW)
      parent_before = parent_file.stat
      validate_private_directory_stat(parent_before)
      fail_policy unless [parent_before.dev, parent_before.ino] ==
        [parent_path_stat.dev, parent_path_stat.ino]
      parent_identity = directory_identity(parent_before)

      flags = File::RDWR | File::CREAT | File::EXCL | File::NOFOLLOW
      output_file = File.open(output, flags, 0o600)
      output_file.binmode
      output_file.sync = true
      created = output_file.stat
      created_identity = [created.dev, created.ino]
      fail_policy unless created.file? && created.nlink == 1 &&
        created.uid == Process.euid && (created.mode & 0o777) == 0o600 && created.size.zero?

      reader, writer = IO.pipe
      child_environment = {
        "GH_TOKEN" => token,
        "GH_CONFIG_DIR" => config_directory,
        "GH_NO_UPDATE_NOTIFIER" => "1",
        "GH_PROMPT_DISABLED" => "1",
        "GH_TELEMETRY" => "0",
        "DO_NOT_TRACK" => "1",
        "LANG" => "C",
        "LC_ALL" => "C",
        "PATH" => "/usr/bin:/bin:/usr/sbin:/sbin"
      }
      child_pid = Process.spawn(
        child_environment,
        executable,
        *arguments,
        in: File::NULL,
        out: writer,
        err: File::NULL,
        unsetenv_others: true,
        close_others: true
      )
      child_environment.clear
      token.clear
      authorization.clear
      writer.close
      writer = nil

      stream_digest = Digest::SHA256.new
      captured_bytes = 0
      reached_eof = false
      until reached_eof && !child_status.nil?
        unless reached_eof
          ready = IO.select([reader], nil, nil, 0.05)
          if ready
            begin
              chunk = reader.read_nonblock(65_536)
              captured_bytes += chunk.bytesize
              fail_policy if captured_bytes > capture_limit(operation)
              stream_digest.update(chunk)
              write_all(output_file, chunk)
            rescue IO::WaitReadable
            rescue EOFError
              reached_eof = true
            end
          end
        end

        if child_status.nil?
          waited = Process.waitpid2(child_pid, Process::WNOHANG)
          child_status = waited.fetch(1) if waited
        end
      end
      child_pid = nil
      fail_policy unless child_status.success?

      output_file.flush
      output_file.fsync
      output_file.rewind
      final_before_read = output_file.stat
      validate_private_file_stat(
        final_before_read,
        secure: true,
        allow_empty: true,
        max_bytes: capture_limit(operation)
      )
      fail_policy unless final_before_read.size == captured_bytes
      final_identity = descriptor_identity(final_before_read)
      readback_digest = Digest::SHA256.new
      readback_bytes = 0
      while (chunk = output_file.read(65_536))
        readback_bytes += chunk.bytesize
        readback_digest.update(chunk)
      end
      final_after_read = output_file.stat
      stream_sha256 = stream_digest.hexdigest
      fail_policy unless descriptor_identity(final_after_read) == final_identity &&
        readback_bytes == captured_bytes && readback_digest.hexdigest == stream_sha256

      after_path = File.lstat(output)
      fail_policy unless descriptor_identity(after_path) == final_identity
      parent_after = parent_file.stat
      parent_after_path = File.lstat(parent)
      validate_private_directory_stat(parent_after)
      validate_private_directory_stat(parent_after_path)
      parent_after_identity = directory_identity(parent_after)
      fail_policy unless parent_after_identity == directory_identity(parent_after_path) &&
        valid_directory_creation_transition?(parent_identity, parent_after_identity)

      output_file.close
      output_file = nil
      parent_file.close
      parent_file = nil
      reader.close
      reader = nil

      body = capture_attestation_body(operation, captured_bytes, stream_sha256)
      mac = capture_attestation_mac(mac_key, body)
      mac_key.clear
      write_private_json(attestation, body.merge("hmacSHA256" => mac))
      succeeded = true
      stream_sha256
    ensure
      writer&.close
      reader&.close
      stop_remote_child(child_pid) unless child_pid.nil?
      token&.clear
      mac_key&.clear
      authorization&.clear
      output_file&.close
      parent_file&.close
      unless succeeded || created_identity.nil?
        begin
          current = File.lstat(output)
          File.unlink(output) if [current.dev, current.ino] == created_identity
        rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP, Errno::ENOTDIR
        end
      end
    end
  rescue Errno::ENOENT, Errno::EACCES, Errno::EEXIST, Errno::EISDIR, Errno::ELOOP,
         Errno::ENOTDIR
    fail_policy
  end

  def verify_remote_capture(operation, output, attestation)
    fail_policy unless output.is_a?(String) && output == File.expand_path(output) &&
      !output.match?(/[\r\n]/) && attestation == "#{output}.attestation"
    remote_operation_arguments(operation, "0" * 40)
    key = read_capture_mac_key
    begin
      value = strict_json_file(attestation, secure: true)
      exact_keys(value, %w[byteCount hmacSHA256 operation schemaVersion sha256])
      fail_policy unless value.fetch("schemaVersion") == CAPTURE_ATTESTATION_SCHEMA_VERSION &&
        value.fetch("operation") == operation && value.fetch("byteCount").is_a?(Integer) &&
        value.fetch("byteCount").between?(0, capture_limit(operation))
      sha256 = validate_sha256(value.fetch("sha256"))
      supplied_mac = validate_sha256(value.fetch("hmacSHA256"))
      body = capture_attestation_body(operation, value.fetch("byteCount"), sha256)
      expected_mac = capture_attestation_mac(key, body)
      fail_policy unless constant_time_equal?(supplied_mac, expected_mac)
      bytes = read_private_bytes(
        output,
        secure: true,
        allow_empty: true,
        max_bytes: capture_limit(operation)
      )
      fail_policy unless bytes.bytesize == value.fetch("byteCount") &&
        Digest::SHA256.hexdigest(bytes) == sha256
      sha256
    ensure
      key.clear
    end
  end

  def strict_json_file(path, secure: false, expected_sha256: nil)
    parse_strict_json(
      read_private_bytes(path, secure: secure, expected_sha256: expected_sha256)
    )
  end

  def read_private_json_lines(path, expected_sha256)
    bytes = read_private_bytes(
      path, allow_empty: true, expected_sha256: expected_sha256
    )
    return [] if bytes.empty?

    text = bytes.dup.force_encoding(Encoding::UTF_8)
    fail_policy unless text.valid_encoding? && !text.include?("\0") && text.end_with?("\n")
    lines = text.lines(chomp: true)
    fail_policy if lines.empty? || lines.any?(&:empty?)
    lines.map { |line| parse_strict_json(line) }
  end

  def validate_private_directory_stat(stat)
    fail_policy unless stat.directory? && !stat.symlink? && stat.uid == Process.euid &&
      (stat.mode & 0o777) == 0o700
  end

  def stable_directory_stat(path)
    fail_policy unless File.const_defined?(:NOFOLLOW)
    before_path = File.lstat(path)
    yield before_path
    opened_identity = nil
    File.open(path, File::RDONLY | File::NOFOLLOW) do |file|
      before = file.stat
      yield before
      fail_policy unless [before.dev, before.ino] == [before_path.dev, before_path.ino]
      before_identity = descriptor_identity(before)
      after = file.stat
      opened_identity = descriptor_identity(after)
      fail_policy unless opened_identity == before_identity
    end
    after_path = File.lstat(path)
    yield after_path
    fail_policy unless descriptor_identity(after_path) == opened_identity
    after_path
  rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP, Errno::ENOTDIR
    fail_policy
  end

  def canonical_temporary_parent(path)
    fail_policy unless path.is_a?(String) && path.start_with?(File::SEPARATOR) &&
      !path.match?(/[\r\n]/)
    resolved = File.realpath(path)
    fail_policy unless resolved == File.expand_path(resolved)
    stat = stable_directory_stat(resolved) do |value|
      fail_policy unless value.directory? && !value.symlink?
    end
    owner_private = stat.uid == Process.euid && (stat.mode & 0o022) == 0
    root_sticky = stat.uid.zero? && (stat.mode & 0o1777) == 0o1777
    fail_policy unless owner_private || root_sticky
    resolved
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR
    fail_policy
  end

  def validate_temporary_root(path, parent)
    fail_policy unless path.is_a?(String) && parent.is_a?(String) &&
      path == File.expand_path(path) && parent == File.expand_path(parent) &&
      !path.match?(/[\r\n]/) && !parent.match?(/[\r\n]/) &&
      File.realpath(path) == path && File.realpath(parent) == parent &&
      File.dirname(path) == parent
    stable_directory_stat(path) { |stat| validate_private_directory_stat(stat) }
    path
  rescue Errno::ENOENT, Errno::EACCES, Errno::ELOOP, Errno::ENOTDIR
    fail_policy
  end

  def write_private_bytes(path, bytes)
    fail_policy unless File.const_defined?(:NOFOLLOW) && path.is_a?(String) &&
      path == File.expand_path(path) && !path.match?(/[\r\n]/) &&
      bytes.is_a?(String) && bytes.bytesize.between?(1, MAX_JSON_BYTES)
    parent = File.dirname(path)
    parent_path_stat = File.lstat(parent)
    validate_private_directory_stat(parent_path_stat)

    parent_file = nil
    output_file = nil
    created_identity = nil
    succeeded = false
    begin
      parent_file = File.open(parent, File::RDONLY | File::NOFOLLOW)
      parent_before = parent_file.stat
      validate_private_directory_stat(parent_before)
      fail_policy unless [parent_before.dev, parent_before.ino] ==
        [parent_path_stat.dev, parent_path_stat.ino]
      parent_identity = directory_identity(parent_before)

      flags = File::RDWR | File::CREAT | File::EXCL | File::NOFOLLOW
      output_file = File.open(path, flags, 0o600)
      output_file.binmode
      created = output_file.stat
      created_identity = [created.dev, created.ino]
      fail_policy unless created.file? && created.nlink == 1 &&
        created.uid == Process.euid && (created.mode & 0o777) == 0o600 && created.size.zero?

      fail_policy unless output_file.write(bytes) == bytes.bytesize
      output_file.flush
      output_file.fsync
      output_file.rewind
      readback = output_file.read(bytes.bytesize + 1)
      final = output_file.stat
      final_identity = descriptor_identity(final)
      fail_policy unless final.file? && final.nlink == 1 && final.uid == Process.euid &&
        (final.mode & 0o777) == 0o600 && final.size == bytes.bytesize && readback == bytes

      after_path = File.lstat(path)
      fail_policy unless descriptor_identity(after_path) == final_identity
      parent_after = parent_file.stat
      parent_after_path = File.lstat(parent)
      validate_private_directory_stat(parent_after)
      validate_private_directory_stat(parent_after_path)
      parent_after_identity = directory_identity(parent_after)
      fail_policy unless parent_after_identity == directory_identity(parent_after_path) &&
        valid_directory_creation_transition?(parent_identity, parent_after_identity)

      output_file.close
      output_file = nil
      parent_file.close
      parent_file = nil
      succeeded = true
    ensure
      output_file&.close
      parent_file&.close
      unless succeeded || created_identity.nil?
        begin
          current = File.lstat(path)
          File.unlink(path) if [current.dev, current.ino] == created_identity
        rescue Errno::ENOENT, Errno::EACCES, Errno::EISDIR, Errno::ELOOP, Errno::ENOTDIR
        end
      end
    end
    Digest::SHA256.hexdigest(bytes)
  rescue Errno::ENOENT, Errno::EACCES, Errno::EEXIST, Errno::EISDIR, Errno::ELOOP,
         Errno::ENOTDIR
    fail_policy
  end

  def write_private_json(path, value)
    write_private_bytes(path, JSON.generate(canonical(value)) + "\n")
  end

  def normalize_json_line_item_pages(input, output, expected_input_sha256)
    pages = read_private_json_lines(input, expected_input_sha256)
    fail_policy if pages.empty?
    items = []
    pages.each do |page|
      exact_keys(page, %w[items])
      page_items = page.fetch("items")
      fail_policy unless page_items.is_a?(Array) && page_items.all?(Hash)
      items.concat(page_items)
    end
    write_private_json(output, items)
  end

  def normalize_workflow_run_pages(input, output, expected_input_sha256)
    pages = read_private_json_lines(input, expected_input_sha256)
    fail_policy if pages.empty?
    page_total_counts = []
    runs = []
    pages.each do |page|
      exact_keys(page, %w[reportedTotalCount runs])
      total = page.fetch("reportedTotalCount")
      page_runs = page.fetch("runs")
      fail_policy unless total.is_a?(Integer) && total >= 0 && page_runs.is_a?(Array)
      page_total_counts << total
      runs.concat(page_runs)
    end
    write_private_json(
      output,
      {
        "reportedTotalCount" => page_total_counts.fetch(0),
        "pageTotalCounts" => page_total_counts,
        "runs" => runs
      }
    )
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

  def normalize_observation(snapshot, expected_master, expected_digests)
    validate_sha1(expected_master)
    fail_policy unless expected_digests.is_a?(Array) &&
      expected_digests.length == OBSERVATION_FILES.length
    expected_digests.each { |value| validate_sha256(value) }
    values = OBSERVATION_FILES.each_with_index.to_h do |filename, index|
      [
        filename,
        strict_json_file(
          File.join(snapshot, filename), expected_sha256: expected_digests.fetch(index)
        )
      ]
    end
    start_anchor = values.fetch("anchor-start-ref.json")
    start_workflow = values.fetch("anchor-start-workflow.json")
    start_content = values.fetch("anchor-start-content.json")
    actor = values.fetch("viewer.json")
    repository = values.fetch("repository.json")
    tags = values.fetch("v-tag-refs.json")
    releases = values.fetch("releases.json")
    runs = values.fetch("workflow-runs.json")
    end_anchor = values.fetch("anchor-end-ref.json")
    end_workflow = values.fetch("anchor-end-workflow.json")
    end_content = values.fetch("anchor-end-content.json")

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

  def read_observation(path, expected_sha256)
    validate_observation(strict_json_file(path, expected_sha256: expected_sha256))
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
    write_private_bytes(destination, bytes)
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

  def validate_receipt_integrity(value, expected_master, expected_digest)
    exact_keys(
      value,
      %w[branch expectedMasterSHA local operation planDigest remote repository schemaVersion]
    )
    fail_policy unless value.fetch("schemaVersion") == SCHEMA_VERSION &&
      value.fetch("operation") == OPERATION && value.fetch("repository") == REPOSITORY &&
      value.fetch("branch") == BRANCH && value.fetch("expectedMasterSHA") == expected_master
    local = exact_keys(value.fetch("local"), %w[headSHA origin toolBlobs])
    validate_sha1(local.fetch("headSHA"))
    fail_policy unless local.fetch("origin") == ORIGIN
    receipt_blobs = exact_keys(local.fetch("toolBlobs"), TOOL_PATHS)
    receipt_blobs.each_value { |blob| validate_sha1(blob) }
    remote = validate_observation(value.fetch("remote"))
    fail_policy unless remote.fetch("masterSHA") == expected_master
    supplied = validate_sha256(expected_digest)
    embedded = validate_sha256(value.fetch("planDigest"))
    body = value.reject { |key, _value| key == "planDigest" }
    actual = digest(body)
    fail_policy unless supplied == embedded && embedded == actual
    [local, remote]
  end

  def validate_receipt(value, expected_master, expected_digest, local_head, tool_blobs)
    local, remote = validate_receipt_integrity(value, expected_master, expected_digest)
    fail_policy unless local.fetch("headSHA") == local_head &&
      local.fetch("toolBlobs") == tool_blobs
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

  def validate_put_response(path, expected_sha256)
    bytes = read_private_bytes(
      path, max_bytes: 65_536, expected_sha256: expected_sha256
    )
    status_and_headers, separator, body = bytes.partition(/\r?\n\r?\n/)
    first_line = status_and_headers.lines.first&.chomp&.delete_suffix("\r")
    fail_policy unless separator.match?(/\A\r?\n\r?\n\z/) && body.empty? &&
      first_line&.match?(/\AHTTP\/(?:1\.1|2(?:\.0)?) 204(?: No Content)?\z/)
  end

  def create_success_receipt(
    plan_receipt_path, expected_digest, expected_master, local_head, helper_blob,
    validator_blob, library_blob, common_library_blob, repository_root,
    pre_first_path, pre_first_sha256, pre_second_path, pre_second_sha256,
    post_first_path, post_first_sha256, post_second_path, post_second_sha256,
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
      read_observation(pre_first_path, pre_first_sha256),
      read_observation(pre_second_path, pre_second_sha256)
    )
    after = same_observation_pair(
      read_observation(post_first_path, post_first_sha256),
      read_observation(post_second_path, post_second_sha256)
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
    when "validate-temporary-parent"
      fail_policy unless argv.length == 1
      STDOUT.write(canonical_temporary_parent(argv.fetch(0)) + "\n")
    when "validate-temporary-root"
      fail_policy unless argv.length == 2
      STDOUT.write(validate_temporary_root(*argv) + "\n")
    when "validate-remote-executable"
      fail_policy unless argv.length == 1
      STDOUT.write(canonical_remote_executable(argv.fetch(0)) + "\n")
    when "validate-remote-config-directory"
      fail_policy unless argv.length == 1
      STDOUT.write(canonical_remote_config_directory(argv.fetch(0)) + "\n")
    when "capture-remote-operation"
      fail_policy unless argv.length == 9
      capture_remote_operation(*argv)
    when "verify-remote-capture"
      fail_policy unless argv.length == 3
      STDOUT.write(verify_remote_capture(*argv) + "\n")
    when "validate-output"
      fail_policy unless argv.length == 2
      output, repository_root = argv
      secure_parent(output, repository_root, expect_absent: true)
    when "normalize-observation"
      fail_policy unless argv.length == 3 + OBSERVATION_FILES.length
      snapshot, expected_master, output, *expected_digests = argv
      normalized = normalize_observation(snapshot, expected_master, expected_digests)
      STDOUT.write(write_private_json(output, normalized) + "\n")
    when "normalize-json-line-item-pages"
      fail_policy unless argv.length == 3
      STDOUT.write(normalize_json_line_item_pages(*argv) + "\n")
    when "normalize-workflow-run-pages"
      fail_policy unless argv.length == 3
      STDOUT.write(normalize_workflow_run_pages(*argv) + "\n")
    when "create-plan"
      fail_policy unless argv.length == 12
      first_path, first_sha256, second_path, second_sha256,
        expected_master, local_head, helper_blob,
        validator_blob, library_blob, common_library_blob, repository_root, output = argv
      first = read_observation(first_path, first_sha256)
      second = read_observation(second_path, second_sha256)
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
      fail_policy unless argv.length == 7
      receipt_path, expected_digest, expected_master,
        first_path, first_sha256, second_path, second_sha256 = argv
      receipt = strict_json_file(receipt_path, secure: true)
      _local, planned = validate_receipt_integrity(
        receipt, expected_master, expected_digest
      )
      first = read_observation(first_path, first_sha256)
      second = read_observation(second_path, second_sha256)
      current = same_observation_pair(first, second)
      fail_policy unless without_state(current) == without_state(planned)
      planned_state = planned.fetch("workflow").fetch("state")
      current_state = current.fetch("workflow").fetch("state")
      fail_policy if planned_state == "disabled_manually" && current_state != "disabled_manually"
      STDOUT.write(current_state + "\n")
    when "validate-post"
      fail_policy unless argv.length == 8
      pre_first_path, pre_first_sha256, pre_second_path, pre_second_sha256,
        post_first_path, post_first_sha256, post_second_path, post_second_sha256 = argv
      pre_first = read_observation(pre_first_path, pre_first_sha256)
      pre_second = read_observation(pre_second_path, pre_second_sha256)
      post_first = read_observation(post_first_path, post_first_sha256)
      post_second = read_observation(post_second_path, post_second_sha256)
      before = same_observation_pair(pre_first, pre_second)
      after = same_observation_pair(post_first, post_second)
      fail_policy unless without_state(before) == without_state(after) &&
        after.fetch("workflow").fetch("state") == "disabled_manually"
    when "validate-put-response"
      fail_policy unless argv.length == 2
      validate_put_response(*argv)
    when "create-success"
      fail_policy unless argv.length == 19
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
