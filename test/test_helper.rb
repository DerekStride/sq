# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "minitest/reporters"

Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Load the gem
require "sift"
require "sift/cli"

# Add test directory to load path
$LOAD_PATH.unshift File.expand_path(".", __dir__)

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

  # Create a StringIO with the given content for stdin simulation
  def stdin_with(content)
    StringIO.new(content)
  end
end
