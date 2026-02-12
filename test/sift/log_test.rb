# frozen_string_literal: true

require "test_helper"
require "stringio"

class Sift::LogTest < Minitest::Test
  def setup
    Sift::Log.reset!
  end

  def teardown
    Sift::Log.reset!
  end

  def test_logs_to_stderr_by_default
    with_log_level("INFO") do
      _, stderr = capture_io { Sift::Log.info("hello from sift") }

      assert_includes stderr, "hello from sift"
    end
  end

  def test_allows_custom_logger
    custom_output = StringIO.new
    Sift::Log.logger = Logger.new(custom_output)

    Sift::Log.info("custom logger test")

    assert_includes custom_output.string, "custom logger test"
  end

  def test_reset_clears_the_logger
    custom_output = StringIO.new
    Sift::Log.logger = Logger.new(custom_output)

    Sift::Log.reset!

    with_log_level("INFO") do
      _, stderr = capture_io { Sift::Log.info("after reset") }

      refute_includes custom_output.string, "after reset"
      assert_includes stderr, "after reset"
    end
  end

  def test_respects_log_level
    _, stderr = with_log_level("WARN") do
      capture_io { Sift::Log.info("should be hidden") }
    end

    refute_includes stderr, "should be hidden"
  end

  def test_raises_on_invalid_log_level
    assert_raises(ArgumentError) do
      with_log_level("INVALID") do
        capture_io { Sift::Log.info("test") }
      end
    end
  end
end
