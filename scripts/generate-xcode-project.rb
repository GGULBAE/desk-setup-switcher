#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"

ROOT = File.expand_path("..", __dir__)
PROJECT_NAME = "DeskSetupSwitcher"
PROJECT_DIR = File.join(ROOT, "#{PROJECT_NAME}.xcodeproj")
CHECK_MODE = ARGV.delete("--check")
abort "Usage: #{File.basename($PROGRAM_NAME)} [--check]" unless ARGV.empty?

FRAMEWORKS = %w[
  AppKit
  ColorSync
  Combine
  CoreAudio
  CoreGraphics
  CoreLocation
  CoreWLAN
  CryptoKit
  IOKit
  Security
  ServiceManagement
  SystemConfiguration
  SwiftUI
  UniformTypeIdentifiers
].freeze

LOCALIZATIONS = %w[en ko].freeze
LOCALIZED_RESOURCES = %w[InfoPlist.strings Localizable.strings].freeze
APP_ICON_PATH = "Assets/AppIcon.icns"

def stable_id(kind, value)
  Digest::SHA256.hexdigest("#{kind}:#{value}").upcase[0, 24]
end

def quoted(value)
  "\"#{value.to_s.gsub("\\", "\\\\").gsub("\"", "\\\"")}\""
end

def xml_escaped(value)
  value.to_s
    .gsub("&", "&amp;")
    .gsub("\"", "&quot;")
    .gsub("<", "&lt;")
    .gsub(">", "&gt;")
end

def required_plist_string(plist, key)
  value = plist[key]
  abort "Missing or invalid #{key} in Config/Info.plist." unless value.is_a?(String) && !value.empty?
  abort "#{key} must not contain a path separator or newline." if value.match?(%r{[/\r\n]})

  value
end

def write_if_changed(path, content)
  return if File.file?(path) && File.binread(path) == content

  if CHECK_MODE
    abort "Generated Xcode project is stale: #{Pathname(path).relative_path_from(Pathname(ROOT))}"
  end

  FileUtils.mkdir_p(File.dirname(path))
  File.binwrite(path, content)
end

source_paths = Dir.glob(File.join(ROOT, "Sources", "**", "*.swift"))
  .map { |path| Pathname(path).relative_path_from(Pathname(ROOT)).to_s }
  .sort

abort "No Swift source files found under Sources/." if source_paths.empty?

info_plist_path = File.join(ROOT, "Config", "Info.plist")
abort "Missing Config/Info.plist." unless File.file?(info_plist_path)

plist_json, plist_error, plist_status = Open3.capture3(
  "/usr/bin/plutil", "-convert", "json", "-o", "-", info_plist_path
)
abort "Unable to read Config/Info.plist: #{plist_error.strip}" unless plist_status.success?

begin
  info_plist = JSON.parse(plist_json)
rescue JSON::ParserError => error
  abort "Unable to parse Config/Info.plist: #{error.message}"
end

app_name = required_plist_string(info_plist, "CFBundleDisplayName")
executable_name = required_plist_string(info_plist, "CFBundleExecutable")
bundle_identifier = required_plist_string(info_plist, "CFBundleIdentifier")
icon_file = required_plist_string(info_plist, "CFBundleIconFile")
marketing_version = required_plist_string(info_plist, "CFBundleShortVersionString")
build_number = required_plist_string(info_plist, "CFBundleVersion")
minimum_system_version = required_plist_string(info_plist, "LSMinimumSystemVersion")
required_plist_string(info_plist, "NSLocationWhenInUseUsageDescription")
app_bundle_name = "#{app_name}.app"

abort "Invalid CFBundleIdentifier: #{bundle_identifier}" unless bundle_identifier.match?(/\A[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9][A-Za-z0-9-]*)+\z/)
abort "Invalid CFBundleShortVersionString: #{marketing_version}" unless marketing_version.match?(/\A\d+(?:\.\d+){0,2}\z/)
abort "Invalid CFBundleVersion: #{build_number}" unless build_number.match?(/\A[1-9][0-9]*\z/)
abort "Invalid LSMinimumSystemVersion: #{minimum_system_version}" unless minimum_system_version.match?(/\A\d+(?:\.\d+){0,2}\z/)
abort "CFBundlePackageType must be APPL." unless info_plist["CFBundlePackageType"] == "APPL"
abort "LSUIElement must be true for a menu-bar-only app." unless info_plist["LSUIElement"] == true

