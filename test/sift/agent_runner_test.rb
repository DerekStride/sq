# frozen_string_literal: true

require "test_helper"
require "async"

class Sift::AgentRunnerTest < Minitest::Test
  def test_spawn_tracks_agent
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("abc", "prompt text", "user prompt")

      assert runner.running?("abc")
      assert_equal 1, runner.running_count
    end
  end

  def test_running_returns_false_for_unknown_item
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)

      refute runner.running?("xyz")
      assert_equal 0, runner.running_count
    end
  end

  def test_poll_returns_completed_agents
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("abc", "prompt text", "user prompt")

      # Yield to let the agent fiber complete
      task.yield

      completed = runner.poll
      assert_equal 1, completed.size
      assert completed.key?("abc")
      assert_equal "user prompt", completed["abc"][:prompt]
      assert_instance_of Sift::Client::Result, completed["abc"][:result]
    end
  end

  def test_poll_removes_completed_agents_from_tracking
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("abc", "prompt text", "user prompt")

      task.yield

      runner.poll
      refute runner.running?("abc")
      assert_equal 0, runner.running_count
    end
  end

  def test_poll_returns_empty_hash_when_nothing_completed
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)

      completed = runner.poll
      assert_equal({}, completed)
    end
  end

  def test_multiple_agents
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("a", "prompt a", "user a")
      runner.spawn("b", "prompt b", "user b")

      assert_equal 2, runner.running_count
      assert runner.running?("a")
      assert runner.running?("b")

      task.yield

      completed = runner.poll
      assert_equal 2, completed.size
      assert_equal 0, runner.running_count
    end
  end

  def test_stop_all_cancels_running_agents
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("abc", "prompt text", "user prompt")

      runner.stop_all
      assert_equal 0, runner.running_count
      refute runner.running?("abc")
    end
  end

  def test_spawn_passes_session_id_to_client
    received_session_id = nil
    mock_client = Object.new
    mock_client.define_singleton_method(:prompt) do |text, session_id: nil, system_prompt: nil|
      received_session_id = session_id
      Sift::Client::Result.new(response: "ok", session_id: "new-session", raw: {})
    end

    Sync do |task|
      runner = Sift::AgentRunner.new(client: mock_client, task: task)
      runner.spawn("abc", "prompt", "user", session_id: "existing-session")

      task.yield

      assert_equal "existing-session", received_session_id
    end
  end

  def test_spawn_passes_system_prompt_to_client
    received_system_prompt = nil
    mock_client = Object.new
    mock_client.define_singleton_method(:prompt) do |text, session_id: nil, system_prompt: nil|
      received_system_prompt = system_prompt
      Sift::Client::Result.new(response: "ok", session_id: "new-session", raw: {})
    end

    Sync do |task|
      runner = Sift::AgentRunner.new(client: mock_client, task: task)
      runner.spawn("abc", "prompt", "user", system_prompt: "You are a reviewer.")

      task.yield

      assert_equal "You are a reviewer.", received_system_prompt
    end
  end

  # --- spawn_general tests ---

  def test_spawn_general_tracks_agent
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn_general("prompt text", "user prompt")

      assert runner.running?("_gen_001")
      assert_equal 1, runner.running_count
      assert_equal 1, runner.general_running_count
    end
  end

  def test_spawn_general_increments_counter
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn_general("prompt 1", "user 1")
      runner.spawn_general("prompt 2", "user 2")

      assert runner.running?("_gen_001")
      assert runner.running?("_gen_002")
      assert_equal 2, runner.general_running_count
    end
  end

  def test_poll_returns_general_flag
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn_general("prompt text", "user prompt")

      task.yield

      completed = runner.poll
      assert_equal 1, completed.size
      assert completed.key?("_gen_001")
      assert_equal true, completed["_gen_001"][:general]
      assert_equal "user prompt", completed["_gen_001"][:prompt]
      assert_instance_of Sift::Client::Result, completed["_gen_001"][:result]
    end
  end

  def test_poll_item_agent_has_false_general
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("abc", "prompt text", "user prompt")

      task.yield

      completed = runner.poll
      assert_equal false, completed["abc"][:general]
    end
  end

  def test_general_running_count_with_mixed_agents
    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      runner.spawn("abc", "prompt", "user")
      runner.spawn_general("prompt", "user")
      runner.spawn("def", "prompt", "user")
      runner.spawn_general("prompt", "user")

      assert_equal 4, runner.running_count
      assert_equal 2, runner.general_running_count
    end
  end

  def test_poll_returns_error_when_client_raises
    error_client = Object.new
    error_client.define_singleton_method(:prompt) do |text, session_id: nil, system_prompt: nil|
      raise Sift::Client::Error, "No conversation found with session ID: abc-123"
    end

    Sync do |task|
      runner = Sift::AgentRunner.new(client: error_client, task: task)
      runner.spawn("abc", "prompt", "user", session_id: "abc-123")

      task.yield

      completed = runner.poll
      assert_equal 1, completed.size
      assert_nil completed["abc"][:result]
      assert_includes completed["abc"][:error], "No conversation found"
      assert_equal "user", completed["abc"][:prompt]
      refute runner.running?("abc")
    end
  end
end
