# frozen_string_literal: true

require "test_helper"
require "stringio"

class Sift::DryClientTest < Minitest::Test
  def setup
    Sift::Log.reset!
    @client = Sift::DryClient.new(model: "opus")
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
  def test_build_args_includes_system_prompt
    client = Sift::Client.new(system_prompt: "You are a reviewer.")
    args = client.send(:build_args)

    assert_includes args, "--system-prompt"
    idx = args.index("--system-prompt")
    assert_equal "You are a reviewer.", args[idx + 1]
  end

  def test_build_args_excludes_system_prompt_when_nil
    client = Sift::Client.new
    args = client.send(:build_args)

    refute_includes args, "--system-prompt"
  end

  def test_build_args_per_call_system_prompt_overrides_instance
    client = Sift::Client.new(system_prompt: "session default")
    args = client.send(:build_args, system_prompt: "per-item override")

    idx = args.index("--system-prompt")
    assert_equal "per-item override", args[idx + 1]
  end

  def test_build_args_falls_back_to_instance_system_prompt
    client = Sift::Client.new(system_prompt: "session default")
    args = client.send(:build_args, system_prompt: nil)

    idx = args.index("--system-prompt")
    assert_equal "session default", args[idx + 1]
  end
end
