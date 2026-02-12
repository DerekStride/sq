# frozen_string_literal: true

require "test_helper"
require "stringio"
require "tempfile"

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
    assert_equal 5, cmd.options[:concurrency]
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

  def test_dry_flag
    cmd = Sift::CLI::SiftCommand.new(["--dry"], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert cmd.options[:dry]
  end

  def test_custom_concurrency
    cmd = Sift::CLI::SiftCommand.new(["--concurrency", "3"], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal 3, cmd.options[:concurrency]
  end

  def test_custom_concurrency_short_flag
    cmd = Sift::CLI::SiftCommand.new(["-c", "10"], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal 10, cmd.options[:concurrency]
  end

  def test_system_prompt_flag
    tmpfile = Tempfile.new(["sp-", ".md"])
    tmpfile.write("You are a code reviewer.")
    tmpfile.close

    cmd = Sift::CLI::SiftCommand.new(["--system-prompt", tmpfile.path], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal tmpfile.path, cmd.options[:system_prompt_path]
  ensure
    tmpfile&.unlink
  end

  def test_system_prompt_short_flag
    tmpfile = Tempfile.new(["sp-", ".md"])
    tmpfile.write("You are a code reviewer.")
    tmpfile.close

    cmd = Sift::CLI::SiftCommand.new(["-s", tmpfile.path], stdout: @stdout, stderr: @stderr)
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal tmpfile.path, cmd.options[:system_prompt_path]
  ensure
    tmpfile&.unlink
  end

  def test_help_includes_system_prompt_flag
    run_command(["--help"])

    assert_includes stdout_output, "--system-prompt"
  end

  def test_help_includes_dry_flag
    run_command(["--help"])

    assert_includes stdout_output, "--dry"
  end

  def test_help_includes_concurrency_flag
    run_command(["--help"])

    assert_includes stdout_output, "--concurrency"
  end

  def test_system_prompt_missing_file_exits_with_error
    assert_raises(SystemExit) do
      run_command(["--system-prompt", "/nonexistent/prompt.md"])
    end

    assert_includes stderr_output, "system prompt file not found"
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