expected_icon_file = File.basename(APP_ICON_PATH)
normalized_icon_file = icon_file.end_with?(".icns") ? icon_file : "#{icon_file}.icns"
abort "CFBundleIconFile must reference #{expected_icon_file}." unless normalized_icon_file == expected_icon_file
abort "Missing #{APP_ICON_PATH}." unless File.file?(File.join(ROOT, APP_ICON_PATH))

LOCALIZED_RESOURCES.each do |resource|
  LOCALIZATIONS.each do |localization|
    path = File.join(
      ROOT,
      "Sources",
      "DeskSetupSwitcher",
      "Resources",
      "#{localization}.lproj",
      resource
    )
    abort "Missing #{path}." unless File.file?(path)
  end
end

ids = {
  main_group: stable_id("PBXGroup", "main"),
  sources_group: stable_id("PBXGroup", "Sources"),
  resources_group: stable_id("PBXGroup", "Resources"),
  assets_group: stable_id("PBXGroup", "Assets"),
  config_group: stable_id("PBXGroup", "Config"),
  frameworks_group: stable_id("PBXGroup", "Frameworks"),
  products_group: stable_id("PBXGroup", "Products"),
  project: stable_id("PBXProject", PROJECT_NAME),
  target: stable_id("PBXNativeTarget", PROJECT_NAME),
  sources_phase: stable_id("PBXSourcesBuildPhase", PROJECT_NAME),
  resources_phase: stable_id("PBXResourcesBuildPhase", PROJECT_NAME),
  frameworks_phase: stable_id("PBXFrameworksBuildPhase", PROJECT_NAME),
  product_reference: stable_id("PBXFileReference", app_bundle_name),
  info_reference: stable_id("PBXFileReference", "Config/Info.plist"),
  app_icon_reference: stable_id("PBXFileReference", APP_ICON_PATH),
  app_icon_build: stable_id("PBXBuildFile", APP_ICON_PATH),
  project_debug: stable_id("XCBuildConfiguration", "Project/Debug"),
  project_release: stable_id("XCBuildConfiguration", "Project/Release"),
  target_debug: stable_id("XCBuildConfiguration", "Target/Debug"),
  target_release: stable_id("XCBuildConfiguration", "Target/Release"),
  project_configuration_list: stable_id("XCConfigurationList", "Project"),
  target_configuration_list: stable_id("XCConfigurationList", "Target")
}

source_reference_ids = {}
source_build_ids = {}
source_paths.each do |path|
  source_reference_ids[path] = stable_id("PBXFileReference", path)
  source_build_ids[path] = stable_id("PBXBuildFile", path)
end

framework_reference_ids = {}
framework_build_ids = {}
FRAMEWORKS.each do |framework|
  framework_reference_ids[framework] = stable_id("PBXFileReference", "#{framework}.framework")
  framework_build_ids[framework] = stable_id("PBXBuildFile", "#{framework}.framework")
end

localized_resource_group_ids = {}
localized_resource_build_ids = {}
localized_resource_reference_ids = {}
LOCALIZED_RESOURCES.each do |resource|
  localized_resource_group_ids[resource] = stable_id("PBXVariantGroup", resource)
  localized_resource_build_ids[resource] = stable_id("PBXBuildFile", resource)
  LOCALIZATIONS.each do |localization|
    localized_resource_reference_ids[[resource, localization]] = stable_id(
      "PBXFileReference",
      "#{localization}.lproj/#{resource}"
    )
  end
end

all_object_ids = ids.values + source_reference_ids.values + source_build_ids.values +
  framework_reference_ids.values + framework_build_ids.values +
  localized_resource_group_ids.values + localized_resource_build_ids.values +
  localized_resource_reference_ids.values
abort "Stable Xcode object ID collision." unless all_object_ids.uniq.length == all_object_ids.length

project = String.new
project << "// !$*UTF8*$!\n"
project << "{\n"
project << "\tarchiveVersion = 1;\n"
project << "\tclasses = {};\n"
project << "\tobjectVersion = 56;\n"
project << "\tobjects = {\n\n"

project << "/* Begin PBXBuildFile section */\n"
source_paths.each do |path|
  project << "\t\t#{source_build_ids.fetch(path)} = { isa = PBXBuildFile; fileRef = #{source_reference_ids.fetch(path)}; };\n"
end
FRAMEWORKS.each do |framework|
  project << "\t\t#{framework_build_ids.fetch(framework)} = { isa = PBXBuildFile; fileRef = #{framework_reference_ids.fetch(framework)}; };\n"
