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
    mock_client.define_singleton_method(:prompt) do |text, session_id: nil|
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
end
