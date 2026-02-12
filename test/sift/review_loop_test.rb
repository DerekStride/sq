# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "async"

class Sift::ReviewLoopTest < Minitest::Test
  include TestHelpers

  def setup
    @tmpdir = create_temp_dir
    @queue_path = create_temp_queue_path(@tmpdir)
    @queue = Sift::Queue.new(@queue_path)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  # --- Constructor tests ---

  def test_initializes_with_queue
    loop = Sift::ReviewLoop.new(queue: @queue)
    assert_instance_of Sift::ReviewLoop, loop
  end

  def test_initializes_with_dry_mode
    loop = Sift::ReviewLoop.new(queue: @queue, dry: true)
    client = loop.instance_variable_get(:@client)
    assert_instance_of Sift::DryClient, client
  end

  def test_initializes_without_dry_mode
    loop = Sift::ReviewLoop.new(queue: @queue)
    client = loop.instance_variable_get(:@client)
    assert_instance_of Sift::Client, client
  end

  # --- build_agent_prompt tests ---

  def test_build_agent_prompt_first_turn_includes_sources
    @queue.push(sources: [
      { type: "diff", path: "foo.rb", content: "+new line\n" },
      { type: "file", path: "bar.rb", content: "class Bar; end" },
    ])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_agent_prompt, item, "Review this")

    assert_includes prompt, "File: foo.rb"
    assert_includes prompt, "```diff"
    assert_includes prompt, "+new line"
    assert_includes prompt, "File: bar.rb"
    assert_includes prompt, "class Bar; end"
    assert_includes prompt, "Review this"
  end

  def test_build_agent_prompt_subsequent_turn_sends_only_user_prompt
    item = @queue.push(
      sources: [{ type: "text", content: "should not appear" }],
      session_id: "existing-session",
    )
    loop = Sift::ReviewLoop.new(queue: @queue)

    prompt = loop.send(:build_agent_prompt, item, "Follow-up question")

    assert_equal "Follow-up question", prompt
    refute_includes prompt, "should not appear"
  end

  def test_build_agent_prompt_with_diff_source
    @queue.push(sources: [{ type: "diff", path: "x.rb", content: "+added\n" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_agent_prompt, item, "check it")

    assert_includes prompt, "File: x.rb"
    assert_includes prompt, "```diff"
    assert_includes prompt, "+added"
    assert_includes prompt, "check it"
  end

  def test_build_agent_prompt_with_file_source
    @queue.push(sources: [{ type: "file", path: "bar.rb", content: "class Bar; end" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_agent_prompt, item, "review")

    assert_includes prompt, "File: bar.rb"
    assert_includes prompt, "class Bar; end"
  end

  def test_build_agent_prompt_with_transcript_source
    @queue.push(sources: [{ type: "transcript", content: "H: Hello\nA: Hi" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_agent_prompt, item, "continue")

    assert_includes prompt, "Previous conversation:"
    assert_includes prompt, "H: Hello"
  end

  def test_build_agent_prompt_with_text_source
    @queue.push(sources: [{ type: "text", content: "some notes" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_agent_prompt, item, "summarize")

    assert_includes prompt, "some notes"
    assert_includes prompt, "summarize"
  end

  # --- handle_close tests ---

  def test_handle_close_sets_status_to_closed
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:handle_close, item)

    updated = @queue.find(item.id)
    assert_equal "closed", updated.status
  end

  # --- display_card tests ---

  def test_display_card_groups_sources_by_type
    @queue.push(sources: [
      { type: "diff", path: "a.rb" },
      { type: "diff", path: "b.rb" },
      { type: "file", path: "c.rb" },
      { type: "text", content: "notes" },
    ])
    loop = Sift::ReviewLoop.new(queue: @queue)
    item = @queue.all.first

    output = capture_cli_ui_output { loop.send(:display_card, item) }

    assert_includes output, "diff"
    assert_includes output, "a.rb"
    assert_includes output, "b.rb"
    assert_includes output, "file"
    assert_includes output, "c.rb"
    assert_includes output, "text"
    assert_includes output, "[inline]"
  end

  # --- process_completed_agents tests ---

  def test_process_completed_agents_appends_transcript
    item = @queue.push(sources: [{ type: "text", content: "original" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt text", "user question")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      assert_equal 2, updated.sources.size
      assert_equal "transcript", updated.sources.last.type
      assert_includes updated.sources.last.content, "user question"
      assert updated.session_id
    end
  end

  private

  def capture_cli_ui_output
    old_stdout = $stdout
    $stdout = StringIO.new
    ::CLI::UI::StdoutRouter.enable
    ::CLI::UI.frame_style = :box
    yield
    $stdout.string
  ensure
    $stdout = old_stdout
  end
end