end
LOCALIZED_RESOURCES.each do |resource|
  project << "\t\t#{localized_resource_build_ids.fetch(resource)} = { isa = PBXBuildFile; fileRef = #{localized_resource_group_ids.fetch(resource)}; };\n"
end
project << "\t\t#{ids.fetch(:app_icon_build)} = { isa = PBXBuildFile; fileRef = #{ids.fetch(:app_icon_reference)}; };\n"
project << "/* End PBXBuildFile section */\n\n"

project << "/* Begin PBXFileReference section */\n"
project << "\t\t#{ids.fetch(:product_reference)} = { isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = #{quoted(app_bundle_name)}; sourceTree = BUILT_PRODUCTS_DIR; };\n"
project << "\t\t#{ids.fetch(:info_reference)} = { isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = \"<group>\"; };\n"
project << "\t\t#{ids.fetch(:app_icon_reference)} = { isa = PBXFileReference; lastKnownFileType = image.icns; path = AppIcon.icns; sourceTree = \"<group>\"; };\n"
source_paths.each do |path|
  relative_path = path.sub(%r{\ASources/}, "")
  project << "\t\t#{source_reference_ids.fetch(path)} = { isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = #{quoted(relative_path)}; sourceTree = \"<group>\"; };\n"
end
LOCALIZED_RESOURCES.each do |resource|
  LOCALIZATIONS.each do |localization|
    reference_id = localized_resource_reference_ids.fetch([resource, localization])
    project << "\t\t#{reference_id} = { isa = PBXFileReference; lastKnownFileType = text.plist.strings; name = #{quoted(localization)}; path = #{quoted("#{localization}.lproj/#{resource}")}; sourceTree = \"<group>\"; };\n"
  end
end
FRAMEWORKS.each do |framework|
  project << "\t\t#{framework_reference_ids.fetch(framework)} = { isa = PBXFileReference; lastKnownFileType = wrapper.framework; name = #{quoted("#{framework}.framework")}; path = #{quoted("System/Library/Frameworks/#{framework}.framework")}; sourceTree = SDKROOT; };\n"
end
project << "/* End PBXFileReference section */\n\n"

project << "/* Begin PBXFrameworksBuildPhase section */\n"
project << "\t\t#{ids.fetch(:frameworks_phase)} = {\n"
project << "\t\t\tisa = PBXFrameworksBuildPhase;\n"
project << "\t\t\tbuildActionMask = 2147483647;\n"
project << "\t\t\tfiles = (\n"
FRAMEWORKS.each do |framework|
  project << "\t\t\t\t#{framework_build_ids.fetch(framework)},\n"
end
project << "\t\t\t);\n"
project << "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
project << "\t\t};\n"
project << "/* End PBXFrameworksBuildPhase section */\n\n"

project << "/* Begin PBXGroup section */\n"
project << "\t\t#{ids.fetch(:main_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
project << "\t\t\t\t#{ids.fetch(:sources_group)},\n"
project << "\t\t\t\t#{ids.fetch(:resources_group)},\n"
project << "\t\t\t\t#{ids.fetch(:assets_group)},\n"
project << "\t\t\t\t#{ids.fetch(:config_group)},\n"
project << "\t\t\t\t#{ids.fetch(:frameworks_group)},\n"
project << "\t\t\t\t#{ids.fetch(:products_group)},\n"
project << "\t\t\t);\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "\t\t#{ids.fetch(:sources_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
source_paths.each do |path|
  project << "\t\t\t\t#{source_reference_ids.fetch(path)},\n"
end
project << "\t\t\t);\n"
project << "\t\t\tpath = Sources;\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "\t\t#{ids.fetch(:resources_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
LOCALIZED_RESOURCES.each do |resource|
  project << "\t\t\t\t#{localized_resource_group_ids.fetch(resource)},\n"
end
project << "\t\t\t);\n"
project << "\t\t\tpath = Sources/DeskSetupSwitcher/Resources;\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "\t\t#{ids.fetch(:config_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
project << "\t\t\t\t#{ids.fetch(:info_reference)},\n"
project << "\t\t\t);\n"
project << "\t\t\tpath = Config;\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "\t\t#{ids.fetch(:assets_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
project << "\t\t\t\t#{ids.fetch(:app_icon_reference)},\n"
project << "\t\t\t);\n"
project << "\t\t\tpath = Assets;\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "\t\t#{ids.fetch(:frameworks_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
FRAMEWORKS.each do |framework|
  project << "\t\t\t\t#{framework_reference_ids.fetch(framework)},\n"
