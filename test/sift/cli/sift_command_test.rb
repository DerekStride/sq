# frozen_string_literal: true

require "test_helper"
require "tempfile"

class Sift::CLI::SiftCommandTest < Minitest::Test
  include TestHelpers

  def test_shows_help_with_help_flag
    exit_code, out, _err = run_command(["--help"])

    assert_equal 0, exit_code
    assert_includes out, "USAGE"
    assert_includes out, "sift"
    assert_includes out, "--queue"
    assert_includes out, "--model"
  end

  def test_shows_help_with_short_help_flag
    exit_code, out, _err = run_command(["-h"])

    assert_equal 0, exit_code
    assert_includes out, "USAGE"
  end

  def test_shows_version
    assert_raises(SystemExit) do
      run_command(["--version"])
    end
  end

  def test_verbose_flag_available
    exit_code, out, _err = run_command(["--help"])

    assert_equal 0, exit_code
    assert_includes out, "--verbose"
  end

  def test_default_config_values
    defaults_only = Sift::Config.load(project_path: "/nonexistent", user_path: "/nonexistent")
    Sift::Config.stub(:load, defaults_only) do
      cmd = Sift::CLI::SiftCommand.new([])
      cmd.send(:build_option_parser)

      assert_equal "sonnet", cmd.config.agent_model
      assert_equal 5, cmd.config.concurrency
      refute cmd.config.dry?
    end
  end

  def test_custom_queue_path
    cmd = Sift::CLI::SiftCommand.new(["--queue", "/tmp/q.jsonl"])
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal "/tmp/q.jsonl", cmd.config.queue_path
  end

  def test_custom_model
    cmd = Sift::CLI::SiftCommand.new(["--model", "opus"])
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal "opus", cmd.config.agent_model
  end

  def test_dry_flag
    cmd = Sift::CLI::SiftCommand.new(["--dry"])
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert cmd.config.dry?
  end

  def test_custom_concurrency
    cmd = Sift::CLI::SiftCommand.new(["--concurrency", "3"])
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal 3, cmd.config.concurrency
  end

  def test_custom_concurrency_short_flag
    cmd = Sift::CLI::SiftCommand.new(["-c", "10"])
    cmd.send(:build_option_parser).parse!(cmd.argv)

    assert_equal 10, cmd.config.concurrency
  end

  def test_help_includes_dry_flag
    _exit_code, out, _err = run_command(["--help"])

    assert_includes out, "--dry"
  end

  def test_help_includes_concurrency_flag
    _exit_code, out, _err = run_command(["--help"])

    assert_includes out, "--concurrency"
  end

  def test_invalid_flag_returns_error
    exit_code, _out, err = run_command(["--bogus"])

    assert_equal 1, exit_code
    assert_match(/error/i, err)
  end

  private

  def run_command(args)
    exit_code = nil
    out, err = capture_io do
      Sift::Log.reset!
      exit_code = Sift::CLI::SiftCommand.new(args).run
    end
    [exit_code, out, err]
  end
end
