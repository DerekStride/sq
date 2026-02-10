# frozen_string_literal: true

require "test_helper"
require "open3"

# System-level smoke tests that verify the CLIs boot without crashing.
# These catch constant resolution issues (like CLI::UI vs Sift::CLI::UI)
# that unit tests miss because they don't exercise the full require chain.
class SmokeTest < Minitest::Test
  EXE_SIFT = File.expand_path("../../exe/sift", __dir__)
  EXE_SQ = File.expand_path("../../exe/sq", __dir__)

  def test_sift_version_flag
    stdout, stderr, status = Open3.capture3("bundle", "exec", EXE_SIFT, "--version")
    assert status.success?, "sift --version failed: #{stderr}"
    assert_match(/sift \d/, stdout)
  end

  def test_sift_help_flag
    stdout, stderr, status = Open3.capture3("bundle", "exec", EXE_SIFT, "--help")
    assert status.success?, "sift --help failed: #{stderr}"
    assert_includes stdout, "Usage: sift"
  end

  def test_sq_help
    stdout, stderr, status = Open3.capture3("bundle", "exec", EXE_SQ, "--help")
    assert status.success?, "sq --help failed: #{stderr}"
    assert_includes stdout, "sq"
  end

  def test_sq_list_empty_queue
    Dir.mktmpdir("sift_smoke_") do |dir|
      env = { "SIFT_QUEUE_PATH" => File.join(dir, "queue.jsonl") }
      stdout, stderr, status = Open3.capture3(env, "bundle", "exec", EXE_SQ, "list")
      assert status.success?, "sq list failed: #{stderr}"
    end
  end

  def test_require_sift_loads_without_error
    # Verify the full require chain works inside Sift module context
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "ruby", "-e",
      'require "sift"; Sift::Source::Base.for(Sift::Queue::Source.new(type: "text", content: "ok"))'
    )
    assert status.success?, "require 'sift' + Source::Base.for failed: #{stderr}"
  end

  def test_review_loop_can_be_instantiated
    # Verify ReviewLoop loads without NameError on CLI::UI
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "ruby", "-e",
      'require "sift"; Sift::ReviewLoop.new(path: ".")'
    )
    assert status.success?, "ReviewLoop.new failed: #{stderr}"
  end
end
