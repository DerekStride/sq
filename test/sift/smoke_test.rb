# frozen_string_literal: true

require "test_helper"
require "open3"
require "timeout"

# Smoke tests that verify the CLIs boot without crashing.
#
# One subprocess test per executable verifies the full cold-start path (shebang,
# Bundler, require chain). The remaining tests run in-process for speed while
# still exercising command behavior.
class SmokeTest < Minitest::Test
  EXE_SIFT = File.expand_path("../../exe/sift", __dir__)
  EXE_SQ = File.expand_path("../../exe/sq", __dir__)

  # --- Subprocess: one per executable to verify cold-start boot ---

  def test_sift_boots
    stdout, stderr, status = Timeout.timeout(10) { Open3.capture3("bundle", "exec", EXE_SIFT, "--help") }
    assert status.success?, "sift --help failed: #{stderr}"
    assert_includes stdout, "USAGE"
  end

  def test_sq_boots
    stdout, stderr, status = Timeout.timeout(10) { Open3.capture3("bundle", "exec", EXE_SQ, "--help") }
    assert status.success?, "sq --help failed: #{stderr}"
    assert_includes stdout, "sq"
  end

  # --- In-process: command behavior without subprocess overhead ---

  def test_require_sift_loads_without_error
    assert defined?(Sift::Queue), "Sift::Queue should be defined after require"
    queue = Sift::Queue.new("/tmp/sift_smoke_#{Process.pid}.jsonl")
    assert_instance_of Sift::Queue, queue
  end

  def test_review_loop_can_be_instantiated
    config = Sift::Config.new({}, "queue_path" => "/tmp/sift_smoke_test_#{Process.pid}.jsonl", "dry" => true)
    rl = Sift::ReviewLoop.new(config: config)
    assert_instance_of Sift::ReviewLoop, rl
  end

  def test_sift_version_flag
    assert_raises(SystemExit) { capture_io { Sift::CLI::SiftCommand.new(["--version"]).run } }
  end

  def test_sift_help_flag
    out, = capture_io { Sift::CLI::SiftCommand.new(["--help"]).run }
    assert_includes out, "USAGE"
    assert_includes out, "sift"
  end

  def test_sift_empty_queue_exits_gracefully
    Dir.mktmpdir("sift_smoke_") do |dir|
      queue_path = File.join(dir, "queue.jsonl")
      exit_code = nil
      capture_io do
        Sift::Log.reset!
        exit_code = Sift::CLI::SiftCommand.new(["--queue", queue_path]).run
      end
      assert_equal 0, exit_code
    end
  end

  def test_sq_help
    out, = capture_io { Sift::CLI::QueueCommand.new(["--help"]).run }
    assert_includes out, "sq"
  end

  def test_sq_list_empty_queue
    Dir.mktmpdir("sift_smoke_") do |dir|
      queue_path = File.join(dir, "queue.jsonl")
      exit_code = nil
      capture_io do
        Sift::Log.reset!
        exit_code = Sift::CLI::QueueCommand.new(["list", "--queue", queue_path]).run
      end
      assert_equal 0, exit_code
    end
  end
end
