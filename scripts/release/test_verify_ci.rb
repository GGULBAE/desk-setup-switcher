#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "timeout"
require "tmpdir"
require "yaml"

assertions = 0
check = lambda do |condition, label|
  raise "CI verification regression: #{label}" unless condition

  assertions += 1
end
git = lambda do |root, *args|
  output, error, status = Open3.capture3("git", "-C", root, *args)
  raise "Fixture Git failed" unless status.success?

  output.strip
end

Dir.mktmpdir("desk-setup-ci-gate-tests.") do |temporary|
  temporary = File.realpath(temporary)
  fixture_number = 0
  fixture = lambda do |event = "push"|
    fixture_number += 1
    root = File.join(temporary, "source-#{fixture_number}")
    state = File.join(temporary, "state-#{fixture_number}")
    FileUtils.mkdir_p([File.join(root, "scripts/release"), state])
    %w[verify_ci.rb run_test_suites.rb].each do |name|
      FileUtils.cp(File.join(__dir__, name), File.join(root, "scripts/release", name))
    end
    File.write(File.join(root, ".gitignore"), ".build/\n")
    File.write(File.join(root, "source.txt"), "head-source")
    File.write(File.join(root, "Makefile"), <<~MAKE.gsub("RECIPE ", "\t"))
      .PHONY: verify audit-public-release
      verify:
      RECIPE @#{RbConfig.ruby} fixture_worker.rb verify
      audit-public-release:
      RECIPE @#{RbConfig.ruby} fixture_worker.rb audit
    MAKE
    File.write(File.join(root, "fixture_worker.rb"), <<~'RUBY')
      require "json"
      require "rbconfig"
      lane = ARGV.fetch(0)
      state = ENV.fetch("CI_TEST_STATE")
      File.write(File.join(state, "#{lane}-start"), JSON.generate({
        "cwd" => Dir.pwd, "source" => File.read("source.txt"),
        "temporary" => ENV.fetch("TMPDIR"), "pid" => Process.pid
      }))
      deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
      until %w[verify audit].all? { |name| File.exist?(File.join(state, "#{name}-start")) }
        abort "Checks did not overlap" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
        sleep 0.01
      end
      if ENV["CI_TEST_BLOCK"] == "1"
        if lane == "verify"
          require_relative "scripts/release/run_test_suites"
          leaf = ReleaseTestSuites::Suite.new("nested-leaf", [RbConfig.ruby, "fixture_leaf.rb"], Dir.pwd)
          exit ReleaseTestSuites.new([leaf], jobs: 1).run
        end
        sleep 30
      end
      File.write("source.txt", "drift") if ENV["CI_TEST_DIRTY"] == lane
      if ENV["CI_TEST_COMMIT_DRIFT"] == lane
        system("git", "commit", "-q", "--allow-empty", "-m", "fixture anchor drift") || abort("Git fixture failed")
      end
      puts "checked-#{lane}"
      exit Integer(ENV.fetch("CI_TEST_EXIT_#{lane.upcase}", "0"), 10)
    RUBY
    File.write(File.join(root, "fixture_leaf.rb"), <<~'RUBY')
      Signal.trap("TERM") {}
      File.write(File.join(ENV.fetch("CI_TEST_STATE"), "leaf-pid"), Process.pid.to_s)
      sleep 30
    RUBY
    git.call(root, "init", "-q", "-b", "master")
    git.call(root, "config", "user.name", "Synthetic CI Fixture")
    git.call(root, "config", "user.email", "ci-fixture@example.invalid")
    git.call(root, "config", "commit.gpgsign", "false")
    git.call(root, "add", ".")
    git.call(root, "commit", "-q", "-m", "fixture source")
    audit_commit = git.call(root, "rev-parse", "HEAD")
    audit_root = root
    if event == "pull_request"
      audit_root = File.join(root, ".build/public-history-audit")
      FileUtils.mkdir_p(File.dirname(audit_root))
      git.call(root, "clone", "-q", "--no-hardlinks", root, audit_root)
      File.write(File.join(root, "source.txt"), "merge-source")
      git.call(root, "add", "source.txt")
      git.call(root, "commit", "-q", "-m", "fixture merge source")
    end
    environment = {
      "GITHUB_ACTIONS" => "true", "GITHUB_EVENT_NAME" => event,
      "GITHUB_SHA" => git.call(root, "rev-parse", "HEAD"),
      "PUBLIC_HISTORY_AUDIT_COMMIT" => audit_commit, "CI_TEST_STATE" => state,
      "CI_TEST_BLOCK" => "0", "CI_TEST_DIRTY" => "", "CI_TEST_COMMIT_DRIFT" => "",
      "CI_TEST_EXIT_VERIFY" => "0", "CI_TEST_EXIT_AUDIT" => "0"
    }
    [root, audit_root, state, environment]
  end
  invoke = lambda do |data, overrides = {}|
    root, _audit, state, environment = data
    stdout, stderr, status = Open3.capture3(environment.merge(overrides), RbConfig.ruby,
                                           File.join(root, "scripts/release/verify_ci.rb"), chdir: root)
    File.write(File.join(state, "upload"), "allowed") if status.success?
    [status, stdout + stderr]
  end

  %w[push workflow_dispatch pull_request].each do |event|
    data = fixture.call(event)
    root, audit, state, = data
    status, output = invoke.call(data)
    check.call(status.success?, "both checks must pass for #{event}")
    verify = JSON.parse(File.read(File.join(state, "verify-start")))
    history = JSON.parse(File.read(File.join(state, "audit-start")))
    check.call(verify["cwd"] == root && history["cwd"] == audit, "exact command working directories")
    check.call(verify["temporary"] != history["temporary"], "independent check temporary directories")
    check.call(!File.exist?(verify["temporary"]) && !File.exist?(history["temporary"]), "check temporaries cleaned after wait")
    check.call(output.include?("checked-verify") && output.include?("checked-audit"), "both check outputs preserved")
    check.call(output.include?("CI checks finished: 2 checks, 0 failed."), "both results gate success")
    if event == "pull_request"
      check.call(verify["source"] == "merge-source" && history["source"] == "head-source", "PR audit uses head instead of merge source")
    end
  end

  [{ "CI_TEST_EXIT_VERIFY" => "7" }, { "CI_TEST_EXIT_AUDIT" => "9" },
   { "CI_TEST_EXIT_VERIFY" => "7", "CI_TEST_EXIT_AUDIT" => "9" }].each do |failure|
    data = fixture.call
    status, output = invoke.call(data, failure)
    state = data[2]
    check.call(!status.success? && !File.exist?(File.join(state, "upload")), "any failed check blocks upload")
    check.call(%w[verify audit].all? { |lane| File.exist?(File.join(state, "#{lane}-start")) }, "failure never skips the other check")
    check.call(output.include?("checked-verify") && output.include?("checked-audit"), "failed-check diagnostics preserved")
  end

  ["verify", "audit"].each do |lane|
    data = fixture.call("pull_request")
    status, = invoke.call(data, { "CI_TEST_DIRTY" => lane })
    check.call(!status.success? && !File.exist?(File.join(data[2], "upload")), "post-check tracked drift blocks upload")
  end
  data = fixture.call
  status, = invoke.call(data, { "CI_TEST_COMMIT_DRIFT" => "verify" })
  check.call(!status.success? && !File.exist?(File.join(data[2], "upload")), "post-check commit drift blocks upload")

  [
    ["push", { "GITHUB_SHA" => "f" * 40 }],
    ["push", { "PUBLIC_HISTORY_AUDIT_COMMIT" => "f" * 40 }],
    ["push", { "GITHUB_EVENT_NAME" => "other" }],
    ["pull_request", { "PUBLIC_HISTORY_AUDIT_COMMIT" => "f" * 40 }],
    ["pull_request", { "PUBLIC_HISTORY_AUDIT_COMMIT" => "" }]
  ].each do |event, overrides|
    data = fixture.call(event)
    status, = invoke.call(data, overrides)
    check.call(!status.success?, "invalid source selection fails closed")
    check.call(Dir.children(data[2]).empty?, "invalid source never starts either check")
  end
  data = fixture.call("pull_request")
  FileUtils.rm_rf(File.join(data[1], ".git"))
  status, = invoke.call(data)
  check.call(!status.success? && Dir.children(data[2]).empty?, "PR folder cannot silently resolve to parent Git checkout")
  data = fixture.call
  File.write(File.join(data[0], ".git/shallow"), data[3].fetch("GITHUB_SHA") + "\n")
  status, = invoke.call(data)
  check.call(!status.success? && Dir.children(data[2]).empty?, "shallow source fails before checks start")

  data = fixture.call
  root, _audit, state, environment = data
  log = File.join(temporary, "interrupt.log")
  pid = Process.spawn(environment.merge("CI_TEST_BLOCK" => "1"), RbConfig.ruby,
                      File.join(root, "scripts/release/verify_ci.rb"), chdir: root, out: log, err: [:child, :out])
  begin
    Timeout.timeout(12) do
      sleep 0.01 until File.exist?(File.join(state, "leaf-pid"))
      Process.kill("TERM", pid)
      _, status = Process.waitpid2(pid)
      pid = nil
      check.call(status.exitstatus == 143 && !File.exist?(File.join(state, "upload")), "interruption cannot permit upload")
      descendants = %w[verify audit].map { |lane| JSON.parse(File.read(File.join(state, "#{lane}-start"))).fetch("pid") }
      descendants << Integer(File.read(File.join(state, "leaf-pid")), 10)
      descendants.each do |child|
        loop do
          begin
            Process.kill(0, child)
            sleep 0.01
          rescue Errno::ESRCH
            break
          end
        end
        check.call(true, "nested process groups terminate before return")
      end
    end
  ensure
    if pid
      Process.kill("KILL", pid)
      Process.wait(pid)
    end
  end
