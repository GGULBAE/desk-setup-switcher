# frozen_string_literal: true

module DeskSetupExternalBetaTemplates
  REPORT_SCHEMA = "desk-setup-switcher.external-beta/v3"
  SET_SCHEMA = "desk-setup-switcher.external-beta-set/v2"
  INVENTORY_SCHEMA = "desk-setup-switcher.candidate-inventory/v1"
  LINEAGE_SCHEMA = "desk-setup-switcher.predecessor-lineage/v3"
  REPORT_CODES = %w[beta-01 beta-02 beta-03].freeze
  TEMPLATE_KINDS = %w[
    candidate-inventory-retained
    predecessor-lineage-recorded
    external-beta-report-recorded
    external-beta-set
  ].freeze
  REPORT_TEMPLATE_KINDS = %w[external-beta-report-recorded].freeze
  COVERAGE_ROLES = %w[sonoma-full-lifecycle additional-apple-silicon].freeze
  REJECTED_PLACEHOLDER_PREFIX = "<REJECTED_TEMPLATE:REPLACE_REQUIRED:".freeze

  module_function

  def placeholder(name)
    "#{REJECTED_PLACEHOLDER_PREFIX}#{name}>"
  end

  def placeholder_candidate
    {
      "repository" => placeholder("repository-owner-and-name"),
      "tag" => "v0.1.0",
      "commit" => placeholder("40-character-lowercase-commit"),
      "version" => "0.1.0",
      "buildNumber" => 2,
      "bundleIdentifier" => placeholder("bundle-identifier"),
      "profileSchemaVersion" => 0,
      "candidateOriginRunId" => 0,
      "candidateOriginRunAttempt" => 1,
      "candidateArtifactId" => 0,
      "candidateArtifactSHA256" => placeholder("candidate-artifact-sha256"),
      "finalDMGSHA256" => placeholder("final-dmg-sha256"),
      "releaseManifestSHA256" => placeholder("release-manifest-sha256")
    }
  end

  def placeholder_report_subject
    placeholder_candidate.merge(
      "finalDMGName" => "Desk-Setup-Switcher-0.1.0.dmg",
      "provenanceBundleName" => "Desk-Setup-Switcher-0.1.0.provenance.sigstore.json",
      "provenanceBundleSHA256" => placeholder("provenance-bundle-sha256"),
      "provenanceSubjectSHA256" => placeholder("provenance-subject-sha256"),
      "predecessorLineageSHA256" => placeholder("predecessor-lineage-sha256")
    )
  end

  def placeholder_inventory_item
    {
      "outcome" => "retained",
      "version" => "0.0.9",
      "buildNumber" => 1,
      "commit" => placeholder("predecessor-40-character-lowercase-commit"),
      "candidateOriginRunId" => 0,
      "candidateOriginRunAttempt" => 1,
      "runConclusion" => "success",
      "completedAt" => placeholder("predecessor-completed-at-utc"),
      "distributionState" => "protected-beta",
      "candidateArtifactId" => 0,
      "candidateArtifactSHA256" => placeholder("predecessor-candidate-artifact-sha256"),
      "finalDMGSHA256" => placeholder("predecessor-final-dmg-sha256"),
      "releaseManifestSHA256" => placeholder("predecessor-release-manifest-sha256")
    }
  end

  def placeholder_installation(prefix = nil)
    predecessor = prefix == "predecessor"
    label = prefix ? "#{prefix}-" : ""
    {
      "destinationPath" => "/Applications/Desk Setup Switcher.app",
      "method" => "finder-drag-from-mounted-dmg",
      "copiedFromMountedDMG" => false,
      "dmgEjectedBeforeLaunch" => false,
      "launchedFromApplications" => false,
      "bundleIdentifier" => placeholder("#{label}installed-bundle-identifier"),
      "version" => predecessor ? "0.0.9" : "0.1.0",
      "buildNumber" => predecessor ? 1 : 2,
      "executableSHA256" => placeholder("#{label}installed-executable-sha256"),
      "bundleManifestSHA256" => placeholder("#{label}installed-bundle-manifest-sha256"),
      "sourceBundleManifestMatched" => false,
      "installationEvidenceSHA256" => placeholder("#{label}installation-evidence-sha256")
    }
  end

  def placeholder_acquisition(prefix = nil)
    label = prefix ? "#{prefix}-quarantine-evidence-sha256" : "quarantine-evidence-sha256"
    {
      "channel" => "protected-workflow-browser",
      "browserDownloaded" => false,
      "normalArchiveExtraction" => false,
      "quarantinePresent" => false,
      "quarantineManufactured" => false,
      "quarantineRemoved" => false,
      "quarantineEvidenceSHA256" => placeholder(label),
      "checksumPass" => false,
      "provenancePass" => false,
      "gatekeeperPass" => false,
      "openAnywayUsed" => false,
      "installation" => placeholder_installation(prefix)
    }
  end

  def inventory(kind)
    raise ArgumentError, "invalid inventory template kind" unless kind == "candidate-inventory-retained"

    items = [placeholder_inventory_item]
    {
      "schemaVersion" => INVENTORY_SCHEMA,
      "subject" => {
        "repository" => placeholder("repository-owner-and-name"),
        "workflowPath" => ".github/workflows/signed-release-candidate.yml",
        "operation" => "build-candidate",
        "currentCandidateRunId" => 0,
        "currentCandidateBuildNumber" => 2
      },
      "collection" => {
        "collectedAt" => placeholder("inventory-collected-at-utc"),
        "reviewedAt" => placeholder("inventory-reviewed-at-utc"),
        "reviewMode" => "protected-complete-history-review",
        "reviewerRole" => "release-approver",
        "allPagesReviewed" => false,
        "sourceEvidenceSHA256" => placeholder("protected-source-evidence-sha256")
      },
      "items" => items
    }
  end

  def lineage(kind)
    upgrade = case kind
              when "predecessor-lineage-recorded"
                {
                  "state" => "recorded",
                  "distributionKind" => "protected-beta",
                  "bundleIdentifier" => placeholder("bundle-identifier"),
                  "version" => "0.0.9",
                  "tag" => "v0.0.9",
                  "buildNumber" => 1,
                  "profileSchemaVersion" => 0,
                  "sourceCommit" => placeholder("predecessor-40-character-lowercase-commit"),
                  "candidateOriginRunId" => 0,
                  "candidateOriginRunAttempt" => 1,
                  "candidateArtifactId" => 0,
                  "candidateArtifactSHA256" => placeholder("predecessor-candidate-artifact-sha256"),
                  "artifactName" => "Desk-Setup-Switcher-0.0.9.dmg",
                  "finalDMGSHA256" => placeholder("predecessor-final-dmg-sha256"),
                  "releaseManifestSHA256" => placeholder("predecessor-release-manifest-sha256"),
                  "provenanceBundleName" => "Desk-Setup-Switcher-0.0.9.provenance.sigstore.json",
                  "provenanceBundleSHA256" => placeholder("predecessor-provenance-bundle-sha256"),
                  "provenanceSubjectSHA256" => placeholder("predecessor-provenance-subject-sha256"),
                  "releaseBoundaryEvidenceSHA256" => placeholder("predecessor-release-boundary-evidence-sha256")
                }
              else
                raise ArgumentError, "invalid lineage template kind"
              end
    {
      "schemaVersion" => LINEAGE_SCHEMA,
      "candidate" => placeholder_candidate,
      "candidateInventorySHA256" => placeholder("candidate-inventory-sha256"),
      "upgradePredecessor" => upgrade
    }
  end

  def report(kind, report_code, coverage_role)
    raise ArgumentError, "invalid report template kind" unless kind == "external-beta-report-recorded"

    upgrade = {
      "state" => "pending",
      "predecessorVersion" => "0.0.9",
      "predecessorBuildNumber" => 1,
      "predecessorFinalDMGSHA256" => placeholder("predecessor-final-dmg-sha256"),
      "predecessorReleaseManifestSHA256" => placeholder("predecessor-release-manifest-sha256"),
      "predecessorProvenanceBundleSHA256" => placeholder("predecessor-provenance-bundle-sha256"),
      "predecessorAcquisition" => placeholder_acquisition("predecessor"),
      "profilesPreserved" => false,
      "settingsPreserved" => false,
      "selectionPreserved" => false,
      "backupsPreserved" => false,
      "loginItemConsentPreserved" => false
    }
    {
      "schemaVersion" => REPORT_SCHEMA,
      "report" => {
        "reportCode" => report_code,
        "startedAt" => placeholder("test-started-at-utc"),
        "completedAt" => placeholder("test-completed-at-utc")
      },
      "subject" => placeholder_report_subject,
      "environment" => {
        "architecture" => "arm64",
        "macOSVersion" => placeholder("macos-version"),
        "hardwareClass" => "apple-silicon",
        "cleanBasis" => placeholder("clean-basis"),
        "coverageRole" => coverage_role
      },
      "independence" => {
        "externalTester" => false,
        "notReleaseOperator" => false,
        "notReleaseApprover" => false,
        "noRepositoryWriteAccess" => false,
        "noReleaseSecretAccess" => false
      },
      "acquisition" => placeholder_acquisition,
      "lifecycle" => {
        "firstLaunchPass" => false,
        "loginItemDefaultOffPass" => false,
        "threeStepFlowPass" => false,
        "stoppedBeforeApply" => false,
        "schema0MigrationPass" => false,
        "backupRecoveryPass" => false,
        "importExportPass" => false,
        "diagnosticsPass" => false,
        "uninstallPass" => false,
        "localDataRemovalPass" => false,
        "hardwareMutationPerformed" => false,
        "upgrade" => upgrade
      },
      "issues" => {
        "unresolvedP0" => -1,
        "unresolvedP1" => -1,
        "allFailuresTracked" => false,
        "blockerEvidenceSHA256" => placeholder("blocker-evidence-sha256")
      },
      "attestation" => {
        "candidateIdentityConfirmed" => false,
        "privacyReviewed" => false,
        "reportComplete" => false,
        "testerAttested" => false,
        "noHardwareMutationClaim" => false
      }
    }
  end

  def set(sonoma_report_code)
    report_entries = REPORT_CODES.map do |code|
      {
        "reportCode" => code,
        "reportSHA256" => placeholder("#{code}-report-sha256")
      }
    end
    {
      "schemaVersion" => SET_SCHEMA,
      "subject" => placeholder_report_subject,
      "reports" => report_entries,
      "independence" => {
        "reviewMode" => "protected-release-review",
        "reviewerRole" => "release-approver",
        "reviewedAt" => placeholder("protected-review-at-utc"),
        "protectedReviewEvidenceSHA256" => placeholder("protected-review-evidence-sha256"),
        "privateRosterBundleSHA256" => placeholder("private-roster-bundle-sha256"),
        "bindings" => REPORT_CODES.map do |code|
          {
            "reportCode" => code,
            "reportSHA256" => placeholder("#{code}-report-sha256"),
            "privateRosterEntryCommitmentSHA256" => placeholder("#{code}-private-roster-entry-commitment-sha256")
          }
        end,
        "assertions" => {
          "threeDistinctNaturalPersons" => false,
          "allExternalToReleaseTeam" => false,
          "noneIsReleaseOperator" => false,
          "noneIsReleaseApprover" => false,
          "noneHasPushReleaseEnvironmentOrSecretAccess" => false
        }
      },
      "coverage" => {
        "acceptedReportCount" => 0,
        "sonomaGateReportCode" => sonoma_report_code,
        "allAppleSilicon" => false,
        "allSupportedOS" => false,
        "allMandatoryLifecyclePassed" => false
      },
      "createdAt" => placeholder("external-beta-set-created-at-utc")
    }
  end
end
