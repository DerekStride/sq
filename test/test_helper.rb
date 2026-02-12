# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "minitest/reporters"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Suppress warn/info/debug logs during tests (override with SIFT_LOG_LEVEL=DEBUG)
ENV["SIFT_LOG_LEVEL"] ||= "ERROR"

# Load the gem
require "sift"
require "sift/cli"

# Add test directory to load path
$LOAD_PATH.unshift File.expand_path(".", __dir__)

def with_log_level(level)
  Sift::Log.reset!
  original = ENV["SIFT_LOG_LEVEL"]
  ENV["SIFT_LOG_LEVEL"] = level
  yield
ensure
  ENV["SIFT_LOG_LEVEL"] = original
  Sift::Log.reset!
end

module TestHelpers
  # Create a temporary directory for test files
  def create_temp_dir
    Dir.mktmpdir("sift_test_")
  end

  # Create a temporary queue file path
  def create_temp_queue_path(dir = nil)
    dir ||= create_temp_dir
    File.join(dir, "queue.jsonl")
  end
end
