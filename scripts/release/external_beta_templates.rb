# frozen_string_literal: true

module DeskSetupExternalBetaTemplates
  REPORT_SCHEMA = "desk-setup-switcher.external-beta/v1"
  SET_SCHEMA = "desk-setup-switcher.external-beta-set/v1"
  INVENTORY_SCHEMA = "desk-setup-switcher.candidate-inventory/v1"
  LINEAGE_SCHEMA = "desk-setup-switcher.predecessor-lineage/v2"
  REPORT_CODES = %w[beta-01 beta-02 beta-03].freeze
  TEMPLATE_KINDS = %w[
    candidate-inventory-empty
    candidate-inventory-retained
    candidate-inventory-not-retained
    predecessor-lineage-none
    predecessor-lineage-recorded
    external-beta-report-none
    external-beta-report-recorded
    external-beta-set
  ].freeze
  REPORT_TEMPLATE_KINDS = %w[
    external-beta-report-none
    external-beta-report-recorded
  ].freeze
  COVERAGE_ROLES = %w[sonoma-full-lifecycle additional-apple-silicon].freeze
  REJECTED_PLACEHOLDER_PREFIX = "<REJECTED_TEMPLATE:REPLACE_REQUIRED:".freeze

  module_function

  def placeholder(name)
    "#{REJECTED_PLACEHOLDER_PREFIX}#{name}>"
  end

  def placeholder_candidate
    {
      "repository" => placeholder("repository-owner-and-name"),
      "tag" => placeholder("release-tag"),
      "commit" => placeholder("40-character-lowercase-commit"),
      "version" => "0.0.0",
      "buildNumber" => 0,
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
      "finalDMGName" => "Desk-Setup-Switcher-0.0.0.dmg",
      "provenanceBundleName" => "Desk-Setup-Switcher-0.0.0.provenance.sigstore.json",
      "provenanceBundleSHA256" => placeholder("provenance-bundle-sha256"),
      "provenanceSubjectSHA256" => placeholder("provenance-subject-sha256"),
      "predecessorLineageSHA256" => placeholder("predecessor-lineage-sha256")
    )
  end

  def placeholder_inventory_item(outcome)
    common = {
      "outcome" => outcome,
      "version" => "0.0.0",
      "buildNumber" => 0,
      "commit" => placeholder("historical-40-character-lowercase-commit"),
      "candidateOriginRunId" => 0,
      "candidateOriginRunAttempt" => 1,
      "runConclusion" => placeholder("historical-run-conclusion"),
      "completedAt" => placeholder("historical-completed-at-utc"),
      "distributionState" => outcome == "retained" ?
        placeholder("historical-distribution-state") : "not-distributed"
    }
    return common.merge(
      "candidateArtifactId" => 0,
      "candidateArtifactSHA256" => placeholder("historical-candidate-artifact-sha256"),
      "finalDMGSHA256" => placeholder("historical-final-dmg-sha256"),
      "releaseManifestSHA256" => placeholder("historical-release-manifest-sha256")
    ) if outcome == "retained"

    common.merge("reason" => placeholder("historical-non-retention-reason"))
  end

  def inventory(kind)
    items = case kind
            when "candidate-inventory-empty"
              []
            when "candidate-inventory-retained"
              [placeholder_inventory_item("retained")]
            when "candidate-inventory-not-retained"
              [placeholder_inventory_item("not-retained")]
            else
              raise ArgumentError, "invalid inventory template kind"
            end
    {
      "schemaVersion" => INVENTORY_SCHEMA,
      "subject" => {
        "repository" => placeholder("repository-owner-and-name"),
        "workflowPath" => ".github/workflows/release.yml",
        "operation" => "build-candidate",
        "currentCandidateRunId" => 0,
        "currentCandidateBuildNumber" => 0
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
              when "predecessor-lineage-none"
                {
                  "state" => "none",
                  "reason" => "first-public-beta-no-installable-predecessor",
                  "candidateInventorySHA256" => placeholder("candidate-inventory-sha256"),
                  "cleanInstallEvidenceSHA256" => placeholder("clean-install-evidence-sha256"),
                  "schema0MigrationEvidenceSHA256" => placeholder("schema0-migration-evidence-sha256")
                }
              when "predecessor-lineage-recorded"
                {
                  "state" => "recorded",
                  "distributionKind" => placeholder("predecessor-distribution-kind"),
                  "bundleIdentifier" => placeholder("bundle-identifier"),
                  "version" => "0.0.0",
                  "buildNumber" => 0,
                  "profileSchemaVersion" => 0,
                  "sourceCommit" => placeholder("predecessor-40-character-lowercase-commit"),
                  "artifactName" => "Desk-Setup-Switcher-0.0.0.dmg",
                  "finalDMGSHA256" => placeholder("predecessor-final-dmg-sha256"),
                  "identityEvidenceSHA256" => placeholder("predecessor-identity-evidence-sha256"),
                  "installEvidenceSHA256" => placeholder("predecessor-install-evidence-sha256")
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
    upgrade = if kind == "external-beta-report-none"
                {
                  "state" => "not-applicable",
                  "reason" => "first-public-beta-no-installable-predecessor"
                }
              else
                {
                  "state" => "pending",
                  "predecessorBuildNumber" => 0,
                  "predecessorFinalDMGSHA256" => placeholder("predecessor-final-dmg-sha256"),
                  "profilesPreserved" => false,
                  "settingsPreserved" => false,
                  "selectionPreserved" => false,
                  "backupsPreserved" => false,
                  "loginItemConsentPreserved" => false
                }
              end
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
      "acquisition" => {
        "channel" => "protected-workflow-browser",
        "browserDownloaded" => false,
        "normalArchiveExtraction" => false,
        "quarantinePresent" => false,
        "quarantineManufactured" => false,
        "quarantineRemoved" => false,
        "quarantineEvidenceSHA256" => placeholder("quarantine-evidence-sha256"),
        "checksumPass" => false,
        "provenancePass" => false,
        "gatekeeperPass" => false,
        "openAnywayUsed" => false
      },
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
