#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "pathname"

module PublicCopyState
  SCHEMA_VERSION = "desk-setup-switcher.site-release/v1"
  VERSION = "0.1.0"
  TAG = "v0.1.0"
  RELEASE_URL = "https://github.com/GGULBAE/desk-setup-switcher/releases/tag/v0.1.0"
  ADVISORY_URL = "https://github.com/GGULBAE/desk-setup-switcher/security/advisories/new"

  MANIFEST_PATH = "site/release-publication.json"
  MANIFEST_KEYS = %w[releaseURL schemaVersion state tag version].freeze
  SITE_MANIFEST_PATH = "site/site-publication.json"
  SITE_SCHEMA_VERSION = "desk-setup-switcher.site-origin/v1"
  SITE_MANIFEST_KEYS = %w[schemaVersion siteURL state].freeze
  STATEFUL_DOCUMENT_PATHS = [
    "README.md",
    "docs/guides/README.md",
    "docs/guides/USER-GUIDE.md",
    "docs/guides/USER-GUIDE.ko.md",
    "docs/PRIVACY.md",
    "docs/SUPPORT-MATRIX.md",
    "SECURITY.md",
    "SUPPORT.md"
  ].freeze
  STATE_NEUTRAL_REQUIREMENTS = {
    ".github/ISSUE_TEMPLATE/support_question.yml" => [
      [/Supported downloads come only from versioned GitHub Releases; local and CI artifacts are unsupported\./i, "the lifecycle-neutral supported-download boundary"]
    ]
  }.freeze
  DOCUMENT_PATHS = (STATEFUL_DOCUMENT_PATHS + STATE_NEUTRAL_REQUIREMENTS.keys).freeze

  HOLDING_REQUIREMENTS = {
    "README.md" => [
      [/there is no supported public download yet/i, "the no-supported-public-download notice"]
    ],
    "docs/guides/README.md" => [
      [/there is no supported download yet/i, "the English no-supported-download notice"],
      [/아직 지원되는 다운로드는 없습니다/, "the Korean no-supported-download notice"]
    ],
    "docs/guides/USER-GUIDE.md" => [
      [/there is no supported public download yet/i, "the no-supported-public-download notice"]
    ],
    "docs/guides/USER-GUIDE.ko.md" => [
      [/아직 지원되는 공개 다운로드가 없습니다/, "the Korean no-supported-public-download notice"]
    ],
    "docs/PRIVACY.md" => [
      [/No site has been deployed or approved yet/i, "the no-deployed-site notice"],
      [/Private vulnerability reporting is currently disabled/i, "the disabled-private-reporting notice"],
      [/no public release exists/i, "the no-public-release notice"]
    ],
    "docs/SUPPORT-MATRIX.md" => [
      [/tracked closed-schema launch state remains `holding` with no download URL/i, "the tracked holding-state notice"],
      [/canonical site\/release publication.{0,160}remain pending/im, "the pending canonical-publication notice"]
    ],
    "SECURITY.md" => [
      [/there is no public release yet/i, "the no-public-release notice"],
      [/v0\.1\.0.{0,160}not published yet/im, "the v0.1.0 not-published notice"]
    ],
    "SUPPORT.md" => [
      [/there is currently no supported public download/i, "the no-supported-public-download notice"]
    ]
  }.freeze

  HOLDING_CTA_PATTERNS = [
    /\bdownload\s+(?:the\s+)?(?:supported\s+)?v0\.1\.0(?:\s+(?:release|public beta))?\b/i,
    /\bget\s+v0\.1\.0\b/i,
    /\bv0\.1\.0\s+is\s+(?:now\s+)?(?:published|publicly available|supported)\b/i,
    /\bv0\.1\.0.{0,48}\b(?:available now|download now)\b/im,
    /v0\.1\.0(?:을|를)?\s*(?:지금\s*)?(?:다운로드|내려받으세요|받으세요)/,
    /v0\.1\.0(?:은|는|이|가)\s*(?:현재\s*)?(?:공개되었|공개되어|지원되는)/,
    /\bdownload\s+(?:the\s+)?(?:supported\s+)?public[- ]beta\b/i,
    /\bget\s+(?:the\s+)?(?:supported\s+)?public[- ]beta\b/i,
    /(?:public\s*beta|공개\s*베타)(?:를|을)?\s*(?:지금\s*)?(?:다운로드|내려받으세요|받으세요)/i
  ].freeze

  STALE_PUBLISHED_PATTERNS = [
    /\bno supported (?:public )?downloads?\b/i,
    /\bthere is no public release yet\b/i,
    /\bnot (?:yet )?published\b/i,
    /\bpreparing (?:its|the) first public beta\b/i,
    /\bplanned (?:initial|first) public[- ]beta\b/i,
    /\bplanned public[- ]beta\b/i,
    /\bpublic[- ]beta.{0,60}\b(?:planned|pending)\b/im,
    /\bpublication.{0,60}\b(?:planned|pending)\b/im,
    /\bv0\.1\.0 release.{0,60}\b(?:planned|pending)\b/im,
    /\bafter (?:the )?(?:supported|official) release (?:exists|is published)\b/i,
    /\bafter the official release\b/i,
    /\bafter v0\.1\.0 is (?:approved and )?published\b/i,
    /\bbefore the first public beta\b/i,
    /\bbecomes supported only after\b/i,
    /\bfuture signed release path\b/i,
    /\b(?:publication|release) (?:is )?pending\b/i,
    /\bpending (?:publication|release)\b/i,
    /\bprivate (?:vulnerability )?reporting (?:is|remains) (?:currently )?(?:disabled|not enabled)\b/i,
    /\buntil a repository administrator enables it\b/i,
    /\bno (?:public )?site has been deployed(?: or approved)?(?: yet)?\b/i,
    /\bplanned Cloudflare Worker\b/i,
    /\bfuture public site\b/i,
    /지원되는 (?:공개 )?다운로드(?:가|는) 없습니다/,
    /첫 public beta를 준비/i,
    /public beta 예정/i,
    /public beta.{0,60}(?:예정|계획|대기 중)/im,
    /계획된 첫 public beta/i,
    /v0\.1\.0.{0,100}공개된 뒤/im,
    /정식 공개 후/,
    /공개 릴리스가 생긴 뒤/,
    /비공개 (?:취약점 )?신고(?: 기능)?(?:은|는|이|가)?\s*.{0,40}(?:비활성|활성화되지)/m
  ].freeze

  GITHUB_RELEASE_URL_PATTERN = %r!https?://github\.com/[^\s/]+/[^\s/]+/releases(?:/[^\s\])}>]*)?!
  MARKDOWN_LINK_PATTERN = /\[([^\]]+)\]\(([^)]+)\)/

  PUBLISHED_IDENTITY_REQUIREMENTS = {
    "README.md" => [
      [/\bv0\.1\.0 is the supported public beta\b/i, "the affirmative v0.1.0 supported-public-beta statement"]
    ],
    "docs/guides/README.md" => [
      [/\bv0\.1\.0 is the published, supported public beta\b/i, "the affirmative English v0.1.0 public identity"],
      [/v0\.1\.0은 공개되어 지원되는 public beta입니다/, "the affirmative Korean v0.1.0 public identity"]
    ],
    "docs/guides/USER-GUIDE.md" => [
      [/\bv0\.1\.0 is the supported public beta\b/i, "the affirmative v0.1.0 supported-public-beta statement"]
    ],
    "docs/guides/USER-GUIDE.ko.md" => [
      [/v0\.1\.0은 공개되어 지원되는 public beta입니다/, "the affirmative Korean v0.1.0 public identity"]
    ],
    "docs/PRIVACY.md" => [
      [/\bv0\.1\.0 is the supported public beta\b/i, "the affirmative v0.1.0 supported-public-beta statement"],
      [/private vulnerability reporting is enabled/i, "the enabled-private-reporting statement"]
    ],
    "docs/SUPPORT-MATRIX.md" => [
      [/tracked closed-schema launch state is published with the canonical v0\.1\.0 URL/i, "the tracked published-state statement"],
      [/private vulnerability reporting is enabled/i, "the enabled-private-reporting statement"]
    ],
    "SECURITY.md" => [
      [/\bv0\.1\.0 is the latest public beta and is supported\b/i, "the affirmative latest-supported-public-beta statement"]
    ],
    "SUPPORT.md" => [
      [/\bv0\.1\.0 is the supported public beta\b/i, "the affirmative v0.1.0 supported-public-beta statement"]
    ]
  }.freeze

  SUPPORT_MATRIX_STALE_PUBLISHED_PATTERNS = [
    /tracked closed-schema launch state remains `holding`/i,
    /current app remains ad-hoc signed development evidence only/i,
    /private vulnerability reporting.{0,160}remain pending/im,
    /canonical site\/release publication.{0,160}remain pending/im
  ].freeze

  class Error < StandardError; end
  class DuplicateKeyError < Error; end

  class UniqueKeyHash < Hash
    def []=(key, value)
      raise DuplicateKeyError, "duplicate JSON key #{key.inspect}" if key?(key)

      super
    end
  end

  class Gate
    attr_reader :assertions

    def initialize(root)
      @root = Pathname.new(root).expand_path
      @assertions = 0
    end

    def run
      check(@root.directory?, "--root must name an existing repository directory")
      manifest = load_manifest
      site_manifest = load_site_manifest
      verify_manifest_pair(manifest, site_manifest)
      documents = STATEFUL_DOCUMENT_PATHS.to_h { |path| [path, read_utf8(path)] }
      neutral_documents = STATE_NEUTRAL_REQUIREMENTS.keys.to_h { |path| [path, read_utf8(path)] }
      verify_state_neutral(neutral_documents)

      case manifest.fetch("state")
      when "holding"
        verify_holding(manifest, documents)
      when "published"
        verify_published(manifest, documents)
      else
        check(false, "release publication state must be exactly holding or published")
      end

      [manifest.fetch("state"), documents.length + neutral_documents.length]
    end

    private

    def check(condition, message)
      @assertions += 1
      raise Error, message unless condition
    end

    def read_utf8(relative_path)
      path = @root.join(relative_path)
      check(path.file?, "required file is missing: #{relative_path}")
      contents = path.binread.force_encoding(Encoding::UTF_8)
      check(contents.valid_encoding?, "required file is not valid UTF-8: #{relative_path}")
      contents
    end

    def load_manifest
      source = read_utf8(MANIFEST_PATH)
      begin
        manifest = JSON.parse(source, object_class: UniqueKeyHash)
      rescue JSON::ParserError, DuplicateKeyError => error
        raise Error, "#{MANIFEST_PATH} is not strict JSON: #{error.message}"
      end

      decoded_keys = source.scan(/"((?:\\.|[^"\\])*)"\s*:/).flatten.map do |encoded_key|
        JSON.parse(%("#{encoded_key}"))
      end
      duplicate_key = decoded_keys.tally.find { |_key, count| count > 1 }&.first
      raise Error, "#{MANIFEST_PATH} is not strict JSON: duplicate JSON key #{duplicate_key.inspect}" if duplicate_key

      check(manifest.instance_of?(UniqueKeyHash), "#{MANIFEST_PATH} must contain one JSON object")
      check(manifest.keys.sort == MANIFEST_KEYS, "#{MANIFEST_PATH} must use the closed v1 schema with exactly #{MANIFEST_KEYS.join(', ')}")
      check(manifest["schemaVersion"] == SCHEMA_VERSION, "schemaVersion must be exactly #{SCHEMA_VERSION}")
      check(manifest["version"] == VERSION, "version must be exactly #{VERSION}")
      check(manifest["tag"] == TAG, "tag must be exactly #{TAG}")
      check(%w[holding published].include?(manifest["state"]), "release publication state must be exactly holding or published")
      check(manifest["releaseURL"].nil? || manifest["releaseURL"].instance_of?(String), "releaseURL must be null or a string")
      manifest
    end

    def load_site_manifest
      source = read_utf8(SITE_MANIFEST_PATH)
      begin
        manifest = JSON.parse(source, object_class: UniqueKeyHash)
      rescue JSON::ParserError, DuplicateKeyError => error
        raise Error, "#{SITE_MANIFEST_PATH} is not strict JSON: #{error.message}"
      end

      decoded_keys = source.scan(/"((?:\\.|[^"\\])*)"\s*:/).flatten.map do |encoded_key|
        JSON.parse(%("#{encoded_key}"))
      end
      duplicate_key = decoded_keys.tally.find { |_key, count| count > 1 }&.first
      raise Error, "#{SITE_MANIFEST_PATH} is not strict JSON: duplicate JSON key #{duplicate_key.inspect}" if duplicate_key

      check(manifest.instance_of?(UniqueKeyHash), "#{SITE_MANIFEST_PATH} must contain one JSON object")
      check(manifest.keys.sort == SITE_MANIFEST_KEYS, "#{SITE_MANIFEST_PATH} must use the closed v1 schema with exactly #{SITE_MANIFEST_KEYS.join(', ')}")
      check(manifest["schemaVersion"] == SITE_SCHEMA_VERSION, "site schemaVersion must be exactly #{SITE_SCHEMA_VERSION}")
      check(%w[holding approved].include?(manifest["state"]), "site publication state must be exactly holding or approved")
      check(manifest["siteURL"].nil? || manifest["siteURL"].instance_of?(String), "siteURL must be null or a string")
      manifest
    end

    def verify_manifest_pair(release_manifest, site_manifest)
      case release_manifest.fetch("state")
      when "holding"
        check(site_manifest["state"] == "holding", "holding release publication requires holding site-origin approval")
        check(site_manifest["siteURL"].nil?, "holding site-origin approval requires siteURL to be null")
      when "published"
        check(site_manifest["state"] == "approved", "published release publication requires approved site-origin approval")
        check(site_manifest["siteURL"].instance_of?(String) && !site_manifest["siteURL"].empty?, "approved site-origin approval requires a nonempty siteURL")
      end
    end

    def verify_holding(manifest, documents)
      check(manifest["releaseURL"].nil?, "holding state requires releaseURL to be null")

      documents.each do |path, contents|
        HOLDING_REQUIREMENTS.fetch(path).each do |pattern, label|
          check(contents.match?(pattern), "#{path} must retain #{label} while publication is holding")
        end
        check(!contents.include?(RELEASE_URL), "#{path} must not contain the canonical v0.1.0 release URL while publication is holding")
        check(HOLDING_CTA_PATTERNS.none? { |pattern| contents.match?(pattern) }, "#{path} must not claim that v0.1.0 is published, supported, or available to download while publication is holding")
        check(!holding_download_link?(contents), "#{path} must not link a download/get-public-beta call to action to GitHub Releases while publication is holding")
      end
    end

    def verify_state_neutral(documents)
      documents.each do |path, contents|
        STATE_NEUTRAL_REQUIREMENTS.fetch(path).each do |pattern, label|
          check(contents.match?(pattern), "#{path} must retain #{label} in every publication state")
        end
        check(!contents.match?(/there is no supported public release until v0\.1\.0 is published/i), "#{path} must not encode a lifecycle-specific pre-publication claim")
      end
    end

    def verify_published(manifest, documents)
      check(manifest["releaseURL"] == RELEASE_URL, "published state requires the exact canonical release URL #{RELEASE_URL}")

      documents.each do |path, contents|
        searchable = contents.delete("`")
        check(STALE_PUBLISHED_PATTERNS.none? { |pattern| searchable.match?(pattern) }, "#{path} contains stale holding, planned/pending lifecycle, or disabled-private-reporting copy")
        PUBLISHED_IDENTITY_REQUIREMENTS.fetch(path).each do |pattern, label|
          check(searchable.match?(pattern), "#{path} must contain #{label}")
        end
        check(contents.include?(TAG), "#{path} must identify #{TAG} in published state")
        check(contents.include?(RELEASE_URL), "#{path} must include the exact canonical release URL #{RELEASE_URL}")
        release_links = contents.scan(GITHUB_RELEASE_URL_PATTERN).map { |url| url.sub(/[.,;:]\z/, "") }
        check(release_links.all? { |url| url == RELEASE_URL }, "#{path} contains a non-canonical GitHub release-tag URL")
      end

      support_matrix = documents.fetch("docs/SUPPORT-MATRIX.md")
      check(SUPPORT_MATRIX_STALE_PUBLISHED_PATTERNS.none? { |pattern| support_matrix.match?(pattern) }, "docs/SUPPORT-MATRIX.md contains stale current publication evidence")
      verify_security(documents.fetch("SECURITY.md").delete("`"))
      verify_support(documents.fetch("SUPPORT.md").delete("`"))
    end

    def holding_download_link?(contents)
      contents.scan(MARKDOWN_LINK_PATTERN).any? do |label, destination|
        destination.match?(%r!https?://github\.com/[^\s/]+/[^\s/]+/releases(?:/|\z)!) &&
          label.match?(/\b(?:download|get)\b|다운로드|내려받|받기/i)
      end
    end

    def verify_security(contents)
      check(contents.match?(/private vulnerability reporting is enabled/i), "SECURITY.md must state that GitHub private vulnerability reporting is enabled")
      check(contents.include?(ADVISORY_URL), "SECURITY.md must include the exact private advisory URL #{ADVISORY_URL}")
      check(contents.match?(/primary.{0,100}(?:private )?reporting (?:path|route).{0,240}#{Regexp.escape(ADVISORY_URL)}/im), "SECURITY.md must make the private advisory URL the primary reporting path")
    end

    def verify_support(contents)
      check(contents.match?(/private vulnerability reporting is enabled/i), "SUPPORT.md must state that GitHub private vulnerability reporting is enabled")
      security_policy_link = contents.match?(%r{\[[^\]]*SECURITY(?:\.md)?[^\]]*\]\([^\s)]*SECURITY\.md(?:#[^)]*)?\)}i)
      check(security_policy_link || contents.include?(ADVISORY_URL), "SUPPORT.md must link SECURITY.md or the exact private advisory route")
    end
  end
end

def usage
  "Usage: #{File.basename($PROGRAM_NAME)} --root REPOSITORY_ROOT"
end

unless ARGV.length == 2 && ARGV.first == "--root" && !ARGV.last.empty?
  warn usage
  exit 2
end

gate = PublicCopyState::Gate.new(ARGV.last)
begin
  state, document_count = gate.run
  puts "OK public-copy-state state=#{state} documents=#{document_count} assertions=#{gate.assertions}"
rescue PublicCopyState::Error, KeyError => error
  warn "FAIL public-copy-state assertion=#{gate.assertions}: #{error.message}"
  exit 1
end
