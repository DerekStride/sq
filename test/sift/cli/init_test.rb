# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Sift::CLI::InitTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @original_dir = Dir.pwd
    Dir.chdir(@temp_dir)
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def test_creates_sift_dir_and_config
    exit_code, out, _err = run_init

    assert_equal 0, exit_code
    assert Dir.exist?(".sift")
    assert File.exist?(".sift/config.yml")
    assert_match(/created.*config\.yml/, out)
  end

  def test_project_config_template_has_all_keys
    run_init
    content = File.read(".sift/config.yml")

    assert_includes content, "agent:"
    assert_includes content, "command: claude"
    assert_includes content, "model: sonnet"
    assert_includes content, "worktree:"
    assert_includes content, "base_branch: main"
    assert_includes content, "queue_path:"
    assert_includes content, "concurrency: 5"
    assert_includes content, "dry: false"
  end

  def test_project_config_template_is_all_commented
    run_init
    content = File.read(".sift/config.yml")

    content.each_line do |line|
      next if line.strip.empty?

      assert_match(/\A#/, line.strip, "Expected all lines to be comments: #{line.inspect}")
    end
  end

  def test_does_not_overwrite_existing_config
    Dir.mkdir(".sift")
    File.write(".sift/config.yml", "custom: true\n")

    exit_code, out, _err = run_init

    assert_equal 0, exit_code
    assert_match(/already exists/, out)
    assert_equal "custom: true\n", File.read(".sift/config.yml")
  end

  def test_creates_config_when_dir_exists_but_config_missing
    Dir.mkdir(".sift")

    exit_code, _out, _err = run_init

    assert_equal 0, exit_code
    assert File.exist?(".sift/config.yml")
  end

  def test_idempotent_multiple_runs
    run_init
    exit_code, out, _err = run_init

    assert_equal 0, exit_code
    assert_match(/already exists/, out)
  end

  def test_help_flag
    exit_code, out, _err = run_sift(["init", "--help"])

    assert_equal 0, exit_code
    assert_includes out, "init"
    assert_includes out, "USAGE"
  end

  def test_sift_help_shows_init_command
    exit_code, out, _err = run_sift(["--help"])

    assert_equal 0, exit_code
    assert_includes out, "init"
    assert_includes out, "ADDITIONAL COMMANDS"
  end

  # --- --user flag ---

  def test_user_flag_creates_user_config
    with_xdg_home do |xdg_dir|
      exit_code, out, _err = run_init(["--user"])
      config_path = File.join(xdg_dir, "sift", "config.yml")

      assert_equal 0, exit_code
      assert File.exist?(config_path)
      assert_match(/created.*config\.yml/, out)
    end
  end

  def test_user_config_uses_same_template_as_project
    with_xdg_home do |xdg_dir|
      run_init # project
      run_init(["--user"]) # user

      project_content = File.read(".sift/config.yml")
      user_content = File.read(File.join(xdg_dir, "sift", "config.yml"))

      assert_equal project_content, user_content
    end
  end

  def test_user_config_template_is_all_commented
    with_xdg_home do |xdg_dir|
      run_init(["--user"])
      content = File.read(File.join(xdg_dir, "sift", "config.yml"))

      content.each_line do |line|
        next if line.strip.empty?

        assert_match(/\A#/, line.strip, "Expected all lines to be comments: #{line.inspect}")
      end
    end
  end

  def test_user_flag_does_not_overwrite_existing_config
    with_xdg_home do |xdg_dir|
      sift_dir = File.join(xdg_dir, "sift")
      FileUtils.mkdir_p(sift_dir)
      config_path = File.join(sift_dir, "config.yml")
      File.write(config_path, "custom: true\n")

      exit_code, out, _err = run_init(["--user"])

      assert_equal 0, exit_code
      assert_match(/already exists/, out)
      assert_equal "custom: true\n", File.read(config_path)
    end
  end

  def test_user_flag_creates_parent_directories
    with_xdg_home do |xdg_dir|
      # xdg_dir/sift/ doesn't exist yet
      run_init(["--user"])

      assert Dir.exist?(File.join(xdg_dir, "sift"))
      assert File.exist?(File.join(xdg_dir, "sift", "config.yml"))
    end
  end

  def test_user_flag_does_not_create_project_dir
    with_xdg_home do
      run_init(["--user"])

      refute Dir.exist?(".sift")
    end
  end

  private

  def with_xdg_home
    dir = Dir.mktmpdir("sift_xdg_test_")
    original = ENV["XDG_CONFIG_HOME"]
    ENV["XDG_CONFIG_HOME"] = dir
    yield dir
  ensure
    ENV["XDG_CONFIG_HOME"] = original
    FileUtils.rm_rf(dir) if dir && File.exist?(dir)
  end

  def run_init(args = [])
    run_sift(["init"] + args)
  end

  def run_sift(args)
    exit_code = nil
    out, err = capture_io do
      Sift::Log.reset!
      exit_code = Sift::CLI::SiftCommand.new(args).run
    end
    [exit_code, out, err]
  end
end