end
project << "\t\t\t);\n"
project << "\t\t\tname = Frameworks;\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "\t\t#{ids.fetch(:products_group)} = {\n"
project << "\t\t\tisa = PBXGroup;\n"
project << "\t\t\tchildren = (\n"
project << "\t\t\t\t#{ids.fetch(:product_reference)},\n"
project << "\t\t\t);\n"
project << "\t\t\tname = Products;\n"
project << "\t\t\tsourceTree = \"<group>\";\n"
project << "\t\t};\n"
project << "/* End PBXGroup section */\n\n"

project << "/* Begin PBXNativeTarget section */\n"
project << "\t\t#{ids.fetch(:target)} = {\n"
project << "\t\t\tisa = PBXNativeTarget;\n"
project << "\t\t\tbuildConfigurationList = #{ids.fetch(:target_configuration_list)};\n"
project << "\t\t\tbuildPhases = (\n"
project << "\t\t\t\t#{ids.fetch(:sources_phase)},\n"
project << "\t\t\t\t#{ids.fetch(:frameworks_phase)},\n"
project << "\t\t\t\t#{ids.fetch(:resources_phase)},\n"
project << "\t\t\t);\n"
project << "\t\t\tbuildRules = ();\n"
project << "\t\t\tdependencies = ();\n"
project << "\t\t\tname = #{PROJECT_NAME};\n"
project << "\t\t\tpackageProductDependencies = ();\n"
project << "\t\t\tproductName = #{quoted(app_name)};\n"
project << "\t\t\tproductReference = #{ids.fetch(:product_reference)};\n"
project << "\t\t\tproductType = \"com.apple.product-type.application\";\n"
project << "\t\t};\n"
project << "/* End PBXNativeTarget section */\n\n"

project << "/* Begin PBXProject section */\n"
project << "\t\t#{ids.fetch(:project)} = {\n"
project << "\t\t\tisa = PBXProject;\n"
project << "\t\t\tattributes = {\n"
project << "\t\t\t\tBuildIndependentTargetsInParallel = YES;\n"
project << "\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
project << "\t\t\t\tLastUpgradeCheck = 1600;\n"
project << "\t\t\t\tTargetAttributes = {\n"
project << "\t\t\t\t\t#{ids.fetch(:target)} = { CreatedOnToolsVersion = 16.0; };\n"
project << "\t\t\t\t};\n"
project << "\t\t\t};\n"
project << "\t\t\tbuildConfigurationList = #{ids.fetch(:project_configuration_list)};\n"
project << "\t\t\tcompatibilityVersion = \"Xcode 14.0\";\n"
project << "\t\t\tdevelopmentRegion = en;\n"
project << "\t\t\thasScannedForEncodings = 0;\n"
project << "\t\t\tknownRegions = (en, ko, Base);\n"
project << "\t\t\tmainGroup = #{ids.fetch(:main_group)};\n"
project << "\t\t\tproductRefGroup = #{ids.fetch(:products_group)};\n"
project << "\t\t\tprojectDirPath = \"\";\n"
project << "\t\t\tprojectRoot = \"\";\n"
project << "\t\t\ttargets = (#{ids.fetch(:target)});\n"
project << "\t\t};\n"
project << "/* End PBXProject section */\n\n"

project << "/* Begin PBXResourcesBuildPhase section */\n"
project << "\t\t#{ids.fetch(:resources_phase)} = {\n"
project << "\t\t\tisa = PBXResourcesBuildPhase;\n"
project << "\t\t\tbuildActionMask = 2147483647;\n"
project << "\t\t\tfiles = ("
LOCALIZED_RESOURCES.each do |resource|
  project << "#{localized_resource_build_ids.fetch(resource)}, "
end
project << "#{ids.fetch(:app_icon_build)});\n"
project << "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
project << "\t\t};\n"
project << "/* End PBXResourcesBuildPhase section */\n\n"

project << "/* Begin PBXSourcesBuildPhase section */\n"
project << "\t\t#{ids.fetch(:sources_phase)} = {\n"
project << "\t\t\tisa = PBXSourcesBuildPhase;\n"
project << "\t\t\tbuildActionMask = 2147483647;\n"
project << "\t\t\tfiles = (\n"
source_paths.each do |path|
  project << "\t\t\t\t#{source_build_ids.fetch(path)},\n"
