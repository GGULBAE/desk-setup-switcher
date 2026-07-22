#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"

class ExternalBetaPolicyTestSuite
  SCRIPT = File.expand_path("external_beta_policy.rb", __dir__)
  TEMPLATE_SCRIPT = File.expand_path("external_beta_template_cli.rb", __dir__)
  REPOSITORY = "GGULBAE/desk-setup-switcher"
  TAG = "v0.1.0"
  VERSION = "0.1.0"
  COMMIT = "a" * 40
  BUNDLE_IDENTIFIER = "io.github.ggullbae.DeskSetupSwitcher"
  RUN_ID = 8001
  ARTIFACT_ID = 9001
  ARTIFACT_SHA256 = "b" * 64
  DMG_BYTES = "synthetic final stapled DMG\n"
  DMG_SHA256 = Digest::SHA256.hexdigest(DMG_BYTES)
  PROVENANCE_BYTES = "synthetic Sigstore provenance bundle\n"
  PROFILE_SCHEMA_VERSION = 1
  MANIFEST_CREATED_AT = "2026-07-18T00:00:00Z"
  PREDECESSOR_VERSION = "0.0.9"
  PREDECESSOR_TAG = "v0.0.9"
  PREDECESSOR_BUILD_NUMBER = 1
  PREDECESSOR_COMMIT = "9" * 40
  PREDECESSOR_RUN_ID = 7999
  PREDECESSOR_ARTIFACT_ID = 8999
  PREDECESSOR_ARTIFACT_SHA256 = "7" * 64
  PREDECESSOR_TAG_OBJECT = "8" * 40
  PREDECESSOR_PRE_TAG_EVIDENCE_SHA256 = "6" * 64
  PREDECESSOR_DMG_BYTES = "synthetic predecessor final stapled DMG\n"
  PREDECESSOR_DMG_SHA256 = Digest::SHA256.hexdigest(PREDECESSOR_DMG_BYTES)
  PREDECESSOR_PROVENANCE_BYTES = "synthetic predecessor Sigstore provenance bundle\n"
  PREDECESSOR_MANIFEST_CREATED_AT = "2026-07-17T22:00:00Z"
  PREDECESSOR_BOUNDARY_COLLECTED_AT = "2026-07-17T23:30:00Z"

  class TestFailure < StandardError; end

  def initialize
    @tests = 0
    @assertions = 0
    @failures = []
  end

  def assert(value, message = "assertion failed")
    @assertions += 1
    raise TestFailure, message unless value
  end

  def assert_equal(expected, actual, message = "values differ")
    assert(expected == actual, message)
  end

  def run(name)
    @tests += 1
    yield
    puts "ok #{@tests} - #{name}"
  rescue StandardError => error
    @failures << [name, error.class.name, error.message]
    puts "not ok #{@tests} - #{name}"
  end

  def deep_copy(value)
    JSON.parse(JSON.generate(value), create_additions: false)
  end

  def write_json(path, value)
    File.binwrite(path, JSON.generate(value) + "\n")
    path
  end

  def digest(path)
    Digest::SHA256.file(path).hexdigest
  end

  def release_manifest(build_number:, version: VERSION, tag: TAG, commit: COMMIT,
                       run_id: RUN_ID, dmg_bytes: DMG_BYTES, dmg_sha256: DMG_SHA256,
                       created_at: MANIFEST_CREATED_AT)
    verification_output = {
      "appCodesign" => "valid on disk\nsatisfies its designated requirement\n",
      "dmgCodesign" => "valid on disk\nsatisfies its designated requirement\n",
      "mountedAppCompatibility" => "Verified release app metadata and resources: architectures=arm64,x86_64; minos=arm64:14.0,x86_64:14.0; executable-sha256=#{"3" * 64}\n",
      "signedAppCompatibility" => "Verified release app metadata and resources: architectures=arm64,x86_64; minos=arm64:14.0,x86_64:14.0; executable-sha256=#{"3" * 64}\n",
      "spctlApp" => "accepted\nsource=Notarized Developer ID\n",
      "spctlDMG" => "accepted\nsource=Notarized Developer ID\n",
      "staplerValidate" => "The validate action worked!\n"
    }
    {
      "schemaVersion" => "desk-setup-switcher.release-evidence/v1",
      "generator" => "scripts/release/release_policy.rb",
      "release" => {
        "version" => version,
        "tag" => tag,
        "commit" => commit,
        "namespace" => "https://github.com/#{REPOSITORY}/release-evidence/#{tag}/#{dmg_sha256}",
        "created" => created_at,
        "buildNumber" => build_number.to_s,
        "run" => {
          "id" => run_id,
          "attempt" => 1,
          "url" => "https://github.com/#{REPOSITORY}/actions/runs/#{run_id}"
        }
      },
      "toolchain" => {
        "minimum-system-version" => "14.0",
        "swift" => "synthetic-6.0"
      },
      "application" => {
        "bundleIdentifier" => BUNDLE_IDENTIFIER,
        "teamIdentifier" => "ABCDE12345",
        "authority" => "Developer ID Application: Synthetic Release (ABCDE12345)",
        "cdhashes" => { "arm64" => "1" * 40, "x86_64" => "2" * 40 },
        "executable" => {
          "name" => "DeskSetupSwitcher",
          "sha256" => "3" * 64,
          "size" => 1
        },
        "designatedRequirement" => {
          "normalized" => "designated => identifier \"#{BUNDLE_IDENTIFIER}\" and certificate leaf[subject.OU] = ABCDE12345"
        },
        "effectiveEntitlements" => { "state" => "absent", "keys" => [] },
        "bundleManifest" => {
          "schemaVersion" => "desk-setup-switcher.app-bundle/v1",
          "rootName" => "Desk Setup Switcher.app",
          "entryCount" => 1,
          "canonicalSha256" => "4" * 64
        }
      },
      "lineage" => {
        "preNotaryDmg" => { "sha256" => "5" * 64, "size" => dmg_bytes.bytesize },
        "notary" => {
          "id" => "12345678-1234-4234-8234-123456789abc",
          "status" => "Accepted",
          "archiveFilename" => "Desk-Setup-Switcher-#{version}.dmg",
          "submittedSha256" => "5" * 64,
          "logSha256" => "6" * 64,
          "logSize" => 1
        },
        "finalStapledDmg" => {
          "name" => "Desk-Setup-Switcher-#{version}.dmg",
          "sha256" => dmg_sha256,
          "size" => dmg_bytes.bytesize
        }
      },
      "verifications" => verification_output.keys.sort.map do |name|
        output = verification_output.fetch(name)
        {
          "name" => name,
          "sha256" => Digest::SHA256.hexdigest(output.b),
          "size" => output.bytesize,
          "result" => "pass",
          "output" => output
        }
      end,
      "assets" => [
        {
          "name" => "Desk-Setup-Switcher-#{version}.dmg",
          "sha256" => dmg_sha256,
          "size" => dmg_bytes.bytesize
        }
      ]
    }
  end

  def candidate(manifest_sha256, build_number)
    {
      "repository" => REPOSITORY,
      "tag" => TAG,
      "commit" => COMMIT,
      "version" => VERSION,
      "buildNumber" => build_number,
      "bundleIdentifier" => BUNDLE_IDENTIFIER,
      "profileSchemaVersion" => PROFILE_SCHEMA_VERSION,
      "candidateOriginRunId" => RUN_ID,
      "candidateOriginRunAttempt" => 1,
      "candidateArtifactId" => ARTIFACT_ID,
      "candidateArtifactSHA256" => ARTIFACT_SHA256,
      "finalDMGSHA256" => DMG_SHA256,
      "releaseManifestSHA256" => manifest_sha256
    }
  end

  def retained_inventory_item(state: "protected-beta", build_number: 1,
                              release_manifest_sha256: "9" * 64,
                              final_dmg_sha256: PREDECESSOR_DMG_SHA256)
    {
      "outcome" => "retained",
      "version" => "0.0.9",
      "buildNumber" => build_number,
      "commit" => PREDECESSOR_COMMIT,
      "candidateOriginRunId" => PREDECESSOR_RUN_ID,
      "candidateOriginRunAttempt" => 1,
      "runConclusion" => "success",
      "completedAt" => "2026-07-17T23:00:00Z",
      "distributionState" => state,
      "candidateArtifactId" => PREDECESSOR_ARTIFACT_ID,
      "candidateArtifactSHA256" => PREDECESSOR_ARTIFACT_SHA256,
      "finalDMGSHA256" => final_dmg_sha256,
      "releaseManifestSHA256" => release_manifest_sha256
    }
  end

  def not_retained_inventory_item(build_number: 1, conclusion: "failure", reason: "build-failed")
    {
      "outcome" => "not-retained",
      "version" => "0.0.9",
      "buildNumber" => build_number,
      "commit" => "9" * 40,
      "candidateOriginRunId" => 7998 + build_number,
      "candidateOriginRunAttempt" => 1,
      "runConclusion" => conclusion,
      "completedAt" => "2026-07-17T23:00:00Z",
      "distributionState" => "not-distributed",
      "reason" => reason
    }
  end

  def upgrade_predecessor(kind:, item: nil, provenance_sha256: "d" * 64,
                          boundary_sha256: "e" * 64)
    item ||= retained_inventory_item(state: "development-installed")
    {
      "state" => "recorded",
      "distributionKind" => kind,
      "bundleIdentifier" => BUNDLE_IDENTIFIER,
      "version" => item.fetch("version"),
      "tag" => PREDECESSOR_TAG,
      "buildNumber" => item.fetch("buildNumber"),
      "profileSchemaVersion" => PROFILE_SCHEMA_VERSION,
      "sourceCommit" => item.fetch("commit"),
      "candidateOriginRunId" => item.fetch("candidateOriginRunId"),
      "candidateOriginRunAttempt" => item.fetch("candidateOriginRunAttempt"),
      "candidateArtifactId" => item.fetch("candidateArtifactId"),
      "candidateArtifactSHA256" => item.fetch("candidateArtifactSHA256"),
      "artifactName" => "Desk-Setup-Switcher-#{item.fetch('version')}.dmg",
      "finalDMGSHA256" => item.fetch("finalDMGSHA256"),
      "releaseManifestSHA256" => item.fetch("releaseManifestSHA256"),
      "provenanceBundleName" => "Desk-Setup-Switcher-#{item.fetch('version')}.provenance.sigstore.json",
      "provenanceBundleSHA256" => provenance_sha256,
      "provenanceSubjectSHA256" => item.fetch("finalDMGSHA256"),
      "releaseBoundaryEvidenceSHA256" => boundary_sha256
    }
  end

  def acquisition(index, offset: 1)
    {
      "channel" => "protected-workflow-browser",
      "browserDownloaded" => true,
      "normalArchiveExtraction" => true,
      "quarantinePresent" => true,
      "quarantineManufactured" => false,
      "quarantineRemoved" => false,
      "quarantineEvidenceSHA256" => ((index + offset) % 10).to_s * 64,
      "checksumPass" => true,
      "provenancePass" => true,
      "gatekeeperPass" => true,
      "openAnywayUsed" => false
    }
  end

  def report(code:, index:, subject:, upgrade:)
    start_hour = 2 + (index * 2)
    {
      "schemaVersion" => "desk-setup-switcher.external-beta/v2",
      "report" => {
        "reportCode" => code,
        "startedAt" => format("2026-07-18T%02d:00:00Z", start_hour),
        "completedAt" => format("2026-07-18T%02d:00:00Z", start_hour + 1)
      },
      "subject" => deep_copy(subject),
      "environment" => {
        "architecture" => "arm64",
        "macOSVersion" => index.zero? ? "14.6.1" : "15.#{index - 1}",
        "hardwareClass" => "apple-silicon",
        "cleanBasis" => index.zero? ? "clean-mac" : "clean-local-account",
        "coverageRole" => index.zero? ? "sonoma-full-lifecycle" : "additional-apple-silicon"
      },
      "independence" => {
        "externalTester" => true,
        "notReleaseOperator" => true,
        "notReleaseApprover" => true,
        "noRepositoryWriteAccess" => true,
        "noReleaseSecretAccess" => true
      },
      "acquisition" => acquisition(index),
      "lifecycle" => {
        "firstLaunchPass" => true,
        "loginItemDefaultOffPass" => true,
        "threeStepFlowPass" => true,
        "stoppedBeforeApply" => true,
        "schema0MigrationPass" => true,
        "backupRecoveryPass" => true,
        "importExportPass" => true,
        "diagnosticsPass" => true,
        "uninstallPass" => true,
        "localDataRemovalPass" => true,
        "hardwareMutationPerformed" => false,
        "upgrade" => deep_copy(upgrade)
      },
      "issues" => {
        "unresolvedP0" => 0,
        "unresolvedP1" => 0,
        "allFailuresTracked" => true,
        "blockerEvidenceSHA256" => (index + 4).to_s * 64
      },
      "attestation" => {
        "candidateIdentityConfirmed" => true,
        "privacyReviewed" => true,
        "reportComplete" => true,
        "testerAttested" => true,
        "noHardwareMutationClaim" => true
      }
    }
  end

  def build_fixture(directory, build_number: 2, predecessor: :protected)
    paths = {
      manifest: File.join(directory, "release-manifest.json"),
      dmg: File.join(directory, "Desk-Setup-Switcher-#{VERSION}.dmg"),
      provenance: File.join(directory, "Desk-Setup-Switcher-#{VERSION}.provenance.sigstore.json"),
      predecessor_manifest: File.join(directory, "predecessor-release-manifest.json"),
      predecessor_dmg: File.join(directory, "Desk-Setup-Switcher-#{PREDECESSOR_VERSION}.dmg"),
      predecessor_provenance: File.join(
        directory,
        "Desk-Setup-Switcher-#{PREDECESSOR_VERSION}.provenance.sigstore.json"
      ),
      predecessor_boundary: File.join(directory, "remote-controls-final-pre-tag.json"),
      inventory: File.join(directory, "candidate-inventory.json"),
      lineage: File.join(directory, "predecessor-lineage.json"),
      set: File.join(directory, "external-beta-set.json"),
      reports: %w[01 02 03].map { |code| File.join(directory, "external-beta-#{code}.json") }
    }
    File.binwrite(paths.fetch(:dmg), DMG_BYTES)
    File.binwrite(paths.fetch(:provenance), PROVENANCE_BYTES)
    File.binwrite(paths.fetch(:predecessor_dmg), PREDECESSOR_DMG_BYTES)
    File.binwrite(paths.fetch(:predecessor_provenance), PREDECESSOR_PROVENANCE_BYTES)
    manifest = release_manifest(build_number: build_number)
    write_json(paths.fetch(:manifest), manifest)
    predecessor_manifest = release_manifest(
      build_number: PREDECESSOR_BUILD_NUMBER,
      version: PREDECESSOR_VERSION,
      tag: PREDECESSOR_TAG,
      commit: PREDECESSOR_COMMIT,
      run_id: PREDECESSOR_RUN_ID,
      dmg_bytes: PREDECESSOR_DMG_BYTES,
      dmg_sha256: PREDECESSOR_DMG_SHA256,
      created_at: PREDECESSOR_MANIFEST_CREATED_AT
    )
    write_json(paths.fetch(:predecessor_manifest), predecessor_manifest)
    boundary = {
      "schemaVersion" => "desk-setup-switcher.remote-release-controls-evidence/v3",
      "phase" => "final-pre-tag",
      "collectedAt" => PREDECESSOR_BOUNDARY_COLLECTED_AT,
      "finalPreTagEvidenceSHA256" => nil,
      "predecessorPreTagEvidenceSHA256" => PREDECESSOR_PRE_TAG_EVIDENCE_SHA256,
      "repository" => {},
      "authenticatedViewer" => {},
      "anchorReads" => {},
      "candidateWorkflow" => {},
      "ciWorkflow" => {},
      "legacyWorkflow" => {},
      "publicationWorkflow" => {},
      "workflowInventory" => {},
      "rulesets" => {},
      "environments" => {},
      "repositoryConfiguration" => {},
      "manualEvidence" => {},
      "security" => {},
      "actions" => {},
      "labels" => {},
      "ci" => {},
      "releaseBoundary" => {
        "vRefs" => {
          "complete" => true,
          "items" => [
            {
              "ref" => "refs/tags/#{PREDECESSOR_TAG}",
              "objectType" => "tag",
              "objectSha" => PREDECESSOR_TAG_OBJECT,
              "commitSha" => PREDECESSOR_COMMIT
            }
          ]
        },
        "releases" => { "complete" => true, "items" => [] }
      }
    }
    write_json(paths.fetch(:predecessor_boundary), boundary)
    candidate_value = candidate(digest(paths.fetch(:manifest)), build_number)

    inventory_items = []
    upgrade = nil
    report_upgrade = nil
    case predecessor
    when :none
      report_upgrade = {
        "state" => "not-applicable",
        "reason" => "first-public-beta-no-installable-predecessor"
      }
    when :failed
      inventory_items << not_retained_inventory_item
      report_upgrade = {
        "state" => "not-applicable",
        "reason" => "first-public-beta-no-installable-predecessor"
      }
    when :published
      item = retained_inventory_item(
        state: "published",
        release_manifest_sha256: digest(paths.fetch(:predecessor_manifest))
      )
      inventory_items << item
      upgrade = upgrade_predecessor(
        kind: "public-release",
        item: item,
        provenance_sha256: digest(paths.fetch(:predecessor_provenance)),
        boundary_sha256: digest(paths.fetch(:predecessor_boundary))
      )
    when :protected
      item = retained_inventory_item(
        state: "protected-beta",
        release_manifest_sha256: digest(paths.fetch(:predecessor_manifest))
      )
      inventory_items << item
      upgrade = upgrade_predecessor(
        kind: "protected-beta",
        item: item,
        provenance_sha256: digest(paths.fetch(:predecessor_provenance)),
        boundary_sha256: digest(paths.fetch(:predecessor_boundary))
      )
    when :development
      item = retained_inventory_item(
        state: "development-installed",
        release_manifest_sha256: digest(paths.fetch(:predecessor_manifest))
      )
      inventory_items << item
      upgrade = upgrade_predecessor(
        kind: "development-evidence",
        item: item,
        provenance_sha256: digest(paths.fetch(:predecessor_provenance)),
        boundary_sha256: digest(paths.fetch(:predecessor_boundary))
      )
    else
      raise "unknown predecessor fixture"
    end
    if upgrade&.fetch("state") == "recorded"
      report_upgrade = {
        "state" => "passed",
        "predecessorVersion" => upgrade.fetch("version"),
        "predecessorBuildNumber" => upgrade.fetch("buildNumber"),
        "predecessorFinalDMGSHA256" => upgrade.fetch("finalDMGSHA256"),
        "predecessorReleaseManifestSHA256" => upgrade.fetch("releaseManifestSHA256"),
        "predecessorProvenanceBundleSHA256" => upgrade.fetch("provenanceBundleSHA256"),
        "predecessorAcquisition" => acquisition(0, offset: 7),
        "profilesPreserved" => true,
        "settingsPreserved" => true,
        "selectionPreserved" => true,
        "backupsPreserved" => true,
        "loginItemConsentPreserved" => true
      }
    end

    inventory = {
      "schemaVersion" => "desk-setup-switcher.candidate-inventory/v1",
      "subject" => {
        "repository" => REPOSITORY,
        "workflowPath" => ".github/workflows/signed-release-candidate.yml",
        "operation" => "build-candidate",
        "currentCandidateRunId" => RUN_ID,
        "currentCandidateBuildNumber" => build_number
      },
      "collection" => {
        "collectedAt" => "2026-07-18T00:30:00Z",
        "reviewedAt" => "2026-07-18T01:00:00Z",
        "reviewMode" => "protected-complete-history-review",
        "reviewerRole" => "release-approver",
        "allPagesReviewed" => true,
        "sourceEvidenceSHA256" => "7" * 64
      },
      "items" => inventory_items
    }
    write_json(paths.fetch(:inventory), inventory)
    inventory_sha256 = digest(paths.fetch(:inventory))
    if upgrade.nil?
      upgrade = {
        "state" => "none",
        "reason" => "first-public-beta-no-installable-predecessor",
        "candidateInventorySHA256" => inventory_sha256,
        "cleanInstallEvidenceSHA256" => "b" * 64,
        "schema0MigrationEvidenceSHA256" => "c" * 64
      }
    end
    lineage = {
      "schemaVersion" => "desk-setup-switcher.predecessor-lineage/v3",
      "candidate" => deep_copy(candidate_value),
      "candidateInventorySHA256" => inventory_sha256,
      "upgradePredecessor" => upgrade
    }
    write_json(paths.fetch(:lineage), lineage)

    report_subject = candidate_value.merge(
      "finalDMGName" => "Desk-Setup-Switcher-#{VERSION}.dmg",
      "provenanceBundleName" => "Desk-Setup-Switcher-#{VERSION}.provenance.sigstore.json",
      "provenanceBundleSHA256" => digest(paths.fetch(:provenance)),
      "provenanceSubjectSHA256" => DMG_SHA256,
      "predecessorLineageSHA256" => digest(paths.fetch(:lineage))
    )
    reports = %w[beta-01 beta-02 beta-03].each_with_index.map do |code, index|
      report(code: code, index: index, subject: report_subject, upgrade: report_upgrade)
    end
    reports.each_with_index { |value, index| write_json(paths.fetch(:reports).fetch(index), value) }
    report_digests = paths.fetch(:reports).map { |path| digest(path) }

    set = {
      "schemaVersion" => "desk-setup-switcher.external-beta-set/v2",
      "subject" => deep_copy(report_subject),
      "reports" => %w[beta-01 beta-02 beta-03].each_with_index.map do |code, index|
        { "reportCode" => code, "reportSHA256" => report_digests.fetch(index) }
      end,
      "independence" => {
        "reviewMode" => "protected-release-review",
        "reviewerRole" => "release-approver",
        "reviewedAt" => "2026-07-18T08:00:00Z",
        "protectedReviewEvidenceSHA256" => "d" * 64,
        "privateRosterBundleSHA256" => "e" * 64,
        "bindings" => %w[beta-01 beta-02 beta-03].each_with_index.map do |code, index|
          {
            "reportCode" => code,
            "reportSHA256" => report_digests.fetch(index),
            "privateRosterEntryCommitmentSHA256" => (index + 7).to_s * 64
          }
        end,
        "assertions" => {
          "threeDistinctNaturalPersons" => true,
          "allExternalToReleaseTeam" => true,
          "noneIsReleaseOperator" => true,
          "noneIsReleaseApprover" => true,
          "noneHasPushReleaseEnvironmentOrSecretAccess" => true
        }
      },
      "coverage" => {
        "acceptedReportCount" => 3,
        "sonomaGateReportCode" => "beta-01",
        "allAppleSilicon" => true,
        "allSupportedOS" => true,
        "allMandatoryLifecyclePassed" => true
      },
      "createdAt" => "2026-07-18T09:00:00Z"
    }
    write_json(paths.fetch(:set), set)
    {
      paths: paths,
      manifest: manifest,
      predecessor_manifest: predecessor_manifest,
      boundary: boundary,
      inventory: inventory,
      lineage: lineage,
      reports: reports,
      set: set
    }
  end

  def arguments(fixture, reports: fixture.dig(:paths, :reports), overrides: {})
    values = {
      repository: REPOSITORY,
      tag: TAG,
      commit: COMMIT,
      run_id: RUN_ID.to_s,
      artifact_id: ARTIFACT_ID.to_s,
      artifact_sha256: ARTIFACT_SHA256,
      dmg_sha256: DMG_SHA256,
      predecessor_tag_object: PREDECESSOR_TAG_OBJECT,
      predecessor_pre_tag_sha256: PREDECESSOR_PRE_TAG_EVIDENCE_SHA256,
      profile_schema_version: PROFILE_SCHEMA_VERSION.to_s
    }.merge(overrides)
    [
      "verify-set",
      "--release-manifest", fixture.dig(:paths, :manifest),
      "--final-dmg", fixture.dig(:paths, :dmg),
      "--provenance-bundle", fixture.dig(:paths, :provenance),
      "--predecessor-release-manifest", fixture.dig(:paths, :predecessor_manifest),
      "--predecessor-provenance-bundle", fixture.dig(:paths, :predecessor_provenance),
      "--predecessor-dmg", fixture.dig(:paths, :predecessor_dmg),
      "--predecessor-release-boundary", fixture.dig(:paths, :predecessor_boundary),
      "--predecessor-tag-object", values.fetch(:predecessor_tag_object),
      "--predecessor-pre-tag-evidence-sha256", values.fetch(:predecessor_pre_tag_sha256),
      "--candidate-inventory", fixture.dig(:paths, :inventory),
      "--predecessor-lineage", fixture.dig(:paths, :lineage),
      "--set-manifest", fixture.dig(:paths, :set),
      *reports.flat_map { |path| ["--report", path] },
      "--repository", values.fetch(:repository),
      "--tag", values.fetch(:tag),
      "--commit", values.fetch(:commit),
      "--candidate-run-id", values.fetch(:run_id),
      "--candidate-artifact-id", values.fetch(:artifact_id),
      "--candidate-artifact-sha256", values.fetch(:artifact_sha256),
      "--final-dmg-sha256", values.fetch(:dmg_sha256),
      "--profile-schema-version", values.fetch(:profile_schema_version)
    ]
  end

  def rebind_candidate_evidence!(fixture)
    write_json(fixture.dig(:paths, :manifest), fixture.fetch(:manifest))
    manifest_sha256 = digest(fixture.dig(:paths, :manifest))
    fixture.dig(:lineage, "candidate")["releaseManifestSHA256"] = manifest_sha256
    write_json(fixture.dig(:paths, :lineage), fixture.fetch(:lineage))
    lineage_sha256 = digest(fixture.dig(:paths, :lineage))

    fixture.fetch(:reports).each_with_index do |report_value, index|
      report_value.fetch("subject")["releaseManifestSHA256"] = manifest_sha256
      report_value.fetch("subject")["predecessorLineageSHA256"] = lineage_sha256
      write_json(fixture.dig(:paths, :reports, index), report_value)
    end
    report_digests = fixture.dig(:paths, :reports).map { |path| digest(path) }
    fixture.fetch(:set).fetch("subject")["releaseManifestSHA256"] = manifest_sha256
    fixture.fetch(:set).fetch("subject")["predecessorLineageSHA256"] = lineage_sha256
    report_digests.each_with_index do |report_sha256, index|
      fixture.dig(:set, "reports", index)["reportSHA256"] = report_sha256
      fixture.dig(:set, "independence", "bindings", index)["reportSHA256"] = report_sha256
    end
    write_json(fixture.dig(:paths, :set), fixture.fetch(:set))
  end

  def cli(*arguments)
    Open3.capture3(RbConfig.ruby, SCRIPT, *arguments)
  end

  def template_cli(*arguments)
    Open3.capture3(RbConfig.ruby, TEMPLATE_SCRIPT, *arguments)
  end

  def template_arguments(kind, report_code: nil, coverage_role: nil, sonoma_report_code: nil)
    arguments = ["--kind", kind]
    arguments += ["--report-code", report_code] if report_code
    arguments += ["--coverage-role", coverage_role] if coverage_role
    arguments += ["--sonoma-report-code", sonoma_report_code] if sonoma_report_code
    arguments
  end

  def template_output(kind, **options)
    stdout, stderr, status = template_cli(*template_arguments(kind, **options))
    assert(status.success?, "template generation failed: #{stderr.inspect}")
    assert(stderr.empty?, "template generation wrote stderr")
    value = JSON.parse(stdout, create_additions: false)
    assert_equal(JSON.pretty_generate(value) + "\n", stdout, "template output is not canonical pretty JSON")
    [value, stdout]
  end

  def json_type(value)
    return :boolean if value == true || value == false

    value.class.name
  end

  def json_shape(value)
    case value
    when Hash
      value.transform_values { |item| json_shape(item) }
    when Array
      value.map { |item| json_shape(item) }
    else
      json_type(value)
    end
  end

  def fill_template(template, replacement)
    case template
    when Hash
      assert(replacement.is_a?(Hash), "template replacement is not an object")
      assert_equal(template.keys.sort, replacement.keys.sort, "template object keys differ")
      template.to_h { |key, value| [key, fill_template(value, replacement.fetch(key))] }
    when Array
      assert(replacement.is_a?(Array), "template replacement is not an array")
      assert_equal(template.length, replacement.length, "template array length differs")
      template.each_index.map { |index| fill_template(template.fetch(index), replacement.fetch(index)) }
    else
      assert_equal(json_type(template), json_type(replacement), "template leaf JSON type differs")
      replacement
    end
  end

  def json_strings(value)
    case value
    when Hash
      value.keys.flat_map { |key| [key] + json_strings(value.fetch(key)) }
    when Array
      value.flat_map { |item| json_strings(item) }
    when String
      [value]
    else
      []
    end
  end

  def assert_success(*arguments, build_number: 2)
    stdout, stderr, status = cli(*arguments)
    assert(status.success?, "expected success: #{stderr.inspect}")
    assert_equal("OK external beta set reports=3 sonoma=beta-01 build=#{build_number}\n", stdout)
    assert(stderr.empty?, "success wrote stderr")
  end

  def assert_failure(*arguments, forbidden: [], expected_error: nil)
    stdout, stderr, status = cli(*arguments)
    assert(!status.success?, "expected failure")
    assert_equal(1, status.exitstatus)
    assert(stdout.empty?, "failure wrote stdout")
    if expected_error
      assert_equal("External beta policy error: #{expected_error}\n", stderr)
    else
      assert(
        stderr.match?(/\AExternal beta policy error: [A-Za-z0-9 .:-]+\n\z/),
        "failure output is unstable: #{stderr.inspect}"
      )
    end
    forbidden.each { |text| assert(!stderr.include?(text), "failure leaked sensitive input") }
  end

  def with_fixture(build_number: 2, predecessor: :protected)
    Dir.mktmpdir do |directory|
      yield build_fixture(directory, build_number: build_number, predecessor: predecessor), directory
    end
  end

  def report_mutation(name, index: 1, build_number: 2, predecessor: :protected)
    run(name) do
      with_fixture(build_number: build_number, predecessor: predecessor) do |fixture|
        yield fixture.fetch(:reports).fetch(index)
        rewrite_reports_and_set!(fixture)
        assert_failure(*arguments(fixture))
      end
    end
  end

  def set_mutation(name)
    run(name) do
      with_fixture do |fixture|
        yield fixture.fetch(:set)
        write_json(fixture.dig(:paths, :set), fixture.fetch(:set))
        assert_failure(*arguments(fixture))
      end
    end
  end

  def lineage_mutation(name, build_number: 2, predecessor: :protected)
    run(name) do
      with_fixture(build_number: build_number, predecessor: predecessor) do |fixture|
        yield fixture.fetch(:lineage)
        rewrite_lineage_and_downstream!(fixture)
        assert_failure(*arguments(fixture))
      end
    end
  end

  def inventory_mutation(name, build_number: 2, predecessor: :protected)
    run(name) do
      with_fixture(build_number: build_number, predecessor: predecessor) do |fixture|
        yield fixture.fetch(:inventory)
        rewrite_inventory_and_lineage!(fixture)
        assert_failure(*arguments(fixture))
      end
    end
  end

  def rewrite_reports_and_set!(fixture)
    fixture.fetch(:reports).each_with_index do |report_value, index|
      write_json(fixture.dig(:paths, :reports, index), report_value)
    end
    report_digests = fixture.dig(:paths, :reports).map { |path| digest(path) }
    report_digests.each_with_index do |report_sha256, index|
      fixture.dig(:set, "reports", index)["reportSHA256"] = report_sha256
      fixture.dig(:set, "independence", "bindings", index)["reportSHA256"] = report_sha256
    end
    write_json(fixture.dig(:paths, :set), fixture.fetch(:set))
  end

  def rewrite_lineage_and_downstream!(fixture)
    write_json(fixture.dig(:paths, :lineage), fixture.fetch(:lineage))
    lineage_sha256 = digest(fixture.dig(:paths, :lineage))
    fixture.fetch(:reports).each do |report_value|
      report_value.fetch("subject")["predecessorLineageSHA256"] = lineage_sha256
    end
    fixture.fetch(:set).fetch("subject")["predecessorLineageSHA256"] = lineage_sha256
    rewrite_reports_and_set!(fixture)
  end

  def rewrite_inventory_and_lineage!(fixture)
    write_json(fixture.dig(:paths, :inventory), fixture.fetch(:inventory))
    inventory_sha256 = digest(fixture.dig(:paths, :inventory))
    fixture.fetch(:lineage)["candidateInventorySHA256"] = inventory_sha256
    if fixture.dig(:lineage, "upgradePredecessor", "state") == "none"
      fixture.dig(:lineage, "upgradePredecessor")["candidateInventorySHA256"] = inventory_sha256
    end
    rewrite_lineage_and_downstream!(fixture)
  end

  def test_rejected_template_generation
    run("prints every closed template variant with the production schema shape") do
      Dir.mktmpdir do |directory|
        fixture = build_fixture(directory)
        cases = [
          ["candidate-inventory-retained", {}, fixture.fetch(:inventory)],
          ["predecessor-lineage-recorded", {}, fixture.fetch(:lineage)],
          [
            "external-beta-report-recorded",
            { report_code: "beta-02", coverage_role: "additional-apple-silicon" },
            fixture.fetch(:reports).fetch(1)
          ],
          ["external-beta-set", { sonoma_report_code: "beta-01" }, fixture.fetch(:set)]
        ]
        cases.each do |kind, options, expected|
          template, = template_output(kind, **options)
          assert_equal(json_shape(expected), json_shape(template), "#{kind} schema shape differs")
        end
      end
    end

    run("prints deterministic private-data-free rejected placeholders") do
      cases = [
        ["candidate-inventory-retained", {}],
        ["predecessor-lineage-recorded", {}],
        ["external-beta-report-recorded", { report_code: "beta-03", coverage_role: "additional-apple-silicon" }],
        ["external-beta-set", { sonoma_report_code: "beta-01" }]
      ]
      cases.each do |kind, options|
        value, first = template_output(kind, **options)
        _, second = template_output(kind, **options)
        assert_equal(first, second, "#{kind} template is not deterministic")
        assert(first.valid_encoding?, "#{kind} template is not valid UTF-8")
        assert(first.bytesize <= 262_144, "#{kind} template exceeds the evidence size bound")
        strings = json_strings(value)
        assert(
          strings.any? { |item| item.start_with?("<REJECTED_TEMPLATE:REPLACE_REQUIRED:") },
          "#{kind} has no explicit rejected placeholder"
        )
        assert(
          strings.none? { |item| item.match?(/(?:\/Users\/|\/home\/|ssid|@[A-Za-z0-9])/i) },
          "#{kind} contains private-data-shaped text"
        )
        assert(strings.none? { |item| item.match?(/\A(?:[0-9a-f]{40}|[0-9a-f]{64})\z/) }, "#{kind} contains a plausible identity digest")
      end

      Dir.mktmpdir do |working_directory|
        environment = {
          "HOME" => "/Users/SENSITIVE_TEMPLATE_HOME",
          "DESK_SETUP_SSID" => "SENSITIVE_TEMPLATE_SSID",
          "DESK_SETUP_ACCOUNT" => "SENSITIVE_TEMPLATE_ACCOUNT"
        }
        stdout, stderr, status = Open3.capture3(
          environment,
          RbConfig.ruby,
          TEMPLATE_SCRIPT,
          *template_arguments("candidate-inventory-retained"),
          chdir: working_directory
        )
        assert(status.success?, "environment-isolation template failed")
        assert(stderr.empty?, "environment-isolation template wrote stderr")
        _, expected = template_output("candidate-inventory-retained")
        assert_equal(expected, stdout, "template output depends on host environment")
        assert_equal([], Dir.children(working_directory), "template generator wrote a file")
        assert(!stdout.include?("SENSITIVE_TEMPLATE"), "template output leaked the host environment")
      end
    end

    run("rejects every generated template before it can close the beta gate") do
      cases = [
        ["candidate-inventory-retained", {}, :protected, :inventory, "candidate inventory"],
        ["predecessor-lineage-recorded", {}, :protected, :lineage, "predecessor lineage"],
        [
          "external-beta-report-recorded",
          { report_code: "beta-02", coverage_role: "additional-apple-silicon" },
          :protected,
          [:reports, 1],
          "external beta report"
        ],
        ["external-beta-set", { sonoma_report_code: "beta-01" }, :protected, :set, "external beta set"]
      ]
      cases.each do |kind, options, predecessor, target, label|
        Dir.mktmpdir do |directory|
          fixture = build_fixture(directory, predecessor: predecessor)
          _, bytes = template_output(kind, **options)
          path = if target.is_a?(Array)
                   fixture.dig(:paths, target.fetch(0), target.fetch(1))
                 else
                   fixture.dig(:paths, target)
                 end
          File.binwrite(path, bytes)
          stdout, stderr, status = cli(*arguments(fixture))
          assert(!status.success?, "#{kind} unexpectedly passed verification")
          assert(stdout.empty?, "#{kind} rejection wrote stdout")
          assert_equal(
            "External beta policy error: #{label} contains rejected template placeholders\n",
            stderr,
            "#{kind} rejection reason differs"
          )
        end
      end
    end

    run("completes generated fixed-upgrade shapes with synthetic leaves and verifies the set") do
      with_fixture do |fixture|
        inventory, = template_output("candidate-inventory-retained")
        lineage, = template_output("predecessor-lineage-recorded")
        reports = [
          template_output(
            "external-beta-report-recorded",
            report_code: "beta-01",
            coverage_role: "sonoma-full-lifecycle"
          ).first,
          template_output(
            "external-beta-report-recorded",
            report_code: "beta-02",
            coverage_role: "additional-apple-silicon"
          ).first,
          template_output(
            "external-beta-report-recorded",
            report_code: "beta-03",
            coverage_role: "additional-apple-silicon"
          ).first
        ]
        set, = template_output("external-beta-set", sonoma_report_code: "beta-01")
        write_json(
          fixture.dig(:paths, :inventory),
          fill_template(inventory, fixture.fetch(:inventory))
        )
        write_json(
          fixture.dig(:paths, :lineage),
          fill_template(lineage, fixture.fetch(:lineage))
        )
        reports.each_with_index do |template, index|
          write_json(
            fixture.dig(:paths, :reports, index),
            fill_template(template, fixture.fetch(:reports).fetch(index))
          )
        end
        write_json(fixture.dig(:paths, :set), fill_template(set, fixture.fetch(:set)))
        assert_success(*arguments(fixture))
      end
    end

    run("fails closed for missing invalid duplicate and cross-kind template options") do
      cases = [
        [[], "External beta template error: template kind is missing\n"],
        [template_arguments("SENSITIVE_KIND"), "External beta template error: template kind is invalid\n"],
        [template_arguments("external-beta-report-recorded"), "External beta template error: report template options are missing\n"],
        [
          template_arguments(
            "external-beta-report-recorded",
            report_code: "SENSITIVE_CODE",
            coverage_role: "sonoma-full-lifecycle"
          ),
          "External beta template error: template report code is invalid\n"
        ],
        [
          template_arguments(
            "external-beta-report-recorded",
            report_code: "beta-01",
            coverage_role: "SENSITIVE_ROLE"
          ),
          "External beta template error: template coverage role is invalid\n"
        ],
        [template_arguments("external-beta-set"), "External beta template error: set template options are missing\n"],
        [
          template_arguments("external-beta-set", sonoma_report_code: "SENSITIVE_CODE"),
          "External beta template error: template Sonoma report code is invalid\n"
        ],
        [
          template_arguments("candidate-inventory-retained", report_code: "beta-01"),
          "External beta template error: template options differ for this kind\n"
        ],
        [
          ["--kind", "candidate-inventory-retained", "--kind", "SENSITIVE_KIND"],
          "External beta template error: template option is repeated\n"
        ],
        [
          ["--kind", "candidate-inventory-retained", "SENSITIVE_ARGUMENT"],
          "External beta template error: unexpected arguments\n"
        ],
        [
          ["--kind", "candidate-inventory-retained", "--output", "SENSITIVE_PATH"],
          "External beta template error: invalid command line.\n"
        ]
      ]
      cases.each do |arguments_value, expected_stderr|
        stdout, stderr, status = template_cli(*arguments_value)
        assert(!status.success?, "invalid template command unexpectedly passed")
        assert_equal(1, status.exitstatus)
        assert(stdout.empty?, "invalid template command wrote stdout")
        assert_equal(expected_stderr, stderr)
        assert(!stderr.include?("SENSITIVE"), "invalid template command leaked an input value")
      end
    end
  end

  def test_candidate_binding
    run("rejects a valid manifest namespace for a different repository") do
      with_fixture do |fixture|
        fixture.fetch(:manifest).fetch("release")["namespace"] =
          "https://github.com/other/repository/release-evidence/#{TAG}/#{DMG_SHA256}"
        rebind_candidate_evidence!(fixture)
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects a valid workflow URL for a different repository") do
      with_fixture do |fixture|
        fixture.fetch(:manifest).dig("release", "run")["url"] =
          "https://github.com/other/repository/actions/runs/#{RUN_ID}"
        rebind_candidate_evidence!(fixture)
        assert_failure(*arguments(fixture))
      end
    end

    {
      "tag" => { tag: "v0.1.1" },
      "commit" => { commit: "f" * 40 },
      "candidate run" => { run_id: "8002" },
      "candidate artifact" => { artifact_id: "9002" },
      "candidate artifact digest" => { artifact_sha256: "f" * 64 },
      "final DMG digest" => { dmg_sha256: "f" * 64 },
      "profile schema" => { profile_schema_version: "2" }
    }.each do |name, overrides|
      run("rejects a mismatched #{name}") do
        with_fixture do |fixture|
          assert_failure(*arguments(fixture, overrides: overrides))
        end
      end
    end

    %w[0 01 1.0].each do |value|
      run("rejects noncanonical build number #{value.inspect}") do
        with_fixture do |fixture|
          fixture.fetch(:manifest).fetch("release")["buildNumber"] = value
          write_json(fixture.dig(:paths, :manifest), fixture.fetch(:manifest))
          assert_failure(*arguments(fixture))
        end
      end
    end

    %w[0 08001 8.001].each do |value|
      run("rejects noncanonical CLI run ID #{value.inspect}") do
        with_fixture do |fixture|
          assert_failure(*arguments(fixture, overrides: { run_id: value }))
        end
      end
    end
  end

  def test_lineage
    lineage_mutation("rejects the stale v1 lineage schema") do |lineage|
      lineage["schemaVersion"] = "desk-setup-switcher.predecessor-lineage/v1"
    end
    lineage_mutation("rejects unknown lineage keys") { |lineage| lineage["extra"] = true }
    lineage_mutation("rejects a lineage candidate mismatch") do |lineage|
      lineage.fetch("candidate")["commit"] = "f" * 40
    end
    lineage_mutation("rejects a floating-point candidate origin attempt") do |lineage|
      lineage.fetch("candidate")["candidateOriginRunAttempt"] = 1.0
    end
    lineage_mutation("rejects a lineage digest for different inventory bytes") do |lineage|
      lineage["candidateInventorySHA256"] = "f" * 64
    end

    inventory_mutation("rejects the wrong inventory schema") do |inventory|
      inventory["schemaVersion"] = "desk-setup-switcher.candidate-inventory/v0"
    end
    inventory_mutation("rejects unknown inventory keys") { |inventory| inventory["extra"] = true }
    inventory_mutation("rejects an inventory for another candidate") do |inventory|
      inventory.fetch("subject")["currentCandidateRunId"] = RUN_ID + 1
    end
    inventory_mutation("rejects inventory collection before manifest creation") do |inventory|
      inventory.fetch("collection")["collectedAt"] = "2026-07-17T23:59:59Z"
    end
    inventory_mutation("rejects inventory review before collection") do |inventory|
      inventory.fetch("collection")["reviewedAt"] = "2026-07-18T00:29:59Z"
    end
    inventory_mutation("rejects an incomplete page review") do |inventory|
      inventory.fetch("collection")["allPagesReviewed"] = false
    end
    inventory_mutation("rejects the wrong inventory reviewer role") do |inventory|
      inventory.fetch("collection")["reviewerRole"] = "release-operator"
    end
    inventory_mutation(
      "rejects a retained item completed with the current candidate",
      build_number: 2,
      predecessor: :published
    ) do |inventory|
      inventory.fetch("items").fetch(0)["completedAt"] = MANIFEST_CREATED_AT
    end
    inventory_mutation(
      "rejects a later non-retained item as historical",
      build_number: 2,
      predecessor: :failed
    ) do |inventory|
      inventory.fetch("items").fetch(0)["completedAt"] = "2026-07-18T00:15:00Z"
    end
    inventory_mutation(
      "rejects an item completed after collection",
      build_number: 2,
      predecessor: :failed
    ) do |inventory|
      inventory.fetch("items").fetch(0)["completedAt"] = "2026-07-18T00:31:00Z"
    end
    inventory_mutation(
      "rejects unsorted historical builds",
      build_number: 3,
      predecessor: :published
    ) do |inventory|
      inventory.fetch("items") << not_retained_inventory_item(build_number: 2)
      inventory.fetch("items").reverse!
    end
    inventory_mutation(
      "rejects duplicate historical builds",
      build_number: 3,
      predecessor: :published
    ) do |inventory|
      duplicate = not_retained_inventory_item(build_number: 1)
      duplicate["candidateOriginRunId"] = 7997
      inventory.fetch("items") << duplicate
    end
    inventory_mutation(
      "rejects retained identity reuse within history",
      build_number: 3,
      predecessor: :published
    ) do |inventory|
      retained = retained_inventory_item(state: "not-distributed", build_number: 2)
      retained["candidateArtifactSHA256"] =
        inventory.fetch("items").fetch(0).fetch("candidateArtifactSHA256")
      inventory.fetch("items") << retained
    end
    inventory_mutation("rejects reuse of the current build", build_number: 2, predecessor: :published) do |inventory|
      inventory.fetch("items").fetch(0)["buildNumber"] = 2
    end
    inventory_mutation("rejects a string inventory build", build_number: 2, predecessor: :published) do |inventory|
      inventory.fetch("items").fetch(0)["buildNumber"] = "1"
    end
    inventory_mutation("rejects a floating-point inventory origin attempt", build_number: 2, predecessor: :published) do |inventory|
      inventory.fetch("items").fetch(0)["candidateOriginRunAttempt"] = 1.0
    end
    inventory_mutation("rejects a retained candidate with a failed run", build_number: 2, predecessor: :published) do |inventory|
      inventory.fetch("items").fetch(0)["runConclusion"] = "failure"
    end
    inventory_mutation("rejects artifact fields on a non-retained candidate", build_number: 2, predecessor: :failed) do |inventory|
      inventory.fetch("items").fetch(0)["candidateArtifactId"] = 8999
    end
    inventory_mutation("rejects a distributed non-retained candidate", build_number: 2, predecessor: :failed) do |inventory|
      inventory.fetch("items").fetch(0)["distributionState"] = "published"
    end
    inventory_mutation("rejects a successful non-retained candidate with a failure reason", build_number: 2, predecessor: :failed) do |inventory|
      item = inventory.fetch("items").fetch(0)
      item["runConclusion"] = "success"
      item["reason"] = "build-failed"
    end
    inventory_mutation("rejects a reused origin run", build_number: 2, predecessor: :published) do |inventory|
      inventory.fetch("items").fetch(0)["candidateOriginRunId"] = RUN_ID
    end
    inventory_mutation("rejects retained identity reused by the current candidate", build_number: 2, predecessor: :published) do |inventory|
      inventory.fetch("items").fetch(0)["candidateArtifactId"] = ARTIFACT_ID
    end

    lineage_mutation("rejects an installable history with no predecessor", build_number: 2, predecessor: :published) do |lineage|
      inventory_sha256 = lineage.fetch("candidateInventorySHA256")
      lineage["upgradePredecessor"] = {
        "state" => "none",
        "reason" => "first-public-beta-no-installable-predecessor",
        "candidateInventorySHA256" => inventory_sha256,
        "cleanInstallEvidenceSHA256" => "b" * 64,
        "schema0MigrationEvidenceSHA256" => "c" * 64
      }
    end
    lineage_mutation("rejects a false public-release kind for protected beta history", build_number: 2, predecessor: :protected) do |lineage|
      lineage.fetch("upgradePredecessor")["distributionKind"] = "public-release"
    end
    lineage_mutation("rejects a noncanonical predecessor artifact name", build_number: 2, predecessor: :published) do |lineage|
      lineage.fetch("upgradePredecessor")["artifactName"] = "renamed-0.0.9.dmg"
    end

    run("rejects a predecessor that is not the latest installable build") do
      with_fixture(build_number: 3, predecessor: :published) do |fixture|
        latest = retained_inventory_item(state: "protected-beta", build_number: 2)
        latest["version"] = "0.0.10"
        latest["commit"] = "8" * 40
        fixture.fetch(:inventory).fetch("items") << latest
        rewrite_inventory_and_lineage!(fixture)
        assert_failure(*arguments(fixture))
      end
    end

    run("accepts schema 0 for the protected predecessor") do
      with_fixture(build_number: 2, predecessor: :protected) do |fixture|
        fixture.dig(:lineage, "upgradePredecessor")["profileSchemaVersion"] = 0
        write_json(fixture.dig(:paths, :lineage), fixture.fetch(:lineage))
        lineage_sha256 = digest(fixture.dig(:paths, :lineage))
        fixture.fetch(:reports).each_with_index do |report_value, index|
          report_value.fetch("subject")["predecessorLineageSHA256"] = lineage_sha256
          write_json(fixture.dig(:paths, :reports, index), report_value)
        end
        report_digests = fixture.dig(:paths, :reports).map { |path| digest(path) }
        fixture.fetch(:set).fetch("subject")["predecessorLineageSHA256"] = lineage_sha256
        report_digests.each_with_index do |report_sha256, index|
          fixture.dig(:set, "reports", index)["reportSHA256"] = report_sha256
          fixture.dig(:set, "independence", "bindings", index)["reportSHA256"] = report_sha256
        end
        write_json(fixture.dig(:paths, :set), fixture.fetch(:set))
        assert_success(*arguments(fixture), build_number: 2)
      end
    end
  end

  def test_reports
    report_mutation("rejects the wrong report schema") do |report|
      report["schemaVersion"] = "desk-setup-switcher.external-beta/v0"
    end
    report_mutation("rejects unknown report keys") { |report| report["extra"] = true }
    report_mutation("rejects a report for another candidate") do |report|
      report.fetch("subject")["commit"] = "f" * 40
    end
    report_mutation("rejects a report with the wrong provenance bytes") do |report|
      report.fetch("subject")["provenanceBundleSHA256"] = "f" * 64
    end
    report_mutation("rejects a report with the wrong lineage bytes") do |report|
      report.fetch("subject")["predecessorLineageSHA256"] = "f" * 64
    end
    report_mutation("rejects a non-arm64 report") do |report|
      report.fetch("environment")["architecture"] = "x86_64"
    end
    report_mutation("rejects an unsupported macOS report") do |report|
      report.fetch("environment")["macOSVersion"] = "13.6.9"
    end
    %w[
      externalTester notReleaseOperator notReleaseApprover
      noRepositoryWriteAccess noReleaseSecretAccess
    ].each do |name|
      report_mutation("rejects false beta independence #{name}") do |report|
        report.fetch("independence")[name] = false
      end
    end
    %w[
      browserDownloaded normalArchiveExtraction quarantinePresent
      checksumPass provenancePass gatekeeperPass
    ].each do |name|
      report_mutation("rejects false beta acquisition #{name}") do |report|
        report.fetch("acquisition")[name] = false
      end
    end
    report_mutation("rejects manufactured quarantine") do |report|
      report.fetch("acquisition")["quarantineManufactured"] = true
    end
    report_mutation("rejects removed quarantine") do |report|
      report.fetch("acquisition")["quarantineRemoved"] = true
    end
    report_mutation("rejects Open Anyway") do |report|
      report.fetch("acquisition")["openAnywayUsed"] = true
    end
    report_mutation("rejects a failed mandatory lifecycle row") do |report|
      report.fetch("lifecycle")["diagnosticsPass"] = false
    end
    report_mutation("rejects a hardware mutation claim") do |report|
      report.fetch("lifecycle")["hardwareMutationPerformed"] = true
    end
    report_mutation("rejects an unresolved P0") do |report|
      report.fetch("issues")["unresolvedP0"] = 1
    end
    report_mutation("rejects an unresolved P1") do |report|
      report.fetch("issues")["unresolvedP1"] = 1
    end
    report_mutation("rejects a floating-point zero issue count") do |report|
      report.fetch("issues")["unresolvedP0"] = 0.0
    end
    report_mutation("rejects a floating-point subject build number") do |report|
      report.fetch("subject")["buildNumber"] = 1.0
    end
    report_mutation("rejects an incomplete tester attestation") do |report|
      report.fetch("attestation")["testerAttested"] = false
    end
    report_mutation("rejects a report start before lineage observation") do |report|
      report.fetch("report")["startedAt"] = MANIFEST_CREATED_AT
    end
    report_mutation("rejects a report completion before its start") do |report|
      report.fetch("report")["completedAt"] = "2026-07-18T01:59:59Z"
    end

    run("rejects report order changes") do
      with_fixture do |fixture|
        reordered = fixture.dig(:paths, :reports).values_at(1, 0, 2)
        assert_failure(*arguments(fixture, reports: reordered))
      end
    end

    run("rejects duplicate report bytes") do
      with_fixture do |fixture|
        FileUtils.cp(fixture.dig(:paths, :reports, 0), fixture.dig(:paths, :reports, 1))
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects a beta set without Sonoma full-lifecycle evidence") do
      with_fixture do |fixture|
        first = fixture.fetch(:reports).fetch(0)
        first.fetch("environment")["macOSVersion"] = "15.0"
        first.fetch("environment")["coverageRole"] = "additional-apple-silicon"
        write_json(fixture.dig(:paths, :reports, 0), first)
        report_sha = digest(fixture.dig(:paths, :reports, 0))
        fixture.dig(:set, "reports", 0)["reportSHA256"] = report_sha
        fixture.dig(:set, "independence", "bindings", 0)["reportSHA256"] = report_sha
        write_json(fixture.dig(:paths, :set), fixture.fetch(:set))
        assert_failure(*arguments(fixture))
      end
    end

    report_mutation("rejects passed upgrade evidence when no predecessor exists", index: 0) do |report|
      report.fetch("lifecycle")["upgrade"] = {
        "state" => "passed",
        "predecessorBuildNumber" => 1,
        "predecessorFinalDMGSHA256" => "9" * 64,
        "profilesPreserved" => true,
        "settingsPreserved" => true,
        "selectionPreserved" => true,
        "backupsPreserved" => true,
        "loginItemConsentPreserved" => true
      }
    end

    report_mutation(
      "rejects a floating-point upgrade predecessor build",
      index: 0,
      build_number: 2,
      predecessor: :published
    ) do |report|
      report.fetch("lifecycle").fetch("upgrade")["predecessorBuildNumber"] = 1.0
    end
  end

  def test_set_review
    set_mutation("rejects the wrong set schema") do |set|
      set["schemaVersion"] = "desk-setup-switcher.external-beta-set/v0"
    end
    set_mutation("rejects unknown set keys") { |set| set["extra"] = true }
    set_mutation("rejects a report-byte binding mismatch") do |set|
      set.fetch("reports").fetch(0)["reportSHA256"] = "f" * 64
    end
    set_mutation("rejects a roster report binding mismatch") do |set|
      set.dig("independence", "bindings", 1)["reportSHA256"] = "f" * 64
    end
    set_mutation("rejects duplicate private roster commitments") do |set|
      bindings = set.dig("independence", "bindings")
      bindings.fetch(1)["privateRosterEntryCommitmentSHA256"] =
        bindings.fetch(0).fetch("privateRosterEntryCommitmentSHA256")
    end
    set_mutation("rejects an unprotected review mode") do |set|
      set.fetch("independence")["reviewMode"] = "local-review"
    end
    set_mutation("rejects the wrong reviewer role") do |set|
      set.fetch("independence")["reviewerRole"] = "release-operator"
    end
    %w[
      threeDistinctNaturalPersons allExternalToReleaseTeam noneIsReleaseOperator
      noneIsReleaseApprover noneHasPushReleaseEnvironmentOrSecretAccess
    ].each do |name|
      set_mutation("rejects false set independence #{name}") do |set|
        set.dig("independence", "assertions")[name] = false
      end
    end
    set_mutation("rejects the wrong accepted report count") do |set|
      set.fetch("coverage")["acceptedReportCount"] = 2
    end
    set_mutation("rejects a floating-point accepted report count") do |set|
      set.fetch("coverage")["acceptedReportCount"] = 3.0
    end
    set_mutation("rejects a missing Sonoma report code") do |set|
      set.fetch("coverage")["sonomaGateReportCode"] = "beta-99"
    end
    set_mutation("rejects review before report completion") do |set|
      set.fetch("independence")["reviewedAt"] = "2026-07-18T06:30:00Z"
    end
    set_mutation("rejects set creation before protected review") do |set|
      set["createdAt"] = "2026-07-18T07:59:59Z"
    end
  end

  def test_strict_inputs
    run("rejects duplicate JSON keys") do
      with_fixture do |fixture, directory|
        marker = "SENSITIVE_DUPLICATE_MARKER"
        path = fixture.dig(:paths, :set)
        valid = File.binread(path)
        duplicate = valid.sub(/\A\{/, %({"schemaVersion":"#{marker}",))
        File.binwrite(path, duplicate)
        assert_failure(
          *arguments(fixture),
          forbidden: [directory, marker],
          expected_error: "external beta set contains duplicate JSON keys"
        )
      end
    end

    run("rejects invalid UTF-8 without leaking bytes or paths") do
      with_fixture do |fixture, directory|
        marker = "SENSITIVE_UTF8_MARKER"
        File.binwrite(fixture.dig(:paths, :set), marker.b + "\xFF".b)
        assert_failure(*arguments(fixture), forbidden: [directory, marker])
      end
    end

    run("rejects excessive JSON nesting") do
      with_fixture do |fixture|
        File.binwrite(fixture.dig(:paths, :set), ("[" * 40) + "0" + ("]" * 40))
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects oversized JSON evidence") do
      with_fixture do |fixture|
        File.binwrite(fixture.dig(:paths, :set), " " * 262_145)
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects symlink evidence") do
      with_fixture do |fixture|
        path = fixture.dig(:paths, :reports, 0)
        target = "#{path}.target"
        FileUtils.mv(path, target)
        File.symlink(target, path)
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects hard-linked evidence") do
      with_fixture do |fixture|
        path = fixture.dig(:paths, :reports, 0)
        target = "#{path}.target"
        FileUtils.mv(path, target)
        File.link(target, path)
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects missing required options safely") do
      stdout, stderr, status = cli("verify-set")
      assert(!status.success?)
      assert(stdout.empty?)
      assert_equal("External beta policy error: required external beta inputs are missing\n", stderr)
    end

    run("requires exactly three report paths") do
      with_fixture do |fixture|
        assert_failure(*arguments(fixture, reports: fixture.dig(:paths, :reports).first(2)))
      end
    end

    run("sanitizes unexpected command-line errors") do
      stdout, stderr, status = cli("verify-set", "--not-a-real-option", "SENSITIVE_OPTION_VALUE")
      assert(!status.success?)
      assert(stdout.empty?)
      assert_equal("External beta policy error: invalid command line.\n", stderr)
      assert(!stderr.include?("SENSITIVE_OPTION_VALUE"))
    end
  end

  def test_fixed_predecessor_contract
    run("accepts the fixed protected v0.0.9 build-1 to v0.1.0 build-2 contract") do
      with_fixture do |fixture|
        assert_success(*arguments(fixture), build_number: 2)
      end
    end

    run("returns every actual predecessor byte identity") do
      with_fixture do |fixture|
        stdout, stderr, status = cli(*arguments(fixture), "--print-result-json")
        assert(status.success?, "expected JSON result success: #{stderr.inspect}")
        assert(stderr.empty?, "JSON result wrote stderr")
        value = JSON.parse(stdout, create_additions: false)
        assert_equal("desk-setup-switcher.external-beta-verification/v3", value.fetch("schemaVersion"))
        assert_equal(digest(fixture.dig(:paths, :predecessor_manifest)), value.fetch("predecessorReleaseManifestSHA256"))
        assert_equal(digest(fixture.dig(:paths, :predecessor_dmg)), value.fetch("predecessorFinalDMGSHA256"))
        assert_equal(digest(fixture.dig(:paths, :predecessor_provenance)), value.fetch("predecessorFinalDMGProvenanceSHA256"))
        assert_equal(digest(fixture.dig(:paths, :predecessor_boundary)), value.fetch("predecessorReleaseBoundarySHA256"))
        assert_equal(2, value.fetch("buildNumber"))
      end
    end

    {
      "current DMG" => :dmg,
      "predecessor manifest" => :predecessor_manifest,
      "predecessor DMG" => :predecessor_dmg,
      "predecessor provenance" => :predecessor_provenance,
      "predecessor release boundary" => :predecessor_boundary
    }.each do |label, key|
      run("rejects changed #{label} bytes") do
        with_fixture do |fixture|
          File.open(fixture.dig(:paths, key), "ab") { |file| file.write("changed\n") }
          assert_failure(*arguments(fixture))
        end
      end

      run("rejects a symlink #{label}") do
        with_fixture do |fixture|
          path = fixture.dig(:paths, key)
          target = "#{path}.target"
          FileUtils.mv(path, target)
          File.symlink(target, path)
          assert_failure(*arguments(fixture))
        end
      end

      run("rejects a hard-linked #{label}") do
        with_fixture do |fixture|
          path = fixture.dig(:paths, key)
          target = "#{path}.target"
          FileUtils.mv(path, target)
          File.link(target, path)
          assert_failure(*arguments(fixture))
        end
      end

      run("rejects an empty #{label}") do
        with_fixture do |fixture|
          File.truncate(fixture.dig(:paths, key), 0)
          assert_failure(*arguments(fixture))
        end
      end
    end

    %i[dmg predecessor_dmg].each do |key|
      run("rejects an oversized #{key.to_s.tr('_', ' ')}") do
        with_fixture do |fixture|
          File.truncate(fixture.dig(:paths, key), (2 * 1024 * 1024 * 1024) + 1)
          assert_failure(*arguments(fixture))
        end
      end
    end

    run("rejects any predecessor GitHub Release even with rebound boundary bytes") do
      with_fixture do |fixture|
        fixture.dig(:boundary, "releaseBoundary", "releases", "items") << { "id" => 7001 }
        write_json(fixture.dig(:paths, :predecessor_boundary), fixture.fetch(:boundary))
        fixture.dig(:lineage, "upgradePredecessor")["releaseBoundaryEvidenceSHA256"] =
          digest(fixture.dig(:paths, :predecessor_boundary))
        rewrite_lineage_and_downstream!(fixture)
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects a lightweight or different predecessor tag boundary") do
      with_fixture do |fixture|
        ref = fixture.dig(:boundary, "releaseBoundary", "vRefs", "items", 0)
        ref["objectType"] = "commit"
        write_json(fixture.dig(:paths, :predecessor_boundary), fixture.fetch(:boundary))
        fixture.dig(:lineage, "upgradePredecessor")["releaseBoundaryEvidenceSHA256"] =
          digest(fixture.dig(:paths, :predecessor_boundary))
        rewrite_lineage_and_downstream!(fixture)
        assert_failure(*arguments(fixture))
      end
    end

    run("rejects a predecessor boundary for a different independently supplied tag object") do
      with_fixture do |fixture|
        assert_failure(
          *arguments(fixture, overrides: { predecessor_tag_object: "f" * 40 })
        )
      end
    end

    run("rejects a predecessor boundary for a different predecessor pre-tag digest") do
      with_fixture do |fixture|
        assert_failure(
          *arguments(fixture, overrides: { predecessor_pre_tag_sha256: "f" * 64 })
        )
      end
    end

    report_mutation("rejects a report bound to different predecessor manifest bytes") do |report|
      report.dig("lifecycle", "upgrade")["predecessorReleaseManifestSHA256"] = "f" * 64
    end
    report_mutation("rejects failed predecessor provenance acquisition") do |report|
      report.dig("lifecycle", "upgrade", "predecessorAcquisition")["provenancePass"] = false
    end
  end

  def test_current_recorded_templates
    run("prints current recorded lineage report and set schema shapes") do
      with_fixture do |fixture|
        cases = [
          ["predecessor-lineage-recorded", {}, fixture.fetch(:lineage)],
          [
            "external-beta-report-recorded",
            { report_code: "beta-01", coverage_role: "sonoma-full-lifecycle" },
            fixture.fetch(:reports).fetch(0)
          ],
          ["external-beta-set", { sonoma_report_code: "beta-01" }, fixture.fetch(:set)]
        ]
        cases.each do |kind, options, expected|
          template, = template_output(kind, **options)
          assert_equal(json_shape(expected), json_shape(template), "#{kind} schema shape differs")
          assert(json_strings(template).any? do |item|
            item.start_with?("<REJECTED_TEMPLATE:REPLACE_REQUIRED:")
          end, "#{kind} lacks rejected placeholders")
        end
      end
    end
  end

  def execute
    test_rejected_template_generation
    test_current_recorded_templates
    test_fixed_predecessor_contract
    test_candidate_binding
    test_lineage
    test_reports
    test_set_review
    test_strict_inputs

    if @failures.empty?
      puts "External beta policy tests passed: #{@tests} tests, #{@assertions} assertions."
      return 0
    end

    warn "External beta policy tests failed: #{@failures.length} of #{@tests} tests."
    @failures.each do |name, type, message|
      warn "- #{name}: #{type}: #{message}"
    end
    1
  end
end

exit ExternalBetaPolicyTestSuite.new.execute
