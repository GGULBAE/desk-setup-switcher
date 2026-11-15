#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "open3"
require "stringio"
require "timeout"
require_relative "run_test_suites"

assertions = 0
check = lambda do |condition, label|
  raise "Release test runner regression: #{label}" unless condition

  assertions += 1
end

check.call(ReleaseTestSuites.jobs("1") == 1 && ReleaseTestSuites.jobs("8") == 8, "valid bounds")
["", "0", "-1", "9", "04", "4.0", "2x", " 2"].each do |value|
  begin
    ReleaseTestSuites.jobs(value)
    raise "Accepted invalid worker limit"
  rescue ArgumentError
    check.call(true, "reject invalid worker limit")
  end
end

Dir.mktmpdir("desk-setup-pool-regression.") do |root|
  fixture = File.join(root, "test_worker.rb")
  File.write(fixture, <<~'RUBY')
    require "json"
    state_path, label, required_peak, outcome = ARGV
    update = lambda do |&block|
      File.open(state_path, File::RDWR | File::CREAT, 0o600) do |file|
        file.flock(File::LOCK_EX)
        text = file.read
        state = text.empty? ? { "active" => 0, "peak" => 0, "labels" => [], "temporary" => [] } : JSON.parse(text)
        block.call(state)
        file.rewind
        file.write(JSON.generate(state))
        file.truncate(file.pos)
        state
      end
    end
    update.call do |state|
      state["active"] += 1
      state["peak"] = [state["peak"], state["active"]].max
      state["labels"] << label
      state["temporary"] << ENV.fetch("TMPDIR")
    end
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    loop do
      break if update.call { |_state| }.fetch("peak") >= required_peak.to_i
      abort "Workers failed to overlap" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    puts "stdout-#{label}"
    warn "stderr-#{label}"
    update.call { |state| state["active"] -= 1 }
    Process.kill("TERM", Process.pid) if outcome == "signal"
    exit outcome.to_i
  RUBY

  run = lambda do |jobs, outcomes|
    state = File.join(root, "state-#{jobs}-#{outcomes.join('-')}.json")
    suites = outcomes.each_with_index.map do |outcome, index|
      ReleaseTestSuites::Suite.new("worker-#{index}",
                                  [RbConfig.ruby, fixture, state, index.to_s, [jobs, outcomes.length].min.to_s, outcome], root)
    end
    output = StringIO.new
    status = ReleaseTestSuites.new(suites, jobs: jobs, output: output).run
    [status, JSON.parse(File.read(state)), output.string]
  end

  serial = run.call(1, %w[0 7 0 0])
  parallel = run.call(2, %w[0 7 0 0])
  check.call(serial[0] == 1 && parallel[0] == 1, "any failed child fails serial and parallel execution")
  check.call(serial[1]["peak"] == 1 && parallel[1]["peak"] == 2, "bounded real process overlap")
  [serial, parallel].each do |status, state, output|
    check.call(state["labels"].sort == %w[0 1 2 3], "every suite runs once despite an earlier failure")
    check.call(state["active"].zero?, "all children finish")
    check.call(state["temporary"].uniq.length == 4, "each suite has an isolated temporary directory")
    check.call(state["temporary"].none? { |path| File.exist?(path) }, "temporary roots are removed after wait")
    check.call(output.include?("4 suites, 1 failed"), "failed suite count is explicit")
    4.times do |index|
      check.call(output.scan("stdout-#{index}\n").length == 1 && output.scan("stderr-#{index}\n").length == 1,
                 "stdout and stderr are preserved exactly once")
    end
  end
  check.call(run.call(2, %w[0 0])[0].zero?, "successful suites pass")
  signalled = run.call(1, ["signal"])
  check.call(signalled[0] == 1 && signalled[2].include?("1 suites, 1 failed"), "signalled suite fails the gate")

  missing = ReleaseTestSuites::Suite.new("missing", [File.join(root, "absent-command")], root)
  after = ReleaseTestSuites::Suite.new("after", [RbConfig.ruby, "-e", "puts 'ran-after-spawn-failure'"], root)
  output = StringIO.new
  check.call(ReleaseTestSuites.new([missing, after], jobs: 1, output: output).run == 1, "spawn failure fails the gate")
  check.call(output.string.include?("ran-after-spawn-failure"), "spawn failure does not skip later suites")
  [[], [after, after]].each do |suites|
    begin
      ReleaseTestSuites.new(suites, jobs: 2)
      raise "Accepted empty or duplicate suite list"
    rescue ArgumentError
      check.call(true, "empty and duplicate inventory fails before launch")
    end
  end

  # Exercise the actual CLI and process groups, including a grandchild. Signals
  # use readiness markers instead of a timing assumption about process startup.
  %w[TERM INT].each do |signal|
    marker = File.join(root, "ready-#{signal}")
    child = File.join(root, "test_cancel_#{signal.downcase}.rb")
    File.write(child, <<~RUBY)
      require "rbconfig"
      grandchild = Process.spawn(RbConfig.ruby, "-e", "sleep 30")
      Signal.trap("TERM") do
        Process.wait(grandchild)
        exit 0
      end
      File.write(#{marker.inspect}, [Process.pid, grandchild].join(" "))
      sleep 30
    RUBY
    log = File.join(root, "cancel-#{signal}.log")
    runner = File.expand_path("run_test_suites.rb", __dir__)
    pid = Process.spawn({ "DESK_SETUP_RELEASE_TEST_JOBS" => "2" }, RbConfig.ruby, runner, child, out: log, err: [:child, :out])
    begin
      Timeout.timeout(8) do
        sleep 0.01 until File.exist?(marker)
        Process.kill(signal, pid)
        _, status = Process.waitpid2(pid)
        pid = nil
        check.call(status.exitstatus == 128 + Signal.list.fetch(signal), "interruption cannot report success")
      end
      File.read(marker).split.map(&:to_i).each do |descendant|
        begin
          Process.kill(0, descendant)
          raise "Interrupted runner left a live descendant"
        rescue Errno::ESRCH
          check.call(true, "interruption reaps child and grandchild")
        end
      end
    ensure
      if pid
        Process.kill("KILL", pid)
        Process.wait(pid)
      end
    end
  end
end

puts "Release test runner regressions passed: #{assertions} assertions."