end
project << "\t\t\t);\n"
project << "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
project << "\t\t};\n"
project << "/* End PBXSourcesBuildPhase section */\n\n"

project << "/* Begin PBXVariantGroup section */\n"
LOCALIZED_RESOURCES.each do |resource|
  project << "\t\t#{localized_resource_group_ids.fetch(resource)} = {\n"
  project << "\t\t\tisa = PBXVariantGroup;\n"
  project << "\t\t\tchildren = (\n"
  LOCALIZATIONS.each do |localization|
    project << "\t\t\t\t#{localized_resource_reference_ids.fetch([resource, localization])},\n"
  end
  project << "\t\t\t);\n"
  project << "\t\t\tname = #{resource};\n"
  project << "\t\t\tsourceTree = \"<group>\";\n"
  project << "\t\t};\n"
end
project << "/* End PBXVariantGroup section */\n\n"

common_project_settings = <<~SETTINGS
\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;
\t\t\t\tARCHS = "$(ARCHS_STANDARD)";
\t\t\t\tCLANG_ENABLE_MODULES = YES;
\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;
\t\t\t\tCLANG_WARN_BLOCK_CAPTURE_AUTORELEASING = YES;
\t\t\t\tCLANG_WARN_BOOL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_COMMA = YES;
\t\t\t\tCLANG_WARN_CONSTANT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS = YES;
\t\t\t\tCLANG_WARN_DOCUMENTATION_COMMENTS = YES;
\t\t\t\tCLANG_WARN_EMPTY_BODY = YES;
\t\t\t\tCLANG_WARN_ENUM_CONVERSION = YES;
\t\t\t\tCLANG_WARN_INFINITE_RECURSION = YES;
\t\t\t\tCLANG_WARN_INT_CONVERSION = YES;
\t\t\t\tCLANG_WARN_NON_LITERAL_NULL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF = YES;
\t\t\t\tCLANG_WARN_OBJC_LITERAL_CONVERSION = YES;
\t\t\t\tCLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER = YES;
\t\t\t\tCLANG_WARN_RANGE_LOOP_ANALYSIS = YES;
\t\t\t\tCLANG_WARN_STRICT_PROTOTYPES = YES;
\t\t\t\tCLANG_WARN_SUSPICIOUS_MOVE = YES;
\t\t\t\tCLANG_WARN_UNGUARDED_AVAILABILITY = YES_AGGRESSIVE;
\t\t\t\tCLANG_WARN_UNREACHABLE_CODE = YES;
\t\t\t\tCLANG_WARN__DUPLICATE_METHOD_MATCH = YES;
\t\t\t\tCOPY_PHASE_STRIP = NO;
\t\t\t\tDEAD_CODE_STRIPPING = YES;
\t\t\t\tENABLE_STRICT_OBJC_MSGSEND = YES;
\t\t\t\tGCC_C_LANGUAGE_STANDARD = gnu17;
\t\t\t\tGCC_NO_COMMON_BLOCKS = YES;
\t\t\t\tGCC_WARN_64_TO_32_BIT_CONVERSION = YES;
\t\t\t\tGCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
\t\t\t\tGCC_WARN_UNDECLARED_SELECTOR = YES;
\t\t\t\tGCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
\t\t\t\tGCC_WARN_UNUSED_FUNCTION = YES;
\t\t\t\tGCC_WARN_UNUSED_VARIABLE = YES;
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = #{quoted(minimum_system_version)};
\t\t\t\tONLY_ACTIVE_ARCH = NO;
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
SETTINGS

common_target_settings = <<~SETTINGS
\t\t\t\tARCHS = "$(ARCHS_STANDARD)";
\t\t\t\tCODE_SIGNING_ALLOWED = NO;
\t\t\t\tCODE_SIGNING_REQUIRED = NO;
\t\t\t\tCURRENT_PROJECT_VERSION = #{quoted(build_number)};
\t\t\t\tENABLE_HARDENED_RUNTIME = YES;
\t\t\t\tEXECUTABLE_NAME = #{quoted(executable_name)};
\t\t\t\tGENERATE_INFOPLIST_FILE = NO;
\t\t\t\tINFOPLIST_FILE = Config/Info.plist;
\t\t\t\tLD_RUNPATH_SEARCH_PATHS = "@executable_path/../Frameworks";
\t\t\t\tMACOSX_DEPLOYMENT_TARGET = #{quoted(minimum_system_version)};
\t\t\t\tMARKETING_VERSION = #{quoted(marketing_version)};
\t\t\t\tONLY_ACTIVE_ARCH = NO;
\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = #{quoted(bundle_identifier)};
\t\t\t\tPRODUCT_NAME = #{quoted(app_name)};
\t\t\t\tSDKROOT = macosx;
\t\t\t\tSUPPORTED_PLATFORMS = macosx;
\t\t\t\tSWIFT_STRICT_CONCURRENCY = complete;
\t\t\t\tSWIFT_VERSION = 6.0;
SETTINGS

