# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "tempfile"

class Sift::ConfigTest < Minitest::Test
  def test_defaults_without_config_file
    config = Sift::Config.load(project_path: "/nonexistent/config.yml", user_path: "/nonexistent/user.yml")

    assert_equal "claude", config.agent_command
    assert_equal [], config.agent_flags
    assert_equal [], config.agent_allowed_tools
    assert_equal "sonnet", config.agent_model
    assert_nil config.agent_system_prompt
    assert_nil config.worktree_setup_command
    assert_equal "main", config.worktree_base_branch
    assert_equal Sift::Queue::DEFAULT_PATH, config.queue_path
    assert_equal 5, config.concurrency
    refute config.dry?
  end

  def test_load_from_file_reads_system_prompt_content
    with_config_dir do |dir|
      prompt_path = File.join(dir, "review.md")
      File.write(prompt_path, "You are a reviewer.")
      config_path = File.join(dir, "config.yml")
      File.write(config_path, <<~YAML)
        agent:
          command: my-agent
          flags: ['--dangerously-skip-permissions']
          allowed_tools: [Edit, Write, Bash]
          model: opus
          system_prompt: #{prompt_path}
        worktree:
          setup_command: dev up
          base_branch: develop
        queue_path: custom/queue.jsonl
        concurrency: 3
      YAML

      config = Sift::Config.load(project_path: config_path, user_path: "/nonexistent/user.yml")

      assert_equal "my-agent", config.agent_command
      assert_equal ["--dangerously-skip-permissions"], config.agent_flags
      assert_equal ["Edit", "Write", "Bash"], config.agent_allowed_tools
      assert_equal "opus", config.agent_model
      assert_equal "You are a reviewer.", config.agent_system_prompt
      assert_equal "dev up", config.worktree_setup_command
      assert_equal "develop", config.worktree_base_branch
      assert_equal "custom/queue.jsonl", config.queue_path
      assert_equal 3, config.concurrency
    end
  end

  def test_load_raises_on_missing_system_prompt_file
    with_config_file("agent:\n  system_prompt: /nonexistent/prompt.md") do |path|
      error = assert_raises(Sift::Config::FileNotFound) do
        Sift::Config.load(project_path: path, user_path: "/nonexistent/user.yml")
      end
      assert_includes error.message, "/nonexistent/prompt.md"
    end
  end

  def test_partial_override_preserves_defaults
    with_config_file(<<~YAML) do |path|
      agent:
        model: haiku
      concurrency: 10
    YAML
      config = Sift::Config.load(project_path: path, user_path: "/nonexistent/user.yml")

      # Overridden
      assert_equal "haiku", config.agent_model
      assert_equal 10, config.concurrency

      # Defaults preserved
      assert_equal "claude", config.agent_command
      assert_equal [], config.agent_flags
      assert_equal [], config.agent_allowed_tools
      assert_nil config.agent_system_prompt
      assert_nil config.worktree_setup_command
      assert_equal "main", config.worktree_base_branch
      assert_equal Sift::Queue::DEFAULT_PATH, config.queue_path
    end
  end

  def test_empty_config_file_uses_defaults
    with_config_file("") do |path|
      config = Sift::Config.load(project_path: path, user_path: "/nonexistent/user.yml")

      assert_equal "sonnet", config.agent_model
      assert_equal 5, config.concurrency
    end
  end

  def test_new_with_no_args_uses_defaults
    config = Sift::Config.new

    assert_equal "sonnet", config.agent_model
    assert_equal 5, config.concurrency
    assert_equal "claude", config.agent_command
    assert_equal Sift::Queue::DEFAULT_PATH, config.queue_path
    refute config.dry?
  end

  # --- Setters for CLI override ---

  def test_agent_model_setter
    config = Sift::Config.new
    config.agent_model = "opus"

    assert_equal "opus", config.agent_model
  end

  def test_agent_system_prompt_setter_reads_file_content
    tmpfile = Tempfile.new(["sp-", ".md"])
    tmpfile.write("You are a reviewer.")
    tmpfile.close

    config = Sift::Config.new
    config.agent_system_prompt = tmpfile.path

    assert_equal "You are a reviewer.", config.agent_system_prompt
  ensure
    tmpfile&.unlink
  end

  def test_agent_system_prompt_setter_raises_on_missing_file
    config = Sift::Config.new

    error = assert_raises(Sift::Config::FileNotFound) do
      config.agent_system_prompt = "/nonexistent/prompt.md"
    end
    assert_includes error.message, "/nonexistent/prompt.md"
  end

  def test_queue_path_setter
    config = Sift::Config.new
    config.queue_path = "/tmp/custom.jsonl"

    assert_equal "/tmp/custom.jsonl", config.queue_path
  end

  def test_concurrency_setter
    config = Sift::Config.new
    config.concurrency = 10

    assert_equal 10, config.concurrency
  end

  def test_dry_setter
    config = Sift::Config.new
    config.dry = true

    assert config.dry?
  end

  # --- Env var override ---

  def test_env_var_overrides_default_queue_path
    with_env("SIFT_QUEUE_PATH" => "/env/queue.jsonl") do
      config = Sift::Config.load(project_path: "/nonexistent/config.yml", user_path: "/nonexistent/user.yml")

      assert_equal "/env/queue.jsonl", config.queue_path
    end
  end

  def test_env_var_overrides_config_file_queue_path
    with_config_file("queue_path: from-file.jsonl") do |path|
      with_env("SIFT_QUEUE_PATH" => "/env/queue.jsonl") do
        config = Sift::Config.load(project_path: path, user_path: "/nonexistent/user.yml")

        assert_equal "/env/queue.jsonl", config.queue_path
      end
    end
  end

  # --- Precedence: setter (CLI) > env > file > default ---

  def test_setter_overrides_env_var
    with_env("SIFT_QUEUE_PATH" => "/env/queue.jsonl") do
      config = Sift::Config.load(project_path: "/nonexistent/config.yml", user_path: "/nonexistent/user.yml")
      config.queue_path = "/cli/queue.jsonl"

      assert_equal "/cli/queue.jsonl", config.queue_path
    end
  end

  def test_agent_flags_as_array
    config = Sift::Config.new(
      {}, "agent" => { "flags" => ["--flag1", "--flag2=value"] },
    )

    assert_equal ["--flag1", "--flag2=value"], config.agent_flags
  end

  # --- User config tier ---

  def test_user_config_overrides_defaults
    with_config_dir do |dir|
      user_path = File.join(dir, "user.yml")
      File.write(user_path, <<~YAML)
        agent:
          model: opus
        concurrency: 8
      YAML

      config = Sift::Config.load(project_path: "/nonexistent/project.yml", user_path: user_path)

      assert_equal "opus", config.agent_model
      assert_equal 8, config.concurrency
      assert_equal "claude", config.agent_command # default preserved
    end
  end

  def test_project_config_overrides_user_config
    with_config_dir do |dir|
      user_path = File.join(dir, "user.yml")
      File.write(user_path, <<~YAML)
        agent:
          model: opus
        concurrency: 8
      YAML

      project_path = File.join(dir, "project.yml")
      File.write(project_path, <<~YAML)
        agent:
          model: haiku
      YAML

      config = Sift::Config.load(project_path: project_path, user_path: user_path)

      assert_equal "haiku", config.agent_model # project wins
      assert_equal 8, config.concurrency       # user setting survives
    end
  end

  def test_deep_merge_across_tiers
    with_config_dir do |dir|
      user_path = File.join(dir, "user.yml")
      File.write(user_path, <<~YAML)
        agent:
          model: opus
          flags: ['--verbose']
      YAML

      project_path = File.join(dir, "project.yml")
      File.write(project_path, <<~YAML)
        agent:
          model: haiku
      YAML

      config = Sift::Config.load(project_path: project_path, user_path: user_path)

      assert_equal "haiku", config.agent_model       # project overrides
      assert_equal ["--verbose"], config.agent_flags  # user's flags survive
    end
  end

  def test_env_var_overrides_both_configs
    with_config_dir do |dir|
      user_path = File.join(dir, "user.yml")
      File.write(user_path, "queue_path: user/queue.jsonl")

      project_path = File.join(dir, "project.yml")
      File.write(project_path, "queue_path: project/queue.jsonl")

      with_env("SIFT_QUEUE_PATH" => "/env/queue.jsonl") do
        config = Sift::Config.load(project_path: project_path, user_path: user_path)

        assert_equal "/env/queue.jsonl", config.queue_path
      end
    end
  end

  def test_missing_user_config_uses_defaults
    with_config_file(<<~YAML) do |path|
      agent:
        model: haiku
    YAML
      config = Sift::Config.load(project_path: path, user_path: "/nonexistent/user.yml")

      assert_equal "haiku", config.agent_model
      assert_equal "claude", config.agent_command
      assert_equal 5, config.concurrency
    end
  end

  def test_both_configs_missing_uses_defaults
    config = Sift::Config.load(project_path: "/nonexistent/project.yml", user_path: "/nonexistent/user.yml")

    assert_equal "sonnet", config.agent_model
    assert_equal 5, config.concurrency
    assert_equal "claude", config.agent_command
    assert_equal Sift::Queue::DEFAULT_PATH, config.queue_path
  end

  def test_default_user_path_respects_xdg_config_home
    with_env("XDG_CONFIG_HOME" => "/custom/config") do
      assert_equal "/custom/config/sift/config.yml", Sift::Config.default_user_path
    end
  end

  def test_default_user_path_falls_back_to_dot_config
    with_env("XDG_CONFIG_HOME" => nil) do
      expected = File.join(Dir.home, ".config", "sift", "config.yml")
      assert_equal expected, Sift::Config.default_user_path
    end
  end

  def test_user_config_bad_system_prompt_raises
    with_config_dir do |dir|
      user_path = File.join(dir, "user.yml")
      File.write(user_path, "agent:\n  system_prompt: /nonexistent/prompt.md")

      error = assert_raises(Sift::Config::FileNotFound) do
        Sift::Config.load(project_path: "/nonexistent/project.yml", user_path: user_path)
      end
      assert_includes error.message, "/nonexistent/prompt.md"
    end
  end

  private

  def with_config_dir
    dir = Dir.mktmpdir("sift_config_test_")
    yield dir
  ensure
    FileUtils.rm_rf(dir)
  end

  def with_config_file(content)
    with_config_dir do |dir|
      path = File.join(dir, "config.yml")
      File.write(path, content)
      yield path
    end
  end

  def with_env(vars)
    originals = vars.keys.to_h { |k| [k, ENV[k]] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    originals.each { |k, v| ENV[k] = v }
  end
end
