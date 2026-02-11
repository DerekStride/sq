# frozen_string_literal: true

require "test_helper"
require "stringio"

class Sift::CLI::SiftCommandTest < Minitest::Test
  include TestHelpers

  def setup
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def test_shows_help_with_help_flag
    exit_code = run_command(["--help"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "USAGE"
    assert_includes stdout_output, "sift"
    assert_includes stdout_output, "--queue"
    assert_includes stdout_output, "--model"
  end

  def test_shows_help_with_short_help_flag
    exit_code = run_command(["-h"])

    assert_equal 0, exit_code
    assert_includes stdout_output, "USAGE"
  end

  def test_shows_version
    assert_raises(SystemExit) { run_command(["--version"]) }

    assert_includes stdout_output, "sift #{Sift::VERSION}"
  end

  def test_shows_version_with_short_flag
    assert_raises(SystemExit) { run_command(["-v"]) }

    assert_includes stdout_output, "sift #{Sift::VERSION}"
  end

  def test_default_options
    cmd = Sift::CLI::SiftCommand.new([], stdout: @stdout, stderr: @stderr)
    # Access the parser to populate defaults
    cmd.send(:build_option_parser)

    assert_equal Sift::CLI::DEFAULT_QUEUE_PATH, cmd.options[:queue_path]
    assert_equal "sonnet", cmd.options[:model]
  end

  def test_custom_queue_path
    cmd = Sift::CLI::SiftCommand.new(["--queue", "/tmp/q.jsonl"], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal "/tmp/q.jsonl", cmd.options[:queue_path]
  end

  def test_custom_model
    cmd = Sift::CLI::SiftCommand.new(["--model", "opus"], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal "opus", cmd.options[:model]
  end

  def test_invalid_flag_returns_error
    exit_code = run_command(["--bogus"])

    assert_equal 1, exit_code
    assert_match(/error/i, stderr_output)
  end

  private

  def run_command(args)
    cmd = Sift::CLI::SiftCommand.new(args, stdout: @stdout, stderr: @stderr)
    cmd.run
  end

  def stdout_output
    @stdout.string
  end

  def stderr_output
    @stderr.string
  end
end
