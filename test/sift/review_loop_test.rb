# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "tempfile"
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

  def test_initializes_with_system_prompt
    loop = Sift::ReviewLoop.new(queue: @queue, system_prompt: "You are a reviewer.")
    client = loop.instance_variable_get(:@client)
    assert_equal "You are a reviewer.", client.instance_variable_get(:@system_prompt)
  end

  # --- resolve_system_prompt tests ---

  def test_resolve_system_prompt_reads_file_from_metadata
    tmpfile = Tempfile.new(["sp-", ".md"])
    tmpfile.write("You are a reviewer.")
    tmpfile.close

    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      metadata: { "system_prompt" => tmpfile.path },
    )
    loop = Sift::ReviewLoop.new(queue: @queue)

    result = loop.send(:resolve_system_prompt, item)
    assert_equal "You are a reviewer.", result
  ensure
    tmpfile&.unlink
  end

  def test_resolve_system_prompt_returns_nil_without_metadata
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    assert_nil loop.send(:resolve_system_prompt, item)
  end

  def test_resolve_system_prompt_returns_nil_for_missing_file
    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      metadata: { "system_prompt" => "/nonexistent/prompt.md" },
    )
    loop = Sift::ReviewLoop.new(queue: @queue)

    _, stderr = with_log_level("WARN") do
      capture_io { assert_nil loop.send(:resolve_system_prompt, item) }
    end

    assert_includes stderr, "system prompt file not found"
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

  def test_display_card_shows_position_when_provided
    @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)
    item = @queue.all.first

    output = capture_cli_ui_output { loop.send(:display_card, item, position: 2, total: 5) }

    assert_includes output, "[2/5]"
  end

  def test_display_card_omits_position_when_not_provided
    @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)
    item = @queue.all.first

    output = capture_cli_ui_output { loop.send(:display_card, item) }

    refute_includes output, "/"
  end

  # --- navigation tests ---

  def test_review_item_returns_next_on_n_key
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)
    item = @queue.all.first

    Sync do |task|
      rl.instance_variable_set(:@agent_runner, Sift::AgentRunner.new(client: Sift::DryClient.new, task: task))

      stub_read_char("n") do
        result = nil
        capture_cli_ui_output do
          result = rl.send(:review_item, item, position: 1, total: 3)
        end
        assert_equal :next, result
      end
    end
  end

  def test_review_item_returns_prev_on_p_key
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)
    item = @queue.all.first

    Sync do |task|
      rl.instance_variable_set(:@agent_runner, Sift::AgentRunner.new(client: Sift::DryClient.new, task: task))

      stub_read_char("p") do
        result = nil
        capture_cli_ui_output do
          result = rl.send(:review_item, item, position: 2, total: 3)
        end
        assert_equal :prev, result
      end
    end
  end

  def test_nav_keys_ignored_with_single_item
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)
    item = @queue.all.first

    Sync do |task|
      rl.instance_variable_set(:@agent_runner, Sift::AgentRunner.new(client: Sift::DryClient.new, task: task))

      # n is ignored (show_nav: false), then q quits
      stub_read_char("n", "q") do
        result = nil
        capture_cli_ui_output do
          result = rl.send(:review_item, item, position: 1, total: 1)
        end
        assert_equal :quit, result
      end
    end
  end

  def test_review_item_returns_acted_on_close
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)
    item = @queue.all.first

    Sync do |task|
      rl.instance_variable_set(:@agent_runner, Sift::AgentRunner.new(client: Sift::DryClient.new, task: task))

      stub_read_char("c") do
        result = nil
        capture_cli_ui_output do
          result = rl.send(:review_item, item, position: 1, total: 3)
        end
        assert_equal :acted, result
      end
    end
  end

  # --- general_agent_system_prompt tests ---

  def test_general_agent_system_prompt_includes_queue_path
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)

    prompt = rl.send(:general_agent_system_prompt)

    assert_includes prompt, "sift"
    assert_includes prompt, @queue_path
    assert_includes prompt, "sq --help"
    refute_includes prompt, "{{queue_path}}"
  end

  # --- general agent key binding ---

  def test_review_item_loops_back_on_general
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)
    item = @queue.all.first

    Sync do |task|
      rl.instance_variable_set(:@agent_runner, Sift::AgentRunner.new(client: Sift::DryClient.new, task: task))

      # g triggers general (loops back), then q quits — item is unaffected
      call_count = 0
      stub_read_char("g", "q") do
        $stdin.stub(:getch, -> {
          call_count += 1
          "\r" # just press enter with empty prompt → no-op
        }) do
          result = nil
          capture_cli_ui_output do
            result = rl.send(:review_item, item, position: 1, total: 1)
          end
          assert_equal :quit, result
        end
      end
    end
  end

  # --- process_completed_agents tests ---

  def test_process_completed_general_agent_creates_new_item
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn_general("explore the CLI", "explore the CLI")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      items = @queue.filter(status: "pending")
      assert_equal 1, items.size

      new_item = items.first
      assert_equal "transcript", new_item.sources.first.type
      assert_includes new_item.sources.first.content, "explore the CLI"
      assert_equal "general_agent", new_item.metadata["source"]
      assert_equal "explore the CLI", new_item.metadata["prompt"]
      assert new_item.session_id
    end
  end

  def test_process_completed_general_agent_error_does_not_create_item
    error_client = Object.new
    error_client.define_singleton_method(:prompt) do |text, session_id: nil, system_prompt: nil|
      raise Sift::Client::Error, "API error"
    end

    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: error_client, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn_general("bad prompt", "bad prompt")
      task.yield

      output = capture_cli_ui_output { rl.send(:process_completed_agents) }

      # No new items created
      assert_equal 0, @queue.count
      assert_includes output, "General agent failed"
    end
  end

  def test_process_completed_agents_records_error_on_item
    error_client = Object.new
    error_client.define_singleton_method(:prompt) do |text, session_id: nil, system_prompt: nil|
      raise Sift::Client::Error, "No conversation found with session ID: bad-id"
    end

    item = @queue.push(
      sources: [{ type: "text", content: "original" }],
      session_id: "bad-id",
    )
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: error_client, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt text", "user question", session_id: "bad-id")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      assert_equal 1, updated.errors.size
      assert_includes updated.errors.first["message"], "No conversation found"
      assert_equal "user question", updated.errors.first["prompt"]
      assert updated.errors.first["timestamp"]
      # session_id preserved
      assert_equal "bad-id", updated.session_id
    end
  end

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

  def test_quit_saves_completed_agent_transcripts
    item = @queue.push(sources: [{ type: "text", content: "original" }])
    rl = Sift::ReviewLoop.new(queue: @queue, dry: true)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt text", "user question")
      task.yield

      # Agent has completed but hasn't been polled yet — simulate quit
      capture_cli_ui_output do
        rl.send(:process_completed_agents)
        runner.stop_all
      end

      updated = @queue.find(item.id)
      assert_equal 2, updated.sources.size
      assert_equal "transcript", updated.sources.last.type
      assert_includes updated.sources.last.content, "user question"
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

  def stub_read_char(*chars)
    chars = chars.flatten
    index = 0
    ::CLI::UI::Prompt.stub(:read_char, -> {
      char = chars[index] || "q"
      index += 1
      char
    }) do
      yield
    end
  end
end
