#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

site_directory="$ROOT_DIR/site"
release_notes="$ROOT_DIR/docs/releases/v0.1.0.md"

ruby - "$release_notes" <<'RUBY'
EXPECTED_RELEASE_LINKS = {
  "distribution gate" => [
    "https://github.com/GGULBAE/desk-setup-switcher/blob/v0.1.0/docs/DISTRIBUTION.md",
    1
  ],
  "배포 게이트" => [
    "https://github.com/GGULBAE/desk-setup-switcher/blob/v0.1.0/docs/DISTRIBUTION.md",
    1
  ],
  "public support form" => [
    "https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml",
    1
  ],
  "공개 지원 양식" => [
    "https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml",
    1
  ],
  "private vulnerability report" => [
    "https://github.com/GGULBAE/desk-setup-switcher/security/advisories/new",
    1
  ],
  "비공개 취약점 신고" => [
    "https://github.com/GGULBAE/desk-setup-switcher/security/advisories/new",
    1
  ]
}.freeze
ALLOWED_RELEASE_URLS = EXPECTED_RELEASE_LINKS.values.map(&:first).uniq.freeze
ABSOLUTE_URL_PATTERN = %r!https?://[^\s<>\])}]+!
STALE_PUBLICATION_CLAIMS = {
  "planned initial target" => /\bplanned\s+(?:initial\s+)?target\b/i,
  "planned publication" => /\bpublication\s+(?:is|remains)\s+planned\b/i,
  "blocked publication" => /\bpublication\s+(?:is|remains)\s+blocked\b/i,
  "planned Korean target" => /초기\s+예정\s+환경/,
  "planned Korean publication" => /공개(?:가|는)?[^.\n]{0,24}예정/,
  "blocked Korean publication" => /공개할\s+수\s+없습니다/
}.freeze

def release_body_errors(body)
  errors = []
  links = body.scan(/\[([^\]]+)\]\(([^)]+)\)/)
  link_counts = Hash.new(0)

  links.each do |label, link|
    expected = EXPECTED_RELEASE_LINKS[label]
    if expected.nil?
      errors << "release body contains an unexpected link role: #{label}"
      next
    end

    expected_link, = expected
    unless link == expected_link
      errors << "release-body link for #{label} must be #{expected_link}: #{link}"
    end
    link_counts[label] += 1
  end

  body.scan(ABSOLUTE_URL_PATTERN).each do |url|
    normalized = url.sub(/[.,;:]\z/, "")
    unless ALLOWED_RELEASE_URLS.include?(normalized)
      errors << "release body contains an unexpected absolute URL: #{normalized}"
    end
  end

  EXPECTED_RELEASE_LINKS.each do |label, (_, expected_count)|
    actual_count = link_counts[label]
    next if actual_count == expected_count

    errors <<
      "release body must contain #{expected_count} #{label} link(s), found #{actual_count}"
  end

  STALE_PUBLICATION_CLAIMS.each do |label, pattern|
    errors << "release body contains stale #{label} copy" if body.match?(pattern)
  end

  errors
end

path = ARGV.fetch(0)
body = File.read(path, encoding: "UTF-8")
errors = release_body_errors(body)
abort errors.join("\n") unless errors.empty?

link_rejection_cases = {
  "repository-relative link" => [
    "[distribution gate](https://github.com/GGULBAE/desk-setup-switcher/blob/v0.1.0/docs/DISTRIBUTION.md)",
    "[distribution gate](../DISTRIBUTION.md)"
  ],
  "mutable branch document" => [
    "[public support form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml)",
    "[public support form](https://github.com/GGULBAE/desk-setup-switcher/blob/master/SUPPORT.md)"
  ],
  "non-primary security route" => [
    "[private vulnerability report](https://github.com/GGULBAE/desk-setup-switcher/security/advisories/new)",
    "[private vulnerability report](https://github.com/GGULBAE/desk-setup-switcher/security/policy)"
  ],
  "bare mutable branch document" => [
    "[public support form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml)",
    "[public support form](https://github.com/GGULBAE/desk-setup-switcher/issues/new?template=support_question.yml) https://github.com/GGULBAE/desk-setup-switcher/blob/master/SUPPORT.md"
  ]
}.freeze

link_rejection_cases.each do |label, (valid_link, invalid_link)|
  abort "Release-body verifier self-test fixture is missing: #{valid_link}" unless
    body.include?(valid_link)

  invalid_body = body.sub(valid_link, invalid_link)
  if release_body_errors(invalid_body).empty?
    abort "Release-body verifier failed its #{label} rejection self-test."
  end
end

copy_rejection_cases = {
  "stale planned target" => "The planned initial target is Apple Silicon.",
  "stale planned publication" => "Publication remains planned for later.",
  "stale blocked publication" => "Publication remains blocked until verification passes.",
  "stale Korean planned target" => "초기 예정 환경은 Apple Silicon입니다.",
  "stale Korean planned publication" => "공개는 추후 예정입니다.",
  "stale Korean blocked publication" => "검증 전에는 공개할 수 없습니다."
}.freeze

copy_rejection_cases.each do |label, invalid_copy|
  if release_body_errors("#{body}\n#{invalid_copy}\n").empty?
    abort "Release-body verifier failed its #{label} rejection self-test."
  end
end
RUBY

ruby "$ROOT_DIR/scripts/test-public-copy-state.rb"
ruby "$ROOT_DIR/scripts/verify-public-copy-state.rb" --root "$ROOT_DIR"

[[ -f "$site_directory/package-lock.json" ]] || {
    echo "Public-surface verification requires site/package-lock.json." >&2
    exit 1
}
[[ -x "$site_directory/node_modules/.bin/eslint" ]] || {
    echo "Public-surface dependencies are missing. Run 'npm ci --ignore-scripts' in site/." >&2
    exit 1
}

"$ROOT_DIR/scripts/verify-public-assets.sh"
(
    cd "$site_directory"
    npm run verify
)

echo "Public site and release assets verified."
