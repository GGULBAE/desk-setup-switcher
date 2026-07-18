#!/usr/bin/env ruby
# frozen_string_literal: true

require "optparse"
require "uri"
require_relative "release_policy"

# Verifies a normalized, value-free snapshot of the GitHub controls that must
# exist immediately before the v0.1.0 tag is created. The policy and evidence
# are separate inputs so the expected public identities cannot be inferred from
# the observation being checked. Both inputs use closed v1 schemas: unknown,
# missing, or duplicate keys fail validation.
module RemoteControlsPolicy
  POLICY_SCHEMA = "desk-setup-switcher.remote-release-controls-policy/v1"
  EVIDENCE_SCHEMA = "desk-setup-switcher.remote-release-controls-evidence/v1"
  PHASE = "final-pre-tag"
  VERSION = "0.1.0"
  TAG = "v0.1.0"
  DEFAULT_BRANCH = "master"
  RELEASE_ENVIRONMENT = "release-candidate"
  RELEASE_WORKFLOW_NAME = "Signed release candidate"
  RELEASE_WORKFLOW_PATH = ".github/workflows/release.yml"
  CI_WORKFLOW_NAME = "CI"
  CI_WORKFLOW_PATH = ".github/workflows/ci.yml"
  CI_RUN_PATH = CI_WORKFLOW_PATH
  CI_WORKFLOW_TRIGGERS = %w[pull_request push workflow_dispatch].freeze
  REQUIRED_CHECK_NAME = "Verify macOS app"
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
      left["login"] == right["login"] &&
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

    { repository: repository, release: release, operator: operator, reviewer: reviewer, approval: approval }
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
                               expected_triggers:)
    workflow = exact_object(value, label, %w[blobSha id name path state triggers])
    reject!(label) unless workflow["id"] == expected["id"] &&
                          workflow["name"] == expected_name &&
                          workflow["path"] == expected_path &&
                          workflow["state"] == "active" &&
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
    checks = exact_array(status_parameters["requiredStatusChecks"], label, length: 1)
    check = exact_object(checks.first, label, %w[context integrationId])
    reject!(label) unless status_parameters["strictRequiredStatusChecksPolicy"] == true &&
                          status_parameters["doNotEnforceOnCreate"] == false &&
                          check["context"] == REQUIRED_CHECK_NAME &&
                          check["integrationId"] == GITHUB_ACTIONS_APP_ID
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

    check = exact_object(
      complete_single_item(value["checkRuns"], "CI check runs"),
      "required CI check",
      %w[appId checkSuiteId conclusion headSha id name status]
    )
    %w[id appId checkSuiteId].each { |key| positive_integer(check[key], "required CI check") }
    %w[name status conclusion].each { |key| exact_string(check[key], "required CI check") }
    sha(check["headSha"], "required CI check")

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
                                         run["checkSuiteId"] == check["checkSuiteId"] &&
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

    job = exact_object(
      complete_single_item(value["jobs"], "CI jobs"),
      "required CI job",
      %w[checkRunId conclusion headBranch headSha id name runAttempt runId status workflowName]
    )
    %w[id runId runAttempt checkRunId].each { |key| positive_integer(job[key], "required CI job") }
    %w[name workflowName headBranch status conclusion].each do |key|
      exact_string(job[key], "required CI job")
    end
    sha(job["headSha"], "required CI job")
    reject!("required CI job") unless job["runId"] == run["id"] &&
                                      job["runAttempt"] == run["runAttempt"] &&
                                      job["name"] == expected_ci["name"] &&
                                      job["workflowName"] == CI_WORKFLOW_NAME &&
                                      job["headBranch"] == DEFAULT_BRANCH &&
                                      job["headSha"] == expected_commit &&
                                      job["status"] == "completed" &&
                                      job["conclusion"] == "success"

    reject!("required CI check") unless check["id"] == job["checkRunId"] &&
                                           check["name"] == job["name"] &&
                                           check["appId"] == expected_ci["appId"] &&
                                           check["checkSuiteId"] == run["checkSuiteId"] &&
                                           check["headSha"] == job["headSha"] &&
                                           check["status"] == job["status"] &&
                                           check["conclusion"] == job["conclusion"]
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

  # The trusted collector/wrapper must derive these anchors from a clean,
  # non-shallow local HEAD and its checked-in workflow. This offline validator
  # intentionally does not inspect the working tree or make network requests.
  def validate_expected_workflow_blobs(policy, expected_workflow_blob:, expected_ci_workflow_blob:)
    sha(expected_workflow_blob, "expected workflow blob anchor")
    reject!("expected workflow blob anchor") unless expected_workflow_blob ==
                                                      policy.dig(:release, "workflow", "blobSha")
    sha(expected_ci_workflow_blob, "expected CI workflow blob anchor")
    reject!("expected CI workflow blob anchor") unless expected_ci_workflow_blob ==
                                                         policy.dig(:release, "ci", "workflow", "blobSha")
  end

  def verify(policy_path:, evidence_path:, expected_commit:, expected_workflow_blob:, expected_ci_workflow_blob:)
    policy = load_policy(policy_path)
    sha(expected_commit, "expected commit anchor")
    validate_expected_workflow_blobs(
      policy,
      expected_workflow_blob: expected_workflow_blob,
      expected_ci_workflow_blob: expected_ci_workflow_blob
    )
    evidence_value = ReleasePolicy.strict_json(evidence_path, "remote controls evidence", max_bytes: 4 * 1024 * 1024)
    validate_evidence(
      evidence_value,
      policy,
      expected_commit: expected_commit,
      expected_workflow_blob: expected_workflow_blob,
      expected_ci_workflow_blob: expected_ci_workflow_blob
    )
  end

  def load_policy(policy_path)
    policy_value = ReleasePolicy.strict_json(policy_path, "remote controls policy", max_bytes: 1024 * 1024)
    validate_policy(policy_value)
  end

  def run_cli(argv)
    options = {}
    parser = OptionParser.new do |option|
      option.banner = "Usage: remote_controls_policy.rb (--check-policy FILE [--expected-workflow-blob SHA --expected-ci-workflow-blob SHA] | --ci-workflow-id FILE --expected-workflow-blob SHA --expected-ci-workflow-blob SHA | --policy FILE --evidence FILE --expected-commit SHA --expected-workflow-blob SHA --expected-ci-workflow-blob SHA)"
      option.separator "The evidence mode validates normalized data only; its trusted wrapper must bind a clean, non-shallow local HEAD."
      option.on("--check-policy FILE") { |value| options[:check_policy] = value }
      option.on("--ci-workflow-id FILE") { |value| options[:ci_workflow_id] = value }
      option.on("--policy FILE") { |value| options[:policy] = value }
      option.on("--evidence FILE") { |value| options[:evidence] = value }
      option.on("--expected-commit SHA") { |value| options[:expected_commit] = value }
      option.on("--expected-workflow-blob SHA") { |value| options[:expected_workflow_blob] = value }
      option.on("--expected-ci-workflow-blob SHA") { |value| options[:expected_ci_workflow_blob] = value }
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

    if options[:ci_workflow_id]
      if options[:check_policy] || options[:policy] || options[:evidence] || options[:expected_commit]
        raise PolicyError, "command options are mutually exclusive"
      end
      unless options[:expected_workflow_blob] && options[:expected_ci_workflow_blob]
        raise PolicyError, "required command option is missing"
      end
      policy = load_policy(options[:ci_workflow_id])
      validate_expected_workflow_blobs(
        policy,
        expected_workflow_blob: options[:expected_workflow_blob],
        expected_ci_workflow_blob: options[:expected_ci_workflow_blob]
      )
      puts policy.dig(:release, "ci", "workflow", "id")
      return 0
    end

    if options[:check_policy]
      if options[:policy] || options[:evidence] || options[:expected_commit]
        raise PolicyError, "command options are mutually exclusive"
      end
      policy = load_policy(options[:check_policy])
      if options[:expected_workflow_blob] || options[:expected_ci_workflow_blob]
        unless options[:expected_workflow_blob] && options[:expected_ci_workflow_blob]
          raise PolicyError, "required command option is missing"
        end
        validate_expected_workflow_blobs(
          policy,
          expected_workflow_blob: options[:expected_workflow_blob],
          expected_ci_workflow_blob: options[:expected_ci_workflow_blob]
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

    verify(
      policy_path: options[:policy],
      evidence_path: options[:evidence],
      expected_commit: options[:expected_commit],
      expected_workflow_blob: options[:expected_workflow_blob],
      expected_ci_workflow_blob: options[:expected_ci_workflow_blob]
    )
    puts "OK remote-controls normalized-evidence manual_gates=1"
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
