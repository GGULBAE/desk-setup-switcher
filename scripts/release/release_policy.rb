#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "find"
require "json"
require "optparse"
require "psych"
require "rexml/document"
require "tempfile"
require "time"
require "uri"

module ReleasePolicy
  SPDX_VERSION = "SPDX-2.3"
  SPDX_DATA_LICENSE = "CC0-1.0"
  SPDX_PACKAGE_ID = "SPDXRef-Package-DeskSetupSwitcher"
  RELEASE_MANIFEST_SCHEMA = "desk-setup-switcher.release-evidence/v1"
  BUNDLE_MANIFEST_SCHEMA = "desk-setup-switcher.app-bundle/v1"
  GENERATOR = "scripts/release/release_policy.rb"
  REQUIRED_VERIFICATIONS = %w[
    appCodesign
    dmgCodesign
    staplerValidate
    spctlDMG
    spctlApp
  ].freeze
  APP_ARCHITECTURES = %w[arm64 x86_64].freeze
  JSON_STRING_TOKEN = /"(?:[^"\\\x00-\x1f]|\\(?:["\\\/bfnrt]|u[0-9a-fA-F]{4}))*"/.freeze

  class PolicyError < StandardError; end
  class DuplicateJSONKeyError < StandardError; end

  module_function

  def with_regular_file(path, label)
    raise PolicyError, "#{label} is required" unless path.is_a?(String) && !path.empty?

    begin
      before = File.lstat(path)
    rescue SystemCallError
      raise PolicyError, "#{label} is missing"
    end
    raise PolicyError, "#{label} must not be a symlink" if before.symlink?
    raise PolicyError, "#{label} must be a regular file" unless before.file?

    flags = File::RDONLY
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    begin
      File.open(path, flags) do |io|
        opened = io.stat
        unless opened.file? && opened.dev == before.dev && opened.ino == before.ino
          raise PolicyError, "#{label} changed before it could be read"
        end

        result = yield io, opened
        after = io.stat
        unless after.dev == opened.dev && after.ino == opened.ino &&
               after.size == opened.size && after.mtime == opened.mtime && after.ctime == opened.ctime
          raise PolicyError, "#{label} changed while it was read"
        end
        result
      end
    rescue PolicyError
      raise
    rescue SystemCallError
      raise PolicyError, "#{label} could not be read safely"
    end
  end

  def read_utf8(path, label, max_bytes:)
    bytes = with_regular_file(path, label) do |io, stat|
      raise PolicyError, "#{label} exceeds the size limit" if stat.size > max_bytes

      data = io.read(max_bytes + 1)
      raise PolicyError, "#{label} exceeds the size limit" if data.bytesize > max_bytes

      data
    end
    text = bytes.force_encoding(Encoding::UTF_8)
    raise PolicyError, "#{label} is not valid UTF-8" unless text.valid_encoding?
    raise PolicyError, "#{label} contains a null byte" if text.include?("\0")

    text
  end

  def file_identity(path, label)
    digest = Digest::SHA256.new
    size = 0
    with_regular_file(path, label) do |io, _stat|
      while (chunk = io.read(1024 * 1024))
        digest.update(chunk)
        size += chunk.bytesize
      end
    end
    { "sha256" => digest.hexdigest, "size" => size }
  end

  def reject_duplicate_json_keys!(node, label)
    case node
    when Psych::Nodes::Mapping
      seen = {}
      node.children.each_slice(2) do |key_node, value_node|
        unless key_node.is_a?(Psych::Nodes::Scalar)
          raise PolicyError, "#{label} is not valid JSON"
        end
        key = key_node.value
        raise DuplicateJSONKeyError if seen.key?(key)

        seen[key] = true
        reject_duplicate_json_keys!(value_node, label)
      end
    when Psych::Nodes::Sequence
      node.children.each { |child| reject_duplicate_json_keys!(child, label) }
    end
  end

  def parse_strict_json(source, label)
    value = JSON.parse(source, create_additions: false)
    normalized_source = source.gsub(JSON_STRING_TOKEN) do |token|
      JSON.generate(JSON.parse(token, create_additions: false))
    end
    document = Psych.parse(normalized_source)
    raise PolicyError, "#{label} is not valid JSON" unless document&.root

    reject_duplicate_json_keys!(document.root, label)
    value
  rescue DuplicateJSONKeyError
    raise PolicyError, "#{label} contains duplicate JSON keys"
  rescue JSON::ParserError, Psych::SyntaxError
    raise PolicyError, "#{label} is not valid JSON"
  end

  def strict_json(path, label, max_bytes: 16 * 1024 * 1024)
    source = read_utf8(path, label, max_bytes: max_bytes)
    parse_strict_json(source, label)
  end

  def strict_json_with_identity(path, label, max_bytes: 16 * 1024 * 1024)
    source = read_utf8(path, label, max_bytes: max_bytes)
    [
      parse_strict_json(source, label),
      { "sha256" => Digest::SHA256.hexdigest(source.b), "size" => source.bytesize }
    ]
  end

  def sanitize_json_value(value, replacements)
    case value
    when Hash
      value.to_h { |key, child| [key, sanitize_json_value(child, replacements)] }
    when Array
      value.map { |child| sanitize_json_value(child, replacements) }
    when String
      replacements.reduce(value) { |text, (from, to)| text.gsub(from, to) }
    else
      value
    end
  end

  def sanitize_json(input_path:, output_path:, repository_path:, home_path: nil, runner_temp_path: nil)
    value = strict_json(input_path, "JSON evidence")
    replacements = [
      [repository_path, "$REPOSITORY"],
      [home_path, "$HOME"],
      [runner_temp_path, "$RUNNER_TEMP"]
    ].select { |from, _to| from.is_a?(String) && !from.empty? }
    replacements = replacements.each_with_index
                               .sort_by { |(entry, index)| [-entry.fetch(0).bytesize, index] }
                               .map(&:first)
    sanitized = sanitize_json_value(value, replacements)
    atomic_write(output_path, canonical_json(sanitized), "sanitized JSON")
  end

  def ensure_single_line(value, label, max_bytes: 1024)
    unless value.is_a?(String) && !value.empty? && value.bytesize <= max_bytes &&
           value.encoding == Encoding::UTF_8 && value.valid_encoding? &&
           !value.match?(/[\r\n\0]/)
      raise PolicyError, "#{label} is invalid"
    end
    value
  end

  def validate_team_id(team_id)
    ensure_single_line(team_id, "team identifier")
    raise PolicyError, "team identifier is invalid" unless team_id.match?(/\A[A-Z0-9]{10}\z/)

    team_id
  end

  def validate_bundle_identifier(identifier)
    ensure_single_line(identifier, "bundle identifier")
    unless identifier.match?(/\A[A-Za-z0-9][A-Za-z0-9.-]*[A-Za-z0-9]\z/) &&
           identifier.include?(".") && !identifier.include?("..")
      raise PolicyError, "bundle identifier is invalid"
    end
    identifier
  end

  def validate_authority(authority, team_id)
    ensure_single_line(authority, "signing authority")
    unless authority.match?(/\ADeveloper ID Application: .+\z/) &&
           authority.end_with?(" (#{team_id})")
      raise PolicyError, "signing authority is not the expected Developer ID Application identity"
    end
    authority
  end

  def report_values(lines, prefix)
    lines.filter_map do |line|
      next unless line.start_with?(prefix)

      line.delete_prefix(prefix)
    end
  end

  def exactly_one_report_value(lines, prefix, label)
    values = report_values(lines, prefix)
    raise PolicyError, "codesign report must contain exactly one #{label}" unless values.length == 1
    raise PolicyError, "codesign report contains an invalid #{label}" unless values.first == values.first.strip

    values.first
  end

  def runtime_flag?(lines)
    lines.any? do |line|
      matches = line.scan(/flags=0x[0-9A-Fa-f]+\(([^)]*)\)/)
      matches.any? do |match|
        match.first.split(",").map(&:strip).include?("runtime")
      end
    end
  end

  def verify_codesign(report_path:, expected_authority:, expected_team_id:, expected_identifier:, kind:,
                      expected_architecture: nil)
    raise PolicyError, "codesign kind must be app or dmg" unless %w[app dmg].include?(kind)
    if kind == "app"
      unless APP_ARCHITECTURES.include?(expected_architecture)
        raise PolicyError, "application codesign architecture is invalid"
      end
    elsif expected_architecture
      raise PolicyError, "DMG codesign reports must not specify an architecture"
    end

    team_id = validate_team_id(expected_team_id)
    identifier = validate_bundle_identifier(expected_identifier)
    authority = validate_authority(expected_authority, team_id)
    report = read_utf8(report_path, "codesign report", max_bytes: 1024 * 1024)
    lines = report.lines(chomp: true).map { |line| line.delete_suffix("\r") }

    if lines.any? { |line| line.match?(/\ASignature=adhoc\z/i) }
      raise PolicyError, "ad hoc signatures are not allowed"
    end

    authorities = report_values(lines, "Authority=")
    raise PolicyError, "codesign report does not contain a signing authority" if authorities.empty?
    forbidden_authority = authorities.any? do |value|
      value.start_with?("Apple Development:", "Mac App Distribution:",
                        "3rd Party Mac Developer Application:", "Apple Distribution:")
    end
    raise PolicyError, "development or App Store signing identities are not allowed" if forbidden_authority
    unless authorities.first == authority
      raise PolicyError, "first codesign authority does not match the expected Developer ID Application identity"
    end

    actual_team = exactly_one_report_value(lines, "TeamIdentifier=", "team identifier")
    raise PolicyError, "codesign team identifier does not match the expected value" unless actual_team == team_id

    actual_identifier = exactly_one_report_value(lines, "Identifier=", "bundle identifier")
    unless actual_identifier == identifier
      raise PolicyError, "codesign bundle identifier does not match the expected value"
    end

    timestamp = exactly_one_report_value(lines, "Timestamp=", "secure timestamp")
    if timestamp.empty? || %w[none n/a].include?(timestamp.downcase) || timestamp.casecmp("not set").zero?
      raise PolicyError, "codesign secure timestamp is missing"
    end

    if kind == "app" && !runtime_flag?(lines)
      raise PolicyError, "application signature does not contain the hardened runtime flag"
    end

    if kind == "app"
      format = exactly_one_report_value(lines, "Format=", "application format")
      expected_format = "app bundle with Mach-O thin (#{expected_architecture})"
      unless format == expected_format
        raise PolicyError, "application codesign report does not match its architecture"
      end
    end

    cdhash_values = report_values(lines, "CDHash=")
    if kind == "app"
      unless cdhash_values.length == 1 && cdhash_values.first.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/)
        raise PolicyError, "application codesign report must contain exactly one valid CDHash"
      end
    elsif cdhash_values.length > 1 ||
          (cdhash_values.length == 1 && !cdhash_values.first.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/))
      raise PolicyError, "DMG codesign report contains an invalid CDHash"
    end

    {
      "authority" => authority,
      "teamIdentifier" => team_id,
      "bundleIdentifier" => identifier,
      "cdhash" => cdhash_values.first,
      "architecture" => expected_architecture
    }
  end

  def verify_app_codesign_reports(report_specs:, expected_authority:, expected_team_id:, expected_identifier:)
    mappings = parse_named_values(report_specs, "application codesign report")
    unless mappings.keys.sort == APP_ARCHITECTURES
      raise PolicyError, "application codesign reports must exactly match the required architectures"
    end

    signings = APP_ARCHITECTURES.map do |architecture|
      verify_codesign(
        report_path: mappings.fetch(architecture),
        expected_authority: expected_authority,
        expected_team_id: expected_team_id,
        expected_identifier: expected_identifier,
        kind: "app",
        expected_architecture: architecture
      )
    end
    first = signings.first
    {
      "authority" => first["authority"],
      "teamIdentifier" => first["teamIdentifier"],
      "bundleIdentifier" => first["bundleIdentifier"],
      "cdhashes" => signings.each_with_object({}) do |signing, result|
        result[signing.fetch("architecture")] = signing.fetch("cdhash")
      end
    }
  end

  def verify_entitlements(absent:, plist_path:)
    if absent
      raise PolicyError, "entitlements absence and plist path are mutually exclusive" if plist_path

      return true
    end
    raise PolicyError, "use --absent or provide an entitlement plist" unless plist_path

    xml = read_utf8(plist_path, "entitlement plist", max_bytes: 1024 * 1024)
    raise PolicyError, "entitlement plist contains an entity declaration" if xml.match?(/<!ENTITY/i)

    begin
      document = REXML::Document.new(xml)
    rescue REXML::ParseException
      raise PolicyError, "entitlement plist is not valid XML"
    end
    root = document.root
    attributes = root ? root.attributes.to_h.transform_values(&:to_s) : {}
    unless root && root.name == "plist" && attributes == { "version" => "1.0" }
      raise PolicyError, "entitlement plist must have a canonical plist root"
    end

    elements = root.children.select { |node| node.is_a?(REXML::Element) }
    unless elements.length == 1 && elements.first.name == "dict"
      raise PolicyError, "entitlement plist must contain exactly one dictionary"
    end
    significant_root_nodes = root.children.reject do |node|
      node.is_a?(REXML::Element) || node.is_a?(REXML::Comment) ||
        (node.is_a?(REXML::Text) && node.value.strip.empty?)
    end
    raise PolicyError, "entitlement plist contains unexpected content" unless significant_root_nodes.empty?

    dictionary = elements.first
    significant_dictionary_nodes = dictionary.children.reject do |node|
      node.is_a?(REXML::Comment) || (node.is_a?(REXML::Text) && node.value.strip.empty?)
    end
    unless significant_dictionary_nodes.empty?
      raise PolicyError, "release entitlements must be an empty dictionary"
    end

    true
  end

  UUID_PATTERN = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def verify_notary(json_path)
    data = strict_json(json_path, "notary result", max_bytes: 2 * 1024 * 1024)
    raise PolicyError, "notary result must be a JSON object" unless data.is_a?(Hash)

    identifier = data["id"]
    status = data["status"]
    raise PolicyError, "notary result contains an invalid submission UUID" unless identifier.is_a?(String) && identifier.match?(UUID_PATTERN)
    raise PolicyError, "notary status is not Accepted" unless status == "Accepted"

    { "id" => identifier.downcase, "status" => status }
  end

  def verify_notary_log(json_path, expected_submission_id:, expected_archive_name:, expected_sha256:)
    data, identity = strict_json_with_identity(json_path, "notary log", max_bytes: 16 * 1024 * 1024)
    raise PolicyError, "notary log must be a JSON object" unless data.is_a?(Hash)

    expected_id = ensure_single_line(expected_submission_id, "notary submission UUID").downcase
    unless expected_id.match?(UUID_PATTERN)
      raise PolicyError, "notary submission UUID is invalid"
    end
    archive_name = validate_asset_name(expected_archive_name)
    submitted_sha256 = validate_sha256(expected_sha256, "submitted DMG digest")

    job_id = data["jobId"]
    unless job_id.is_a?(String) && job_id.match?(UUID_PATTERN) && job_id.downcase == expected_id
      raise PolicyError, "notary log does not match the submitted job"
    end
    raise PolicyError, "notary log status is not Accepted" unless data["status"] == "Accepted"
    raise PolicyError, "notary log status code is not zero" unless data["statusCode"] == 0
    ensure_single_line(data["statusSummary"], "notary status summary", max_bytes: 1024)
    unless data["archiveFilename"] == archive_name
      raise PolicyError, "notary log archive name does not match the submitted DMG"
    end
    log_sha256 = data["sha256"]
    unless log_sha256.is_a?(String) && log_sha256.downcase == submitted_sha256
      raise PolicyError, "notary log digest does not match the submitted DMG"
    end
    issues = data["issues"]
    unless issues.nil? || issues.is_a?(Array)
      raise PolicyError, "notary log issues must be null or an array"
    end
    if Array(issues).any? { |issue| issue.is_a?(Hash) && issue["severity"].to_s.downcase == "error" }
      raise PolicyError, "Accepted notary log contains an error issue"
    end

    {
      "id" => expected_id,
      "status" => "Accepted",
      "archiveFilename" => archive_name,
      "submittedSha256" => submitted_sha256,
      "logSha256" => identity["sha256"],
      "logSize" => identity["size"]
    }
  end

  SEMVER_PATTERN = /\A(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?\z/

  def validate_release_identity(version:, tag:, commit:, namespace:, created:)
    ensure_single_line(version, "version")
    raise PolicyError, "version must be valid SemVer" unless version.match?(SEMVER_PATTERN)
    raise PolicyError, "release tag must exactly match the version" unless tag == "v#{version}"
    raise PolicyError, "release commit must be a lowercase 40-character SHA" unless commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)

    begin
      uri = URI.parse(namespace.to_s)
    rescue URI::InvalidURIError
      raise PolicyError, "release namespace must be a valid HTTPS URI"
    end
    unless uri.scheme == "https" && uri.host && !uri.host.empty? && uri.userinfo.nil?
      raise PolicyError, "release namespace must be a valid HTTPS URI"
    end

    begin
      parsed_time = Time.iso8601(created.to_s)
    rescue ArgumentError
      raise PolicyError, "creation time must be canonical UTC RFC3339"
    end
    canonical_created = parsed_time.utc.strftime("%Y-%m-%dT%H:%M:%SZ")
    unless created == canonical_created
      raise PolicyError, "creation time must be canonical UTC RFC3339"
    end

    {
      "version" => version,
      "tag" => tag,
      "commit" => commit,
      "namespace" => namespace,
      "created" => created
    }
  end

  def validate_build_number(build_number)
    ensure_single_line(build_number, "build number")
    unless build_number.match?(/\A[1-9][0-9]*(?:\.[0-9]+){0,2}\z/)
      raise PolicyError, "build number is invalid"
    end
    build_number
  end

  def designated_requirement_evidence(path, identifier:, team_id:)
    text = read_utf8(path, "designated requirement", max_bytes: 256 * 1024)
    requirement_lines = text.lines.map(&:strip).select { |line| line.start_with?("designated =>") }
    unless requirement_lines.length == 1
      raise PolicyError, "designated requirement output must contain exactly one requirement"
    end
    normalized = requirement_lines.first.gsub(/\s+/, " ")
    unless normalized.include?(%(identifier "#{identifier}")) && normalized.match?(/(?:^|[^A-Z0-9])#{Regexp.escape(team_id)}(?:[^A-Z0-9]|$)/)
      raise PolicyError, "designated requirement does not bind the expected application identity"
    end
    { "normalized" => normalized }
  end

  def effective_entitlements_evidence(absent:, plist_path:)
    verify_entitlements(absent: absent, plist_path: plist_path)
    if absent
      { "state" => "absent", "keys" => [] }
    else
      { "state" => "empty-dictionary", "keys" => [] }
    end
  end

  def validate_sha256(value, label)
    unless value.is_a?(String) && value.match?(/\A[0-9a-f]{64}\z/)
      raise PolicyError, "#{label} must be a lowercase SHA-256 digest"
    end
    value
  end

  def validate_nonnegative_integer(value, label)
    raise PolicyError, "#{label} must be a nonnegative integer" unless value.is_a?(Integer) && value >= 0

    value
  end

  def parse_integer_option(value, label, positive: false)
    parsed = value.is_a?(Integer) ? value : Integer(value, 10)
    if positive ? parsed <= 0 : parsed.negative?
      raise PolicyError, "#{label} is outside the allowed range"
    end
    parsed
  rescue ArgumentError, TypeError
    raise PolicyError, "#{label} must be an integer"
  end

  def validate_package_dump(path)
    dump = strict_json(path, "Package.swift dump")
    unless dump.is_a?(Hash) && dump["name"].is_a?(String) && !dump["name"].empty? &&
           dump["products"].is_a?(Array) && dump["targets"].is_a?(Array) &&
           dump.key?("dependencies") && dump["dependencies"].is_a?(Array)
      raise PolicyError, "Package.swift dump does not have the expected structure"
    end
    unless dump["dependencies"].empty?
      raise PolicyError, "Package.swift dump contains third-party package dependencies"
    end

    0
  end

  def canonical_json(data, pretty: true)
    output = pretty ? JSON.pretty_generate(data) : JSON.generate(data)
    output << "\n" if pretty
    output
  end

  def atomic_write(path, bytes, label)
    raise PolicyError, "#{label} output path is required" unless path.is_a?(String) && !path.empty?

    directory = File.dirname(File.expand_path(path))
    raise PolicyError, "#{label} output directory is missing" unless File.directory?(directory)
    if File.exist?(path) || File.symlink?(path)
      current = File.lstat(path)
      raise PolicyError, "#{label} output must not be a symlink" if current.symlink?
      raise PolicyError, "#{label} output must be a regular file" unless current.file?
    end

    Tempfile.create([".release-policy-", ".tmp"], directory) do |temp|
      temp.binmode
      temp.write(bytes)
      temp.flush
      temp.fsync
      temp.chmod(0o644)
      temp.close
      File.rename(temp.path, path)
    end
  rescue PolicyError
    raise
  rescue SystemCallError
    raise PolicyError, "#{label} output could not be written safely"
  end

  def generate_sbom(dmg_path:, expected_sha256:, expected_size:, version:, tag:, commit:,
                    namespace:, created:, package_dump_path:, output_path:)
    identity = validate_release_identity(
      version: version,
      tag: tag,
      commit: commit,
      namespace: namespace,
      created: created
    )
    expected_digest = validate_sha256(expected_sha256, "expected DMG digest")
    expected_bytes = parse_integer_option(expected_size, "expected DMG size")
    raise PolicyError, "candidate file must have a .dmg name" unless File.basename(dmg_path.to_s).end_with?(".dmg")

    actual = file_identity(dmg_path, "final DMG")
    raise PolicyError, "final DMG digest does not match the expected candidate" unless actual["sha256"] == expected_digest
    raise PolicyError, "final DMG size does not match the expected candidate" unless actual["size"] == expected_bytes
    dependency_count = validate_package_dump(package_dump_path)

    package = {
      "name" => "Desk Setup Switcher",
      "SPDXID" => SPDX_PACKAGE_ID,
      "versionInfo" => identity["version"],
      "packageFileName" => File.basename(dmg_path),
      "downloadLocation" => "NOASSERTION",
      "filesAnalyzed" => false,
      "licenseConcluded" => "MIT",
      "licenseDeclared" => "MIT",
      "copyrightText" => "NOASSERTION",
      "primaryPackagePurpose" => "APPLICATION",
      "checksums" => [
        { "algorithm" => "SHA256", "checksumValue" => actual["sha256"] }
      ],
      "sourceInfo" => "releaseTag=#{identity['tag']}; commit=#{identity['commit']}; dmgSizeBytes=#{actual['size']}; swiftPackageThirdPartyDependencies=#{dependency_count}; applePlatformFrameworks=system-provided-not-bundled; releaseSiteDependencies=build-time-only-not-bundled",
      "comment" => "Package.swift dump verified zero third-party Swift package dependencies. Apple platform frameworks are system-provided, and release-site dependencies are build-time tooling; neither is bundled in the DMG."
    }
    document = {
      "spdxVersion" => SPDX_VERSION,
      "dataLicense" => SPDX_DATA_LICENSE,
      "SPDXID" => "SPDXRef-DOCUMENT",
      "name" => "Desk Setup Switcher #{identity['version']} release candidate",
      "documentNamespace" => identity["namespace"],
      "creationInfo" => {
        "created" => identity["created"],
        "creators" => ["Tool: #{GENERATOR}"]
      },
      "documentDescribes" => [SPDX_PACKAGE_ID],
      "packages" => [package],
      "relationships" => [
        {
          "spdxElementId" => "SPDXRef-DOCUMENT",
          "relationshipType" => "DESCRIBES",
          "relatedSpdxElement" => SPDX_PACKAGE_ID
        }
      ]
    }
    atomic_write(output_path, canonical_json(document), "SBOM")
    document
  end

  def verify_sbom(sbom_path:, dmg_path:, version:, tag:, commit:)
    expected_identity = validate_release_identity(
      version: version,
      tag: tag,
      commit: commit,
      namespace: "https://example.invalid/release-policy-validation",
      created: "1970-01-01T00:00:00Z"
    )
    document = strict_json(sbom_path, "SBOM")
    exact_keys!(document,
                %w[spdxVersion dataLicense SPDXID name documentNamespace creationInfo documentDescribes packages relationships],
                "SBOM document")
    raise PolicyError, "SBOM version is not SPDX-2.3" unless document["spdxVersion"] == SPDX_VERSION
    raise PolicyError, "SBOM data license is invalid" unless document["dataLicense"] == SPDX_DATA_LICENSE
    raise PolicyError, "SBOM document SPDX identifier is invalid" unless document["SPDXID"] == "SPDXRef-DOCUMENT"
    raise PolicyError, "SBOM document name is invalid" unless document["name"] == "Desk Setup Switcher #{version} release candidate"

    begin
      namespace_uri = URI.parse(document["documentNamespace"].to_s)
    rescue URI::InvalidURIError
      raise PolicyError, "SBOM document namespace is invalid"
    end
    unless namespace_uri.scheme == "https" && namespace_uri.host && !namespace_uri.host.empty? && namespace_uri.userinfo.nil?
      raise PolicyError, "SBOM document namespace is invalid"
    end

    creation = document["creationInfo"]
    exact_keys!(creation, %w[created creators], "SBOM creation information")
    validate_release_identity(
      version: version,
      tag: tag,
      commit: commit,
      namespace: document["documentNamespace"],
      created: creation["created"]
    )
    unless creation["creators"] == ["Tool: #{GENERATOR}"]
      raise PolicyError, "SBOM creator is invalid"
    end
    unless document["documentDescribes"] == [SPDX_PACKAGE_ID]
      raise PolicyError, "SBOM documentDescribes does not identify the candidate package"
    end
    unless document["relationships"] == [{
      "spdxElementId" => "SPDXRef-DOCUMENT",
      "relationshipType" => "DESCRIBES",
      "relatedSpdxElement" => SPDX_PACKAGE_ID
    }]
      raise PolicyError, "SBOM DESCRIBES relationship is invalid"
    end

    packages = document["packages"]
    raise PolicyError, "SBOM must contain exactly one package" unless packages.is_a?(Array) && packages.length == 1
    package = packages.first
    exact_keys!(package,
                %w[name SPDXID versionInfo packageFileName downloadLocation filesAnalyzed licenseConcluded licenseDeclared copyrightText primaryPackagePurpose checksums sourceInfo comment],
                "SBOM package")
    unless package["name"] == "Desk Setup Switcher" && package["SPDXID"] == SPDX_PACKAGE_ID &&
           package["versionInfo"] == expected_identity["version"] && package["packageFileName"] == File.basename(dmg_path) &&
           package["downloadLocation"] == "NOASSERTION" && package["filesAnalyzed"] == false &&
           package["licenseConcluded"] == "MIT" && package["licenseDeclared"] == "MIT" &&
           package["copyrightText"] == "NOASSERTION" && package["primaryPackagePurpose"] == "APPLICATION"
      raise PolicyError, "SBOM package identity or license is invalid"
    end
    expected_comment = "Package.swift dump verified zero third-party Swift package dependencies. Apple platform frameworks are system-provided, and release-site dependencies are build-time tooling; neither is bundled in the DMG."
    raise PolicyError, "SBOM dependency scope statement is invalid" unless package["comment"] == expected_comment

    actual_dmg = file_identity(dmg_path, "final DMG")
    unless package["checksums"] == [{ "algorithm" => "SHA256", "checksumValue" => actual_dmg["sha256"] }]
      raise PolicyError, "SBOM DMG checksum does not match the candidate"
    end
    expected_source_info = "releaseTag=#{expected_identity['tag']}; commit=#{expected_identity['commit']}; dmgSizeBytes=#{actual_dmg['size']}; swiftPackageThirdPartyDependencies=0; applePlatformFrameworks=system-provided-not-bundled; releaseSiteDependencies=build-time-only-not-bundled"
    unless package["sourceInfo"] == expected_source_info
      raise PolicyError, "SBOM candidate or dependency evidence is invalid"
    end
    document
  end

  def validate_relative_bundle_path(path)
    unless path.is_a?(String) && path.valid_encoding? && !path.empty? &&
           !path.start_with?("/") && !path.include?("\\") && !path.match?(/[\0\r\n]/) &&
           path.split("/").none? { |component| component.empty? || component == "." || component == ".." }
      raise PolicyError, "application bundle contains an invalid entry name"
    end
    path
  end

  def build_bundle_manifest(app_path)
    begin
      root_stat = File.lstat(app_path)
    rescue SystemCallError
      raise PolicyError, "application bundle is missing"
    end
    raise PolicyError, "application bundle must not be a symlink" if root_stat.symlink?
    raise PolicyError, "application bundle must be a directory" unless root_stat.directory?
    root_name = ensure_single_line(File.basename(app_path), "application bundle name")
    raise PolicyError, "application bundle must have an .app name" unless root_name.end_with?(".app")

    root = File.expand_path(app_path)
    entries = []
    begin
      Find.find(root) do |entry_path|
        next if entry_path == root

        relative = entry_path.delete_prefix("#{root}/")
        validate_relative_bundle_path(relative)
        stat = File.lstat(entry_path)
        raise PolicyError, "application bundle contains a symlink" if stat.symlink?

        mode = format("%04o", stat.mode & 0o7777)
        if stat.directory?
          entries << { "path" => relative, "type" => "directory", "mode" => mode }
        elsif stat.file?
          identity = file_identity(entry_path, "application bundle file")
          entries << {
            "path" => relative,
            "type" => "file",
            "mode" => mode,
            "size" => identity["size"],
            "sha256" => identity["sha256"]
          }
        else
          raise PolicyError, "application bundle contains a non-regular entry"
        end
      end
    rescue PolicyError
      raise
    rescue SystemCallError
      raise PolicyError, "application bundle could not be enumerated safely"
    end

    entries.sort_by! { |entry| entry["path"].b }
    canonical = {
      "schemaVersion" => BUNDLE_MANIFEST_SCHEMA,
      "rootName" => root_name,
      "entries" => entries
    }
    digest = Digest::SHA256.hexdigest(canonical_json(canonical, pretty: false))
    {
      "schemaVersion" => BUNDLE_MANIFEST_SCHEMA,
      "rootName" => root_name,
      "entryCount" => entries.length,
      "canonicalSha256" => digest,
      "entries" => entries
    }
  end

  def generate_bundle_manifest(app_path:, output_path:)
    manifest = build_bundle_manifest(app_path)
    atomic_write(output_path, canonical_json(manifest), "bundle manifest")
    manifest
  end

  def validate_asset_name(name)
    ensure_single_line(name, "release asset name", max_bytes: 255)
    unless name == File.basename(name) && name != "." && name != ".." &&
           name.match?(/\A[A-Za-z0-9][A-Za-z0-9._+()-]*\z/)
      raise PolicyError, "release asset name is invalid"
    end
    name
  end

  def parse_named_values(specs, label)
    result = {}
    Array(specs).each do |spec|
      name, value = spec.to_s.split("=", 2)
      if value.nil? || value.empty?
        raise PolicyError, "#{label} must use NAME=VALUE"
      end
      validate_asset_name(name) if label == "release asset"
      if label == "toolchain field"
        unless name.match?(/\A[a-z][a-z0-9._-]*\z/)
          raise PolicyError, "toolchain field name is invalid"
        end
        ensure_single_line(value, "toolchain field value", max_bytes: 512)
      end
      raise PolicyError, "#{label} names must be unique" if result.key?(name)

      result[name] = value
    end
    result
  end

  def asset_entries(asset_specs)
    mappings = parse_named_values(asset_specs, "release asset")
    raise PolicyError, "at least one release asset is required" if mappings.empty?

    mappings.keys.sort.map do |name|
      identity = file_identity(mappings.fetch(name), "release asset")
      { "name" => name, "sha256" => identity["sha256"], "size" => identity["size"] }
    end
  end

  def verification_passes?(name, text)
    normalized = text.gsub("\r\n", "\n").lines.map(&:strip).reject(&:empty?).join("\n")
    lower = normalized.downcase
    return false if lower.match?(/(?:^|\b)(?:failed|failure|rejected|invalid|error)(?:\b|$)/)

    case name
    when "appCodesign", "dmgCodesign"
      lower.include?("valid on disk") && lower.include?("satisfies its designated requirement")
    when "staplerValidate"
      lower.include?("the validate action worked")
    when "spctlDMG", "spctlApp"
      lower.include?("accepted") && lower.include?("source=notarized developer id")
    else
      false
    end
  end

  def verification_records(specs)
    mappings = parse_named_values(specs, "verification")
    unless mappings.keys.sort == REQUIRED_VERIFICATIONS.sort
      raise PolicyError, "release verification records must exactly match the required set"
    end

    mappings.keys.sort.map do |name|
      validate_asset_name(name)
      text = read_utf8(mappings.fetch(name), "verification output", max_bytes: 256 * 1024)
      unless verification_passes?(name, text)
        raise PolicyError, "release verification output does not prove a passing result"
      end
      identity = file_identity(mappings.fetch(name), "verification output")
      {
        "name" => name,
        "sha256" => identity["sha256"],
        "size" => identity["size"],
        "result" => "pass",
        "output" => text
      }
    end
  end

  def validate_run(run_id:, run_attempt:, run_url:)
    id = parse_integer_option(run_id, "workflow run id", positive: true)
    attempt = parse_integer_option(run_attempt, "workflow run attempt", positive: true)
    begin
      uri = URI.parse(run_url.to_s)
    rescue URI::InvalidURIError
      raise PolicyError, "workflow run URL must be a valid HTTPS URL"
    end
    unless uri.scheme == "https" && uri.host == "github.com" && uri.userinfo.nil?
      raise PolicyError, "workflow run URL must be a valid GitHub HTTPS URL"
    end
    { "id" => id, "attempt" => attempt, "url" => run_url }
  end

  def validate_toolchain(specs)
    fields = parse_named_values(specs, "toolchain field")
    raise PolicyError, "at least one toolchain field is required" if fields.empty?

    fields.keys.sort.each_with_object({}) { |key, sorted| sorted[key] = fields.fetch(key) }
  end

  def generate_release_manifest(version:, build_number:, tag:, commit:, namespace:, created:, run_id:, run_attempt:,
                                run_url:, toolchain_specs:, app_path:, codesign_report_specs:,
                                expected_authority:, expected_team_id:, expected_identifier:,
                                executable_path:, designated_requirement_path:,
                                entitlements_absent:, entitlements_plist_path:,
                                pre_notary_dmg_path:, final_dmg_path:, notary_json_path:, notary_log_path:,
                                asset_specs:, verification_specs:, output_path:)
    release = validate_release_identity(
      version: version,
      tag: tag,
      commit: commit,
      namespace: namespace,
      created: created
    )
    release["buildNumber"] = validate_build_number(build_number)
    release["run"] = validate_run(run_id: run_id, run_attempt: run_attempt, run_url: run_url)
    toolchain = validate_toolchain(toolchain_specs)
    signing = verify_app_codesign_reports(
      report_specs: codesign_report_specs,
      expected_authority: expected_authority,
      expected_team_id: expected_team_id,
      expected_identifier: expected_identifier
    )
    bundle = build_bundle_manifest(app_path)
    executable = file_identity(executable_path, "application executable")
    executable["name"] = ensure_single_line(File.basename(executable_path), "application executable name")
    designated_requirement = designated_requirement_evidence(
      designated_requirement_path,
      identifier: signing["bundleIdentifier"],
      team_id: signing["teamIdentifier"]
    )
    effective_entitlements = effective_entitlements_evidence(
      absent: entitlements_absent,
      plist_path: entitlements_plist_path
    )
    pre_notary = file_identity(pre_notary_dmg_path, "pre-notary DMG")
    final_dmg = file_identity(final_dmg_path, "final stapled DMG")
    if pre_notary["sha256"] == final_dmg["sha256"]
      raise PolicyError, "pre-notary and final stapled DMG digests must differ"
    end
    notary_result = verify_notary(notary_json_path)
    notary = verify_notary_log(
      notary_log_path,
      expected_submission_id: notary_result["id"],
      expected_archive_name: File.basename(final_dmg_path),
      expected_sha256: pre_notary["sha256"]
    )
    assets = asset_entries(asset_specs)
    verifications = verification_records(verification_specs)
    final_name = validate_asset_name(File.basename(final_dmg_path))
    final_asset = assets.find { |asset| asset["name"] == final_name }
    unless final_asset && final_asset["sha256"] == final_dmg["sha256"] && final_asset["size"] == final_dmg["size"]
      raise PolicyError, "release assets do not contain the exact final stapled DMG"
    end

    manifest = {
      "schemaVersion" => RELEASE_MANIFEST_SCHEMA,
      "generator" => GENERATOR,
      "release" => release,
      "toolchain" => toolchain,
      "application" => {
        "bundleIdentifier" => signing["bundleIdentifier"],
        "teamIdentifier" => signing["teamIdentifier"],
        "authority" => signing["authority"],
        "cdhashes" => signing["cdhashes"],
        "executable" => {
          "name" => executable["name"],
          "sha256" => executable["sha256"],
          "size" => executable["size"]
        },
        "designatedRequirement" => designated_requirement,
        "effectiveEntitlements" => effective_entitlements,
        "bundleManifest" => {
          "schemaVersion" => bundle["schemaVersion"],
          "rootName" => bundle["rootName"],
          "entryCount" => bundle["entryCount"],
          "canonicalSha256" => bundle["canonicalSha256"]
        }
      },
      "lineage" => {
        "preNotaryDmg" => pre_notary,
        "notary" => notary,
        "finalStapledDmg" => {
          "name" => final_name,
          "sha256" => final_dmg["sha256"],
          "size" => final_dmg["size"]
        }
      },
      "verifications" => verifications,
      "assets" => assets
    }
    validate_release_manifest_data(manifest)
    atomic_write(output_path, canonical_json(manifest), "release manifest")
    manifest
  end

  def exact_keys!(hash, keys, label)
    unless hash.is_a?(Hash) && hash.keys.sort == keys.sort
      raise PolicyError, "#{label} does not have the expected fields"
    end
  end

  def validate_asset_records(records)
    raise PolicyError, "release manifest assets must be a nonempty array" unless records.is_a?(Array) && !records.empty?

    names = records.map do |record|
      exact_keys!(record, %w[name sha256 size], "release asset record")
      validate_asset_name(record["name"])
      validate_sha256(record["sha256"], "release asset digest")
      validate_nonnegative_integer(record["size"], "release asset size")
      record["name"]
    end
    raise PolicyError, "release manifest asset names must be unique" unless names.uniq.length == names.length
    raise PolicyError, "release manifest assets must be sorted by name" unless names == names.sort

    records
  end

  def validate_bundle_summary(summary)
    exact_keys!(summary, %w[schemaVersion rootName entryCount canonicalSha256], "bundle manifest summary")
    raise PolicyError, "bundle manifest schema is unsupported" unless summary["schemaVersion"] == BUNDLE_MANIFEST_SCHEMA
    ensure_single_line(summary["rootName"], "application bundle name")
    raise PolicyError, "application bundle name must end in .app" unless summary["rootName"].end_with?(".app")
    validate_nonnegative_integer(summary["entryCount"], "bundle manifest entry count")
    validate_sha256(summary["canonicalSha256"], "bundle manifest digest")
    summary
  end

  def validate_release_manifest_data(manifest)
    exact_keys!(manifest, %w[schemaVersion generator release toolchain application lineage verifications assets], "release manifest")
    raise PolicyError, "release manifest schema is unsupported" unless manifest["schemaVersion"] == RELEASE_MANIFEST_SCHEMA
    raise PolicyError, "release manifest generator is unsupported" unless manifest["generator"] == GENERATOR

    release = manifest["release"]
    exact_keys!(release, %w[version tag commit namespace created buildNumber run], "release identity")
    validate_release_identity(
      version: release["version"],
      tag: release["tag"],
      commit: release["commit"],
      namespace: release["namespace"],
      created: release["created"]
    )
    validate_build_number(release["buildNumber"])
    run = release["run"]
    exact_keys!(run, %w[id attempt url], "workflow run identity")
    validate_run(run_id: run["id"], run_attempt: run["attempt"], run_url: run["url"])

    toolchain = manifest["toolchain"]
    raise PolicyError, "release manifest toolchain must be a nonempty object" unless toolchain.is_a?(Hash) && !toolchain.empty?
    unless toolchain.keys == toolchain.keys.sort
      raise PolicyError, "release manifest toolchain fields must be sorted"
    end
    toolchain.each do |name, value|
      unless name.match?(/\A[a-z][a-z0-9._-]*\z/)
        raise PolicyError, "toolchain field name is invalid"
      end
      ensure_single_line(value, "toolchain field value", max_bytes: 512)
    end

    application = manifest["application"]
    exact_keys!(application,
                %w[bundleIdentifier teamIdentifier authority cdhashes executable designatedRequirement effectiveEntitlements bundleManifest],
                "application evidence")
    team = validate_team_id(application["teamIdentifier"])
    validate_bundle_identifier(application["bundleIdentifier"])
    validate_authority(application["authority"], team)
    cdhashes = application["cdhashes"]
    unless cdhashes.is_a?(Hash) && cdhashes.keys == APP_ARCHITECTURES
      raise PolicyError, "application CDHashes must exactly match the required architectures"
    end
    valid_cdhashes = cdhashes.values.all? do |cdhash|
      cdhash.is_a?(String) && cdhash.match?(/\A[0-9a-f]{40}(?:[0-9a-f]{24})?\z/)
    end
    unless valid_cdhashes
      raise PolicyError, "application CDHash is invalid"
    end
    unless cdhashes.values.uniq.length == APP_ARCHITECTURES.length
      raise PolicyError, "application CDHashes must be unique by architecture"
    end
    executable = application["executable"]
    exact_keys!(executable, %w[name sha256 size], "application executable evidence")
    ensure_single_line(executable["name"], "application executable name")
    validate_sha256(executable["sha256"], "application executable digest")
    validate_nonnegative_integer(executable["size"], "application executable size")

    requirement = application["designatedRequirement"]
    exact_keys!(requirement, %w[normalized], "designated requirement evidence")
    normalized_requirement = ensure_single_line(requirement["normalized"], "designated requirement", max_bytes: 16 * 1024)
    unless normalized_requirement.start_with?("designated =>") &&
           normalized_requirement.include?(%(identifier "#{application['bundleIdentifier']}")) &&
           normalized_requirement.match?(/(?:^|[^A-Z0-9])#{Regexp.escape(team)}(?:[^A-Z0-9]|$)/)
      raise PolicyError, "designated requirement evidence does not bind the application identity"
    end
    entitlements = application["effectiveEntitlements"]
    raise PolicyError, "effective entitlements evidence must be an object" unless entitlements.is_a?(Hash)
    case entitlements["state"]
    when "absent"
      exact_keys!(entitlements, %w[state keys], "effective entitlements evidence")
    when "empty-dictionary"
      exact_keys!(entitlements, %w[state keys], "effective entitlements evidence")
    else
      raise PolicyError, "effective entitlements state is invalid"
    end
    raise PolicyError, "effective release entitlements must have zero keys" unless entitlements["keys"] == []
    validate_bundle_summary(application["bundleManifest"])

    lineage = manifest["lineage"]
    exact_keys!(lineage, %w[preNotaryDmg notary finalStapledDmg], "candidate lineage")
    pre_notary = lineage["preNotaryDmg"]
    exact_keys!(pre_notary, %w[sha256 size], "pre-notary DMG evidence")
    validate_sha256(pre_notary["sha256"], "pre-notary DMG digest")
    validate_nonnegative_integer(pre_notary["size"], "pre-notary DMG size")
    notary = lineage["notary"]
    exact_keys!(notary, %w[id status archiveFilename submittedSha256 logSha256 logSize], "notary evidence")
    unless notary["id"].is_a?(String) && notary["id"].match?(UUID_PATTERN)
      raise PolicyError, "notary evidence UUID is invalid"
    end
    raise PolicyError, "notary evidence status is not Accepted" unless notary["status"] == "Accepted"
    validate_asset_name(notary["archiveFilename"])
    validate_sha256(notary["submittedSha256"], "notary submitted DMG digest")
    validate_sha256(notary["logSha256"], "notary log digest")
    validate_nonnegative_integer(notary["logSize"], "notary log size")
    unless notary["submittedSha256"] == pre_notary["sha256"]
      raise PolicyError, "notary evidence is not bound to the pre-notary DMG"
    end
    final_dmg = lineage["finalStapledDmg"]
    exact_keys!(final_dmg, %w[name sha256 size], "final stapled DMG evidence")
    validate_asset_name(final_dmg["name"])
    validate_sha256(final_dmg["sha256"], "final stapled DMG digest")
    validate_nonnegative_integer(final_dmg["size"], "final stapled DMG size")
    if pre_notary["sha256"] == final_dmg["sha256"]
      raise PolicyError, "pre-notary and final stapled DMG digests must differ"
    end
    unless notary["archiveFilename"] == final_dmg["name"]
      raise PolicyError, "notary evidence archive name does not match the final DMG name"
    end


    verifications = manifest["verifications"]
    unless verifications.is_a?(Array) && !verifications.empty?
      raise PolicyError, "release verification records must be a nonempty array"
    end
    verification_names = verifications.map do |record|
      exact_keys!(record, %w[name sha256 size result output], "release verification record")
      validate_asset_name(record["name"])
      validate_sha256(record["sha256"], "release verification digest")
      validate_nonnegative_integer(record["size"], "release verification size")
      raise PolicyError, "release verification result is not pass" unless record["result"] == "pass"
      output = record["output"]
      unless output.is_a?(String) && output.valid_encoding? && output.bytesize <= 256 * 1024 && !output.include?("\0")
        raise PolicyError, "release verification output is invalid"
      end
      unless Digest::SHA256.hexdigest(output.b) == record["sha256"] && output.bytesize == record["size"]
        raise PolicyError, "release verification output does not match its digest"
      end
      unless verification_passes?(record["name"], output)
        raise PolicyError, "release verification output does not prove a passing result"
      end
      record["name"]
    end
    unless verification_names == verification_names.sort && verification_names.uniq.length == verification_names.length
      raise PolicyError, "release verification records must be unique and sorted"
    end
    unless verification_names == REQUIRED_VERIFICATIONS.sort
      raise PolicyError, "release verification records must exactly match the required set"
    end

    assets = validate_asset_records(manifest["assets"])
    final_asset = assets.find { |asset| asset["name"] == final_dmg["name"] }
    unless final_asset && final_asset["sha256"] == final_dmg["sha256"] && final_asset["size"] == final_dmg["size"]
      raise PolicyError, "release manifest does not bind the exact final stapled DMG"
    end
    manifest
  end

  def load_release_manifest(path)
    manifest = strict_json(path, "release manifest")
    validate_release_manifest_data(manifest)
  end

  def verify_asset_mappings(records, specs)
    mappings = parse_named_values(specs, "release asset")
    expected_names = records.map { |record| record["name"] }
    unless mappings.keys.sort == expected_names.sort
      raise PolicyError, "provided release assets do not exactly match the manifest"
    end

    records.each do |record|
      actual = file_identity(mappings.fetch(record["name"]), "release asset")
      unless actual["sha256"] == record["sha256"] && actual["size"] == record["size"]
        raise PolicyError, "release asset digest or size does not match the manifest"
      end
    end
    mappings
  end

  def verify_release_manifest(manifest_path:, asset_specs:, expected_version:, expected_build_number:,
                              expected_tag:, expected_commit:, expected_namespace:, expected_created:,
                              expected_run_id:, expected_run_attempt:, expected_run_url:)
    manifest = load_release_manifest(manifest_path)
    expected_release = validate_release_identity(
      version: expected_version,
      tag: expected_tag,
      commit: expected_commit,
      namespace: expected_namespace,
      created: expected_created
    )
    expected_release["buildNumber"] = validate_build_number(expected_build_number)
    expected_release["run"] = validate_run(
      run_id: expected_run_id,
      run_attempt: expected_run_attempt,
      run_url: expected_run_url
    )
    unless manifest["release"] == expected_release
      raise PolicyError, "release manifest identity does not match the expected candidate"
    end

    mappings = verify_asset_mappings(manifest["assets"], asset_specs)
    result_path = mappings["notary-result.json"]
    log_path = mappings["notary-log.json"]
    unless result_path && log_path
      raise PolicyError, "release manifest is missing exact notary evidence assets"
    end
    result = verify_notary(result_path)
    expected_notary = manifest.dig("lineage", "notary")
    unless result["id"] == expected_notary["id"] && result["status"] == expected_notary["status"]
      raise PolicyError, "notary result does not match the release manifest"
    end
    log = verify_notary_log(
      log_path,
      expected_submission_id: result["id"],
      expected_archive_name: manifest.dig("lineage", "finalStapledDmg", "name"),
      expected_sha256: manifest.dig("lineage", "preNotaryDmg", "sha256")
    )
    unless log == expected_notary
      raise PolicyError, "notary log does not match the release manifest"
    end
    manifest
  end

  def verify_mounted_app(manifest_path:, app_path:, dmg_path:, codesign_report_specs:,
                         codesign_verify_path:, executable_path:, designated_requirement_path:,
                         entitlements_absent:, entitlements_plist_path:)
    manifest = load_release_manifest(manifest_path)
    expected_application = manifest["application"]
    signing = verify_app_codesign_reports(
      report_specs: codesign_report_specs,
      expected_authority: expected_application["authority"],
      expected_team_id: expected_application["teamIdentifier"],
      expected_identifier: expected_application["bundleIdentifier"]
    )
    unless signing["cdhashes"] == expected_application["cdhashes"]
      raise PolicyError, "mounted application CDHashes do not match the signed candidate"
    end
    codesign_verify = read_utf8(codesign_verify_path, "mounted application codesign verification", max_bytes: 256 * 1024)
    unless verification_passes?("appCodesign", codesign_verify)
      raise PolicyError, "mounted application codesign verification did not pass"
    end
    expected_executable = expected_application["executable"]
    actual_executable = file_identity(executable_path, "mounted application executable")
    unless File.basename(executable_path) == expected_executable["name"] &&
           actual_executable["sha256"] == expected_executable["sha256"] &&
           actual_executable["size"] == expected_executable["size"]
      raise PolicyError, "mounted application executable does not match the signed candidate"
    end
    actual_requirement = designated_requirement_evidence(
      designated_requirement_path,
      identifier: expected_application["bundleIdentifier"],
      team_id: expected_application["teamIdentifier"]
    )
    unless actual_requirement["normalized"] == expected_application["designatedRequirement"]["normalized"]
      raise PolicyError, "mounted application designated requirement does not match the signed candidate"
    end

    expected_entitlements = expected_application["effectiveEntitlements"]
    if expected_entitlements["state"] == "absent"
      unless entitlements_absent && entitlements_plist_path.nil?
        raise PolicyError, "mounted application entitlement state does not match the signed candidate"
      end
    elsif entitlements_absent || entitlements_plist_path.nil?
      raise PolicyError, "mounted application entitlement state does not match the signed candidate"
    end
    verify_entitlements(absent: entitlements_absent, plist_path: entitlements_plist_path)

    expected_bundle = manifest["application"]["bundleManifest"]
    actual_bundle = build_bundle_manifest(app_path)
    unless actual_bundle["schemaVersion"] == expected_bundle["schemaVersion"] &&
           actual_bundle["rootName"] == expected_bundle["rootName"] &&
           actual_bundle["entryCount"] == expected_bundle["entryCount"] &&
           actual_bundle["canonicalSha256"] == expected_bundle["canonicalSha256"]
      raise PolicyError, "mounted application bundle does not match the signed candidate manifest"
    end

    expected_dmg = manifest["lineage"]["finalStapledDmg"]
    actual_dmg = file_identity(dmg_path, "redownloaded final DMG")
    unless actual_dmg["sha256"] == expected_dmg["sha256"] && actual_dmg["size"] == expected_dmg["size"]
      raise PolicyError, "redownloaded final DMG does not match the release manifest"
    end
    true
  end

  def required!(options, *keys)
    keys.each do |key|
      value = options[key]
      missing = value.nil? || (value.respond_to?(:empty?) && value.empty?)
      raise PolicyError, "required command option is missing" if missing
    end
  end

  def option_parser(banner)
    OptionParser.new do |parser|
      parser.banner = banner
      parser.on("-h", "--help", "Show this help") do
        puts parser
        exit 0
      end
    end
  end

  def parse_common_identity(parser, options)
    parser.on("--version VERSION") { |value| options[:version] = value }
    parser.on("--tag TAG") { |value| options[:tag] = value }
    parser.on("--commit SHA") { |value| options[:commit] = value }
    parser.on("--namespace URI") { |value| options[:namespace] = value }
    parser.on("--created RFC3339Z") { |value| options[:created] = value }
  end

  def parse_codesign_identity(parser, options)
    parser.on("--app-codesign-report ARCH=FILE") { |value| options[:codesign_reports] << value }
    parser.on("--authority VALUE") { |value| options[:authority] = value }
    parser.on("--team-id TEAM_ID") { |value| options[:team_id] = value }
    parser.on("--identifier BUNDLE_ID") { |value| options[:identifier] = value }
  end

  def parse_exact!(parser, arguments)
    parser.parse!(arguments)
    raise PolicyError, "unexpected positional arguments" unless arguments.empty?
  rescue OptionParser::ParseError
    raise PolicyError, "invalid command options"
  end

  def run_cli(argv)
    command = argv.shift
    case command
    when "verify-json"
      options = {}
      parser = option_parser("Usage: release_policy.rb verify-json --json FILE")
      parser.on("--json FILE") { |value| options[:json] = value }
      parse_exact!(parser, argv)
      required!(options, :json)
      strict_json(options[:json], "JSON evidence")
      puts "OK json"
    when "sanitize-json"
      options = {}
      parser = option_parser("Usage: release_policy.rb sanitize-json --json FILE --output FILE --repository PATH [--home PATH] [--runner-temp PATH]")
      parser.on("--json FILE") { |value| options[:json] = value }
      parser.on("--output FILE") { |value| options[:output] = value }
      parser.on("--repository PATH") { |value| options[:repository] = value }
      parser.on("--home PATH") { |value| options[:home] = value }
      parser.on("--runner-temp PATH") { |value| options[:runner_temp] = value }
      parse_exact!(parser, argv)
      required!(options, :json, :output, :repository)
      sanitize_json(
        input_path: options[:json],
        output_path: options[:output],
        repository_path: options[:repository],
        home_path: options[:home],
        runner_temp_path: options[:runner_temp]
      )
      puts "OK sanitized-json"
    when "verify-codesign"
      options = {}
      parser = option_parser("Usage: release_policy.rb verify-codesign --report FILE --authority VALUE --team-id ID --identifier ID --kind app|dmg [--architecture arm64|x86_64]")
      parser.on("--report FILE") { |value| options[:report] = value }
      parser.on("--authority VALUE") { |value| options[:authority] = value }
      parser.on("--team-id TEAM_ID") { |value| options[:team_id] = value }
      parser.on("--identifier BUNDLE_ID") { |value| options[:identifier] = value }
      parser.on("--kind KIND") { |value| options[:kind] = value }
      parser.on("--architecture ARCH") { |value| options[:architecture] = value }
      parse_exact!(parser, argv)
      required!(options, :report, :authority, :team_id, :identifier, :kind)
      verify_codesign(
        report_path: options[:report],
        expected_authority: options[:authority],
        expected_team_id: options[:team_id],
        expected_identifier: options[:identifier],
        kind: options[:kind],
        expected_architecture: options[:architecture]
      )
      puts "OK codesign"
    when "verify-entitlements"
      options = { absent: false }
      parser = option_parser("Usage: release_policy.rb verify-entitlements (--absent | --plist FILE)")
      parser.on("--absent") { options[:absent] = true }
      parser.on("--plist FILE") { |value| options[:plist] = value }
      parse_exact!(parser, argv)
      verify_entitlements(absent: options[:absent], plist_path: options[:plist])
      puts "OK entitlements"
    when "verify-notary"
      options = { print_id: false }
      parser = option_parser("Usage: release_policy.rb verify-notary --json FILE [--print-id]")
      parser.on("--json FILE") { |value| options[:json] = value }
      parser.on("--print-id") { options[:print_id] = true }
      parse_exact!(parser, argv)
      required!(options, :json)
      result = verify_notary(options[:json])
      puts(options[:print_id] ? result.fetch("id") : "OK notary")
    when "generate-sbom"
      options = {}
      parser = option_parser("Usage: release_policy.rb generate-sbom --dmg FILE --sha256 DIGEST --size BYTES --version VERSION --tag TAG --commit SHA --namespace URI --created RFC3339Z --package-dump FILE --output FILE")
      parser.on("--dmg FILE") { |value| options[:dmg] = value }
      parser.on("--sha256 DIGEST") { |value| options[:sha256] = value }
      parser.on("--size BYTES") { |value| options[:size] = value }
      parse_common_identity(parser, options)
      parser.on("--package-dump FILE") { |value| options[:package_dump] = value }
      parser.on("--output FILE") { |value| options[:output] = value }
      parse_exact!(parser, argv)
      required!(options, :dmg, :sha256, :size, :version, :tag, :commit, :namespace, :created, :package_dump, :output)
      generate_sbom(
        dmg_path: options[:dmg],
        expected_sha256: options[:sha256],
        expected_size: options[:size],
        version: options[:version],
        tag: options[:tag],
        commit: options[:commit],
        namespace: options[:namespace],
        created: options[:created],
        package_dump_path: options[:package_dump],
        output_path: options[:output]
      )
      puts "OK sbom"
    when "verify-sbom"
      options = {}
      parser = option_parser("Usage: release_policy.rb verify-sbom --sbom FILE --dmg FILE --version VERSION --tag TAG --commit SHA")
      parser.on("--sbom FILE") { |value| options[:sbom] = value }
      parser.on("--dmg FILE") { |value| options[:dmg] = value }
      parser.on("--version VERSION") { |value| options[:version] = value }
      parser.on("--tag TAG") { |value| options[:tag] = value }
      parser.on("--commit SHA") { |value| options[:commit] = value }
      parse_exact!(parser, argv)
      required!(options, :sbom, :dmg, :version, :tag, :commit)
      verify_sbom(
        sbom_path: options[:sbom], dmg_path: options[:dmg], version: options[:version],
        tag: options[:tag], commit: options[:commit]
      )
      puts "OK sbom-verified"
    when "generate-bundle-manifest"
      options = {}
      parser = option_parser("Usage: release_policy.rb generate-bundle-manifest --app APP --output FILE")
      parser.on("--app APP") { |value| options[:app] = value }
      parser.on("--output FILE") { |value| options[:output] = value }
      parse_exact!(parser, argv)
      required!(options, :app, :output)
      generate_bundle_manifest(app_path: options[:app], output_path: options[:output])
      puts "OK bundle-manifest"
    when "generate-release-manifest"
      options = { toolchain: [], codesign_reports: [], assets: [], verifications: [] }
      parser = option_parser("Usage: release_policy.rb generate-release-manifest [identity/run/signing/lineage options] --toolchain NAME=VALUE --asset NAME=PATH --output FILE")
      parse_common_identity(parser, options)
      parser.on("--build-number BUILD") { |value| options[:build_number] = value }
      parser.on("--run-id ID") { |value| options[:run_id] = value }
      parser.on("--run-attempt N") { |value| options[:run_attempt] = value }
      parser.on("--run-url URL") { |value| options[:run_url] = value }
      parser.on("--toolchain NAME=VALUE") { |value| options[:toolchain] << value }
      parser.on("--app APP") { |value| options[:app] = value }
      parse_codesign_identity(parser, options)
      parser.on("--executable FILE") { |value| options[:executable] = value }
      parser.on("--designated-requirement FILE") { |value| options[:designated_requirement] = value }
      parser.on("--entitlements-absent") { options[:entitlements_absent] = true }
      parser.on("--entitlements-plist FILE") { |value| options[:entitlements_plist] = value }
      parser.on("--pre-notary-dmg FILE") { |value| options[:pre_notary_dmg] = value }
      parser.on("--final-dmg FILE") { |value| options[:final_dmg] = value }
      parser.on("--notary-json FILE") { |value| options[:notary_json] = value }
      parser.on("--notary-log FILE") { |value| options[:notary_log] = value }
      parser.on("--asset NAME=PATH") { |value| options[:assets] << value }
      parser.on("--verification NAME=FILE") { |value| options[:verifications] << value }
      parser.on("--output FILE") { |value| options[:output] = value }
      parse_exact!(parser, argv)
      required!(options, :version, :build_number, :tag, :commit, :namespace, :created, :run_id, :run_attempt,
                :run_url, :toolchain, :app, :codesign_reports, :authority, :team_id, :identifier,
                :executable, :designated_requirement, :pre_notary_dmg, :final_dmg, :notary_json, :notary_log,
                :assets, :verifications, :output)
      generate_release_manifest(
        version: options[:version], build_number: options[:build_number], tag: options[:tag], commit: options[:commit],
        namespace: options[:namespace], created: options[:created], run_id: options[:run_id],
        run_attempt: options[:run_attempt], run_url: options[:run_url],
        toolchain_specs: options[:toolchain], app_path: options[:app],
        codesign_report_specs: options[:codesign_reports], expected_authority: options[:authority],
        expected_team_id: options[:team_id], expected_identifier: options[:identifier],
        executable_path: options[:executable], designated_requirement_path: options[:designated_requirement],
        entitlements_absent: options[:entitlements_absent] || false,
        entitlements_plist_path: options[:entitlements_plist],
        pre_notary_dmg_path: options[:pre_notary_dmg], final_dmg_path: options[:final_dmg],
        notary_json_path: options[:notary_json], notary_log_path: options[:notary_log], asset_specs: options[:assets],
        verification_specs: options[:verifications], output_path: options[:output]
      )
      puts "OK release-manifest"
    when "verify-release-manifest"
      options = { assets: [] }
      parser = option_parser("Usage: release_policy.rb verify-release-manifest --manifest FILE --version VERSION --build-number BUILD --tag TAG --commit SHA --namespace URI --created RFC3339Z --run-id ID --run-attempt N --run-url URL --asset NAME=PATH [--asset NAME=PATH ...]")
      parser.on("--manifest FILE") { |value| options[:manifest] = value }
      parse_common_identity(parser, options)
      parser.on("--build-number BUILD") { |value| options[:build_number] = value }
      parser.on("--run-id ID") { |value| options[:run_id] = value }
      parser.on("--run-attempt N") { |value| options[:run_attempt] = value }
      parser.on("--run-url URL") { |value| options[:run_url] = value }
      parser.on("--asset NAME=PATH") { |value| options[:assets] << value }
      parse_exact!(parser, argv)
      required!(options, :manifest, :version, :build_number, :tag, :commit, :namespace, :created,
                :run_id, :run_attempt, :run_url, :assets)
      verify_release_manifest(
        manifest_path: options[:manifest], asset_specs: options[:assets],
        expected_version: options[:version], expected_build_number: options[:build_number],
        expected_tag: options[:tag], expected_commit: options[:commit],
        expected_namespace: options[:namespace], expected_created: options[:created],
        expected_run_id: options[:run_id], expected_run_attempt: options[:run_attempt],
        expected_run_url: options[:run_url]
      )
      puts "OK release-manifest-assets"
    when "verify-mounted-app"
      options = { codesign_reports: [], entitlements_absent: false }
      parser = option_parser("Usage: release_policy.rb verify-mounted-app --manifest FILE --app APP --dmg FILE --app-codesign-report ARCH=FILE --app-codesign-verify FILE (--entitlements-absent | --entitlements-plist FILE)")
      parser.on("--manifest FILE") { |value| options[:manifest] = value }
      parser.on("--app APP") { |value| options[:app] = value }
      parser.on("--dmg FILE") { |value| options[:dmg] = value }
      parser.on("--app-codesign-report ARCH=FILE") { |value| options[:codesign_reports] << value }
      parser.on("--app-codesign-verify FILE") { |value| options[:codesign_verify] = value }
      parser.on("--executable FILE") { |value| options[:executable] = value }
      parser.on("--designated-requirement FILE") { |value| options[:designated_requirement] = value }
      parser.on("--entitlements-absent") { options[:entitlements_absent] = true }
      parser.on("--entitlements-plist FILE") { |value| options[:entitlements_plist] = value }
      parse_exact!(parser, argv)
      required!(options, :manifest, :app, :dmg, :codesign_reports, :codesign_verify, :executable, :designated_requirement)
      verify_mounted_app(
        manifest_path: options[:manifest], app_path: options[:app], dmg_path: options[:dmg],
        codesign_report_specs: options[:codesign_reports], codesign_verify_path: options[:codesign_verify],
        executable_path: options[:executable], designated_requirement_path: options[:designated_requirement],
        entitlements_absent: options[:entitlements_absent], entitlements_plist_path: options[:entitlements_plist]
      )
      puts "OK mounted-app"
    when nil, "help", "--help", "-h"
      puts <<~USAGE
        Usage: release_policy.rb COMMAND [options]

        Commands:
        verify-codesign
        verify-json
        sanitize-json
        verify-entitlements
        verify-notary
        generate-sbom
        verify-sbom
        generate-bundle-manifest
        generate-release-manifest
        verify-release-manifest
        verify-mounted-app

        Run `release_policy.rb COMMAND --help` for command options.
      USAGE
    else
      raise PolicyError, "unknown release policy command"
    end
    0
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit ReleasePolicy.run_cli(ARGV.dup)
  rescue ReleasePolicy::PolicyError => error
    warn "ERROR: #{error.message}"
    exit 1
  rescue StandardError
    warn "ERROR: release policy validation failed"
    exit 70
  end
end
