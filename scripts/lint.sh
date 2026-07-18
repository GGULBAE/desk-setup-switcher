#!/usr/bin/env bash

set -euo pipefail
source "$(dirname "$0")/lib/common.sh"

cd "$ROOT_DIR"

for script in scripts/*.sh scripts/lib/*.sh scripts/release/*.sh; do
    bash -n "$script"
    [[ -x "$script" ]] || {
        echo "Script is not executable: $script" >&2
        exit 1
    }
done
ruby -c scripts/generate-xcode-project.rb >/dev/null
[[ -x scripts/generate-xcode-project.rb ]] || {
    echo "Script is not executable: scripts/generate-xcode-project.rb" >&2
    exit 1
}
for ruby_script in scripts/release/*.rb; do
    ruby -c "$ruby_script" >/dev/null
    [[ -x "$ruby_script" ]] || {
        echo "Script is not executable: $ruby_script" >&2
        exit 1
    }
done

swift format lint --recursive --strict Sources Tests Package.swift
swift package dump-package | ruby -rjson -e '
  package = JSON.parse(STDIN.read)
  minimum_version, executable_name = ARGV
  platform = package.fetch("platforms").find { |item| item["platformName"] == "macos" }
  abort "Package.swift macOS minimum does not match Config/Info.plist" unless platform&.fetch("version") == minimum_version
  product = package.fetch("products").find { |item| item["name"] == executable_name }
  abort "Package.swift is missing the #{executable_name} executable product" unless product&.fetch("type", {})&.key?("executable")
' "$MINIMUM_SYSTEM_VERSION" "$EXECUTABLE_NAME"
ruby scripts/generate-xcode-project.rb --check
plutil -lint Config/Info.plist
plutil -lint Config/ReleaseEntitlements.plist
for strings_file in Sources/DeskSetupSwitcher/Resources/{en,ko}.lproj/{InfoPlist,Localizable}.strings; do
    plutil -lint "$strings_file"
done

ruby scripts/validate-localizations.rb

xcodebuild \
    -project DeskSetupSwitcher.xcodeproj \
    -list \
    -json | ruby -rjson -e '
      project = JSON.parse(STDIN.read).fetch("project")
      abort "Generated Xcode target is missing" unless project.fetch("targets").include?("DeskSetupSwitcher")
      abort "Shared Xcode scheme is missing" unless project.fetch("schemes").include?("DeskSetupSwitcher")
    '

forbidden_matches="$(grep -ERn --include='*.swift' '(^|[^[:alnum:]_])((Foundation\.)?Process[[:space:]]*(\(|\.init)|NSTask[[:space:]]*(\(|\.init)|URLSession([^[:alnum:]_]|$)|NSAppleScript([^[:alnum:]_]|$)|NW(Connection|Browser|Listener)([^[:alnum:]_]|$)|CFStreamCreatePairWithSocketToHost([^[:alnum:]_]|$))' Sources || true)"
if [[ -n "$forbidden_matches" ]]; then
    printf '%s\n' "$forbidden_matches"
    echo "Forbidden shell, outbound networking, or UI-scripting primitive found in Sources." >&2
    exit 1
fi

ruby -e '
  bad = []
  ignored_prefixes = ["site/node_modules/", "site/dist/", "site/.next/", "site/.wrangler/"]
  Dir["**/*.md", ".github/**/*.md"].uniq.each do |file|
    next if ignored_prefixes.any? { |prefix| file.start_with?(prefix) }
    File.read(file).scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |link|
      next if link.start_with?("http://", "https://", "mailto:", "#")
      target = File.expand_path(link.split("#", 2).first, File.dirname(file))
      bad << "#{file}: missing #{link}" unless File.exist?(target)
    end
  end
  abort bad.join("\n") unless bad.empty?
'

git diff --check
git diff --cached --check
