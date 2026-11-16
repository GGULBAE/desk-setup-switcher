#!/usr/bin/env ruby
# frozen_string_literal: true

require "open3"
require_relative "run_test_suites"

# The CI entry point runs exactly the two existing commands and succeeds only
# after both commands and their pinned source anchors have passed.
class CIVerification
  class InvalidSource < StandardError; end

  def initialize(root:, environment: ENV, output: $stdout)
    @root = File.realpath(root)
    @environment = environment
    @output = output
    @hosted = environment["GITHUB_ACTIONS"] == "true"
    @event = @hosted ? environment.fetch("GITHUB_EVENT_NAME") : "local"
    raise InvalidSource unless %w[local push pull_request workflow_dispatch].include?(@event)

    @app_commit = @hosted ? environment.fetch("GITHUB_SHA") : git(@root, "rev-parse", "HEAD")
    @audit_commit = @hosted ? environment.fetch("PUBLIC_HISTORY_AUDIT_COMMIT") : @app_commit
    raise InvalidSource unless [@app_commit, @audit_commit].all? { |value| value.match?(/\A[0-9a-f]{40}\z/) }
    raise InvalidSource if @event != "pull_request" && @audit_commit != @app_commit

    @audit_root = @event == "pull_request" ? File.realpath(File.join(@root, ".build/public-history-audit")) : @root
  end

  def run
    validate_sources
    checks = [
      ReleaseTestSuites::Suite.new("app-verification", ["make", "verify"], @root),
      ReleaseTestSuites::Suite.new("public-history-audit", ["make", "audit-public-release"], @audit_root)
    ]
    status = ReleaseTestSuites.new(checks, jobs: 2, output: @output,
                                  prefix: "ci-checks", summary: "CI checks", noun: "checks",
                                  termination_grace: 5).run
    return status unless status.zero?

    validate_sources
    @output.puts("CI app verification and public-history audit passed.")
    0
  rescue InvalidSource, KeyError, SystemCallError
    @output.puts("CI verification failed: source checkout or commit anchor mismatch.")
    1
  end

  private

  def git(directory, *arguments)
    stdout, _stderr, status = Open3.capture3("git", "-C", directory, *arguments)
    raise InvalidSource unless status.success?

    stdout.strip
  end

  def validate_sources
    [[@root, @app_commit], [@audit_root, @audit_commit]].uniq.each do |directory, commit|
      raise InvalidSource unless File.realpath(git(directory, "rev-parse", "--show-toplevel")) == directory
      raise InvalidSource unless git(directory, "rev-parse", "HEAD") == commit
      raise InvalidSource unless git(directory, "rev-parse", "--is-shallow-repository") == "false"
      raise InvalidSource if @hosted && !git(directory, "status", "--porcelain=v1", "--untracked-files=no").empty?
    end
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    exit CIVerification.new(root: File.expand_path("../..", __dir__)).run
  rescue CIVerification::InvalidSource, KeyError, SystemCallError
    warn "CI verification failed: invalid CI source selection."
    exit 1
  end
end
