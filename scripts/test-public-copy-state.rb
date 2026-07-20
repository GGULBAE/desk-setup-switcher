#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

VERIFIER = File.expand_path("verify-public-copy-state.rb", __dir__)
SCHEMA = "desk-setup-switcher.site-release/v1"
CANONICAL_RELEASE = "https://github.com/GGULBAE/desk-setup-switcher/releases/tag/v0.1.0"
PRIVATE_ADVISORY = "https://github.com/GGULBAE/desk-setup-switcher/security/advisories/new"
APPROVED_SITE = "https://desksetup.app"

DOCUMENT_PATHS = [
  "README.md",
  "docs/guides/README.md",
  "docs/guides/USER-GUIDE.md",
  "docs/guides/USER-GUIDE.ko.md",
  "docs/PRIVACY.md",
  "docs/SUPPORT-MATRIX.md",
  "SECURITY.md",
  "SUPPORT.md",
  ".github/ISSUE_TEMPLATE/support_question.yml"
].freeze

HOLDING_DOCUMENTS = {
  "README.md" => <<~TEXT,
    # Desk Setup Switcher

    There is no supported public download yet. Development artifacts are not releases.
  TEXT
  "docs/guides/README.md" => <<~TEXT,
    # User guides / 사용자 가이드

    There is no supported download yet. Development artifacts are not releases.
    아직 지원되는 다운로드는 없습니다. 개발 검증 자료는 릴리스가 아닙니다.
  TEXT
  "docs/guides/USER-GUIDE.md" => <<~TEXT,
    # User guide

    There is no supported public download yet. After `v0.1.0` is approved and published,
    use the general GitHub Releases page.
  TEXT
  "docs/guides/USER-GUIDE.ko.md" => <<~TEXT,
    # 사용자 가이드

    아직 지원되는 공개 다운로드가 없습니다. `v0.1.0`이 승인되어 공개된 뒤에는
    일반 GitHub Releases 페이지를 사용합니다.
  TEXT
  "docs/PRIVACY.md" => <<~TEXT,
    # Privacy

    No site has been deployed or approved yet.
    Private vulnerability reporting is currently disabled.
    The current package is development evidence and no public release exists.
  TEXT
  "docs/SUPPORT-MATRIX.md" => <<~TEXT,
    # Support matrix

    The tracked closed-schema launch state remains `holding` with no download URL.
    Private vulnerability reporting and canonical site/release publication remain pending.
  TEXT
  "SECURITY.md" => <<~TEXT,
    # Security

    There is no public release yet.
    `v0.1.0` public beta: Not published yet.
  TEXT
  "SUPPORT.md" => <<~TEXT,
    # Support

    There is currently no supported public download. Development artifacts are not releases.
  TEXT
  ".github/ISSUE_TEMPLATE/support_question.yml" => <<~TEXT
    name: Support question
    description: Ask a non-sensitive question
    version_help: Supported downloads come only from versioned GitHub Releases; local and CI artifacts are unsupported.
  TEXT
}.freeze

PUBLISHED_DOCUMENTS = {
  "README.md" => <<~TEXT,
    # Desk Setup Switcher

    v0.1.0 is the supported public beta. Download it from #{CANONICAL_RELEASE}.
  TEXT
  "docs/guides/README.md" => <<~TEXT,
    # User guides / 사용자 가이드

    v0.1.0 is the published, supported public beta: #{CANONICAL_RELEASE}
    v0.1.0은 공개되어 지원되는 public beta입니다: #{CANONICAL_RELEASE}
  TEXT
  "docs/guides/USER-GUIDE.md" => <<~TEXT,
    # User guide

    v0.1.0 is the supported public beta. Canonical release: #{CANONICAL_RELEASE}
  TEXT
  "docs/guides/USER-GUIDE.ko.md" => <<~TEXT,
    # 사용자 가이드

    v0.1.0은 공개되어 지원되는 public beta입니다. 공식 릴리스: #{CANONICAL_RELEASE}
  TEXT
  "docs/PRIVACY.md" => <<~TEXT,
    # Privacy

    v0.1.0 is the supported public beta: #{CANONICAL_RELEASE}
    GitHub private vulnerability reporting is enabled.
  TEXT
  "docs/SUPPORT-MATRIX.md" => <<~TEXT,
    # Support matrix

    The tracked closed-schema launch state is `published` with the canonical `v0.1.0` URL:
    #{CANONICAL_RELEASE}
    GitHub private vulnerability reporting is enabled.
  TEXT
  "SECURITY.md" => <<~TEXT,
    # Security

    v0.1.0 is the latest public beta and is supported: #{CANONICAL_RELEASE}
    GitHub private vulnerability reporting is enabled.
    The primary private reporting route is #{PRIVATE_ADVISORY}
  TEXT
  "SUPPORT.md" => <<~TEXT,
    # Support

    v0.1.0 is the supported public beta. Canonical release: #{CANONICAL_RELEASE}
    GitHub private vulnerability reporting is enabled. Report vulnerabilities through
    [SECURITY.md](SECURITY.md).
  TEXT
  ".github/ISSUE_TEMPLATE/support_question.yml" => <<~TEXT
    name: Support question
    description: Ask a non-sensitive question
    version_help: Supported downloads come only from versioned GitHub Releases; local and CI artifacts are unsupported.
  TEXT
}.freeze

