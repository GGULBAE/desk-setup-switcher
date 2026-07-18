#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "release_policy"

class ReleasePolicyTestSuite
  SCRIPT = File.expand_path("release_policy.rb", __dir__)
  FIXTURES = File.expand_path("fixtures", __dir__)
  AUTHORITY = "Developer ID Application: Synthetic Maintainer (ABCDE12345)"
  TEAM_ID = "ABCDE12345"
  IDENTIFIER = "com.example.DeskSetupSwitcher"
  VERSION = "0.1.0"
  TAG = "v0.1.0"
  COMMIT = "a" * 40
  NAMESPACE = "https://example.invalid/desk-setup-switcher/v0.1.0/audit"
  CREATED = "2026-07-18T03:00:00Z"
  RUN_ID = "123456789"
  RUN_ATTEMPT = "1"
  RUN_URL = "https://github.com/example/repository/actions/runs/123456789"

  class TestFailure < StandardError; end

  def initialize
    @assertions = 0
    @tests = 0
    @failures = []
  end

  def assert(condition, message = "assertion failed")
    @assertions += 1
    raise TestFailure, message unless condition
  end

  def assert_equal(expected, actual, message = "values are not equal")
    assert(expected == actual, message)
  end

  def cli(*arguments)
    Open3.capture3(RbConfig.ruby, SCRIPT, *arguments)
  end

  def assert_success(*arguments)
    stdout, stderr, status = cli(*arguments)
    assert(status.success?, "command was expected to succeed: #{stderr.strip}")
    assert(stderr.empty?, "successful command wrote to stderr")
    assert(stdout.start_with?("OK ") || stdout.start_with?("Usage:"), "successful command did not report a stable result")
    [stdout, stderr]
  end

  def assert_failure(*arguments)
    stdout, stderr, status = cli(*arguments)
    assert(!status.success?, "command was expected to fail")
    assert(stdout.empty?, "failed command wrote to stdout")
    assert(stderr.start_with?("ERROR: "), "failed command did not report a sanitized error")
    [stdout, stderr]
  end

  def fixture(name)
    File.join(FIXTURES, name)
  end

  def write(path, contents, mode: nil)
    FileUtils.mkdir_p(File.dirname(path))
    File.binwrite(path, contents)
    File.chmod(mode, path) if mode
    path
  end

  def run(name)
    @tests += 1
    yield
    puts "ok #{@tests} - #{name}"
  rescue StandardError => error
    @failures << [name, error.class.name, error.message]
    puts "not ok #{@tests} - #{name}"
  end

  def codesign_arguments(report, kind: "app", identifier: IDENTIFIER, architecture: nil)
    arguments = [
      "verify-codesign",
      "--report", report,
      "--authority", AUTHORITY,
      "--team-id", TEAM_ID,
      "--identifier", identifier,
      "--kind", kind
    ]
    arguments.concat(["--architecture", architecture || "arm64"]) if kind == "app"
    arguments
  end

  def app_codesign_report_specs
    [
      "arm64=#{fixture('codesign-app-accepted.txt')}",
      "x86_64=#{fixture('codesign-app-x86_64-accepted.txt')}"
    ]
  end

  def test_codesign
    run("accepted Developer ID app and DMG reports") do
      assert_success(*codesign_arguments(fixture("codesign-app-accepted.txt")))
      assert_success(*codesign_arguments(
        fixture("codesign-app-x86_64-accepted.txt"),
        architecture: "x86_64"
      ))
      Dir.mktmpdir do |directory|
        report = File.binread(fixture("codesign-app-accepted.txt"))
        report = report.gsub("Identifier=#{IDENTIFIER}", "Identifier=#{IDENTIFIER}.dmg")
                       .gsub("flags=0x10000(runtime)", "flags=0x0(none)")
        path = write(File.join(directory, "dmg-report.txt"), report)
        assert_success(*codesign_arguments(path, kind: "dmg", identifier: "#{IDENTIFIER}.dmg"))
      end
    end

    mutations = {
      "wrong first authority" => [
        "Authority=Developer ID Application: Synthetic Maintainer (ABCDE12345)",
        "Authority=Developer ID Application: Different Maintainer (ABCDE12345)"
      ],
      "Apple Development authority" => [
        "Authority=Developer ID Application: Synthetic Maintainer (ABCDE12345)",
        "Authority=Apple Development: Synthetic Maintainer (ABCDE12345)"
      ],
      "Mac App Distribution authority" => [
        "Authority=Developer ID Application: Synthetic Maintainer (ABCDE12345)",
        "Authority=Mac App Distribution: Synthetic Maintainer (ABCDE12345)"
      ],
      "wrong team identifier" => ["TeamIdentifier=ABCDE12345", "TeamIdentifier=ZZZZZ99999"],
      "wrong bundle identifier" => ["Identifier=#{IDENTIFIER}", "Identifier=com.example.Wrong"],
      "missing runtime flag" => ["flags=0x10000(runtime)", "flags=0x0(none)"],
      "missing secure timestamp" => ["Timestamp=Jul 18, 2026 at 12:00:00 PM", "Timestamp=none"],
      "invalid CDHash" => ["CDHash=0123456789abcdef0123456789abcdef01234567", "CDHash=invalid"]
    }
    mutations.each do |name, (from, to)|
      run("codesign rejects #{name}") do
        Dir.mktmpdir do |directory|
          content = File.binread(fixture("codesign-app-accepted.txt")).sub(from, to)
          path = write(File.join(directory, "report.txt"), content)
          assert_failure(*codesign_arguments(path))
        end
      end
    end

    run("codesign rejects ad hoc signatures") do
      Dir.mktmpdir do |directory|
        content = File.binread(fixture("codesign-app-accepted.txt")).sub("Signature size=9046", "Signature=adhoc")
        path = write(File.join(directory, "report.txt"), content)
        assert_failure(*codesign_arguments(path))
      end
    end

    run("codesign rejects a report labelled as the wrong architecture") do
      assert_failure(*codesign_arguments(
        fixture("codesign-app-accepted.txt"),
        architecture: "x86_64"
      ))
      assert_failure(*codesign_arguments(
        fixture("codesign-app-x86_64-accepted.txt"),
        architecture: "arm64"
      ))
    end

    run("codesign errors do not echo report contents") do
      Dir.mktmpdir do |directory|
        marker = "SENSITIVE_FILE_CONTENT_MARKER"
        content = File.binread(fixture("codesign-app-accepted.txt")).sub("Timestamp=Jul 18, 2026 at 12:00:00 PM", "Timestamp=none\n#{marker}")
        path = write(File.join(directory, "report.txt"), content)
        _stdout, stderr = assert_failure(*codesign_arguments(path))
        assert(!stderr.include?(marker), "error leaked report contents")
        assert(!stderr.include?(directory), "error leaked a local path")
      end
    end
  end

  def test_entitlements
    run("entitlements accept explicit absence and an empty dictionary") do
      assert_success("verify-entitlements", "--absent")
      assert_success("verify-entitlements", "--plist", fixture("entitlements-empty.plist"))
    end
    run("entitlements reject get-task-allow and every extra key") do
      assert_failure("verify-entitlements", "--plist", fixture("entitlements-extra.plist"))
    end
    run("entitlements reject ambiguous absence plus plist") do
      assert_failure("verify-entitlements", "--absent", "--plist", fixture("entitlements-empty.plist"))
    end
    run("entitlements reject a missing plist") do
      Dir.mktmpdir do |directory|
        assert_failure("verify-entitlements", "--plist", File.join(directory, "missing.plist"))
      end
    end
  end

  def test_notary
    run("notary accepts an Accepted result with a valid UUID") do
      assert_success("verify-notary", "--json", fixture("notary-accepted.json"))
      stdout, stderr, status = cli(
        "verify-notary", "--json", fixture("notary-accepted.json"), "--print-id"
      )
      assert(status.success?, "verified notary ID extraction failed")
      assert(stderr.empty?, "verified notary ID extraction wrote to stderr")
      assert_equal(
        "123e4567-e89b-42d3-a456-426614174000\n",
        stdout,
        "verified notary ID extraction was not normalized"
      )
    end
    run("notary rejects a non-Accepted status") do
      Dir.mktmpdir do |directory|
        path = write(File.join(directory, "notary.json"), JSON.generate("id" => "123e4567-e89b-42d3-a456-426614174000", "status" => "Invalid"))
        assert_failure("verify-notary", "--json", path)
      end
    end
    run("notary rejects an invalid UUID") do
      Dir.mktmpdir do |directory|
        path = write(File.join(directory, "notary.json"), JSON.generate("id" => "not-a-uuid", "status" => "Accepted"))
        assert_failure("verify-notary", "--json", path)
      end
    end
    run("notary rejects duplicate status keys") do
      Dir.mktmpdir do |directory|
        path = write(File.join(directory, "notary.json"), "{\"id\":\"123e4567-e89b-42d3-a456-426614174000\",\"status\":\"Accepted\",\"status\":\"Invalid\"}\n")
        assert_failure("verify-notary", "--json", path)
      end
    end

    run("notary ID extraction uses its verified snapshot after the input path is replaced") do
      Dir.mktmpdir do |directory|
        original_id = "123e4567-e89b-42d3-a456-426614174000"
        replacement_id = "223e4567-e89b-42d3-a456-426614174000"
        path = write(
          File.join(directory, "notary.json"),
          JSON.generate("id" => original_id, "status" => "Accepted") + "\n"
        )
        original_read_utf8 = ReleasePolicy.method(:read_utf8)
        read_count = 0
        singleton = class << ReleasePolicy; self; end
        singleton.send(:define_method, :read_utf8) do |input_path, label, max_bytes:|
          read_count += 1
          source = original_read_utf8.call(input_path, label, max_bytes: max_bytes)
          File.binwrite(
            input_path,
            JSON.generate("id" => replacement_id, "status" => "Accepted") + "\n"
          )
          source
        end

        begin
          result = ReleasePolicy.verify_notary(path)
        ensure
          singleton.send(:define_method, :read_utf8, original_read_utf8)
        end

        assert_equal(1, read_count, "notary verification reopened the verified input path")
        assert_equal(original_id, result.fetch("id"), "notary verification did not use its verified snapshot")
      end
    end
  end

  def test_strict_json
    run("strict JSON accepts surrogate pairs and rejects decoded-equivalent keys") do
      Dir.mktmpdir do |directory|
        valid = write(File.join(directory, "valid.json"), %q({"message":"\uD83D\uDE00"}) + "\n")
        assert_success("verify-json", "--json", valid)

        duplicate = write(
          File.join(directory, "duplicate.json"),
          %q({"😀":1,"\uD83D\uDE00":2}) + "\n"
        )
        assert_failure("verify-json", "--json", duplicate)
      end
    end

    run("JSON sanitization rejects decoded-equivalent duplicate keys without changing output") do
      Dir.mktmpdir do |directory|
        input = write(
          File.join(directory, "duplicate.json"),
          %q({"😀":"/repo/first","\uD83D\uDE00":"/repo/second"}) + "\n"
        )
        output = write(File.join(directory, "sanitized.json"), "existing-output\n", mode: 0o600)
        assert_failure(
          "sanitize-json",
          "--json", input,
          "--output", output,
          "--repository", "/repo"
        )
        assert_equal("existing-output\n", File.binread(output), "failed sanitization changed the output")
        assert_equal(0o600, File.stat(output).mode & 0o777, "failed sanitization changed the output mode")
      end
    end

    run("JSON sanitization is exact, recursive, newline-terminated, and mode 0644") do
      Dir.mktmpdir do |directory|
        home = "/Users/release-runner"
        repository = "#{home}/work/desk-setup-switcher"
        runner_temp = "#{home}/work/_temp"
        input = write(
          File.join(directory, "input.json"),
          JSON.generate(
            "repository" => "#{repository}/artifacts/candidate.dmg",
            "nested" => [
              { "home" => "#{home}/Library/Logs/notary.log" },
              "#{runner_temp}/notary-result.json",
              "#{repository}:#{home}:#{runner_temp}"
            ],
            "unchanged" => 7
          )
        )
        output = File.join(directory, "sanitized.json")
        assert_success(
          "sanitize-json",
          "--json", input,
          "--output", output,
          "--repository", repository,
          "--home", home,
          "--runner-temp", runner_temp
        )
        expected = <<~JSON
          {
            "repository": "$REPOSITORY/artifacts/candidate.dmg",
            "nested": [
              {
                "home": "$HOME/Library/Logs/notary.log"
              },
              "$RUNNER_TEMP/notary-result.json",
              "$REPOSITORY:$HOME:$RUNNER_TEMP"
            ],
            "unchanged": 7
          }
        JSON
        assert_equal(expected, File.binread(output), "sanitized JSON bytes were not exact")
        assert_equal(0o644, File.stat(output).mode & 0o777, "sanitized JSON mode was not 0644")
      end
    end

    run("JSON sanitization uses its verified in-memory snapshot after the input path is replaced") do
      Dir.mktmpdir do |directory|
        repository = "/private/work/desk-setup-switcher"
        input = write(
          File.join(directory, "input.json"),
          JSON.generate("path" => "#{repository}/verified") + "\n"
        )
        output = File.join(directory, "sanitized.json")
        original_read_utf8 = ReleasePolicy.method(:read_utf8)
        read_count = 0
        singleton = class << ReleasePolicy; self; end
        singleton.send(:define_method, :read_utf8) do |path, label, max_bytes:|
          read_count += 1
          source = original_read_utf8.call(path, label, max_bytes: max_bytes)
          File.binwrite(path, JSON.generate("path" => "#{repository}/replacement") + "\n")
          source
        end

        begin
          ReleasePolicy.sanitize_json(
            input_path: input,
            output_path: output,
            repository_path: repository
          )
        ensure
          singleton.send(:define_method, :read_utf8, original_read_utf8)
        end

        assert_equal(1, read_count, "sanitization reopened the verified input path")
        assert_equal(<<~JSON, File.binread(output), "sanitization did not use the verified snapshot")
          {
            "path": "$REPOSITORY/verified"
          }
        JSON
      end
    end
  end

  def sbom_arguments(dmg:, digest:, size:, package_dump:, output:)
    [
      "generate-sbom",
      "--dmg", dmg,
      "--sha256", digest,
      "--size", size.to_s,
      "--version", VERSION,
      "--tag", TAG,
      "--commit", COMMIT,
      "--namespace", NAMESPACE,
      "--created", CREATED,
      "--package-dump", package_dump,
      "--output", output
    ]
  end

  def test_sbom
    run("SBOM generation is exact, deterministic, and independently verifiable") do
      Dir.mktmpdir do |directory|
        dmg = write(File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg"), "synthetic-final-dmg\n")
        digest = Digest::SHA256.file(dmg).hexdigest
        size = File.size(dmg)
        first = File.join(directory, "first.spdx.json")
        second = File.join(directory, "second.spdx.json")
        assert_success(*sbom_arguments(dmg: dmg, digest: digest, size: size, package_dump: fixture("package-dump-zero.json"), output: first))
        assert_success(*sbom_arguments(dmg: dmg, digest: digest, size: size, package_dump: fixture("package-dump-zero.json"), output: second))
        assert_equal(File.binread(first), File.binread(second), "SBOM bytes were not deterministic")

        document = JSON.parse(File.binread(first))
        package = document.fetch("packages").first
        assert_equal("SPDX-2.3", document.fetch("spdxVersion"))
        assert_equal(NAMESPACE, document.fetch("documentNamespace"))
        assert_equal(["SPDXRef-Package-DeskSetupSwitcher"], document.fetch("documentDescribes"))
        assert_equal("Desk Setup Switcher", package.fetch("name"))
        assert_equal("MIT", package.fetch("licenseDeclared"))
        assert_equal(digest, package.fetch("checksums").first.fetch("checksumValue"))
        expected_source_info = "releaseTag=#{TAG}; commit=#{COMMIT}; dmgSizeBytes=#{size}; swiftPackageThirdPartyDependencies=0; applePlatformFrameworks=system-provided-not-bundled; releaseSiteDependencies=build-time-only-not-bundled"
        assert_equal(expected_source_info, package.fetch("sourceInfo"))
        assert(!File.binread(first).include?(directory), "SBOM leaked a local path")
        assert_success("verify-sbom", "--sbom", first, "--dmg", dmg, "--version", VERSION, "--tag", TAG, "--commit", COMMIT)
      end
    end

    run("SBOM generation rejects a mismatched DMG digest") do
      Dir.mktmpdir do |directory|
        dmg = write(File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg"), "candidate\n")
        output = File.join(directory, "candidate.spdx.json")
        assert_failure(*sbom_arguments(dmg: dmg, digest: "0" * 64, size: File.size(dmg), package_dump: fixture("package-dump-zero.json"), output: output))
        assert(!File.exist?(output), "failed SBOM generation left an output")
      end
    end

    run("SBOM generation rejects third-party Package.swift dependencies") do
      Dir.mktmpdir do |directory|
        dmg = write(File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg"), "candidate\n")
        output = File.join(directory, "candidate.spdx.json")
        assert_failure(*sbom_arguments(
          dmg: dmg,
          digest: Digest::SHA256.file(dmg).hexdigest,
          size: File.size(dmg),
          package_dump: fixture("package-dump-dependency.json"),
          output: output
        ))
      end
    end

    run("SBOM verifier rejects tampered digest and dependency evidence") do
      Dir.mktmpdir do |directory|
        dmg = write(File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg"), "candidate\n")
        sbom = File.join(directory, "candidate.spdx.json")
        assert_success(*sbom_arguments(
          dmg: dmg,
          digest: Digest::SHA256.file(dmg).hexdigest,
          size: File.size(dmg),
          package_dump: fixture("package-dump-zero.json"),
          output: sbom
        ))
        data = JSON.parse(File.binread(sbom))
        data["packages"][0]["checksums"][0]["checksumValue"] = "0" * 64
        bad_digest = write(File.join(directory, "bad-digest.spdx.json"), JSON.pretty_generate(data) + "\n")
        assert_failure("verify-sbom", "--sbom", bad_digest, "--dmg", dmg, "--version", VERSION, "--tag", TAG, "--commit", COMMIT)

        data = JSON.parse(File.binread(sbom))
        data["packages"][0]["sourceInfo"] = data["packages"][0]["sourceInfo"].sub("swiftPackageThirdPartyDependencies=0", "swiftPackageThirdPartyDependencies=1")
        bad_dependency = write(File.join(directory, "bad-dependency.spdx.json"), JSON.pretty_generate(data) + "\n")
        assert_failure("verify-sbom", "--sbom", bad_dependency, "--dmg", dmg, "--version", VERSION, "--tag", TAG, "--commit", COMMIT)
      end
    end
  end

  def create_app(directory)
    app = File.join(directory, "Desk Setup Switcher.app")
    write(File.join(app, "Contents", "Info.plist"), "synthetic-info\n")
    write(File.join(app, "Contents", "MacOS", "DeskSetupSwitcher"), "synthetic-executable\n", mode: 0o755)
    write(File.join(app, "Contents", "_CodeSignature", "CodeResources"), "synthetic-signature-resources\n")
    app
  end

  def verification_files(directory)
    {
      "appCodesign" => write(File.join(directory, "app-codesign.txt"), "/synthetic/app: valid on disk\n/synthetic/app: satisfies its Designated Requirement\n"),
      "dmgCodesign" => write(File.join(directory, "dmg-codesign.txt"), "/synthetic/dmg: valid on disk\n/synthetic/dmg: satisfies its Designated Requirement\n"),
      "staplerValidate" => write(File.join(directory, "stapler.txt"), "The validate action worked!\n"),
      "spctlDMG" => write(File.join(directory, "spctl-dmg.txt"), "/synthetic/dmg: accepted\nsource=Notarized Developer ID\n"),
      "spctlApp" => write(File.join(directory, "spctl-app.txt"), "/synthetic/app: accepted\nsource=Notarized Developer ID\n")
    }
  end

  def release_manifest_arguments(context, output:, codesign_report_specs: app_codesign_report_specs)
    arguments = [
      "generate-release-manifest",
      "--version", VERSION,
      "--build-number", "1",
      "--tag", TAG,
      "--commit", COMMIT,
      "--namespace", NAMESPACE,
      "--created", CREATED,
      "--run-id", RUN_ID,
      "--run-attempt", RUN_ATTEMPT,
      "--run-url", RUN_URL,
      "--toolchain", "architecture=arm64",
      "--toolchain", "runner=macos-15",
      "--toolchain", "swift=Swift 6.1",
      "--toolchain", "xcode=Xcode 16.4",
      "--app", context.fetch(:app),
      "--authority", AUTHORITY,
      "--team-id", TEAM_ID,
      "--identifier", IDENTIFIER,
      "--executable", context.fetch(:executable),
      "--designated-requirement", context.fetch(:designated_requirement),
      "--entitlements-plist", fixture("entitlements-empty.plist"),
      "--pre-notary-dmg", context.fetch(:pre_dmg),
      "--final-dmg", context.fetch(:final_dmg),
      "--notary-json", context.fetch(:notary),
      "--notary-log", context.fetch(:notary_log),
      "--output", output
    ]
    codesign_report_specs.each do |spec|
      arguments.concat(["--app-codesign-report", spec])
    end
    context.fetch(:assets).each do |name, path|
      arguments.concat(["--asset", "#{name}=#{path}"])
    end
    context.fetch(:verifications).each do |name, path|
      arguments.concat(["--verification", "#{name}=#{path}"])
    end
    arguments
  end

  def create_release_context(directory)
    app = create_app(directory)
    executable = File.join(app, "Contents", "MacOS", "DeskSetupSwitcher")
    designated_requirement = write(
      File.join(directory, "designated-requirement.txt"),
      %(designated => identifier "#{IDENTIFIER}" and anchor apple generic and certificate leaf[subject.OU] = #{TEAM_ID}\n)
    )
    pre_dmg = write(File.join(directory, "pre-notary.dmg"), "synthetic-pre-notary-dmg\n")
    final_dmg = write(File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg"), "synthetic-final-stapled-dmg\n")
    checksum = write(File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg.sha256"), "#{Digest::SHA256.file(final_dmg).hexdigest}  Desk-Setup-Switcher-#{VERSION}.dmg\n")
    sbom = File.join(directory, "Desk-Setup-Switcher-#{VERSION}.spdx.json")
    assert_success(*sbom_arguments(
      dmg: final_dmg,
      digest: Digest::SHA256.file(final_dmg).hexdigest,
      size: File.size(final_dmg),
      package_dump: fixture("package-dump-zero.json"),
      output: sbom
    ))
    notary = File.join(directory, "notary-result.json")
    FileUtils.cp(fixture("notary-accepted.json"), notary)
    notary_result = JSON.parse(File.binread(notary))
    notary_log = write(
      File.join(directory, "notary-log.json"),
      JSON.pretty_generate(
        {
          "logFormatVersion" => 1,
          "jobId" => notary_result.fetch("id"),
          "status" => "Accepted",
          "statusSummary" => "Ready for distribution",
          "statusCode" => 0,
          "archiveFilename" => File.basename(final_dmg),
          "uploadDate" => CREATED,
          "sha256" => Digest::SHA256.file(pre_dmg).hexdigest,
          "ticketContents" => [],
          "issues" => []
        }
      ) + "\n"
    )
    {
      app: app,
      executable: executable,
      designated_requirement: designated_requirement,
      pre_dmg: pre_dmg,
      final_dmg: final_dmg,
      notary: notary,
      notary_log: notary_log,
      assets: {
        File.basename(final_dmg) => final_dmg,
        File.basename(checksum) => checksum,
        File.basename(sbom) => sbom,
        File.basename(notary) => notary,
        File.basename(notary_log) => notary_log
      },
      verifications: verification_files(directory)
    }
  end

  def asset_cli_arguments(context)
    context.fetch(:assets).flat_map { |name, path| ["--asset", "#{name}=#{path}"] }
  end

  def verify_manifest_arguments(context, manifest:, asset_arguments: asset_cli_arguments(context))
    [
      "verify-release-manifest",
      "--manifest", manifest,
      "--version", VERSION,
      "--build-number", "1",
      "--tag", TAG,
      "--commit", COMMIT,
      "--namespace", NAMESPACE,
      "--created", CREATED,
      "--run-id", RUN_ID,
      "--run-attempt", RUN_ATTEMPT,
      "--run-url", RUN_URL,
      *asset_arguments
    ]
  end

  def test_release_manifest
    run("bundle and release manifests are deterministic same-candidate evidence") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        bundle_one = File.join(directory, "bundle-one.json")
        bundle_two = File.join(directory, "bundle-two.json")
        assert_success("generate-bundle-manifest", "--app", context[:app], "--output", bundle_one)
        assert_success("generate-bundle-manifest", "--app", context[:app], "--output", bundle_two)
        assert_equal(File.binread(bundle_one), File.binread(bundle_two), "bundle manifest bytes were not deterministic")

        first = File.join(directory, "release-manifest-one.json")
        second = File.join(directory, "release-manifest-two.json")
        assert_success(*release_manifest_arguments(context, output: first))
        assert_success(*release_manifest_arguments(context, output: second))
        assert_equal(File.binread(first), File.binread(second), "release manifest bytes were not deterministic")

        manifest = JSON.parse(File.binread(first))
        bundle = JSON.parse(File.binread(bundle_one))
        assert_equal("desk-setup-switcher.release-evidence/v1", manifest.fetch("schemaVersion"))
        assert_equal(COMMIT, manifest.dig("release", "commit"))
        assert_equal(123456789, manifest.dig("release", "run", "id"))
        assert_equal(%w[architecture runner swift xcode], manifest.fetch("toolchain").keys)
        assert_equal(
          {
            "arm64" => "0123456789abcdef0123456789abcdef01234567",
            "x86_64" => "fedcba9876543210fedcba9876543210fedcba98"
          },
          manifest.dig("application", "cdhashes")
        )
        assert_equal(%w[arm64 x86_64], manifest.dig("application", "cdhashes").keys)
        assert_equal(bundle.fetch("canonicalSha256"), manifest.dig("application", "bundleManifest", "canonicalSha256"))
        assert_equal(bundle.fetch("entryCount"), manifest.dig("application", "bundleManifest", "entryCount"))
        assert(manifest.dig("lineage", "preNotaryDmg", "sha256") != manifest.dig("lineage", "finalStapledDmg", "sha256"), "DMG lineage did not distinguish pre-notary and final bytes")
        assert_equal("Accepted", manifest.dig("lineage", "notary", "status"))
        assert_equal(Digest::SHA256.file(context.fetch(:pre_dmg)).hexdigest,
                     manifest.dig("lineage", "notary", "submittedSha256"))
        assert_equal(%w[appCodesign dmgCodesign spctlApp spctlDMG staplerValidate], manifest.fetch("verifications").map { |record| record.fetch("name") })
        assert(manifest.fetch("verifications").all? { |record| record.fetch("result") == "pass" }, "verification records were not pass-only")
        assert(manifest.fetch("verifications").all? { |record| !record.fetch("output").empty? }, "verification outputs were not embedded")
        assert(
          manifest.fetch("verifications").all? do |record|
            Digest::SHA256.hexdigest(record.fetch("output").b) == record.fetch("sha256") &&
              record.fetch("output").bytesize == record.fetch("size")
          end,
          "verification outputs were not bound to their digests"
        )
        assert_equal(manifest.fetch("assets").map { |asset| asset.fetch("name") }.sort,
                     manifest.fetch("assets").map { |asset| asset.fetch("name") })
        assert(!File.binread(first).include?(directory), "release manifest leaked a local path")
        assert_success(*verify_manifest_arguments(context, manifest: first))
      end
    end

    run("release manifest verifies byte-identical redownloaded assets at different paths") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        downloaded = File.join(directory, "downloads")
        FileUtils.mkdir_p(downloaded)
        mappings = context[:assets].map.with_index do |(name, path), index|
          copy = File.join(downloaded, "download-#{index}.bin")
          FileUtils.cp(path, copy)
          ["--asset", "#{name}=#{copy}"]
        end.flatten
        assert_success(*verify_manifest_arguments(context, manifest: manifest, asset_arguments: mappings))
      end
    end

    run("release manifest requires exact unique architecture-labelled app reports") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        arm64 = "arm64=#{fixture('codesign-app-accepted.txt')}"

        assert_failure(*release_manifest_arguments(
          context,
          output: File.join(directory, "missing.json"),
          codesign_report_specs: [arm64]
        ))
        assert_failure(*release_manifest_arguments(
          context,
          output: File.join(directory, "unknown.json"),
          codesign_report_specs: [arm64, "ppc=#{fixture('codesign-app-x86_64-accepted.txt')}"]
        ))
        assert_failure(*release_manifest_arguments(
          context,
          output: File.join(directory, "duplicate.json"),
          codesign_report_specs: [arm64, "arm64=#{fixture('codesign-app-x86_64-accepted.txt')}"]
        ))
        assert_failure(*release_manifest_arguments(
          context,
          output: File.join(directory, "swapped.json"),
          codesign_report_specs: [
            "arm64=#{fixture('codesign-app-x86_64-accepted.txt')}",
            "x86_64=#{fixture('codesign-app-accepted.txt')}"
          ]
        ))

        duplicate_hash_report = File.binread(fixture("codesign-app-x86_64-accepted.txt")).sub(
          "fedcba9876543210fedcba9876543210fedcba98",
          "0123456789abcdef0123456789abcdef01234567"
        )
        duplicate_hash_path = write(File.join(directory, "duplicate-hash.txt"), duplicate_hash_report)
        assert_failure(*release_manifest_arguments(
          context,
          output: File.join(directory, "duplicate-hash.json"),
          codesign_report_specs: [arm64, "x86_64=#{duplicate_hash_path}"]
        ))
      end
    end

    run("release manifest rejects a tampered asset") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        File.open(context[:assets].values.first, "ab") { |file| file.write("tampered") }
        assert_failure(*verify_manifest_arguments(context, manifest: manifest))
      end
    end

    run("release manifest rejects missing asset mappings and files") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        incomplete = context[:assets].to_a.drop(1).flat_map { |name, path| ["--asset", "#{name}=#{path}"] }
        assert_failure(*verify_manifest_arguments(context, manifest: manifest, asset_arguments: incomplete))

        name, path = context[:assets].to_a.last
        File.unlink(path)
        assert_failure(*verify_manifest_arguments(context, manifest: manifest))
        assert(name.is_a?(String), "synthetic asset setup failed")
      end
    end

    run("release manifest requires the exact verification set") do
      Dir.mktmpdir do |directory|
        context = create_release_context(File.join(directory, "missing"))
        context[:verifications].delete("spctlApp")
        manifest = File.join(directory, "release-manifest.json")
        assert_failure(*release_manifest_arguments(context, output: manifest))

        extra_context = create_release_context(File.join(directory, "extra"))
        extra_context[:verifications]["securityAudit"] = write(File.join(directory, "extra", "security-audit.txt"), "PASS\n")
        assert_failure(*release_manifest_arguments(extra_context, output: File.join(directory, "extra.json")))
      end
    end

    run("release manifest rejects a different candidate identity") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        data = JSON.parse(File.binread(manifest))
        data.fetch("release")["commit"] = "b" * 40
        changed = write(File.join(directory, "changed-identity.json"), JSON.pretty_generate(data) + "\n")
        assert_failure(*verify_manifest_arguments(context, manifest: changed))
      end
    end

    run("release manifest rejects forged verification digests") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        data = JSON.parse(File.binread(manifest))
        record = data.fetch("verifications").first
        record["sha256"] = "0" * 64
        record["size"] = 0
        changed = write(File.join(directory, "changed-verification.json"), JSON.pretty_generate(data) + "\n")
        assert_failure(*verify_manifest_arguments(context, manifest: changed))
      end
    end

    run("release manifest rejects a mismatched notary log") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        data = JSON.parse(File.binread(context.fetch(:notary_log)))
        data["sha256"] = "0" * 64
        write(context.fetch(:notary_log), JSON.pretty_generate(data) + "\n")
        assert_failure(*release_manifest_arguments(context, output: File.join(directory, "mismatch.json")))
      end
    end

    run("release manifest rejects duplicate notary-log keys") do
      Dir.mktmpdir do |directory|
        duplicate_context = create_release_context(File.join(directory, "top-level"))
        source = File.binread(duplicate_context.fetch(:notary_log))
        job_line = source.lines.find { |line| line.include?('"jobId"') }
        duplicate_source = source.sub(job_line, job_line + job_line)
        write(duplicate_context.fetch(:notary_log), duplicate_source)
        assert_failure(*release_manifest_arguments(duplicate_context, output: File.join(directory, "duplicate.json")))

        nested_context = create_release_context(File.join(directory, "nested"))
        nested_source = File.binread(nested_context.fetch(:notary_log)).sub(
          '"issues": []',
          '"issues": [{"metadata":{"key":1,"\u006bey":2}}]'
        )
        write(nested_context.fetch(:notary_log), nested_source)
        assert_failure(*release_manifest_arguments(nested_context, output: File.join(directory, "nested.json")))
      end
    end
  end

  def test_mounted_app
    run("mounted-app verifier rechecks identity, CDHash, runtime, timestamp, entitlements, bundle, and DMG") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        assert_success(
          "verify-mounted-app",
          "--manifest", manifest,
          "--app", context[:app],
          "--dmg", context[:final_dmg],
          "--app-codesign-report", "arm64=#{fixture('codesign-app-accepted.txt')}",
          "--app-codesign-report", "x86_64=#{fixture('codesign-app-x86_64-accepted.txt')}",
          "--app-codesign-verify", context[:verifications].fetch("appCodesign"),
          "--executable", context[:executable],
          "--designated-requirement", context[:designated_requirement],
          "--entitlements-plist", fixture("entitlements-empty.plist")
        )
      end
    end

    run("mounted-app verifier requires both candidate CDHashes to match by architecture") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        common_arguments = [
          "verify-mounted-app", "--manifest", manifest,
          "--app", context[:app], "--dmg", context[:final_dmg],
          "--app-codesign-verify", context[:verifications].fetch("appCodesign"),
          "--executable", context[:executable],
          "--designated-requirement", context[:designated_requirement],
          "--entitlements-plist", fixture("entitlements-empty.plist")
        ]
        assert_failure(
          *common_arguments,
          "--app-codesign-report", "arm64=#{fixture('codesign-app-accepted.txt')}"
        )

        changed_report = File.binread(fixture("codesign-app-x86_64-accepted.txt")).sub(
          "fedcba9876543210fedcba9876543210fedcba98",
          "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
        )
        changed_path = write(File.join(directory, "changed-x86_64.txt"), changed_report)
        assert_failure(
          *common_arguments,
          "--app-codesign-report", "arm64=#{fixture('codesign-app-accepted.txt')}",
          "--app-codesign-report", "x86_64=#{changed_path}"
        )
      end
    end

    run("mounted-app verifier rejects changed bundle bytes") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        File.open(File.join(context[:app], "Contents", "Info.plist"), "ab") { |file| file.write("changed") }
        assert_failure(
          "verify-mounted-app", "--manifest", manifest, "--app", context[:app], "--dmg", context[:final_dmg],
          "--app-codesign-report", "arm64=#{fixture('codesign-app-accepted.txt')}",
          "--app-codesign-report", "x86_64=#{fixture('codesign-app-x86_64-accepted.txt')}",
          "--app-codesign-verify", context[:verifications].fetch("appCodesign"),
          "--executable", context[:executable],
          "--designated-requirement", context[:designated_requirement],
          "--entitlements-plist", fixture("entitlements-empty.plist")
        )
      end
    end

    run("mounted-app verifier rejects extra entitlements") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        assert_failure(
          "verify-mounted-app", "--manifest", manifest, "--app", context[:app], "--dmg", context[:final_dmg],
          "--app-codesign-report", "arm64=#{fixture('codesign-app-accepted.txt')}",
          "--app-codesign-report", "x86_64=#{fixture('codesign-app-x86_64-accepted.txt')}",
          "--app-codesign-verify", context[:verifications].fetch("appCodesign"),
          "--executable", context[:executable],
          "--designated-requirement", context[:designated_requirement],
          "--entitlements-plist", fixture("entitlements-extra.plist")
        )
      end
    end

    run("mounted-app verifier rejects a changed final DMG") do
      Dir.mktmpdir do |directory|
        context = create_release_context(directory)
        manifest = File.join(directory, "release-manifest.json")
        assert_success(*release_manifest_arguments(context, output: manifest))
        changed_dmg = write(File.join(directory, "downloaded.dmg"), "changed-download\n")
        assert_failure(
          "verify-mounted-app", "--manifest", manifest, "--app", context[:app], "--dmg", changed_dmg,
          "--app-codesign-report", "arm64=#{fixture('codesign-app-accepted.txt')}",
          "--app-codesign-report", "x86_64=#{fixture('codesign-app-x86_64-accepted.txt')}",
          "--app-codesign-verify", context[:verifications].fetch("appCodesign"),
          "--executable", context[:executable],
          "--designated-requirement", context[:designated_requirement],
          "--entitlements-plist", fixture("entitlements-empty.plist")
        )
      end
    end
  end

  def test_cli_help
    run("CLI help lists every release policy subcommand") do
      stdout, stderr = assert_success("--help")
      %w[
        verify-json
        sanitize-json
        verify-codesign
        verify-entitlements
        verify-notary
        generate-sbom
        verify-sbom
        generate-bundle-manifest
        generate-release-manifest
        verify-release-manifest
        verify-mounted-app
      ].each { |command| assert(stdout.include?(command), "help omitted a command") }
      assert(stderr.empty?, "help wrote to stderr")
    end
  end

  def execute
    test_codesign
    test_entitlements
    test_strict_json
    test_notary
    test_sbom
    test_release_manifest
    test_mounted_app
    test_cli_help

    if @failures.empty?
      puts "PASS: #{@tests} tests, #{@assertions} assertions"
      return 0
    end

    @failures.each do |name, error_class, message|
      warn "FAIL: #{name} (#{error_class}: #{message})"
    end
    warn "FAIL: #{@failures.length} of #{@tests} tests failed after #{@assertions} assertions"
    1
  end
end

exit ReleasePolicyTestSuite.new.execute
