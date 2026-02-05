# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Sift::Roast::OrchestratorTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @queue_path = File.join(@temp_dir, "queue.jsonl")
    @queue = Sift::Queue.new(@queue_path)

    # Create dummy workflow files
    @workflow_path = File.join(@temp_dir, "workflow.rb")
    @revision_workflow_path = File.join(@temp_dir, "revision_workflow.rb")
    File.write(@workflow_path, "# dummy workflow")
    File.write(@revision_workflow_path, "# dummy revision workflow")
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  # --- Initialization tests ---

  def test_initialize_with_valid_workflow
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    assert_equal @workflow_path, orchestrator.workflow
    assert_equal @queue, orchestrator.queue
    assert_nil orchestrator.revision_workflow
  end

  def test_initialize_with_revision_workflow
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue,
      revision_workflow: @revision_workflow_path
    )

    assert_equal @revision_workflow_path, orchestrator.revision_workflow
  end

  def test_initialize_raises_for_missing_workflow
    error = assert_raises(Sift::Roast::Error) do
      Sift::Roast::Orchestrator.new(
        workflow: "/nonexistent/workflow.rb",
        queue: @queue
      )
    end

    assert_match(/workflow not found/i, error.message)
    assert_match(/nonexistent/, error.message)
  end

  def test_initialize_raises_for_missing_revision_workflow
    error = assert_raises(Sift::Roast::Error) do
      Sift::Roast::Orchestrator.new(
        workflow: @workflow_path,
        queue: @queue,
        revision_workflow: "/nonexistent/revision.rb"
      )
    end

    assert_match(/workflow not found/i, error.message)
  end

  # --- build_command tests ---

  def test_build_command_basic
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    cmd = orchestrator.send(:build_command, @workflow_path, [], {})

    assert_equal ["bundle", "exec", "roast", "execute", @workflow_path], cmd
  end

  def test_build_command_with_targets
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    cmd = orchestrator.send(:build_command, @workflow_path, ["target1", "target2"], {})

    expected = ["bundle", "exec", "roast", "execute", @workflow_path, "target1", "target2"]
    assert_equal expected, cmd
  end

  def test_build_command_with_kwargs
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    cmd = orchestrator.send(:build_command, @workflow_path, [], { key1: "value1", key2: "value2" })

    expected = ["bundle", "exec", "roast", "execute", @workflow_path, "--", "key1=value1", "key2=value2"]
    assert_equal expected, cmd
  end

  def test_build_command_with_targets_and_kwargs
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    cmd = orchestrator.send(:build_command, @workflow_path, ["target.rb"], { mode: "strict" })

    expected = ["bundle", "exec", "roast", "execute", @workflow_path, "target.rb", "--", "mode=strict"]
    assert_equal expected, cmd
  end

  # --- build_env tests ---

  def test_build_env_sets_queue_path
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    env = orchestrator.send(:build_env)

    assert_equal @queue_path, env[Sift::Roast::QUEUE_PATH_ENV]
  end

  # --- revise without revision_workflow ---

  def test_revise_returns_nil_without_revision_workflow
    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue
    )

    result = orchestrator.revise(item_id: "abc", feedback: "needs work")

    assert_nil result
  end

  def test_revise_raises_for_missing_item
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    orchestrator = Sift::Roast::Orchestrator.new(
      workflow: @workflow_path,
      queue: @queue,
      revision_workflow: @revision_workflow_path
    )

    error = assert_raises(Sift::Roast::Error) do
      orchestrator.revise(item_id: "nonexistent", feedback: "fix this")
    end

    assert_match(/not found/i, error.message)
  end
end
