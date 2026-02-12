# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

# Shared setup for all queue subcommand tests.
# Include in any Minitest::Test that exercises QueueCommand.
module QueueTestHelper
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @queue_path = File.join(@temp_dir, "queue.jsonl")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def run_command(args, stdin_content: nil)
    exit_code = nil
    @stdout, @stderr = capture_io do
      with_log_level("INFO") do
        if stdin_content
          old_stdin = $stdin
          $stdin = StringIO.new(stdin_content)
        end
        cmd = Sift::CLI::QueueCommand.new(args, queue_path: @queue_path)
        exit_code = cmd.run
      ensure
        $stdin = old_stdin if stdin_content
      end
    end
    exit_code
  end

  def queue
    @queue ||= Sift::Queue.new(@queue_path)
  end
end
