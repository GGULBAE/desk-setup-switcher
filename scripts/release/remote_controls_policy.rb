#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "json"
require "uri"
require "time"
require_relative "release_policy"

# Verifies a normalized, value-free snapshot of the GitHub controls that must
# exist immediately before the v0.1.0 tag is created. The policy and evidence
# are separate inputs so the expected public identities cannot be inferred from
# the observation being checked. Both inputs use closed v1 schemas: unknown,
# missing, or duplicate keys fail validation.
module RemoteControlsPolicy
  POLICY_SCHEMA = "desk-setup-switcher.remote-release-controls-policy/v1"
  EVIDENCE_SCHEMA = "desk-setup-switcher.remote-release-controls-evidence/v1"
  POLICY_SCHEMA_V2 = "desk-setup-switcher.remote-release-controls-policy/v2"
  EVIDENCE_SCHEMA_V2 = "desk-setup-switcher.remote-release-controls-evidence/v2"
  POLICY_SCHEMA_V3 = "desk-setup-switcher.remote-release-controls-policy/v3"
  EVIDENCE_SCHEMA_V3 = "desk-setup-switcher.remote-release-controls-evidence/v3"
  PREDECESSOR_PRE_TAG_PHASE = "predecessor-pre-tag"
  PHASE = "final-pre-tag"
  LIFECYCLE_PHASE = "release-lifecycle"
  PRE_PUBLICATION_PHASE = "pre-publication"
  PREDECESSOR_TAG = "v0.0.9"
  VERSION = "0.1.0"
  TAG = "v0.1.0"
  DEFAULT_BRANCH = "master"
  RELEASE_ENVIRONMENT = "release-candidate"
  RELEASE_WORKFLOW_NAME = "Signed release candidate"
  RELEASE_WORKFLOW_PATH = ".github/workflows/signed-release-candidate.yml"
  LEGACY_WORKFLOW_NAME = "Retired legacy release workflow"
  LEGACY_WORKFLOW_PATH = ".github/workflows/release.yml"
  CI_WORKFLOW_NAME = "CI"
  CI_WORKFLOW_PATH = ".github/workflows/ci.yml"
  PUBLICATION_WORKFLOW_NAME = "Publish approved signed release"
  PUBLICATION_WORKFLOW_PATH = ".github/workflows/publish-release.yml"
  CI_RUN_PATH = CI_WORKFLOW_PATH
  CI_WORKFLOW_TRIGGERS = %w[pull_request push workflow_dispatch].freeze
  REQUIRED_CHECK_NAME = "Verify macOS app"
  PUBLIC_SURFACE_CHECK_NAME = "Verify public site and release assets"
  REQUIRED_CHECK_NAMES = [REQUIRED_CHECK_NAME, PUBLIC_SURFACE_CHECK_NAME].sort.freeze
  GITHUB_ACTIONS_APP_ID = 15_368
  MASTER_REF = "refs/heads/master"
  TAG_PATTERN = "refs/tags/v*"

  REQUIRED_ENVIRONMENT_SECRETS = %w[
    APPLE_NOTARY_API_KEY_BASE64
    DEVELOPER_ID_CERTIFICATE_BASE64
    DEVELOPER_ID_CERTIFICATE_PASSWORD
  ].freeze
  REQUIRED_ENVIRONMENT_VARIABLES = %w[
    APPLE_NOTARY_ISSUER_ID
    APPLE_NOTARY_KEY_ID
    APPLE_TEAM_ID
    DEVELOPER_ID_APPLICATION
  ].freeze
  REQUIRED_PUBLICATION_SECRETS = %w[RELEASE_ADMIN_READ_TOKEN].freeze
  REQUIRED_PUBLICATION_VARIABLES = %w[APPLE_TEAM_ID DEVELOPER_ID_APPLICATION].freeze
  MANUAL_CONTROLS = %w[
    release-candidate-administrator-bypass-disabled
    release-publication-administrator-bypass-disabled-and-admin-read-token-minimum-scope
  ].freeze
  MANUAL_EVIDENCE_PATHS = %w[
    docs/evidence/releases/v0.1.0/release-candidate-admin-bypass.json
    docs/evidence/releases/v0.1.0/release-publication-admin-token-scope.json
  ].freeze
  MANUAL_EVIDENCE_SCHEMA = "desk-setup-switcher.manual-release-control-evidence/v1"

  PolicyError = ReleasePolicy::PolicyError

  module_function

  def reject!(label)
    raise PolicyError, "#{label} is invalid"
  end

  def exact_object(value, label, keys)
    reject!(label) unless value.is_a?(Hash)
    reject!(label) unless value.keys.all? { |key| key.is_a?(String) }
    reject!(label) unless value.keys.sort == keys.sort

    value
  end

  def exact_array(value, label, length: nil)
    reject!(label) unless value.is_a?(Array)
    reject!(label) if length && value.length != length

    value
  end

  def exact_string(value, label, max_bytes: 1024)
    value = value.encode(Encoding::UTF_8) if value.is_a?(String) &&
                                                value.encoding == Encoding::US_ASCII
    unless value.is_a?(String) && !value.empty? && value.bytesize <= max_bytes &&
           value.encoding == Encoding::UTF_8 && value.valid_encoding? &&
           !value.match?(/[\r\n\0]/)
      reject!(label)
    end
    value
  end

  def exact_boolean(value, label)
    reject!(label) unless value == true || value == false

    value
  end

  def positive_integer(value, label)
    reject!(label) unless value.is_a?(Integer) && value.positive?

    value
  end

  def sha(value, label)
    exact_string(value, label)
    reject!(label) unless value.match?(/\A[0-9a-f]{40}\z/)

    value
  end

  def sha256(value, label)
    exact_string(value, label)
    reject!(label) unless value.match?(/\A[0-9a-f]{64}\z/)

    value
  end

  def github_login(value, label)
    exact_string(value, label, max_bytes: 39)
    reject!(label) unless value.match?(/\A(?!-)[A-Za-z0-9-]+(?<!-)\z/)

    value
  end

  def actor(value, label, configured: false)
    keys = configured ? %w[configured id login type] : %w[id login type]
    exact_object(value, label, keys)
    reject!(label) if configured && value["configured"] != true
    positive_integer(value["id"], label)
    github_login(value["login"], label)
    reject!(label) unless value["type"] == "User"
    value
  end

  def same_actor?(left, right)
    left["id"] == right["id"] &&
      left["login"].casecmp?(right["login"]) &&
      left["type"] == right["type"]
  end

  def canonical_strings(value, label, allow_empty: true, pattern: nil)
    items = exact_array(value, label)
    reject!(label) if !allow_empty && items.empty?
    items.each do |item|
      exact_string(item, label)
      reject!(label) if pattern && !item.match?(pattern)
    end
    reject!(label) unless items.uniq.length == items.length && items.sort == items
    items
  end

  def named_collection(value, label)
    exact_object(value, label, %w[complete names])
    reject!(label) unless value["complete"] == true
    canonical_strings(value["names"], label, pattern: /\A[A-Za-z_][A-Za-z0-9_]*\z/)
  end

  def validate_policy_repository(value)
    exact_object(
      value,
      "policy repository",
      %w[archived defaultBranch description disabled fullName hasDiscussions homepage id name nodeId topics visibility]
    )
    positive_integer(value["id"], "policy repository")
    exact_string(value["nodeId"], "policy repository")
    exact_string(value["name"], "policy repository", max_bytes: 100)
    exact_string(value["fullName"], "policy repository", max_bytes: 141)
    reject!("policy repository") unless value["visibility"] == "public"
    reject!("policy repository") unless value["defaultBranch"] == DEFAULT_BRANCH
    reject!("policy repository") unless value["archived"] == false && value["disabled"] == false
    reject!("policy repository") unless value["hasDiscussions"] == false
    exact_string(value["description"], "policy repository", max_bytes: 160)
    unless value["homepage"].nil?
      homepage = exact_string(value["homepage"], "policy repository", max_bytes: 2048)
      begin
        uri = URI.parse(homepage)
        reject!("policy repository") unless uri.is_a?(URI::HTTPS) && uri.host && !uri.host.empty? &&
                                             uri.userinfo.nil? && uri.fragment.nil?
      rescue URI::InvalidURIError
        reject!("policy repository")
      end
    end
    canonical_strings(
      value["topics"],
      "policy repository",
      allow_empty: false,
      pattern: /\A[a-z0-9][a-z0-9-]{0,49}\z/
    )
    value
  end

  def validate_policy_release(value)
    exact_object(value, "policy release", %w[ci tag version workflow])
    reject!("policy release") unless value["version"] == VERSION && value["tag"] == TAG

    workflow = exact_object(value["workflow"], "policy workflow", %w[blobSha id name path])
    positive_integer(workflow["id"], "policy workflow")
    reject!("policy workflow") unless workflow["name"] == RELEASE_WORKFLOW_NAME &&
                                      workflow["path"] == RELEASE_WORKFLOW_PATH
    sha(workflow["blobSha"], "policy workflow")

    ci = exact_object(value["ci"], "policy CI", %w[appId name workflow])
    reject!("policy CI") unless ci["name"] == REQUIRED_CHECK_NAME &&
                                ci["appId"] == GITHUB_ACTIONS_APP_ID
    ci_workflow = exact_object(ci["workflow"], "policy CI workflow", %w[blobSha id name path])
    positive_integer(ci_workflow["id"], "policy CI workflow")
    reject!("policy CI workflow") unless ci_workflow["name"] == CI_WORKFLOW_NAME &&
                                         ci_workflow["path"] == CI_WORKFLOW_PATH
    sha(ci_workflow["blobSha"], "policy CI workflow")
    value
  end

  def validate_policy(value)
    exact_object(value, "remote controls policy preamble", %w[configured phase schemaVersion]) if
      value.is_a?(Hash) && value["configured"] == false
    if value.is_a?(Hash) && value["configured"] == false
      reject!("remote controls policy schema") unless value["schemaVersion"] == POLICY_SCHEMA
      reject!("remote controls policy phase") unless value["phase"] == PHASE
      reject!("remote controls policy configuration")
    end
    exact_object(
      value,
      "remote controls policy",
      %w[actors approval configured phase release repository schemaVersion]
    )
    reject!("remote controls policy schema") unless value["schemaVersion"] == POLICY_SCHEMA
    reject!("remote controls policy phase") unless value["phase"] == PHASE
    reject!("remote controls policy configuration") unless value["configured"] == true

    repository = validate_policy_repository(value["repository"])
    release = validate_policy_release(value["release"])
    actors = exact_object(value["actors"], "policy actors", %w[operator reviewer])
    operator = actor(actors["operator"], "policy operator", configured: true)
    reviewer = actor(actors["reviewer"], "policy reviewer", configured: true)
    expected_full_name = "#{operator.fetch('login')}/#{repository.fetch('name')}"
    reject!("policy repository identity") unless repository["fullName"] == expected_full_name

    approval = exact_object(
      value["approval"],
      "policy approval",
      %w[mode preventSelfReview requiredApprovals]
    )
    exact_boolean(approval["preventSelfReview"], "policy approval")
    reject!("policy approval") unless approval["requiredApprovals"].is_a?(Integer)
    case approval["mode"]
    when "independent-review"
      reject!("policy approval") if same_actor?(operator, reviewer)
      reject!("policy approval") unless approval["preventSelfReview"] == true &&
                                          approval["requiredApprovals"] == 1
    when "one-maintainer"
      reject!("policy approval") unless same_actor?(operator, reviewer)
      reject!("policy approval") unless approval["preventSelfReview"] == false &&
                                          approval["requiredApprovals"] == 0
    else
      reject!("policy approval")
    end

    {
      schema: :v1,
      repository: repository,
      release: release,
      operator: operator,
      reviewer: reviewer,
      approval: approval
    }
  end

  def policy_ci_checks(policy)
    ci = policy.dig(:release, "ci")
    return ci.fetch("checks") unless policy.fetch(:schema) == :v1

    [{ "name" => ci.fetch("name"), "appId" => ci.fetch("appId") }]
  end

  def compare_repository(value, policy)
    exact_object(
      value,
      "repository evidence",
      %w[archived defaultBranch description disabled fullName hasDiscussions homepage id name nodeId owner private topics visibility]
    )
    actor(value["owner"], "repository owner")
    exact_boolean(value["private"], "repository evidence")
    expected = policy.fetch(:repository)
    %w[id nodeId name fullName visibility defaultBranch archived disabled description hasDiscussions homepage topics].each do |key|
      reject!("repository evidence") unless value[key] == expected[key]
    end
    reject!("repository evidence") unless value["private"] == false
    reject!("repository owner") unless same_actor?(value["owner"], policy.fetch(:operator))
  end

  def validate_anchor_workflow(value, label, expected:, expected_blob:, expected_name:, expected_path:,
                               expected_triggers:, expected_state: "active")
    workflow = exact_object(value, label, %w[blobSha id name path state triggers])
    reject!(label) unless workflow["id"] == expected["id"] &&
                          workflow["name"] == expected_name &&
                          workflow["path"] == expected_path &&
                          workflow["state"] == expected_state &&
                          workflow["blobSha"] == expected_blob &&
                          workflow["triggers"] == expected_triggers
    workflow
  end

  def validate_anchors(value, policy, expected_commit:, expected_workflow_blob:, expected_ci_workflow_blob:)
    reads = exact_array(value, "anchor reads", length: 2)
    expected_release_workflow = policy.dig(:release, "workflow")
    expected_ci_workflow = policy.dig(:release, "ci", "workflow")
    reads.each_with_index do |read, index|
      exact_object(read, "anchor read", %w[ciWorkflow master releaseWorkflow sequence])
      reject!("anchor read sequence") unless read["sequence"] == index + 1
      master = exact_object(read["master"], "master anchor", %w[commitSha ref])
      reject!("master anchor") unless master["ref"] == MASTER_REF &&
                                         master["commitSha"] == expected_commit
      validate_anchor_workflow(
        read["releaseWorkflow"],
        "release workflow anchor",
        expected: expected_release_workflow,
        expected_blob: expected_workflow_blob,
        expected_name: RELEASE_WORKFLOW_NAME,
        expected_path: RELEASE_WORKFLOW_PATH,
        expected_triggers: ["workflow_dispatch"]
      )
      validate_anchor_workflow(
        read["ciWorkflow"],
        "CI workflow anchor",
        expected: expected_ci_workflow,
        expected_blob: expected_ci_workflow_blob,
        expected_name: CI_WORKFLOW_NAME,
        expected_path: CI_WORKFLOW_PATH,
        expected_triggers: CI_WORKFLOW_TRIGGERS
      )
    end
    reject!("anchor reads") unless reads[0]["master"] == reads[1]["master"] &&
                                    reads[0]["releaseWorkflow"] == reads[1]["releaseWorkflow"] &&
                                    reads[0]["ciWorkflow"] == reads[1]["ciWorkflow"]
  end

  def validate_workflow(value, label, expected:, expected_commit:, expected_blob:, expected_name:,
                        expected_path:, expected_triggers:)
    exact_object(
      value,
      label,
      %w[blobSha commitSha id name path state triggers]
    )
    reject!(label) unless value["id"] == expected["id"] &&
                          value["name"] == expected_name &&
                          value["path"] == expected_path &&
                          value["state"] == "active" &&
                          value["commitSha"] == expected_commit &&
                          value["blobSha"] == expected_blob &&
                          value["triggers"] == expected_triggers
  end

  def conditions(value, label, expected_ref)
    exact_object(value, label, %w[exclude include])
    reject!(label) unless value["include"] == [expected_ref] && value["exclude"] == []
  end

  def rule_map(value, label)
    rules = exact_array(value, label)
    mapped = {}
    rules.each do |rule|
      reject!(label) unless rule.is_a?(Hash) && rule["type"].is_a?(String)
      reject!(label) if mapped.key?(rule["type"])
      mapped[rule["type"]] = rule
    end
    mapped
  end

  def parameterless_rule(rule, label, expected_type)
    exact_object(rule, label, %w[type])
    reject!(label) unless rule["type"] == expected_type
  end

  def validate_ruleset_base(value, label, target:, expected_ref:, repository_full_name:)
    exact_object(
      value,
      label,
      %w[bypassActors conditions enforcement id name rules source sourceType target]
    )
    positive_integer(value["id"], label)
    exact_string(value["name"], label, max_bytes: 100)
    reject!(label) unless value["target"] == target && value["enforcement"] == "active"
    reject!(label) unless value["sourceType"] == "Repository" && value["source"] == repository_full_name
    conditions(value["conditions"], label, expected_ref)
  end

  def validate_master_ruleset(value, policy)
    label = "master ruleset"
    validate_ruleset_base(
      value,
      label,
      target: "branch",
      expected_ref: MASTER_REF,
      repository_full_name: policy.dig(:repository, "fullName")
    )
    reject!(label) unless value["bypassActors"] == []
    rules = rule_map(value["rules"], label)
    expected_types = %w[
      deletion
      non_fast_forward
      pull_request
      required_status_checks
    ]
    reject!(label) unless rules.keys.sort == expected_types.sort
    %w[deletion non_fast_forward].each do |type|
      parameterless_rule(rules.fetch(type), label, type)
    end

    pull_request = exact_object(rules.fetch("pull_request"), label, %w[parameters type])
    parameters = exact_object(
      pull_request["parameters"],
      label,
      %w[dismissStaleReviewsOnPush requireCodeOwnerReview requireLastPushApproval requiredApprovingReviewCount requiredReviewThreadResolution]
    )
    approval = policy.fetch(:approval)
    reject!(label) unless parameters["requiredApprovingReviewCount"] == approval["requiredApprovals"] &&
                          parameters["dismissStaleReviewsOnPush"] == true &&
                          parameters["requireCodeOwnerReview"] == false &&
                          parameters["requiredReviewThreadResolution"] == true &&
                          parameters["requireLastPushApproval"] == (approval["mode"] == "independent-review")

    status = exact_object(rules.fetch("required_status_checks"), label, %w[parameters type])
    status_parameters = exact_object(
      status["parameters"],
      label,
      %w[doNotEnforceOnCreate requiredStatusChecks strictRequiredStatusChecksPolicy]
    )
    expected_checks = policy_ci_checks(policy).map do |check|
      { "context" => check.fetch("name"), "integrationId" => check.fetch("appId") }
    end
    checks = exact_array(
      status_parameters["requiredStatusChecks"],
      label,
      length: expected_checks.length
    ).map { |value| exact_object(value, label, %w[context integrationId]) }
    reject!(label) unless status_parameters["strictRequiredStatusChecksPolicy"] == true &&
                          status_parameters["doNotEnforceOnCreate"] == false &&
                          checks == expected_checks
  end

  def validate_tag_rulesets(values, policy)
    exact_array(values, "tag rulesets", length: 2)
    rulesets = values.map do |value|
      validate_ruleset_base(
        value,
        "tag ruleset",
        target: "tag",
        expected_ref: TAG_PATTERN,
        repository_full_name: policy.dig(:repository, "fullName")
      )
      [value, rule_map(value["rules"], "tag ruleset")]
    end
    creation_entries = rulesets.select { |_value, rules| rules.keys == ["creation"] }
    immutable_entries = rulesets.select { |_value, rules| rules.keys.sort == %w[deletion update] }
    reject!("tag rulesets") unless creation_entries.length == 1 && immutable_entries.length == 1

    creation, creation_rules = creation_entries.first
    parameterless_rule(creation_rules.fetch("creation"), "tag creation ruleset", "creation")
    bypasses = exact_array(creation["bypassActors"], "tag creation bypass", length: 1)
    bypass = exact_object(bypasses.first, "tag creation bypass", %w[actor bypassMode])
    reject!("tag creation bypass") unless bypass["bypassMode"] == "always"
    actor(bypass["actor"], "tag creation bypass actor")
    reject!("tag creation bypass actor") unless same_actor?(bypass["actor"], policy.fetch(:operator))

    immutable, immutable_rules = immutable_entries.first
    reject!("tag immutability ruleset") unless immutable["bypassActors"] == []
    update_rule = exact_object(
      immutable_rules.fetch("update"),
      "tag immutability ruleset",
      %w[parameters type]
    )
    update_parameters = exact_object(
      update_rule["parameters"],
      "tag immutability ruleset",
      %w[updateAllowsFetchAndMerge]
    )
    reject!("tag immutability ruleset") unless update_parameters["updateAllowsFetchAndMerge"] == false
    parameterless_rule(immutable_rules.fetch("deletion"), "tag immutability ruleset", "deletion")
  end

  def validate_rulesets(value, policy)
    exact_object(value, "ruleset evidence", %w[complete effectiveMaster master tags])
    reject!("ruleset evidence") unless value["complete"] == true
    master = exact_array(value["master"], "master rulesets", length: 1)
    validate_master_ruleset(master.first, policy)
    validate_effective_master(value["effectiveMaster"], master.first, policy)
    validate_tag_rulesets(value["tags"], policy)
    ids = master.concat(value["tags"]).map { |ruleset| ruleset["id"] }
    reject!("ruleset evidence") unless ids.uniq.length == ids.length
  end

  def validate_effective_master(value, master_ruleset, policy)
    exact_object(value, "effective master rules", %w[complete items])
    reject!("effective master rules") unless value["complete"] == true
    expected_rules = master_ruleset.fetch("rules").to_h { |rule| [rule.fetch("type"), rule] }
    items = exact_array(value["items"], "effective master rules", length: expected_rules.length)
    observed_rules = {}
    items.each do |item|
      exact_object(item, "effective master rule", %w[rule rulesetId source sourceType])
      reject!("effective master rule") unless item["rulesetId"] == master_ruleset["id"] &&
                                                item["sourceType"] == "Repository" &&
                                                item["source"] == policy.dig(:repository, "fullName")
      rule = item["rule"]
      reject!("effective master rule") unless rule.is_a?(Hash) && rule["type"].is_a?(String)
      reject!("effective master rules") if observed_rules.key?(rule["type"])
      observed_rules[rule["type"]] = rule
    end
    reject!("effective master rules") unless observed_rules == expected_rules
  end

  def validate_environment(value, policy)
    exact_object(
      value,
      "release environment",
      %w[deployment name protection secrets variables]
    )
    reject!("release environment") unless value["name"] == RELEASE_ENVIRONMENT
    protection = exact_object(value["protection"], "environment protection", %w[preventSelfReview reviewers])
    reject!("environment protection") unless protection["preventSelfReview"] ==
                                                 policy.dig(:approval, "preventSelfReview")
    reviewers = exact_array(protection["reviewers"], "environment reviewers", length: 1)
    actor(reviewers.first, "environment reviewer")
    reject!("environment reviewer") unless same_actor?(reviewers.first, policy.fetch(:reviewer))

    deployment = exact_object(
      value["deployment"],
      "environment deployment policy",
      %w[customBranchPolicies policies protectedBranches]
    )
    reject!("environment deployment policy") unless deployment["protectedBranches"] == false &&
                                                       deployment["customBranchPolicies"] == true
    policies = exact_array(deployment["policies"], "environment deployment policy", length: 1)
    exact_object(policies.first, "environment deployment policy", %w[name type])
    reject!("environment deployment policy") unless policies.first == { "name" => TAG, "type" => "tag" }

    secrets = named_collection(value["secrets"], "environment secret names")
    variables = named_collection(value["variables"], "environment variable names")
    reject!("environment secret names") unless secrets == REQUIRED_ENVIRONMENT_SECRETS
    reject!("environment variable names") unless variables == REQUIRED_ENVIRONMENT_VARIABLES
  end

  def validate_repository_configuration(value)
    exact_object(value, "repository configuration names", %w[secrets variables])
    secrets = named_collection(value["secrets"], "repository secret names")
    variables = named_collection(value["variables"], "repository variable names")
    reject!("repository secret shadowing") unless (secrets & REQUIRED_ENVIRONMENT_SECRETS).empty?
    reject!("repository variable shadowing") unless (variables & REQUIRED_ENVIRONMENT_VARIABLES).empty?
  end

  def validate_security(value)
    exact_object(value, "security controls", %w[immutableReleases privateVulnerabilityReporting])
    reject!("private vulnerability reporting") unless value["privateVulnerabilityReporting"] == true
    immutable = exact_object(value["immutableReleases"], "immutable releases", %w[enabled enforcedByOwner])
    exact_boolean(immutable["enforcedByOwner"], "immutable releases")
    reject!("immutable releases") unless immutable["enabled"] == true
  end

  def validate_actions(value)
    exact_object(
      value,
      "Actions controls",
      %w[allowedActions enabled selectedActions shaPinningRequired workflowPermissions]
    )
    reject!("Actions controls") unless value["enabled"] == true &&
                                        value["allowedActions"] == "selected" &&
                                        value["shaPinningRequired"] == true
    selected = exact_object(
      value["selectedActions"],
      "selected Actions policy",
      %w[githubOwnedAllowed patternsAllowed verifiedAllowed]
    )
    reject!("selected Actions policy") unless selected["githubOwnedAllowed"] == true &&
                                                selected["verifiedAllowed"] == false &&
                                                selected["patternsAllowed"] == []
    permissions = exact_object(
      value["workflowPermissions"],
      "workflow token policy",
      %w[canApprovePullRequestReviews defaultWorkflowPermissions]
    )
    reject!("workflow token policy") unless permissions["defaultWorkflowPermissions"] == "read" &&
                                              permissions["canApprovePullRequestReviews"] == false
  end

  def validate_labels(value)
    exact_object(value, "required labels", %w[needsTriage])
    label = exact_object(value["needsTriage"], "needs-triage label", %w[name present])
    reject!("needs-triage label") unless label["name"] == "needs-triage" && label["present"] == true
  end

  def validate_authenticated_viewer(value, policy)
    exact_object(value, "authenticated viewer", %w[actor repositoryPermission])
    actor(value["actor"], "authenticated viewer actor")
    reject!("authenticated viewer actor") unless same_actor?(value["actor"], policy.fetch(:operator))
    reject!("authenticated viewer permission") unless value["repositoryPermission"] == "admin"
  end

  def empty_complete_collection(value, label)
    exact_object(value, label, %w[complete items])
    reject!(label) unless value["complete"] == true && value["items"] == []
  end

  def validate_release_boundary(value)
    exact_object(value, "pre-tag release boundary", %w[releases vRefs])
    empty_complete_collection(value["vRefs"], "v tag references")
    empty_complete_collection(value["releases"], "GitHub releases")
  end

  def complete_single_item(value, label)
    collection = exact_object(value, label, %w[complete items])
    reject!(label) unless collection["complete"] == true
    exact_array(collection["items"], label, length: 1).first
  end

  def validate_ci(value, policy, expected_commit:)
    exact_object(value, "CI evidence", %w[checkRuns commitSha jobs workflowRuns])
    reject!("CI evidence") unless value["commitSha"] == expected_commit
    expected_ci = policy.dig(:release, "ci")
    expected_checks = policy_ci_checks(policy)
    expected_check_names = expected_checks.map { |check| check.fetch("name") }
    expected_apps_by_name = expected_checks.to_h do |check|
      [check.fetch("name"), check.fetch("appId")]
    end

    check_collection = exact_object(value["checkRuns"], "CI check runs", %w[complete items])
    reject!("CI check runs") unless check_collection["complete"] == true
    checks = exact_array(
      check_collection["items"],
      "CI check runs",
      length: expected_checks.length
    ).map do |item|
      check = exact_object(
        item,
        "required CI check",
        %w[appId checkSuiteId conclusion headSha id name status]
      )
      %w[id appId checkSuiteId].each do |key|
        positive_integer(check[key], "required CI check")
      end
      %w[name status conclusion].each do |key|
        exact_string(check[key], "required CI check")
      end
      sha(check["headSha"], "required CI check")
      check
    end
    reject!("CI check runs") unless checks.map { |check| check["name"] }.sort == expected_check_names
    reject!("CI check runs") unless checks.map { |check| check["id"] }.uniq.length == checks.length
    check_suite_ids = checks.map { |check| check["checkSuiteId"] }.uniq
    reject!("CI check runs") unless check_suite_ids.length == 1
    check_suite_id = check_suite_ids.first

    workflow_runs = exact_object(value["workflowRuns"], "CI workflow runs", %w[complete items])
    reject!("CI workflow runs") unless workflow_runs["complete"] == true
    run_items = exact_array(workflow_runs["items"], "CI workflow runs")
    reject!("CI workflow runs") if run_items.empty?
    runs = run_items.map do |item|
      run = exact_object(
        item,
        "CI workflow run",
        %w[checkSuiteId conclusion event headBranch headSha id path runAttempt status workflowId]
      )
      %w[id workflowId checkSuiteId runAttempt].each { |key| positive_integer(run[key], "CI workflow run") }
      %w[path event headBranch status conclusion].each do |key|
        exact_string(run[key], "CI workflow run")
      end
      sha(run["headSha"], "CI workflow run")
      reject!("CI workflow run") unless run["workflowId"] == expected_ci.dig("workflow", "id") &&
                                         run["checkSuiteId"] == check_suite_id &&
                                         run["path"] == CI_RUN_PATH &&
                                         run["event"] == "push" &&
                                         run["headBranch"] == DEFAULT_BRANCH &&
                                         run["headSha"] == expected_commit
      run
    end
    reject!("CI workflow runs") unless runs.map { |run| [run["id"], run["runAttempt"]] }.uniq.length == runs.length
    reject!("CI workflow runs") unless runs.map { |run| run["id"] }.uniq.length == 1
    latest_attempt = runs.map { |run| run["runAttempt"] }.max
    latest_runs = runs.select { |run| run["runAttempt"] == latest_attempt }
    reject!("CI workflow runs") unless latest_runs.length == 1
    run = latest_runs.first
    reject!("required CI workflow run") unless run["status"] == "completed" &&
                                               run["conclusion"] == "success"

    job_collection = exact_object(value["jobs"], "CI jobs", %w[complete items])
    reject!("CI jobs") unless job_collection["complete"] == true
    jobs = exact_array(
      job_collection["items"],
      "CI jobs",
      length: expected_checks.length
    ).map do |item|
      job = exact_object(
        item,
        "required CI job",
        %w[checkRunId conclusion headBranch headSha id name runAttempt runId status workflowName]
      )
      %w[id runId runAttempt checkRunId].each do |key|
        positive_integer(job[key], "required CI job")
      end
      %w[name workflowName headBranch status conclusion].each do |key|
        exact_string(job[key], "required CI job")
      end
      sha(job["headSha"], "required CI job")
      job
    end
    reject!("CI jobs") unless jobs.map { |job| job["name"] }.sort == expected_check_names
    reject!("CI jobs") unless jobs.map { |job| job["id"] }.uniq.length == jobs.length
    checks_by_name = checks.to_h { |check| [check["name"], check] }
    jobs.each do |job|
      reject!("required CI job") unless job["runId"] == run["id"] &&
                                         job["runAttempt"] == run["runAttempt"] &&
                                         job["workflowName"] == CI_WORKFLOW_NAME &&
                                         job["headBranch"] == DEFAULT_BRANCH &&
                                         job["headSha"] == expected_commit &&
                                         job["status"] == "completed" &&
                                         job["conclusion"] == "success"

      check = checks_by_name.fetch(job["name"])
      reject!("required CI check") unless check["id"] == job["checkRunId"] &&
                                             check["appId"] == expected_apps_by_name.fetch(job["name"]) &&
                                             check["checkSuiteId"] == run["checkSuiteId"] &&
                                             check["headSha"] == job["headSha"] &&
                                             check["status"] == job["status"] &&
                                             check["conclusion"] == job["conclusion"]
    end
  end

  def validate_evidence(value, policy, expected_commit:, expected_workflow_blob:, expected_ci_workflow_blob:)
    exact_object(
      value,
      "remote controls evidence",
      %w[actions anchorReads authenticatedViewer ci ciWorkflow environment labels phase releaseBoundary repository repositoryConfiguration rulesets schemaVersion security workflow]
    )
    reject!("remote controls evidence schema") unless value["schemaVersion"] == EVIDENCE_SCHEMA
    reject!("remote controls evidence phase") unless value["phase"] == PHASE
    compare_repository(value["repository"], policy)
    validate_authenticated_viewer(value["authenticatedViewer"], policy)
    validate_anchors(
      value["anchorReads"],
      policy,
      expected_commit: expected_commit,
      expected_workflow_blob: expected_workflow_blob,
      expected_ci_workflow_blob: expected_ci_workflow_blob
    )
    validate_workflow(
      value["workflow"],
      "release workflow evidence",
      expected: policy.dig(:release, "workflow"),
      expected_commit: expected_commit,
      expected_blob: expected_workflow_blob,
      expected_name: RELEASE_WORKFLOW_NAME,
      expected_path: RELEASE_WORKFLOW_PATH,
      expected_triggers: ["workflow_dispatch"]
    )
    validate_workflow(
      value["ciWorkflow"],
      "CI workflow evidence",
      expected: policy.dig(:release, "ci", "workflow"),
      expected_commit: expected_commit,
      expected_blob: expected_ci_workflow_blob,
      expected_name: CI_WORKFLOW_NAME,
      expected_path: CI_WORKFLOW_PATH,
      expected_triggers: CI_WORKFLOW_TRIGGERS
    )
    validate_rulesets(value["rulesets"], policy)
    validate_environment(value["environment"], policy)
    validate_repository_configuration(value["repositoryConfiguration"])
    validate_security(value["security"])
    validate_actions(value["actions"])
    validate_labels(value["labels"])
    validate_release_boundary(value["releaseBoundary"])
    validate_ci(value["ci"], policy, expected_commit: expected_commit)
    true
  end

  # v2 is a release-lifecycle contract. It preserves the one-time final-pre-tag
  # observation while also supporting a fresh pre-publication observation after
  # the exact draft exists. The publication workflow and environment are part of
  # the authoritative policy rather than being inferred from the observation.
  def validate_policy_workflow_v2(value, label, expected_name:, expected_path:)
    workflow = exact_object(value, label, %w[blobSha id name path])
    positive_integer(workflow["id"], label)
    sha(workflow["blobSha"], label)
    reject!(label) unless workflow["name"] == expected_name && workflow["path"] == expected_path
    workflow
  end

  def validate_policy_release_v2(value, schema: :v2)
    release_keys = %w[candidateWorkflow ci legacyWorkflow publicationWorkflow tag version]
    release_keys << "predecessorTag" if schema == :v3
    exact_object(
      value,
      "lifecycle policy release",
      release_keys
    )
    reject!("v2 policy release") unless value["version"] == VERSION && value["tag"] == TAG
    reject!("v3 policy predecessor tag") if schema == :v3 && value["predecessorTag"] != PREDECESSOR_TAG
    candidate = validate_policy_workflow_v2(
      value["candidateWorkflow"],
      "v2 candidate workflow",
      expected_name: RELEASE_WORKFLOW_NAME,
      expected_path: RELEASE_WORKFLOW_PATH
    )
    publication = validate_policy_workflow_v2(
      value["publicationWorkflow"],
      "v2 publication workflow",
      expected_name: PUBLICATION_WORKFLOW_NAME,
      expected_path: PUBLICATION_WORKFLOW_PATH
    )
    legacy = validate_policy_workflow_v2(
      value["legacyWorkflow"],
      "v2 legacy workflow",
      expected_name: LEGACY_WORKFLOW_NAME,
      expected_path: LEGACY_WORKFLOW_PATH
    )
    ci = exact_object(value["ci"], "v2 policy CI", %w[checks workflow])
    checks = exact_array(
      ci["checks"],
      "v2 policy CI checks",
      length: REQUIRED_CHECK_NAMES.length
    ).map do |item|
      check = exact_object(item, "v2 policy CI check", %w[appId name])
      exact_string(check["name"], "v2 policy CI check", max_bytes: 256)
      positive_integer(check["appId"], "v2 policy CI check")
      check
    end
    expected_checks = REQUIRED_CHECK_NAMES.map do |name|
      { "name" => name, "appId" => GITHUB_ACTIONS_APP_ID }
    end
    reject!("v2 policy CI checks") unless checks == expected_checks
    ci_workflow = validate_policy_workflow_v2(
      ci["workflow"],
      "v2 CI workflow",
      expected_name: CI_WORKFLOW_NAME,
      expected_path: CI_WORKFLOW_PATH
    )
    ids = [candidate["id"], ci_workflow["id"], publication["id"], legacy["id"]]
    reject!("v2 policy workflow identities") unless ids.uniq.length == 4
    value
  end

  def validate_manual_evidence_v2(value, expected: nil)
    exact_object(value, "manual release-control evidence", %w[complete items])
    reject!("manual release-control evidence") unless value["complete"] == true
    items = exact_array(value["items"], "manual release-control evidence", length: 2)
    normalized = items.map do |item|
      exact_object(item, "manual release-control item", %w[control sha256])
      control = exact_string(item["control"], "manual release-control item", max_bytes: 160)
      digest = sha256(item["sha256"], "manual release-control item")
      { "control" => control, "sha256" => digest }
    end
    reject!("manual release-control evidence") unless
      normalized.map { |item| item["control"] } == MANUAL_CONTROLS &&
      normalized.map { |item| item["sha256"] }.uniq.length == 2
    if expected
      reject!("manual release-control evidence") unless
        normalized.map { |item| item["control"] } == expected["items"].map { |item| item["control"] }
    end
    { "complete" => true, "items" => normalized }
  end

  def validate_policy_manual_controls_v2(value)
    exact_object(value, "manual release-control policy", %w[complete items])
    reject!("manual release-control policy") unless value["complete"] == true
    items = exact_array(value["items"], "manual release-control policy", length: 2)
    normalized = items.map do |item|
      exact_object(item, "manual release-control policy item", %w[control path schemaVersion])
      {
        "control" => exact_string(item["control"], "manual release-control policy item", max_bytes: 160),
        "path" => exact_string(item["path"], "manual release-control policy item", max_bytes: 256),
        "schemaVersion" => exact_string(
          item["schemaVersion"], "manual release-control policy item", max_bytes: 160
        )
      }
    end
    reject!("manual release-control policy") unless
      normalized.map { |item| item["control"] } == MANUAL_CONTROLS &&
      normalized.map { |item| item["path"] } == MANUAL_EVIDENCE_PATHS &&
      normalized.all? { |item| item["schemaVersion"] == MANUAL_EVIDENCE_SCHEMA }
    { "complete" => true, "items" => normalized }
  end

  def validate_policy_v2(value, schema: :v2)
    expected_schema = schema == :v3 ? POLICY_SCHEMA_V3 : POLICY_SCHEMA_V2
    label = schema == :v3 ? "v3" : "v2"
    if value.is_a?(Hash) && value["configured"] == false
      exact_object(value, "#{label} remote controls policy preamble", %w[configured phase schemaVersion])
      reject!("#{label} remote controls policy schema") unless value["schemaVersion"] == expected_schema
      reject!("#{label} remote controls policy phase") unless value["phase"] == LIFECYCLE_PHASE
      reject!("remote controls policy configuration")
    end
    exact_object(
      value,
      "#{label} remote controls policy",
      %w[actors approval configured manualEvidence phase release repository schemaVersion]
    )
    reject!("#{label} remote controls policy schema") unless value["schemaVersion"] == expected_schema
    reject!("#{label} remote controls policy phase") unless value["phase"] == LIFECYCLE_PHASE
    reject!("remote controls policy configuration") unless value["configured"] == true

    repository = validate_policy_repository(value["repository"])
    release = validate_policy_release_v2(value["release"], schema: schema)
    actors = exact_object(value["actors"], "v2 policy actors", %w[operator publisher reviewer])
    operator = actor(actors["operator"], "v2 policy operator", configured: true)
    reviewer = actor(actors["reviewer"], "v2 policy reviewer", configured: true)
    publisher = actor(actors["publisher"], "v2 policy publisher", configured: true)
    owner, repository_name = repository["fullName"].split("/", 2)
    reject!("v2 policy repository identity") unless repository_name == repository["name"] &&
                                                    owner&.casecmp?(operator["login"])

    approval = exact_object(
      value["approval"],
      "v2 policy approval",
      %w[mode preventSelfReview requiredApprovals]
    )
    exact_boolean(approval["preventSelfReview"], "v2 policy approval")
    reject!("v2 policy approval") unless approval["requiredApprovals"].is_a?(Integer)
    case approval["mode"]
    when "independent-review"
      reject!("v2 policy approval") unless same_actor?(operator, publisher)
      reject!("v2 policy approval") if same_actor?(reviewer, publisher)
      reject!("v2 policy approval") unless approval["preventSelfReview"] == true &&
                                             approval["requiredApprovals"] == 1
    when "one-maintainer"
      reject!("v2 policy approval") unless same_actor?(operator, reviewer) &&
                                             same_actor?(operator, publisher)
      reject!("v2 policy approval") unless approval["preventSelfReview"] == false &&
                                             approval["requiredApprovals"] == 0
    else
      reject!("v2 policy approval")
    end
    manual_evidence = validate_policy_manual_controls_v2(value["manualEvidence"])
    {
      schema: schema,
      repository: repository,
      release: release,
      operator: operator,
      reviewer: reviewer,
      publisher: publisher,
      approval: approval,
      manual_evidence: manual_evidence
    }
  end

  def validate_anchor_workflow_v2(value, label, expected:, expected_blob:, expected_name:,
                                  expected_path:, expected_triggers:, expected_state: "active")
    validate_anchor_workflow(
      value,
      label,
      expected: expected,
      expected_blob: expected_blob,
      expected_name: expected_name,
      expected_path: expected_path,
      expected_triggers: expected_triggers,
      expected_state: expected_state
    )
  end

  def validate_anchors_v2(value, policy, expected_commit:, expected_workflow_blob:,
                          expected_ci_workflow_blob:, expected_publication_workflow_blob:,
                          expected_legacy_workflow_blob:)
    reads = exact_array(value, "v2 anchor reads", length: 2)
    expected_candidate = policy.dig(:release, "candidateWorkflow")
    expected_ci = policy.dig(:release, "ci", "workflow")
    expected_publication = policy.dig(:release, "publicationWorkflow")
    expected_legacy = policy.dig(:release, "legacyWorkflow")
    reads.each_with_index do |read, index|
      exact_object(
        read,
        "v2 anchor read",
        %w[candidateWorkflow ciWorkflow legacyWorkflow master publicationWorkflow sequence]
      )
      reject!("v2 anchor read sequence") unless read["sequence"] == index + 1
      master = exact_object(read["master"], "v2 master anchor", %w[commitSha ref])
      reject!("v2 master anchor") unless master == {
        "ref" => MASTER_REF,
        "commitSha" => expected_commit
      }
      validate_anchor_workflow_v2(
        read["candidateWorkflow"], "v2 candidate workflow anchor",
        expected: expected_candidate, expected_blob: expected_workflow_blob,
        expected_name: RELEASE_WORKFLOW_NAME, expected_path: RELEASE_WORKFLOW_PATH,
        expected_triggers: ["workflow_dispatch"]
      )
      validate_anchor_workflow_v2(
        read["legacyWorkflow"], "v2 legacy workflow anchor",
        expected: expected_legacy, expected_blob: expected_legacy_workflow_blob,
        expected_name: LEGACY_WORKFLOW_NAME, expected_path: LEGACY_WORKFLOW_PATH,
        expected_triggers: ["workflow_dispatch"], expected_state: "disabled_manually"
      )
      validate_anchor_workflow_v2(
        read["ciWorkflow"], "v2 CI workflow anchor",
        expected: expected_ci, expected_blob: expected_ci_workflow_blob,
        expected_name: CI_WORKFLOW_NAME, expected_path: CI_WORKFLOW_PATH,
        expected_triggers: CI_WORKFLOW_TRIGGERS
      )
      validate_anchor_workflow_v2(
        read["publicationWorkflow"], "v2 publication workflow anchor",
        expected: expected_publication, expected_blob: expected_publication_workflow_blob,
        expected_name: PUBLICATION_WORKFLOW_NAME, expected_path: PUBLICATION_WORKFLOW_PATH,
        expected_triggers: ["workflow_dispatch"]
      )
    end
    reject!("v2 anchor reads") unless reads[0].except("sequence") == reads[1].except("sequence")
  end

  def validate_workflow_v2(value, label, expected:, expected_commit:, expected_blob:,
                           expected_name:, expected_path:, expected_triggers:, contents_write:,
                           expected_state: "active")
    exact_object(value, label, %w[blobSha commitSha contentsWrite id name path state triggers])
    exact_boolean(value["contentsWrite"], label)
    reject!(label) unless value["id"] == expected["id"] && value["name"] == expected_name &&
                          value["path"] == expected_path && value["state"] == expected_state &&
                          value["commitSha"] == expected_commit && value["blobSha"] == expected_blob &&
                          value["triggers"] == expected_triggers &&
                          value["contentsWrite"] == contents_write
    value
  end

  def validate_workflow_inventory_v2(value, workflows)
    exact_object(value, "active workflow inventory", %w[complete items])
    reject!("active workflow inventory") unless value["complete"] == true
    items = exact_array(value["items"], "complete workflow inventory", length: 4)
    items.each do |item|
      exact_object(
        item,
        "active workflow inventory item",
        %w[blobSha commitSha contentsWrite id name path state triggers]
      )
    end
    reject!("complete workflow inventory") unless items == workflows.sort_by { |item| item["path"] }
    states = items.to_h { |item| [item["path"], item["state"]] }
    reject!("complete workflow inventory") unless states == {
      CI_WORKFLOW_PATH => "active",
      LEGACY_WORKFLOW_PATH => "disabled_manually",
      PUBLICATION_WORKFLOW_PATH => "active",
      RELEASE_WORKFLOW_PATH => "active"
    }
    reject!("complete workflow inventory") unless items.map { |item| item["id"] }.uniq.length == 4 &&
                                                     items.map { |item| item["path"] }.uniq.length == 4 &&
                                                     items.map { |item| item["name"] }.uniq.length == 4
    write_paths = items.select { |item| item["contentsWrite"] }.map { |item| item["path"] }.sort
    reject!("active workflow inventory") unless write_paths == [RELEASE_WORKFLOW_PATH, PUBLICATION_WORKFLOW_PATH].sort
  end

  def validate_environment_v2(value, policy, label:, name:, required_secrets:, required_variables:,
                              expected_policies: [{ "name" => TAG, "type" => "tag" }])
    exact_object(value, label, %w[deployment name protection secrets variables])
    reject!(label) unless value["name"] == name
    protection = exact_object(value["protection"], "#{label} protection", %w[preventSelfReview reviewers])
    reject!("#{label} protection") unless protection["preventSelfReview"] ==
                                             policy.dig(:approval, "preventSelfReview")
    reviewers = exact_array(protection["reviewers"], "#{label} reviewers", length: 1)
    actor(reviewers.first, "#{label} reviewer")
    reject!("#{label} reviewer") unless same_actor?(reviewers.first, policy.fetch(:reviewer))
    deployment = exact_object(
      value["deployment"], "#{label} deployment", %w[customBranchPolicies policies protectedBranches]
    )
    reject!("#{label} deployment") unless deployment["protectedBranches"] == false &&
                                            deployment["customBranchPolicies"] == true
    policies = exact_array(
      deployment["policies"], "#{label} deployment", length: expected_policies.length
    )
    policies.each { |policy| exact_object(policy, "#{label} deployment", %w[name type]) }
    reject!("#{label} deployment") unless policies == expected_policies
    reject!("#{label} secrets") unless named_collection(value["secrets"], "#{label} secrets") == required_secrets
    reject!("#{label} variables") unless named_collection(value["variables"], "#{label} variables") == required_variables
  end

  def validate_repository_configuration_v2(value)
    exact_object(value, "v2 repository configuration names", %w[secrets variables])
    secrets = named_collection(value["secrets"], "v2 repository secret names")
    variables = named_collection(value["variables"], "v2 repository variable names")
    all_secrets = REQUIRED_ENVIRONMENT_SECRETS + REQUIRED_PUBLICATION_SECRETS
    all_variables = REQUIRED_ENVIRONMENT_VARIABLES + REQUIRED_PUBLICATION_VARIABLES
    reject!("v2 repository secret shadowing") unless (secrets & all_secrets).empty?
    reject!("v2 repository variable shadowing") unless (variables & all_variables).empty?
  end

  def validate_release_boundary_v2(value, phase:, expected_release_commit:, expected_release_id:,
                                   expected_release_tag_object:)
    exact_object(value, "v2 release boundary", %w[releases vRefs])
    if phase == PHASE
      empty_complete_collection(value["vRefs"], "v2 v tag references")
      empty_complete_collection(value["releases"], "v2 GitHub releases")
      return
    end
    reject!("v2 pre-publication release boundary") unless phase == PRE_PUBLICATION_PHASE
    ref = complete_single_item(value["vRefs"], "v2 pre-publication tag references")
    exact_object(ref, "v2 pre-publication tag reference", %w[commitSha objectSha objectType ref])
    sha(ref["objectSha"], "v2 pre-publication tag reference")
    sha(ref["commitSha"], "v2 pre-publication tag reference")
    reject!("v2 pre-publication tag reference") unless ref["objectType"] == "tag"
    reject!("v2 pre-publication tag reference") unless ref["ref"] == "refs/tags/#{TAG}" &&
                                                        ref["commitSha"] == expected_release_commit &&
                                                        ref["objectSha"] == expected_release_tag_object
    release = complete_single_item(value["releases"], "v2 pre-publication releases")
    exact_object(release, "v2 pre-publication release", %w[draft id prerelease tag])
    positive_integer(release["id"], "v2 pre-publication release")
    reject!("v2 pre-publication release") unless release == {
      "id" => expected_release_id,
      "tag" => TAG,
      "draft" => true,
      "prerelease" => true
    }
  end

  def validate_evidence_v2(value, policy, expected_commit:, expected_workflow_blob:,
                           expected_ci_workflow_blob:, expected_publication_workflow_blob:,
                           expected_legacy_workflow_blob:,
                           expected_release_commit:, expected_release_id:,
                           expected_release_tag_object:)
    exact_object(
      value,
      "v2 remote controls evidence",
      %w[actions anchorReads authenticatedViewer candidateWorkflow ci ciWorkflow collectedAt environments finalPreTagEvidenceSHA256 labels legacyWorkflow manualEvidence phase publicationWorkflow releaseBoundary repository repositoryConfiguration rulesets schemaVersion security workflowInventory]
    )
    reject!("v2 remote controls evidence schema") unless value["schemaVersion"] == EVIDENCE_SCHEMA_V2
    phase = value["phase"]
    reject!("v2 remote controls evidence phase") unless [PHASE, PRE_PUBLICATION_PHASE].include?(phase)
    collected_at = value["collectedAt"]
    reject!("v2 collected timestamp") unless collected_at.is_a?(String) && collected_at.bytesize <= 32
    begin
      collected_time = Time.iso8601(collected_at)
    rescue ArgumentError
      reject!("v2 collected timestamp")
    end
    reject!("v2 collected timestamp") unless collected_at == collected_time.utc.iso8601
    if phase == PRE_PUBLICATION_PHASE
      sha256(value["finalPreTagEvidenceSHA256"], "final-pre-tag evidence digest")
      sha(expected_release_commit, "expected release commit anchor")
      sha(expected_release_tag_object, "expected release tag object anchor")
      positive_integer(expected_release_id, "expected release ID anchor")
    else
      reject!("unexpected final-pre-tag evidence digest") unless value["finalPreTagEvidenceSHA256"].nil?
      reject!("unexpected pre-publication anchors") if expected_release_commit || expected_release_id ||
                                                       expected_release_tag_object
    end
    compare_repository(value["repository"], policy)
    validate_authenticated_viewer(value["authenticatedViewer"], policy)
    validate_anchors_v2(
      value["anchorReads"], policy,
      expected_commit: expected_commit,
      expected_workflow_blob: expected_workflow_blob,
      expected_ci_workflow_blob: expected_ci_workflow_blob,
      expected_publication_workflow_blob: expected_publication_workflow_blob,
      expected_legacy_workflow_blob: expected_legacy_workflow_blob
    )
    candidate = validate_workflow_v2(
      value["candidateWorkflow"], "v2 candidate workflow evidence",
      expected: policy.dig(:release, "candidateWorkflow"), expected_commit: expected_commit,
      expected_blob: expected_workflow_blob, expected_name: RELEASE_WORKFLOW_NAME,
      expected_path: RELEASE_WORKFLOW_PATH, expected_triggers: ["workflow_dispatch"],
      contents_write: true
    )
    ci_workflow = validate_workflow_v2(
      value["ciWorkflow"], "v2 CI workflow evidence",
      expected: policy.dig(:release, "ci", "workflow"), expected_commit: expected_commit,
      expected_blob: expected_ci_workflow_blob, expected_name: CI_WORKFLOW_NAME,
      expected_path: CI_WORKFLOW_PATH, expected_triggers: CI_WORKFLOW_TRIGGERS,
      contents_write: false
    )
    publication = validate_workflow_v2(
      value["publicationWorkflow"], "v2 publication workflow evidence",
      expected: policy.dig(:release, "publicationWorkflow"), expected_commit: expected_commit,
      expected_blob: expected_publication_workflow_blob, expected_name: PUBLICATION_WORKFLOW_NAME,
      expected_path: PUBLICATION_WORKFLOW_PATH, expected_triggers: ["workflow_dispatch"],
      contents_write: true
    )
    legacy = validate_workflow_v2(
      value["legacyWorkflow"], "v2 legacy workflow evidence",
      expected: policy.dig(:release, "legacyWorkflow"), expected_commit: expected_commit,
      expected_blob: expected_legacy_workflow_blob, expected_name: LEGACY_WORKFLOW_NAME,
      expected_path: LEGACY_WORKFLOW_PATH, expected_triggers: ["workflow_dispatch"],
      contents_write: false, expected_state: "disabled_manually"
    )
    validate_workflow_inventory_v2(
      value["workflowInventory"], [candidate, ci_workflow, publication, legacy]
    )
    validate_rulesets(value["rulesets"], policy)
    environments = exact_object(
      value["environments"], "v2 release environments", %w[releaseCandidate releasePublication]
    )
    validate_environment_v2(
      environments["releaseCandidate"], policy, label: "release-candidate environment",
      name: RELEASE_ENVIRONMENT, required_secrets: REQUIRED_ENVIRONMENT_SECRETS,
      required_variables: REQUIRED_ENVIRONMENT_VARIABLES
    )
    validate_environment_v2(
      environments["releasePublication"], policy, label: "release-publication environment",
      name: "release-publication", required_secrets: REQUIRED_PUBLICATION_SECRETS,
      required_variables: REQUIRED_PUBLICATION_VARIABLES
    )
    validate_repository_configuration_v2(value["repositoryConfiguration"])
    validate_manual_evidence_v2(value["manualEvidence"], expected: policy.fetch(:manual_evidence))
    validate_security(value["security"])
    validate_actions(value["actions"])
    validate_labels(value["labels"])
    validate_release_boundary_v2(
      value["releaseBoundary"], phase: phase,
      expected_release_commit: expected_release_commit,
      expected_release_id: expected_release_id,
      expected_release_tag_object: expected_release_tag_object
    )
    validate_ci(value["ci"], policy, expected_commit: expected_commit)
    true
  end

  def complete_items(value, label, length: nil)
    collection = exact_object(value, label, %w[complete items])
    reject!(label) unless collection["complete"] == true
    exact_array(collection["items"], label, length: length)
  end

  def validate_release_ref_v3(value, label, tag:, expected_commit:, expected_tag_object:)
    exact_object(value, label, %w[commitSha objectSha objectType ref])
    sha(value["commitSha"], label)
    sha(value["objectSha"], label)
    reject!(label) unless value == {
      "ref" => "refs/tags/#{tag}",
      "objectType" => "tag",
      "objectSha" => expected_tag_object,
      "commitSha" => expected_commit
    }
    value
  end

  def validate_release_boundary_v3(value, phase:, expected_predecessor_commit:,
                                   expected_predecessor_tag_object:, expected_release_commit:,
                                   expected_release_id:, expected_release_tag_object:)
    exact_object(value, "v3 release boundary", %w[releases vRefs])
    refs = complete_items(value["vRefs"], "v3 tag references")
    releases = complete_items(value["releases"], "v3 GitHub releases")
    case phase
    when PREDECESSOR_PRE_TAG_PHASE
      reject!("v3 predecessor-pre-tag boundary") unless refs.empty? && releases.empty?
    when PHASE
      reject!("v3 final-pre-tag references") unless refs.length == 1
      validate_release_ref_v3(
        refs.first, "v3 predecessor tag reference", tag: PREDECESSOR_TAG,
        expected_commit: expected_predecessor_commit,
        expected_tag_object: expected_predecessor_tag_object
      )
      reject!("v3 predecessor GitHub releases") unless releases.empty?
    when PRE_PUBLICATION_PHASE
      reject!("v3 pre-publication references") unless refs.length == 2
      validate_release_ref_v3(
        refs.fetch(0), "v3 predecessor tag reference", tag: PREDECESSOR_TAG,
        expected_commit: expected_predecessor_commit,
        expected_tag_object: expected_predecessor_tag_object
      )
      validate_release_ref_v3(
        refs.fetch(1), "v3 release tag reference", tag: TAG,
        expected_commit: expected_release_commit,
        expected_tag_object: expected_release_tag_object
      )
      reject!("v3 pre-publication releases") unless releases.length == 1
      release = exact_object(
        releases.first, "v3 pre-publication release", %w[draft id prerelease tag]
      )
      positive_integer(release["id"], "v3 pre-publication release")
      reject!("v3 pre-publication release") unless release == {
        "id" => expected_release_id,
        "tag" => TAG,
        "draft" => true,
        "prerelease" => true
      }
    else
      reject!("v3 release boundary phase")
    end
  end

  def validate_evidence_v3(value, policy, expected_phase:, expected_commit:,
                           expected_workflow_blob:, expected_ci_workflow_blob:,
                           expected_publication_workflow_blob:, expected_legacy_workflow_blob:,
                           expected_predecessor_commit:, expected_predecessor_tag_object:,
                           expected_predecessor_pre_tag_evidence_sha256:,
                           expected_release_commit:, expected_release_id:,
                           expected_release_tag_object:, expected_final_pre_tag_evidence_sha256:)
    exact_object(
      value,
      "v3 remote controls evidence",
      %w[actions anchorReads authenticatedViewer candidateWorkflow ci ciWorkflow collectedAt environments finalPreTagEvidenceSHA256 labels legacyWorkflow manualEvidence phase predecessorPreTagEvidenceSHA256 publicationWorkflow releaseBoundary repository repositoryConfiguration rulesets schemaVersion security workflowInventory]
    )
    reject!("v3 remote controls evidence schema") unless value["schemaVersion"] == EVIDENCE_SCHEMA_V3
    phases = [PREDECESSOR_PRE_TAG_PHASE, PHASE, PRE_PUBLICATION_PHASE]
    reject!("v3 expected phase") unless phases.include?(expected_phase)
    reject!("v3 remote controls evidence phase") unless value["phase"] == expected_phase
    collected_at = value["collectedAt"]
    reject!("v3 collected timestamp") unless collected_at.is_a?(String) && collected_at.bytesize <= 32
    begin
      collected_time = Time.iso8601(collected_at)
    rescue ArgumentError
      reject!("v3 collected timestamp")
    end
    reject!("v3 collected timestamp") unless collected_at == collected_time.utc.iso8601

    predecessor_digest = value["predecessorPreTagEvidenceSHA256"]
    final_digest = value["finalPreTagEvidenceSHA256"]
    case expected_phase
    when PREDECESSOR_PRE_TAG_PHASE
      reject!("v3 predecessor-pre-tag digest") unless predecessor_digest.nil? && final_digest.nil?
      reject!("v3 predecessor-pre-tag anchors") if expected_predecessor_commit ||
                                                     expected_predecessor_tag_object ||
                                                     expected_predecessor_pre_tag_evidence_sha256 ||
                                                     expected_release_commit || expected_release_id ||
                                                     expected_release_tag_object ||
                                                     expected_final_pre_tag_evidence_sha256
    when PHASE
      sha(expected_predecessor_commit, "expected predecessor commit anchor")
      sha(expected_predecessor_tag_object, "expected predecessor tag object anchor")
      sha256(
        expected_predecessor_pre_tag_evidence_sha256,
        "expected predecessor-pre-tag evidence digest"
      )
      reject!("v3 predecessor-pre-tag evidence digest") unless
        predecessor_digest == expected_predecessor_pre_tag_evidence_sha256 && final_digest.nil?
      reject!("v3 final-pre-tag release anchors") if expected_release_commit || expected_release_id ||
                                                      expected_release_tag_object ||
                                                      expected_final_pre_tag_evidence_sha256
    when PRE_PUBLICATION_PHASE
      sha(expected_predecessor_commit, "expected predecessor commit anchor")
      sha(expected_predecessor_tag_object, "expected predecessor tag object anchor")
      sha256(
        expected_predecessor_pre_tag_evidence_sha256,
        "expected predecessor-pre-tag evidence digest"
      )
      sha(expected_release_commit, "expected release commit anchor")
      sha(expected_release_tag_object, "expected release tag object anchor")
      positive_integer(expected_release_id, "expected release ID anchor")
      sha256(expected_final_pre_tag_evidence_sha256, "expected final-pre-tag evidence digest")
      reject!("v3 predecessor-pre-tag evidence digest") unless
        predecessor_digest == expected_predecessor_pre_tag_evidence_sha256
      reject!("v3 final-pre-tag evidence digest") unless
        final_digest == expected_final_pre_tag_evidence_sha256
    end

    compare_repository(value["repository"], policy)
    validate_authenticated_viewer(value["authenticatedViewer"], policy)
    validate_anchors_v2(
      value["anchorReads"], policy,
      expected_commit: expected_commit,
      expected_workflow_blob: expected_workflow_blob,
      expected_ci_workflow_blob: expected_ci_workflow_blob,
      expected_publication_workflow_blob: expected_publication_workflow_blob,
      expected_legacy_workflow_blob: expected_legacy_workflow_blob
    )
    candidate = validate_workflow_v2(
      value["candidateWorkflow"], "v3 candidate workflow evidence",
      expected: policy.dig(:release, "candidateWorkflow"), expected_commit: expected_commit,
      expected_blob: expected_workflow_blob, expected_name: RELEASE_WORKFLOW_NAME,
      expected_path: RELEASE_WORKFLOW_PATH, expected_triggers: ["workflow_dispatch"],
      contents_write: true
    )
    ci_workflow = validate_workflow_v2(
      value["ciWorkflow"], "v3 CI workflow evidence",
      expected: policy.dig(:release, "ci", "workflow"), expected_commit: expected_commit,
      expected_blob: expected_ci_workflow_blob, expected_name: CI_WORKFLOW_NAME,
      expected_path: CI_WORKFLOW_PATH, expected_triggers: CI_WORKFLOW_TRIGGERS,
      contents_write: false
    )
    publication = validate_workflow_v2(
      value["publicationWorkflow"], "v3 publication workflow evidence",
      expected: policy.dig(:release, "publicationWorkflow"), expected_commit: expected_commit,
      expected_blob: expected_publication_workflow_blob, expected_name: PUBLICATION_WORKFLOW_NAME,
      expected_path: PUBLICATION_WORKFLOW_PATH, expected_triggers: ["workflow_dispatch"],
      contents_write: true
    )
    legacy = validate_workflow_v2(
      value["legacyWorkflow"], "v3 legacy workflow evidence",
      expected: policy.dig(:release, "legacyWorkflow"), expected_commit: expected_commit,
      expected_blob: expected_legacy_workflow_blob, expected_name: LEGACY_WORKFLOW_NAME,
      expected_path: LEGACY_WORKFLOW_PATH, expected_triggers: ["workflow_dispatch"],
      contents_write: false, expected_state: "disabled_manually"
    )
    validate_workflow_inventory_v2(
      value["workflowInventory"], [candidate, ci_workflow, publication, legacy]
    )
    validate_rulesets(value["rulesets"], policy)
    environments = exact_object(
      value["environments"], "v3 release environments", %w[releaseCandidate releasePublication]
    )
    candidate_policies = [PREDECESSOR_TAG, TAG].map { |tag| { "name" => tag, "type" => "tag" } }
    validate_environment_v2(
      environments["releaseCandidate"], policy, label: "release-candidate environment",
      name: RELEASE_ENVIRONMENT, required_secrets: REQUIRED_ENVIRONMENT_SECRETS,
      required_variables: REQUIRED_ENVIRONMENT_VARIABLES,
      expected_policies: candidate_policies
    )
    validate_environment_v2(
      environments["releasePublication"], policy, label: "release-publication environment",
      name: "release-publication", required_secrets: REQUIRED_PUBLICATION_SECRETS,
      required_variables: REQUIRED_PUBLICATION_VARIABLES
    )
    validate_repository_configuration_v2(value["repositoryConfiguration"])
    validate_manual_evidence_v2(value["manualEvidence"], expected: policy.fetch(:manual_evidence))
    validate_security(value["security"])
    validate_actions(value["actions"])
    validate_labels(value["labels"])
    validate_release_boundary_v3(
      value["releaseBoundary"], phase: expected_phase,
      expected_predecessor_commit: expected_predecessor_commit,
      expected_predecessor_tag_object: expected_predecessor_tag_object,
      expected_release_commit: expected_release_commit,
      expected_release_id: expected_release_id,
      expected_release_tag_object: expected_release_tag_object
    )
    validate_ci(value["ci"], policy, expected_commit: expected_commit)
    true
  end

  # The trusted collector/wrapper must derive these anchors from a clean,
  # non-shallow local HEAD and its checked-in workflow. This offline validator
  # intentionally does not inspect the working tree or make network requests.
  def validate_expected_workflow_blobs(policy, expected_workflow_blob:, expected_ci_workflow_blob:,
                                       expected_publication_workflow_blob: nil,
                                       expected_legacy_workflow_blob: nil)
    sha(expected_workflow_blob, "expected workflow blob anchor")
    candidate_key = policy[:schema] == :v1 ? "workflow" : "candidateWorkflow"
    reject!("expected workflow blob anchor") unless expected_workflow_blob ==
                                                      policy.dig(:release, candidate_key, "blobSha")
    sha(expected_ci_workflow_blob, "expected CI workflow blob anchor")
    reject!("expected CI workflow blob anchor") unless expected_ci_workflow_blob ==
                                                         policy.dig(:release, "ci", "workflow", "blobSha")
    if policy[:schema] != :v1
      sha(expected_publication_workflow_blob, "expected publication workflow blob anchor")
      reject!("expected publication workflow blob anchor") unless expected_publication_workflow_blob ==
                                                                  policy.dig(:release, "publicationWorkflow", "blobSha")
      sha(expected_legacy_workflow_blob, "expected legacy workflow blob anchor")
      reject!("expected legacy workflow blob anchor") unless expected_legacy_workflow_blob ==
                                                             policy.dig(:release, "legacyWorkflow", "blobSha")
    elsif expected_publication_workflow_blob || expected_legacy_workflow_blob
      reject!("expected publication workflow blob anchor")
    end
  end

  def verify(policy_path:, evidence_path:, expected_commit:, expected_workflow_blob:, expected_ci_workflow_blob:,
             expected_publication_workflow_blob: nil, expected_legacy_workflow_blob: nil,
             expected_phase: nil, expected_predecessor_commit: nil,
             expected_predecessor_tag_object: nil,
             expected_predecessor_pre_tag_evidence_sha256: nil,
             expected_release_commit: nil, expected_release_id: nil,
             expected_release_tag_object: nil, expected_final_pre_tag_evidence_sha256: nil)
    policy = load_policy(policy_path)
    sha(expected_commit, "expected commit anchor")
    validate_expected_workflow_blobs(
      policy,
      expected_workflow_blob: expected_workflow_blob,
      expected_ci_workflow_blob: expected_ci_workflow_blob,
      expected_publication_workflow_blob: expected_publication_workflow_blob,
      expected_legacy_workflow_blob: expected_legacy_workflow_blob
    )
    evidence_value = ReleasePolicy.strict_json(evidence_path, "remote controls evidence", max_bytes: 4 * 1024 * 1024)
    if policy[:schema] == :v3
      validate_evidence_v3(
        evidence_value, policy,
        expected_phase: expected_phase,
        expected_commit: expected_commit,
        expected_workflow_blob: expected_workflow_blob,
        expected_ci_workflow_blob: expected_ci_workflow_blob,
        expected_publication_workflow_blob: expected_publication_workflow_blob,
        expected_legacy_workflow_blob: expected_legacy_workflow_blob,
        expected_predecessor_commit: expected_predecessor_commit,
        expected_predecessor_tag_object: expected_predecessor_tag_object,
        expected_predecessor_pre_tag_evidence_sha256:
          expected_predecessor_pre_tag_evidence_sha256,
        expected_release_commit: expected_release_commit,
        expected_release_id: expected_release_id,
        expected_release_tag_object: expected_release_tag_object,
        expected_final_pre_tag_evidence_sha256: expected_final_pre_tag_evidence_sha256
      )
      [:v3, evidence_value["phase"]]
    elsif policy[:schema] == :v2
      reject!("unexpected v3 lifecycle anchors") if expected_phase || expected_predecessor_commit ||
                                                     expected_predecessor_tag_object ||
                                                     expected_predecessor_pre_tag_evidence_sha256 ||
                                                     expected_final_pre_tag_evidence_sha256
      validate_evidence_v2(
        evidence_value, policy,
        expected_commit: expected_commit,
        expected_workflow_blob: expected_workflow_blob,
        expected_ci_workflow_blob: expected_ci_workflow_blob,
        expected_publication_workflow_blob: expected_publication_workflow_blob,
        expected_legacy_workflow_blob: expected_legacy_workflow_blob,
        expected_release_commit: expected_release_commit,
        expected_release_id: expected_release_id,
        expected_release_tag_object: expected_release_tag_object
      )
      [:v2, evidence_value["phase"]]
    else
      reject!("unexpected pre-publication anchors") if expected_phase || expected_predecessor_commit ||
                                                       expected_predecessor_tag_object ||
                                                       expected_predecessor_pre_tag_evidence_sha256 ||
                                                       expected_release_commit || expected_release_id ||
                                                       expected_release_tag_object ||
                                                       expected_final_pre_tag_evidence_sha256
      validate_evidence(
        evidence_value,
        policy,
        expected_commit: expected_commit,
        expected_workflow_blob: expected_workflow_blob,
        expected_ci_workflow_blob: expected_ci_workflow_blob
      )
      [:v1, PHASE]
    end
  end

  def load_policy(policy_path)
    policy_value = ReleasePolicy.strict_json(policy_path, "remote controls policy", max_bytes: 1024 * 1024)
    case policy_value.is_a?(Hash) && policy_value["schemaVersion"]
    when POLICY_SCHEMA_V3
      validate_policy_v2(policy_value, schema: :v3)
    when POLICY_SCHEMA_V2
      validate_policy_v2(policy_value)
    else
      validate_policy(policy_value).merge(schema: :v1)
    end
  end

  def publication_approval_contract(policy)
    reject!("publication approval contract") if policy[:schema] == :v1
    {
      "schemaVersion" => "desk-setup-switcher.publication-approval-contract/v1",
      "approvalMode" => policy.dig(:approval, "mode"),
      "operator" => policy.fetch(:operator).slice("id", "login", "type"),
      "reviewer" => policy.fetch(:reviewer).slice("id", "login", "type"),
      "publisher" => policy.fetch(:publisher).slice("id", "login", "type")
    }
  end

  def run_cli(argv)
    options = {}
    parser = OptionParser.new do |option|
      option.banner = "Usage: remote_controls_policy.rb (--check-policy FILE [workflow blob anchors] | --ci-workflow-id FILE [workflow blob anchors] | --publication-workflow-id FILE [workflow blob anchors] | --publication-approval-contract FILE | --policy FILE --evidence FILE --expected-commit SHA [workflow blob anchors] [lifecycle anchors])"
      option.separator "The evidence mode validates normalized data only; its trusted wrapper must bind a clean, non-shallow local HEAD."
      option.on("--check-policy FILE") { |value| options[:check_policy] = value }
      option.on("--ci-workflow-id FILE") { |value| options[:ci_workflow_id] = value }
      option.on("--publication-workflow-id FILE") { |value| options[:publication_workflow_id] = value }
      option.on("--publication-approval-contract FILE") do |value|
        options[:publication_approval_contract] = value
      end
      option.on("--policy FILE") { |value| options[:policy] = value }
      option.on("--evidence FILE") { |value| options[:evidence] = value }
      option.on("--expected-commit SHA") { |value| options[:expected_commit] = value }
      option.on("--expected-workflow-blob SHA") { |value| options[:expected_workflow_blob] = value }
      option.on("--expected-ci-workflow-blob SHA") { |value| options[:expected_ci_workflow_blob] = value }
      option.on("--expected-publication-workflow-blob SHA") { |value| options[:expected_publication_workflow_blob] = value }
      option.on("--expected-legacy-workflow-blob SHA") { |value| options[:expected_legacy_workflow_blob] = value }
      option.on("--expected-phase PHASE") { |value| options[:expected_phase] = value }
      option.on("--expected-predecessor-commit SHA") do |value|
        options[:expected_predecessor_commit] = value
      end
      option.on("--expected-predecessor-tag-object SHA") do |value|
        options[:expected_predecessor_tag_object] = value
      end
      option.on("--expected-predecessor-pre-tag-evidence-sha256 SHA256") do |value|
        options[:expected_predecessor_pre_tag_evidence_sha256] = value
      end
      option.on("--expected-release-commit SHA") { |value| options[:expected_release_commit] = value }
      option.on("--expected-release-id ID") { |value| options[:expected_release_id] = value }
      option.on("--expected-release-tag-object SHA") do |value|
        options[:expected_release_tag_object] = value
      end
      option.on("--expected-final-pre-tag-evidence-sha256 SHA256") do |value|
        options[:expected_final_pre_tag_evidence_sha256] = value
      end
      option.on("-h", "--help") do
        puts option
        return 0
      end
    end
    begin
      parser.parse!(argv)
    rescue OptionParser::ParseError
      raise PolicyError, "invalid command options"
    end
    raise PolicyError, "unexpected positional arguments" unless argv.empty?

    if options[:publication_approval_contract]
      disallowed = options.keys - [:publication_approval_contract]
      raise PolicyError, "command options are mutually exclusive" unless disallowed.empty?
      contract = publication_approval_contract(load_policy(options.fetch(:publication_approval_contract)))
      puts JSON.generate(contract)
      return 0
    end

    workflow_id_policy = options[:ci_workflow_id] || options[:publication_workflow_id]
    if workflow_id_policy
      if options[:ci_workflow_id] && options[:publication_workflow_id]
        raise PolicyError, "command options are mutually exclusive"
      end
      if options[:check_policy] || options[:policy] || options[:evidence] || options[:expected_commit] ||
         options[:expected_phase] || options[:expected_predecessor_commit] ||
         options[:expected_predecessor_tag_object] ||
         options[:expected_predecessor_pre_tag_evidence_sha256] ||
         options[:expected_release_commit] || options[:expected_release_id] ||
         options[:expected_release_tag_object] || options[:expected_final_pre_tag_evidence_sha256]
        raise PolicyError, "command options are mutually exclusive"
      end
      unless options[:expected_workflow_blob] && options[:expected_ci_workflow_blob]
        raise PolicyError, "required command option is missing"
      end
      policy = load_policy(workflow_id_policy)
      validate_expected_workflow_blobs(
        policy,
        expected_workflow_blob: options[:expected_workflow_blob],
        expected_ci_workflow_blob: options[:expected_ci_workflow_blob],
        expected_publication_workflow_blob: options[:expected_publication_workflow_blob],
        expected_legacy_workflow_blob: options[:expected_legacy_workflow_blob]
      )
      if options[:publication_workflow_id]
        reject!("publication workflow ID mode") if policy[:schema] == :v1
        puts policy.dig(:release, "publicationWorkflow", "id")
      else
        puts policy.dig(:release, "ci", "workflow", "id")
      end
      return 0
    end

    if options[:check_policy]
      if options[:policy] || options[:evidence] || options[:expected_commit] ||
         options[:expected_phase] || options[:expected_predecessor_commit] ||
         options[:expected_predecessor_tag_object] ||
         options[:expected_predecessor_pre_tag_evidence_sha256] ||
         options[:expected_release_commit] || options[:expected_release_id] ||
         options[:expected_release_tag_object] || options[:expected_final_pre_tag_evidence_sha256]
        raise PolicyError, "command options are mutually exclusive"
      end
      policy = load_policy(options[:check_policy])
      if options[:expected_workflow_blob] || options[:expected_ci_workflow_blob] ||
         options[:expected_publication_workflow_blob] || options[:expected_legacy_workflow_blob]
        unless options[:expected_workflow_blob] && options[:expected_ci_workflow_blob]
          raise PolicyError, "required command option is missing"
        end
        validate_expected_workflow_blobs(
          policy,
          expected_workflow_blob: options[:expected_workflow_blob],
          expected_ci_workflow_blob: options[:expected_ci_workflow_blob],
          expected_publication_workflow_blob: options[:expected_publication_workflow_blob],
          expected_legacy_workflow_blob: options[:expected_legacy_workflow_blob]
        )
        puts "OK remote-controls policy workflow-blobs-bound"
      else
        puts "OK remote-controls policy"
      end
      return 0
    end
    unless options[:policy] && options[:evidence] && options[:expected_commit] &&
           options[:expected_workflow_blob] && options[:expected_ci_workflow_blob]
      raise PolicyError, "required command option is missing"
    end

    schema, phase = verify(
      policy_path: options[:policy],
      evidence_path: options[:evidence],
      expected_commit: options[:expected_commit],
      expected_workflow_blob: options[:expected_workflow_blob],
      expected_ci_workflow_blob: options[:expected_ci_workflow_blob],
      expected_publication_workflow_blob: options[:expected_publication_workflow_blob],
      expected_legacy_workflow_blob: options[:expected_legacy_workflow_blob],
      expected_phase: options[:expected_phase],
      expected_predecessor_commit: options[:expected_predecessor_commit],
      expected_predecessor_tag_object: options[:expected_predecessor_tag_object],
      expected_predecessor_pre_tag_evidence_sha256:
        options[:expected_predecessor_pre_tag_evidence_sha256],
      expected_release_commit: options[:expected_release_commit],
      expected_release_tag_object: options[:expected_release_tag_object],
      expected_final_pre_tag_evidence_sha256: options[:expected_final_pre_tag_evidence_sha256],
      expected_release_id: options[:expected_release_id]&.then do |value|
        reject!("expected release ID anchor") unless value.match?(/\A[1-9][0-9]*\z/)
        Integer(value, 10)
      end
    )
    if schema != :v1
      puts "OK remote-controls normalized-evidence phase=#{phase} manual_gates=2"
    else
      puts "OK remote-controls normalized-evidence manual_gates=1"
    end
    0
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit RemoteControlsPolicy.run_cli(ARGV.dup)
  rescue RemoteControlsPolicy::PolicyError => error
    warn "ERROR: #{error.message}"
    exit 1
  rescue StandardError
    warn "ERROR: remote controls policy validation failed"
    exit 70
  end
end
