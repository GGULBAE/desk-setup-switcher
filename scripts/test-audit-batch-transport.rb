#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "open3"
require "rbconfig"
require "shellwords"
require "tmpdir"

assertions = 0
check = lambda do |condition, label|
  raise "Audit batch transport regression: #{label}" unless condition

  assertions += 1
end

Dir.mktmpdir("desk-setup-audit-batch.") do |temporary|
  root = File.join(temporary, "source")
  shim = File.join(temporary, "bin")
  FileUtils.mkdir_p([File.join(root, "scripts"), File.join(root, "docs"), shim])
  audit = File.join(root, "scripts/audit-public-release.sh")
  FileUtils.cp(File.join(__dir__, "audit-public-release.sh"), audit)
  File.chmod(0o755, audit)
  File.write(File.join(root, "README.md"), "synthetic transport fixture\n")
  File.write(File.join(root, "docs/LEGACY-GIT-IDENTITY-ALLOWLIST.txt"), "")
  git = lambda do |*arguments|
    stdout, _stderr, status = Open3.capture3("git", "-C", root, *arguments)
    raise "Audit transport Git fixture failed" unless status.success?

    stdout.strip
  end
  git.call("init", "-q", "-b", "master")
  git.call("config", "user.name", "Synthetic Transport Fixture")
  git.call("config", "user.email", "12345+synthetic-audit@users.noreply.github.com")
  git.call("config", "commit.gpgsign", "false")
  git.call("config", "tag.gpgsign", "false")
  git.call("add", ".")
  git.call("commit", "-q", "-m", "synthetic transport source")
  git.call("tag", "-a", "batch-fixture", "-m", "synthetic transport message")

  guard = File.join(temporary, "transport_guard.rb")
  File.write(guard, <<~'RUBY')
    require "open3"

    # Reject write-ahead deterministically, independently of pipe capacity or
    # process timing, while retaining real Git responses and the real scanner.
    module StrictGitBatchTransport
      def popen3(*command, **options, &block)
        return super unless command.last(2) == ["cat-file", "--batch"]

        super(*command, **options) do |stdin, stdout, stderr, wait_thread|
          pending = false
          phase = :header
          requests = 0
          write_request = stdin.method(:puts)
          read_header = stdout.method(:gets)
          read_bytes = stdout.method(:read)
          stdin.define_singleton_method(:puts) do |object|
            raise "Batch request written before draining the previous response" if pending

            pending = true
            requests += 1
            write_request.call(object)
          end
          stdout.define_singleton_method(:gets) do
            raise "Batch response header read out of order" unless pending && phase == :header

            phase = :body
            read_header.call
          end
          stdout.define_singleton_method(:read) do |size|
            raise "Batch response body read out of order" unless pending && [:body, :separator].include?(phase)

            bytes = read_bytes.call(size)
            if phase == :separator
              raise "Batch response separator differs" unless size == 1 && bytes == "\n"

              pending = false
              phase = :header
            else
              phase = :separator
            end
            bytes
          end
          result = block.call(stdin, stdout, stderr, wait_thread)
          raise "Batch response was not drained" if pending

          File.open(ENV.fetch("AUDIT_BATCH_OBSERVATIONS"), "a") { |file| file.puts(requests) }
          result
        end
      end
    end

    Open3.singleton_class.prepend(StrictGitBatchTransport)
  RUBY
  File.write(File.join(shim, "ruby"), "#!/bin/sh\nexec #{Shellwords.join([RbConfig.ruby, '-r', guard])} \"$@\"\n")
  File.chmod(0o755, File.join(shim, "ruby"))
  observations = File.join(temporary, "observations")
  environment = { "PATH" => shim + File::PATH_SEPARATOR + ENV.fetch("PATH"),
                  "AUDIT_BATCH_OBSERVATIONS" => observations }

  # Prove that the guard itself rejects the old write-all/read-all protocol.
  bad_client = <<~'RUBY'
    require "open3"
    Open3.popen3("git", "-C", ARGV.fetch(0), "cat-file", "--batch") do |stdin, _stdout, _stderr, _wait|
      stdin.puts(ARGV.fetch(1))
      stdin.puts(ARGV.fetch(1))
    end
  RUBY
  _stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, "-r", guard,
                                         "-e", bad_client, root, git.call("rev-parse", "HEAD"))
  check.call(!status.success? && stderr.include?("Batch request written before draining"), "guard rejects write-ahead")

  stdout, stderr, status = Open3.capture3(environment, audit)
  check.call(status.success?, "complete scanner drains each response before requesting the next object")
  check.call(stdout.include?("Public-release history, privacy, and asset metadata audit passed.") && stderr.empty?,
             "full audit boundary and diagnostics are retained")
  counts = File.readlines(observations).map { |line| Integer(line, 10) }
  check.call(counts.length == 2 && counts.all? { |count| count >= 2 }, "both history and message streams inspect multiple real objects")
end

puts "Audit batch transport regressions passed: #{assertions} assertions."