project << "/* Begin XCBuildConfiguration section */\n"
project << "\t\t#{ids.fetch(:project_debug)} = { isa = XCBuildConfiguration; buildSettings = {\n"
project << common_project_settings
project << "\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;\n"
project << "\t\t\t\tENABLE_TESTABILITY = YES;\n"
project << "\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;\n"
project << "\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;\n"
project << "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";\n"
project << "\t\t\t}; name = Debug; };\n"
project << "\t\t#{ids.fetch(:project_release)} = { isa = XCBuildConfiguration; buildSettings = {\n"
project << common_project_settings
project << "\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";\n"
project << "\t\t\t\tENABLE_NS_ASSERTIONS = NO;\n"
project << "\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;\n"
project << "\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";\n"
project << "\t\t\t}; name = Release; };\n"
project << "\t\t#{ids.fetch(:target_debug)} = { isa = XCBuildConfiguration; buildSettings = {\n"
project << common_target_settings
project << "\t\t\t\tENABLE_TESTABILITY = YES;\n"
project << "\t\t\t}; name = Debug; };\n"
project << "\t\t#{ids.fetch(:target_release)} = { isa = XCBuildConfiguration; buildSettings = {\n"
project << common_target_settings
project << "\t\t\t}; name = Release; };\n"
project << "/* End XCBuildConfiguration section */\n\n"

project << "/* Begin XCConfigurationList section */\n"
project << "\t\t#{ids.fetch(:project_configuration_list)} = { isa = XCConfigurationList; buildConfigurations = (#{ids.fetch(:project_debug)}, #{ids.fetch(:project_release)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };\n"
project << "\t\t#{ids.fetch(:target_configuration_list)} = { isa = XCConfigurationList; buildConfigurations = (#{ids.fetch(:target_debug)}, #{ids.fetch(:target_release)}); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release; };\n"
project << "/* End XCConfigurationList section */\n"

project << "\t};\n"
project << "\trootObject = #{ids.fetch(:project)};\n"
project << "}\n"

escaped_app_bundle_name = xml_escaped(app_bundle_name)

scheme = <<~XML
  <?xml version="1.0" encoding="UTF-8"?>
  <Scheme LastUpgradeVersion="1600" version="1.7">
     <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
        <BuildActionEntries>
           <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
              <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{ids.fetch(:target)}" BuildableName="#{escaped_app_bundle_name}" BlueprintName="#{PROJECT_NAME}" ReferencedContainer="container:#{PROJECT_NAME}.xcodeproj">
              </BuildableReference>
           </BuildActionEntry>
        </BuildActionEntries>
     </BuildAction>
     <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES">
        <Testables>
        </Testables>
     </TestAction>
     <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
        <BuildableProductRunnable runnableDebuggingMode="0">
           <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{ids.fetch(:target)}" BuildableName="#{escaped_app_bundle_name}" BlueprintName="#{PROJECT_NAME}" ReferencedContainer="container:#{PROJECT_NAME}.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </LaunchAction>
     <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
        <BuildableProductRunnable runnableDebuggingMode="0">
           <BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="#{ids.fetch(:target)}" BuildableName="#{escaped_app_bundle_name}" BlueprintName="#{PROJECT_NAME}" ReferencedContainer="container:#{PROJECT_NAME}.xcodeproj">
           </BuildableReference>
        </BuildableProductRunnable>
     </ProfileAction>
     <AnalyzeAction buildConfiguration="Debug">
     </AnalyzeAction>
     <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES">
     </ArchiveAction>
  </Scheme>
XML

write_if_changed(File.join(PROJECT_DIR, "project.pbxproj"), project)
write_if_changed(
  File.join(PROJECT_DIR, "xcshareddata", "xcschemes", "#{PROJECT_NAME}.xcscheme"),
  scheme
)

verb = CHECK_MODE ? "Verified" : "Generated"
puts "#{verb} #{PROJECT_NAME}.xcodeproj with #{source_paths.length} Swift files."
