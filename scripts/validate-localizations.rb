#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "pathname"

ROOT = File.expand_path("..", __dir__)
RESOURCE_ROOT = File.join(ROOT, "Sources", "DeskSetupSwitcher", "Resources")
TABLES = %w[InfoPlist.strings Localizable.strings].freeze
LOCALES = %w[en ko].freeze
ENTRY_PATTERN = /^\s*"((?:\\.|[^"\\])*)"\s*=/.freeze
FORMAT_PATTERN = /%(?!%)(?:\d+\$)?[-+0 #']*(?:\d+|\*)?(?:\.(?:\d+|\*))?(?:hh|h|ll|l|q|L|z|j|t)?[@diuoxXfFeEgGaAcCsSp]/.freeze
LOCALIZED_CALLS = %w[
  Text Button Label Toggle Picker Section DisclosureGroup ContentUnavailableView
  LabeledContent Menu TextField accessibilityLabel accessibilityHint help alert
  confirmationDialog appLocalized appLocalizedRuntime appRuntimeLocalizedFormat
].freeze
STATIC_LOCALIZED_KEY_PATTERN =
  /(?:#{LOCALIZED_CALLS.join('|')})\s*\(\s*"((?:\\.|[^"\\])*)"/m.freeze

def relative(path)
  Pathname(path).relative_path_from(Pathname(ROOT)).to_s
end

def load_dictionary(path)
  output, error, status = Open3.capture3(
    "/usr/bin/plutil", "-convert", "json", "-o", "-", path
  )
  abort "Unable to parse #{relative(path)}: #{error.strip}" unless status.success?

  parsed = JSON.parse(output)
  abort "Expected a string dictionary in #{relative(path)}." unless parsed.is_a?(Hash)
  unless parsed.all? { |key, value| key.is_a?(String) && value.is_a?(String) }
    abort "Expected only string keys and values in #{relative(path)}."
  end
  parsed
rescue JSON::ParserError => error
  abort "Unable to decode #{relative(path)}: #{error.message}"
end

def validate_unique_source_keys(path)
  keys = File.binread(path).scan(ENTRY_PATTERN).flatten
  counts = keys.each_with_object(Hash.new(0)) { |key, result| result[key] += 1 }
  duplicates = counts.select { |_key, count| count > 1 }.keys
  return if duplicates.empty?

  abort "Duplicate localization key(s) in #{relative(path)}: #{duplicates.sort.join(', ')}"
end

def placeholders(value)
  value.scan(FORMAT_PATTERN).map { |token| token.sub(/\A%(?:\d+\$)?/, "%") }.sort
end

TABLES.each do |table|
  paths = LOCALES.to_h do |locale|
    [locale, File.join(RESOURCE_ROOT, "#{locale}.lproj", table)]
  end
  paths.each_value { |path| validate_unique_source_keys(path) }

  dictionaries = paths.transform_values { |path| load_dictionary(path) }
  reference_locale = LOCALES.first
  reference = dictionaries.fetch(reference_locale)

  LOCALES.drop(1).each do |locale|
    localized = dictionaries.fetch(locale)
    missing = reference.keys - localized.keys
    extra = localized.keys - reference.keys
    unless missing.empty? && extra.empty?
      abort [
        "Localization key mismatch for #{table} (#{reference_locale} vs #{locale}).",
        ("Missing in #{locale}: #{missing.sort.join(', ')}" unless missing.empty?),
        ("Extra in #{locale}: #{extra.sort.join(', ')}" unless extra.empty?),
      ].compact.join("\n")
    end

    reference.each do |key, reference_value|
      expected = placeholders(reference_value)
      actual = placeholders(localized.fetch(key))
      next if expected == actual

      abort "Placeholder mismatch for #{table} key #{key.inspect} " \
        "(#{reference_locale}: #{expected.inspect}, #{locale}: #{actual.inspect})."
    end
  end
end

catalog_path = File.join(RESOURCE_ROOT, "en.lproj", "Localizable.strings")
catalog = load_dictionary(catalog_path)
swift_source = Dir[File.join(ROOT, "Sources", "DeskSetupSwitcher", "*.swift")]
  .sort
  .map { |path| File.read(path) }
  .join("\n")
static_keys = swift_source.scan(STATIC_LOCALIZED_KEY_PATTERN).flatten
  .reject { |key| key.include?("\\(") }
  .map { |key| key.gsub('\\"', '"').gsub('\\\\', '\\') }
  .uniq
missing_static_keys = static_keys - catalog.keys
unless missing_static_keys.empty?
  abort "Static user-facing localization key(s) missing from " \
    "#{relative(catalog_path)}: #{missing_static_keys.sort.join(', ')}"
end

puts "Validated English/Korean localization keys, duplicates, placeholders, and static UI coverage."
