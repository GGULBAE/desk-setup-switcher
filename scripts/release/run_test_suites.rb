#!/usr/bin/env ruby
# frozen_string_literal: true

require "rbconfig"
require "tmpdir"

# Each existing suite retains its own process and fixtures. Only scheduling is
# shared; failures never cancel or skip the other registered suites.
class ReleaseTestSuites
  Suite = Struct.new(:name, :command, :directory)

  def self.jobs(value)
    raise ArgumentError, "DESK_SETUP_RELEASE_TEST_JOBS must be an integer from 1 to 8" unless
      value.to_s.match?(/\A[1-8]\z/)

    value.to_i
  end

  def initialize(suites, jobs:, output: $stdout, prefix: "release-tests",
                 summary: "Release test suites", noun: "suites", termination_grace: 2)
    @jobs = self.class.jobs(jobs)
    raise ArgumentError, "Test suites must be nonempty and have unique names" if
      suites.empty? || suites.map(&:name).uniq.length != suites.length

    @pending = suites.dup
    @active = {}
    @results = []
    @output = output
    @prefix, @summary, @noun = prefix, summary, noun
    @termination_grace = termination_grace
    @cancelled = nil
  end

  def run
    previous = {}
    %w[INT TERM].each { |signal| previous[signal] = Signal.trap(signal) { @cancelled = Signal.list.fetch(signal) } }
    Dir.mktmpdir("desk-setup-release-pool.") do |root|
      begin
        until @pending.empty? && @active.empty?
          break if @cancelled

          launch(root) while !@cancelled && !@pending.empty? && @active.length < @jobs
          finished = @active.keys.select do |pid|
            pair = Process.waitpid2(pid, Process::WNOHANG)
            finish(pid, pair.last) if pair
            pair
          end
          sleep 0.05 if finished.empty? && !@active.empty?
        end
      ensure
        stop_children
      end
    end
    return 128 + @cancelled if @cancelled

    @output.puts("#{@summary} finished: #{@results.length} #{@noun}, #{@results.count(false)} failed.")
    @results.all? ? 0 : 1
  ensure
    previous.each { |signal, handler| Signal.trap(signal, handler) }
  end

  private

  def launch(root)
    suite = @pending.shift
    directory = File.join(root, (@results.length + @active.length).to_s)
    Dir.mkdir(directory, 0o700)
    temporary = File.join(directory, "tmp")
    Dir.mkdir(temporary, 0o700)
    log = File.join(directory, "output.log")
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    @output.puts("[#{@prefix}] START #{suite.name}")
    @output.flush
    File.open(log, "wb", 0o600) do |file|
      executable, *arguments = suite.command
      pid = Process.spawn({ "TMPDIR" => temporary + File::SEPARATOR }, [executable, executable], *arguments,
                          chdir: suite.directory, out: file, err: [:child, :out], pgroup: true)
      @active[pid] = [suite, log, started]
    end
  rescue SystemCallError
    @results << false
    @output.puts("[#{@prefix}] FAIL #{suite.name}: could not start suite")
  end

  def finish(pid, status)
    suite, log, started = @active.delete(pid)
    @results << (status.success? == true)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    @output.puts(format("[#{@prefix}] %s %s (%.2fs)", status.success? ? "PASS" : "FAIL", suite.name, elapsed))
    @output.puts("--- #{suite.name} output ---")
    File.open(log, "rb") { |file| IO.copy_stream(file, @output) }
    @output.puts("--- #{suite.name} end ---")
    @output.flush
  end

  def stop_children
    pids = @active.keys
    pids.each { |pid| signal_group("TERM", pid) }
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @termination_grace
    until Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline
      @active.keys.each do |pid|
        @active.delete(pid) if Process.waitpid2(pid, Process::WNOHANG)
      end
      break if @active.empty? && pids.none? { |pid| group_alive?(pid) }

      sleep 0.05
    end
    # A suite may exit before its descendants. Address the original groups as
    # well as the remaining direct children before removing their temp files.
    pids.each { |pid| signal_group("KILL", pid) }
    @active.keys.each { |pid| Process.waitpid(pid) }
    @active.clear
  end

  def signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH
    nil
  end

  def group_alive?(pid)
    Process.kill(0, -pid)
    true
  rescue Errno::ESRCH
    false
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    jobs = ReleaseTestSuites.jobs(ENV.fetch("DESK_SETUP_RELEASE_TEST_JOBS", "4"))
    suites = ARGV.map do |path|
      path = File.realpath(path)
      raise ArgumentError, "Expected Ruby or shell test suite files" unless
        File.file?(path) && File.basename(path).match?(/\Atest_[a-z0-9_]+\.(rb|sh)\z/)

      command = File.extname(path) == ".rb" ? [RbConfig.ruby, path] : [path]
      ReleaseTestSuites::Suite.new(File.basename(path), command, Dir.pwd)
    end
    exit ReleaseTestSuites.new(suites, jobs: jobs).run
  rescue ArgumentError, SystemCallError
    warn "Release test runner: invalid suite list or DESK_SETUP_RELEASE_TEST_JOBS (expected 1–8)."
    exit 2
  end
end