@assertions = 0

def assert(condition, message)
  @assertions += 1
  raise "assertion #{@assertions} failed: #{message}" unless condition
end

def manifest(state, release_url)
  {
    "schemaVersion" => SCHEMA,
    "state" => state,
    "version" => "0.1.0",
    "tag" => "v0.1.0",
    "releaseURL" => release_url
  }
end

def site_manifest(state, site_url)
  {
    "schemaVersion" => "desk-setup-switcher.site-origin/v1",
    "state" => state,
    "siteURL" => site_url
  }
end

def write_root(root, state:, documents:, release_url: state == "published" ? CANONICAL_RELEASE : nil, raw_manifest: nil, site_state: state == "published" ? "approved" : "holding", site_url: state == "published" ? APPROVED_SITE : nil, raw_site_manifest: nil)
  DOCUMENT_PATHS.each do |relative|
    path = File.join(root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, documents.fetch(relative))
  end
  manifest_path = File.join(root, "site/release-publication.json")
  FileUtils.mkdir_p(File.dirname(manifest_path))
  File.binwrite(manifest_path, raw_manifest || JSON.pretty_generate(manifest(state, release_url)) + "\n")
  site_manifest_path = File.join(root, "site/site-publication.json")
  File.binwrite(site_manifest_path, raw_site_manifest || JSON.pretty_generate(site_manifest(site_state, site_url)) + "\n")
end

def run_gate(root)
  Open3.capture3(RbConfig.ruby, VERIFIER, "--root", root)
end

