#!/usr/bin/env ruby
# frozen_string_literal: true

require_relative "collect_remote_controls_evidence"

class RemoteControlsCollectorV3Test
  COMMIT = "a" * 40
  CANDIDATE_BLOB = "b" * 40
  CI_BLOB = "c" * 40
  PUBLICATION_BLOB = "d" * 40
  LEGACY_BLOB = "e" * 40
  PREDECESSOR_COMMIT = "7" * 40
  PREDECESSOR_TAG_OBJECT = "8" * 40
  RELEASE_COMMIT = "9" * 40
  RELEASE_TAG_OBJECT = "6" * 40
  PREDECESSOR_DIGEST = "1" * 64
  FINAL_DIGEST = "2" * 64

  def initialize
    @tests = 0
    @assertions = 0
    @failures = []
  end

  def assert(value, message = "assertion failed")
    @assertions += 1
    raise message unless value
  end

  def equal(expected, actual)
    assert(expected == actual, "expected #{expected.inspect}, got #{actual.inspect}")
  end

  def run(name)
    @tests += 1
    yield
    puts "ok #{@tests} - #{name}"
  rescue StandardError => error
    @failures << [name, error.message]
    puts "not ok #{@tests} - #{name}"
  end

  def unavailable
    yield
    raise "expected unavailable"
  rescue RemoteControlsCollector::CollectionUnavailable
    @assertions += 1
  end

  def workflow(path, blob, contents_write)
    {
      "projection" => "strict-local-workflow-ast/v1",
      "workflowPath" => path,
      "workflowBlob" => blob,
      "triggers" => path.end_with?("ci.yml") ? %w[pull_request push workflow_dispatch] : ["workflow_dispatch"],
      "contentsWrite" => contents_write
    }
  end

  def manifest(phase)
    value = {
      "schemaVersion" => "desk-setup-switcher.remote-release-controls-input/v3",
      "phase" => phase,
      "collectedAt" => "2026-07-18T01:00:00Z",
      "expectedCommit" => COMMIT,
      "expectedWorkflowBlob" => CANDIDATE_BLOB,
      "expectedCIWorkflowBlob" => CI_BLOB,
      "expectedPublicationWorkflowBlob" => PUBLICATION_BLOB,
      "expectedLegacyWorkflowBlob" => LEGACY_BLOB,
      "expectedPredecessor" => nil,
      "expectedRelease" => nil,
      "predecessorPreTagEvidenceSHA256" => nil,
      "finalPreTagEvidenceSHA256" => nil,
      "localCandidateWorkflow" => workflow(
        ".github/workflows/signed-release-candidate.yml", CANDIDATE_BLOB, true
      ),
      "localCIWorkflow" => workflow(".github/workflows/ci.yml", CI_BLOB, false),
      "localPublicationWorkflow" => workflow(
        ".github/workflows/publish-release.yml", PUBLICATION_BLOB, true
      ),
      "localLegacyWorkflow" => workflow(
        ".github/workflows/release.yml", LEGACY_BLOB, false
      ),
      "manualEvidence" => {
        "complete" => true,
        "items" => [
          {
            "control" => "release-candidate-administrator-bypass-disabled",
            "sha256" => "3" * 64
          },
          {
            "control" => "release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope",
            "sha256" => "4" * 64
          }
        ]
      },
      "files" => ["projection.json"]
    }
    if %w[final-pre-tag pre-publication].include?(phase)
      value["expectedPredecessor"] = {
        "commitSha" => PREDECESSOR_COMMIT,
        "tagObjectSha" => PREDECESSOR_TAG_OBJECT
      }
      value["predecessorPreTagEvidenceSHA256"] = PREDECESSOR_DIGEST
    end
    if phase == "pre-publication"
      value["expectedRelease"] = {
        "commitSha" => RELEASE_COMMIT,
        "id" => 12_345,
        "tagObjectSha" => RELEASE_TAG_OBJECT
      }
      value["finalPreTagEvidenceSHA256"] = FINAL_DIGEST
    end
    value
  end

  def execute
    %w[predecessor-pre-tag final-pre-tag pre-publication].each do |phase|
      run("normalizes the closed #{phase} v3 manifest") do
        value = RemoteControlsCollector.normalize_lifecycle_manifest(manifest(phase))
        equal("desk-setup-switcher.remote-release-controls-input/v3", value["schemaVersion"])
        equal("desk-setup-switcher.remote-release-controls-evidence/v3", value["evidenceSchemaVersion"])
        equal(phase, value["phase"])
      end
    end

    run("rejects a final-pre-tag manifest without predecessor anchors") do
      value = manifest("final-pre-tag")
      value["expectedPredecessor"] = nil
      unavailable { RemoteControlsCollector.normalize_lifecycle_manifest(value) }
    end

    run("rejects a final-pre-tag manifest without the predecessor evidence digest") do
      value = manifest("final-pre-tag")
      value["predecessorPreTagEvidenceSHA256"] = nil
      unavailable { RemoteControlsCollector.normalize_lifecycle_manifest(value) }
    end

    run("rejects a pre-publication manifest without the final evidence digest") do
      value = manifest("pre-publication")
      value["finalPreTagEvidenceSHA256"] = nil
      unavailable { RemoteControlsCollector.normalize_lifecycle_manifest(value) }
    end

    run("rejects predecessor anchors before any predecessor tag exists") do
      value = manifest("predecessor-pre-tag")
      value["expectedPredecessor"] = {
        "commitSha" => PREDECESSOR_COMMIT,
        "tagObjectSha" => PREDECESSOR_TAG_OBJECT
      }
      unavailable { RemoteControlsCollector.normalize_lifecycle_manifest(value) }
    end

    run("normalizes both annotated refs in canonical order") do
      raw = [
        {
          "ref" => "refs/tags/v0.1.0", "object_type" => "tag",
          "object_sha" => RELEASE_TAG_OBJECT, "commit_sha" => RELEASE_COMMIT
        },
        {
          "ref" => "refs/tags/v0.0.9", "object_type" => "tag",
          "object_sha" => PREDECESSOR_TAG_OBJECT, "commit_sha" => PREDECESSOR_COMMIT
        }
      ]
      value = RemoteControlsCollector.normalize_pre_publication_refs(raw)
      equal(%w[refs/tags/v0.0.9 refs/tags/v0.1.0], value["items"].map { |item| item["ref"] })
      equal(%w[tag tag], value["items"].map { |item| item["objectType"] })
    end

    run("retains a predecessor Release so policy validation can reject it") do
      value = RemoteControlsCollector.normalize_pre_publication_releases(
        [
          { "id" => 7_009, "tag_name" => "v0.0.9", "draft" => true, "prerelease" => true },
          { "id" => 12_345, "tag_name" => "v0.1.0", "draft" => true, "prerelease" => true }
        ]
      )
      equal(%w[v0.0.9 v0.1.0], value["items"].map { |item| item["tag"] })
    end

    run("rejects an unknown lifecycle phase") do
      value = manifest("predecessor-pre-tag")
      value["phase"] = "other"
      unavailable { RemoteControlsCollector.normalize_lifecycle_manifest(value) }
    end

    if @failures.empty?
      puts "PASS: #{@tests} tests, #{@assertions} assertions"
      return 0
    end
    @failures.each { |name, message| warn "FAIL: #{name}: #{message}" }
    warn "FAIL: #{@failures.length} of #{@tests} tests failed"
    1
  end
end

exit RemoteControlsCollectorV3Test.new.execute