end

workflow = YAML.safe_load(File.read(File.expand_path("../../.github/workflows/ci.yml", __dir__)))
check.call(workflow.fetch("permissions") == { "contents" => "read" }, "CI contents permission remains read-only")
check.call(workflow.fetch(true).keys.sort == %w[pull_request push workflow_dispatch], "CI triggers retained")
jobs = workflow.fetch("jobs")
check.call(jobs.keys.sort == %w[verify verify-public-surface], "exact two-job approval contract retained")
check.call(jobs.values.map { |job| job.fetch("name") }.sort == ["Verify macOS app", "Verify public site and release assets"], "required check names retained")
app = jobs.fetch("verify")
check.call(app.fetch("runs-on") == "macos-15" && app.fetch("timeout-minutes") == 60, "app runner and timeout retained")
steps = app.fetch("steps")
parallel = steps.find { |step| step["run"] == "make verify-ci" }
upload = steps.find { |step| step["name"] == "Upload unsigned package" }
head = steps.find { |step| step["name"] == "Check out exact pull request head for public-history audit" }
check.call(parallel && upload && steps.index(parallel) < steps.index(upload), "upload follows the aggregate gate")
check.call(!upload.key?("if") && !upload.key?("continue-on-error") && !parallel.key?("continue-on-error"), "no approval bypass on gate or upload")
check.call(head && steps.index(head) < steps.index(parallel), "PR checkout precedes both checks")
check.call(head.fetch("with") == { "ref" => "${{ github.event.pull_request.head.sha }}", "path" => ".build/public-history-audit", "fetch-depth" => 0, "persist-credentials" => false }, "PR exact-head checkout and credential boundary retained")
check.call(head.fetch("if") == "github.event_name == 'pull_request'", "PR-specific checkout condition retained")
check.call(parallel.fetch("env").fetch("PUBLIC_HISTORY_AUDIT_COMMIT") == "${{ github.event.pull_request.head.sha || github.sha }}", "audit commit comes from event head")
check.call(upload.fetch("with") == { "name" => "desk-setup-switcher-unsigned", "path" => "artifacts/*.dmg\nartifacts/*.sha256\n", "if-no-files-found" => "error", "retention-days" => 14 }, "artifact inventory and retention retained")

puts "CI verification gate regressions passed: #{assertions} assertions."