def expect_success(label, state:, documents:, release_url: state == "published" ? CANONICAL_RELEASE : nil, site_state: state == "published" ? "approved" : "holding", site_url: state == "published" ? APPROVED_SITE : nil)
  Dir.mktmpdir("public-copy-state.") do |root|
    write_root(root, state: state, documents: documents, release_url: release_url, site_state: site_state, site_url: site_url)
    stdout, stderr, status = run_gate(root)
    assert(status.success?, "#{label} should pass, stderr=#{stderr.inspect}")
    assert(stdout.match?(/\AOK public-copy-state state=#{Regexp.escape(state)} documents=9 assertions=\d+\n\z/), "#{label} should print a counted success receipt")
    assert(stderr.empty?, "#{label} should not write stderr")
  end
end

def expect_failure(label, expected:, state: "published", documents: PUBLISHED_DOCUMENTS, release_url: state == "published" ? CANONICAL_RELEASE : nil, raw_manifest: nil, site_state: state == "published" ? "approved" : "holding", site_url: state == "published" ? APPROVED_SITE : nil, raw_site_manifest: nil)
  Dir.mktmpdir("public-copy-state.") do |root|
    write_root(root, state: state, documents: documents, release_url: release_url, raw_manifest: raw_manifest, site_state: site_state, site_url: site_url, raw_site_manifest: raw_site_manifest)
    stdout, stderr, status = run_gate(root)
    assert(!status.success?, "#{label} should fail")
    assert(stdout.empty?, "#{label} should not print a success receipt")
    assert(stderr.include?(expected), "#{label} should explain #{expected.inspect}, stderr=#{stderr.inspect}")
  end
end

expect_success("valid holding state", state: "holding", documents: HOLDING_DOCUMENTS)
expect_success("valid published state", state: "published", documents: PUBLISHED_DOCUMENTS)

expect_failure(
  "holding release with approved site origin",
  expected: "holding release publication requires holding site-origin approval",
  state: "holding",
  documents: HOLDING_DOCUMENTS,
  site_state: "approved",
  site_url: APPROVED_SITE
)

expect_failure(
  "published release with holding site origin",
  expected: "published release publication requires approved site-origin approval",
  documents: PUBLISHED_DOCUMENTS,
  site_state: "holding",
  site_url: nil
)

duplicate_site_manifest = <<~JSON
  {"schemaVersion":"desk-setup-switcher.site-origin/v1","state":"holding","state":"approved","siteURL":null}
JSON
expect_failure(
  "duplicate site-origin manifest key",
  expected: "site/site-publication.json is not strict JSON: duplicate JSON key",
  state: "holding",
  documents: HOLDING_DOCUMENTS,
  raw_site_manifest: duplicate_site_manifest
)

expect_failure(
  "unknown publication state",
  expected: "state must be exactly holding or published",
  state: "launching",
  documents: HOLDING_DOCUMENTS,
  release_url: nil
)

extra_key_manifest = manifest("holding", nil).merge("unexpected" => true)
expect_failure(
  "closed schema extra key",
  expected: "closed v1 schema",
  state: "holding",
  documents: HOLDING_DOCUMENTS,
  raw_manifest: JSON.generate(extra_key_manifest)
)

expect_failure(
  "malformed JSON",
  expected: "is not strict JSON",
  state: "holding",
  documents: HOLDING_DOCUMENTS,
  raw_manifest: '{"schemaVersion":'
)

duplicate_manifest = <<~JSON
  {"schemaVersion":"#{SCHEMA}","state":"holding","state":"published","version":"0.1.0","tag":"v0.1.0","releaseURL":null}
JSON
expect_failure(
  "duplicate manifest key",
  expected: "duplicate JSON key",
  state: "holding",
  documents: HOLDING_DOCUMENTS,
  raw_manifest: duplicate_manifest
)

holding_with_url = HOLDING_DOCUMENTS.merge(
  "README.md" => HOLDING_DOCUMENTS.fetch("README.md") + "\n#{CANONICAL_RELEASE}\n"
)
expect_failure(
  "holding canonical release CTA",
  expected: "must not contain the canonical v0.1.0 release URL",
  state: "holding",
  documents: holding_with_url
)

holding_with_claim = HOLDING_DOCUMENTS.merge(
  "SUPPORT.md" => HOLDING_DOCUMENTS.fetch("SUPPORT.md") + "\nDownload v0.1.0 now.\n"
)
expect_failure(
  "holding positive download claim",
  expected: "must not claim that v0.1.0",
  state: "holding",
  documents: holding_with_claim
)

holding_with_generic_release_cta = HOLDING_DOCUMENTS.merge(
  "README.md" => HOLDING_DOCUMENTS.fetch("README.md") +
    "\n[Download the public beta](https://github.com/GGULBAE/desk-setup-switcher/releases)\n"
)
expect_failure(
  "holding generic release CTA",
  expected: "must not claim that v0.1.0",
  state: "holding",
  documents: holding_with_generic_release_cta
)

stale_issue_template = HOLDING_DOCUMENTS.merge(
  ".github/ISSUE_TEMPLATE/support_question.yml" => <<~TEXT
    name: Support question
    version_help: There is no supported public release until v0.1.0 is published.
  TEXT
)
expect_failure(
  "lifecycle-specific issue-template copy",
  expected: "must retain the lifecycle-neutral supported-download boundary",
  state: "holding",
  documents: stale_issue_template
)

stale_published = PUBLISHED_DOCUMENTS.merge(
  "README.md" => PUBLISHED_DOCUMENTS.fetch("README.md") + "\nThere is no supported public download yet.\n"
)
expect_failure(
  "published stale holding copy",
  expected: "README.md contains stale holding",
  documents: stale_published
)

expect_failure(
  "published manifest wrong URL",
  expected: "published state requires the exact canonical release URL",
  release_url: "https://github.com/GGULBAE/desk-setup-switcher/releases/tag/v0.1.1"
)

wrong_document_url = PUBLISHED_DOCUMENTS.merge(
  "SUPPORT.md" => PUBLISHED_DOCUMENTS.fetch("SUPPORT.md").sub("v0.1.0\n", "v0.1.1\n").gsub(CANONICAL_RELEASE, "https://github.com/GGULBAE/desk-setup-switcher/releases/tag/v0.1.1")
)
expect_failure(
  "published document wrong URL",
  expected: "SUPPORT.md must include the exact canonical release URL",
  documents: wrong_document_url
)

published_general_release_link = PUBLISHED_DOCUMENTS.merge(
  "README.md" => PUBLISHED_DOCUMENTS.fetch("README.md") +
    "\n[Download v0.1.0](https://github.com/GGULBAE/desk-setup-switcher/releases)\n"
)
expect_failure(
  "published general releases-page link",
  expected: "contains a non-canonical GitHub release-tag URL",
  documents: published_general_release_link
)

published_asset_link = PUBLISHED_DOCUMENTS.merge(
  "README.md" => PUBLISHED_DOCUMENTS.fetch("README.md") +
    "\n[Direct DMG](https://github.com/GGULBAE/desk-setup-switcher/releases/download/v0.1.0/Desk-Setup-Switcher.dmg)\n"
)
expect_failure(
  "published mutable direct-asset link",
  expected: "contains a non-canonical GitHub release-tag URL",
  documents: published_asset_link
)

negated_english_identity = PUBLISHED_DOCUMENTS.merge(
  "README.md" => <<~TEXT
    # Desk Setup Switcher
    v0.1.0 is not the latest public beta and is not supported: #{CANONICAL_RELEASE}
  TEXT
)
expect_failure(
  "negated English release identity",
  expected: "must contain the affirmative v0.1.0 supported-public-beta statement",
  documents: negated_english_identity
)

missing_korean_update = PUBLISHED_DOCUMENTS.merge(
  "docs/guides/USER-GUIDE.ko.md" => <<~TEXT
    # Korean guide left in English
    v0.1.0 is the supported public beta: #{CANONICAL_RELEASE}
  TEXT
)
expect_failure(
  "missing Korean release update",
  expected: "must contain the affirmative Korean v0.1.0 public identity",
  documents: missing_korean_update
)

negated_korean_identity = PUBLISHED_DOCUMENTS.merge(
  "docs/guides/USER-GUIDE.ko.md" => <<~TEXT
    # 사용자 가이드
    v0.1.0은 공개되지 않아 지원되지 않습니다: #{CANONICAL_RELEASE}
  TEXT
)
expect_failure(
  "negated Korean release identity",
  expected: "must contain the affirmative Korean v0.1.0 public identity",
  documents: negated_korean_identity
)

stale_published_privacy = PUBLISHED_DOCUMENTS.merge(
  "docs/PRIVACY.md" => PUBLISHED_DOCUMENTS.fetch("docs/PRIVACY.md") +
    "\nNo site has been deployed or approved yet.\n"
)
expect_failure(
  "published stale privacy lifecycle",
  expected: "docs/PRIVACY.md contains stale holding",
  documents: stale_published_privacy
)

security_disabled = PUBLISHED_DOCUMENTS.merge(
  "SECURITY.md" => PUBLISHED_DOCUMENTS.fetch("SECURITY.md").sub("is enabled", "is disabled")
)
expect_failure(
  "security reporting state drift",
  expected: "SECURITY.md contains stale holding",
  documents: security_disabled
)

security_without_primary_route = PUBLISHED_DOCUMENTS.merge(
  "SECURITY.md" => PUBLISHED_DOCUMENTS.fetch("SECURITY.md").sub("The primary private reporting route is", "An optional reporting link is")
)
expect_failure(
  "security advisory route drift",
  expected: "must make the private advisory URL the primary reporting path",
  documents: security_without_primary_route
)

support_drift = PUBLISHED_DOCUMENTS.merge(
  "SUPPORT.md" => <<~TEXT
    # Support
    General support policy: #{CANONICAL_RELEASE}
  TEXT
)
expect_failure(
  "support release identity drift",
  expected: "SUPPORT.md must contain the affirmative v0.1.0 supported-public-beta statement",
  documents: support_drift
)

support_without_reporting_state = PUBLISHED_DOCUMENTS.merge(
  "SUPPORT.md" => PUBLISHED_DOCUMENTS.fetch("SUPPORT.md").sub("GitHub private vulnerability reporting is enabled. ", "")
)
expect_failure(
  "support private-reporting state drift",
  expected: "SUPPORT.md must state that GitHub private vulnerability reporting is enabled",
  documents: support_without_reporting_state
)

support_without_security_route = PUBLISHED_DOCUMENTS.merge(
  "SUPPORT.md" => PUBLISHED_DOCUMENTS.fetch("SUPPORT.md").sub("[SECURITY.md](SECURITY.md).", "the project's private reporting instructions.")
)
expect_failure(
  "support private-reporting route drift",
  expected: "SUPPORT.md must link SECURITY.md or the exact private advisory route",
  documents: support_without_security_route
)

puts "OK test-public-copy-state assertions=#{@assertions} scenarios=27"
