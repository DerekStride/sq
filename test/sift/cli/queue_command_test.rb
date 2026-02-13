# frozen_string_literal: true

require "test_helper"

class Sift::CLI::QueueCommandTest < Minitest::Test
  def test_shows_help_with_no_args
    exit_code, out, _err = run_command([])

    assert_equal 0, exit_code
    assert_includes out, "USAGE"
    assert_includes out, "sq"
    assert_includes out, "add"
    assert_includes out, "list"
  end

  def test_shows_help_with_help_flag
    exit_code, out, _err = run_command(["--help"])

    assert_equal 0, exit_code
    assert_includes out, "USAGE"
  end

  def test_unknown_subcommand_returns_error
    exit_code, _out, err = run_command(["unknown"])

    assert_equal 1, exit_code
    assert_match(/unknown command/i, err)
  end

  private

  def run_command(args)
    exit_code = nil
    out, err = capture_io do
      with_log_level("ERROR") do
        exit_code = Sift::CLI::QueueCommand.new(args).run
      end
    end
    [exit_code, out, err]
  end
end
