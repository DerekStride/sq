# frozen_string_literal: true

require "test_helper"
require "stringio"

class Sift::DryClientTest < Minitest::Test
  def setup
    Sift::Log.reset!
    @config = Sift::Config.new("agent" => { "model" => "opus" })
    @client = Sift::DryClient.new(config: @config)
  end

  def teardown
    Sift::Log.reset!
  end

  def test_prompt_returns_result
    result = nil
    capture_io { result = @client.prompt("Hello world") }

    assert_instance_of Sift::Client::Result, result
    assert_includes result.response, "dry mode"
    assert result.session_id.start_with?("dry-")
  end

  def test_prompt_preserves_existing_session_id
    result = nil
    capture_io { result = @client.prompt("Hello", session_id: "existing-session") }

    assert_equal "existing-session", result.session_id
  end

  def test_prompt_logs_details
    _, stderr = with_log_level("DEBUG") do
      capture_io { @client.prompt("Review this code\nMore details", session_id: "sess-1") }
    end

    assert_includes stderr, "[dry] model=opus session=sess-1"
    assert_includes stderr, "[dry] prompt: Review this code"
  end

  def test_prompt_logs_new_session_when_none
    _, stderr = with_log_level("DEBUG") do
      capture_io { @client.prompt("Hello") }
    end

    assert_includes stderr, "session=new"
  end

  def test_prompt_accepts_cwd
    _, stderr = with_log_level("DEBUG") do
      capture_io { @client.prompt("Hello", cwd: "/some/path") }
    end

    assert_includes stderr, "cwd=/some/path"
  end

  def test_analyze_diff_delegates_to_prompt
    result = nil
    _, stderr = with_log_level("DEBUG") do
      capture_io { result = @client.analyze_diff("+foo", file: "bar.rb") }
    end

    assert_instance_of Sift::Client::Result, result
    assert_includes stderr, "File: bar.rb"
  end

  def test_default_model
    client = Sift::DryClient.new
    _, stderr = with_log_level("DEBUG") do
      capture_io { client.prompt("test") }
    end

    assert_includes stderr, "model=default"
  end
end

class Sift::ClientBuildArgsTest < Minitest::Test
  def test_build_args_uses_config_command
    config = Sift::Config.new("agent" => { "command" => "my-claude", "model" => nil })
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    assert_equal "my-claude", args.first
  end

  def test_build_args_includes_config_flags
    config = Sift::Config.new("agent" => { "flags" => ["--verbose", "--no-cache"] })
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    assert_includes args, "--verbose"
    assert_includes args, "--no-cache"
  end

  def test_build_args_includes_allowed_tools
    config = Sift::Config.new("agent" => { "allowed_tools" => ["Read", "Write"] })
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    # Should have --allowedTools Read --allowedTools Write
    tool_indices = args.each_index.select { |i| args[i] == "--allowedTools" }
    assert_equal 2, tool_indices.size
    assert_equal "Read", args[tool_indices[0] + 1]
    assert_equal "Write", args[tool_indices[1] + 1]
  end

  def test_build_args_includes_append_system_prompt
    config = Sift::Config.new
    client = Sift::Client.new(config: config)
    args = client.send(:build_args, append_system_prompt: "Extra context here.")

    assert_includes args, "--append-system-prompt"
    idx = args.index("--append-system-prompt")
    assert_equal "Extra context here.", args[idx + 1]
  end

  def test_build_args_excludes_append_system_prompt_when_nil
    config = Sift::Config.new
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    refute_includes args, "--append-system-prompt"
  end

  def test_build_args_default_command_is_claude
    config = Sift::Config.new
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    assert_equal "claude", args.first
  end

  def test_build_args_empty_flags_are_skipped
    config = Sift::Config.new("agent" => { "flags" => [] })
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    # Should just be: claude -p --output-format json --model sonnet
    assert_equal "claude", args[0]
    assert_equal "-p", args[1]
  end

  def test_build_args_empty_allowed_tools_are_skipped
    config = Sift::Config.new("agent" => { "allowed_tools" => [] })
    client = Sift::Client.new(config: config)
    args = client.send(:build_args)

    refute_includes args, "--allowedTools"
  end
end
