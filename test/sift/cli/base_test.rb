# frozen_string_literal: true

require "test_helper"

# Stub commands for testing the Base class
module StubCommands
  class Child < Sift::CLI::Base
    command_name "greet"
    summary "Say hello"
    description "Greet someone by name"
    examples "testcli greet --name World", "testcli greet --name World --shout"

    def define_flags(parser, options)
      parser.on("--name NAME", "Name to greet") { |v| options[:name] = v }
      super
    end

    def validate
      raise OptionParser::MissingArgument, "--name is required" unless options[:name]
    end

    def execute
      msg = "Hello, #{options[:name]}!"
      msg = msg.upcase if options[:shout]
      puts msg
      0
    end
  end

  class Extra < Sift::CLI::Base
    command_name "farewell"
    summary "Say goodbye"

    def execute
      puts "Goodbye!"
      0
    end
  end

  class Root < Sift::CLI::Base
    command_name "testcli"
    summary "A test CLI"

    register_subcommand Child, category: :core
    register_subcommand Extra, category: :additional

    def define_flags(parser, options)
      parser.on("--shout", "Enable shout mode") { options[:shout] = true }
      super
    end
  end

  class Leaf < Sift::CLI::Base
    command_name "leaf"
    summary "A standalone leaf command"

    def define_flags(parser, options)
      parser.on("--count N", Integer, "Number of times") { |v| options[:count] = v }
      super
    end

    def execute
      puts "count=#{options[:count]}"
      0
    end
  end
end

class Sift::CLI::BaseTest < Minitest::Test
  private def run_root(argv)
    exit_code = nil
    @stdout, @stderr = capture_io do
      with_log_level("ERROR") do
        exit_code = StubCommands::Root.new(argv).run
      end
    end
    exit_code
  end

  private def run_leaf(argv)
    exit_code = nil
    @stdout, @stderr = capture_io do
      with_log_level("ERROR") do
        exit_code = StubCommands::Leaf.new(argv).run
      end
    end
    exit_code
  end

  # --- Subcommand routing ---

  def test_routes_to_subcommand
    exit_code = run_root(["greet", "--name", "World"])

    assert_equal 0, exit_code
    assert_equal "Hello, World!\n", @stdout
  end

  def test_flags_before_subcommand
    exit_code = run_root(["--shout", "greet", "--name", "World"])

    assert_equal 0, exit_code
    assert_includes @stdout, "HELLO, WORLD!"
  end

  def test_flags_after_subcommand
    exit_code = run_root(["greet", "--shout", "--name", "World"])

    assert_equal 0, exit_code
    assert_includes @stdout, "HELLO, WORLD!"
  end

  def test_parent_flags_flow_to_child_options
    exit_code = run_root(["greet", "--name", "X", "--shout"])

    assert_equal 0, exit_code
    assert_includes @stdout, "HELLO, X!"
  end

  # --- No args / help ---

  def test_no_args_shows_help
    exit_code = run_root([])

    assert_equal 0, exit_code
    assert_includes @stdout, "testcli"
    assert_includes @stdout, "CORE COMMANDS"
    assert_includes @stdout, "greet"
  end

  def test_help_flag_shows_help
    exit_code = run_root(["--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "testcli"
  end

  def test_leaf_help_flag
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "FLAGS"
    assert_includes @stdout, "--name"
    assert_includes @stdout, "INHERITED FLAGS"
    assert_includes @stdout, "--shout"
    assert_includes @stdout, "EXAMPLES"
    assert_includes @stdout, "testcli greet --name World"
  end

  # --- Unknown subcommand ---

  def test_unknown_subcommand_returns_error
    exit_code = run_root(["bogus"])

    assert_equal 1, exit_code
    assert_includes @stderr, "Unknown command: bogus"
    assert_includes @stdout, "CORE COMMANDS"
  end

  # --- Help structure ---

  def test_help_has_description
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "Greet someone by name"
  end

  def test_help_has_usage
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "USAGE"
    assert_includes @stdout, "testcli greet [flags]"
  end

  def test_parent_help_has_commands_grouped
    exit_code = run_root([])

    assert_equal 0, exit_code
    assert_includes @stdout, "CORE COMMANDS"
    assert_includes @stdout, "greet"
    assert_includes @stdout, "ADDITIONAL COMMANDS"
    assert_includes @stdout, "farewell"
  end

  def test_help_has_learn_more
    exit_code = run_root([])

    assert_equal 0, exit_code
    assert_includes @stdout, "LEARN MORE"
  end

  # --- Verbose flag ---

  def test_verbose_flag_in_help
    exit_code = run_root(["--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "--verbose"
  end

  def test_verbose_flag_inherited_by_subcommands
    exit_code = run_root(["greet", "--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "--verbose"
  end

  # --- Error handling ---

  def test_invalid_option_returns_error
    exit_code = run_root(["greet", "--nonexistent"])

    assert_equal 1, exit_code
    assert_includes @stderr, "Error:"
  end

  def test_validate_failure_returns_error
    exit_code = run_root(["greet"])

    assert_equal 1, exit_code
    assert_includes @stderr, "Error:"
    assert_includes @stderr, "--name is required"
  end

  # --- Leaf command (no subcommands) ---

  def test_leaf_command_parses_flags
    exit_code = run_leaf(["--count", "5"])

    assert_equal 0, exit_code
    assert_equal "count=5\n", @stdout
  end

  def test_leaf_command_help
    exit_code = run_leaf(["--help"])

    assert_equal 0, exit_code
    assert_includes @stdout, "USAGE"
    assert_includes @stdout, "leaf [flags]"
    assert_includes @stdout, "--count"
  end

  def test_leaf_invalid_flag_type
    exit_code = run_leaf(["--count", "abc"])

    assert_equal 1, exit_code
    assert_includes @stderr, "Error:"
  end

  # --- execute not implemented ---

  def test_execute_not_implemented_raises
    klass = Class.new(Sift::CLI::Base) do
      command_name "noop"
    end

    cmd = klass.new([])
    assert_raises(NotImplementedError) { cmd.execute }
  end

  # --- Class-level metadata ---

  def test_command_name
    assert_equal "greet", StubCommands::Child.command_name
  end

  def test_summary
    assert_equal "Say hello", StubCommands::Child.summary
  end

  def test_description_falls_back_to_summary
    assert_equal "Say goodbye", StubCommands::Extra.description
  end

  def test_examples
    assert_equal ["testcli greet --name World", "testcli greet --name World --shout"],
      StubCommands::Child.examples
  end

  # --- full_command_name ---

  def test_full_command_name_root
    root = StubCommands::Root.new([])
    assert_equal "testcli", root.full_command_name
  end

  def test_full_command_name_child
    root = StubCommands::Root.new([])
    child = StubCommands::Child.new([], parent: root)
    assert_equal "testcli greet", child.full_command_name
  end
end
