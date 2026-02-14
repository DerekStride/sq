# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "tempfile"
require "async"
require "support/fake_git"

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

  def test_initializes_with_config
    rl = Sift::ReviewLoop.new(config: build_config)
    assert_instance_of Sift::ReviewLoop, rl
  end

  def test_initializes_with_dry_mode
    rl = Sift::ReviewLoop.new(config: build_config(dry: true))
    client = rl.instance_variable_get(:@client)
    assert_instance_of Sift::DryClient, client
  end

  def test_initializes_without_dry_mode
    rl = Sift::ReviewLoop.new(config: build_config(dry: false))
    client = rl.instance_variable_get(:@client)
    assert_instance_of Sift::Client, client
  end

  # --- build_agent_prompt tests ---

  def test_build_agent_prompt_first_turn_includes_sources
    @queue.push(sources: [
      { type: "diff", path: "foo.rb", content: "+new line\n" },
      { type: "file", path: "bar.rb", content: "class Bar; end" },
    ])
    rl = Sift::ReviewLoop.new(config: build_config)

    item = @queue.all.first
    prompt = rl.send(:build_agent_prompt, item, "Review this")

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
    rl = Sift::ReviewLoop.new(config: build_config)

    prompt = rl.send(:build_agent_prompt, item, "Follow-up question")

    assert_equal "Follow-up question", prompt
    refute_includes prompt, "should not appear"
  end

  def test_build_agent_prompt_with_diff_source
    @queue.push(sources: [{ type: "diff", path: "x.rb", content: "+added\n" }])
    rl = Sift::ReviewLoop.new(config: build_config)

    item = @queue.all.first
    prompt = rl.send(:build_agent_prompt, item, "check it")

    assert_includes prompt, "File: x.rb"
    assert_includes prompt, "```diff"
    assert_includes prompt, "+added"
    assert_includes prompt, "check it"
  end

  def test_build_agent_prompt_with_file_source
    @queue.push(sources: [{ type: "file", path: "bar.rb", content: "class Bar; end" }])
    rl = Sift::ReviewLoop.new(config: build_config)

    item = @queue.all.first
    prompt = rl.send(:build_agent_prompt, item, "review")

    assert_includes prompt, "File: bar.rb"
    assert_includes prompt, "class Bar; end"
  end

  def test_build_agent_prompt_with_text_source
    @queue.push(sources: [{ type: "text", content: "some notes" }])
    rl = Sift::ReviewLoop.new(config: build_config)

    item = @queue.all.first
    prompt = rl.send(:build_agent_prompt, item, "summarize")

    assert_includes prompt, "some notes"
    assert_includes prompt, "summarize"
  end

  # --- handle_close tests ---

  def test_handle_close_sets_status_to_closed
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(config: build_config)

    rl.send(:handle_close, item)

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
    rl = Sift::ReviewLoop.new(config: build_config)
    item = @queue.all.first

    output = capture_cli_ui_output { rl.send(:display_card, item) }

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
    rl = Sift::ReviewLoop.new(config: build_config)
    item = @queue.all.first

    output = capture_cli_ui_output { rl.send(:display_card, item, position: 2, total: 5) }

    assert_includes output, "[2/5]"
  end

  def test_display_card_omits_position_when_not_provided
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(config: build_config)
    item = @queue.all.first

    output = capture_cli_ui_output { rl.send(:display_card, item) }

    refute_includes output, "/"
  end

  def test_display_card_shows_transcript_when_session_id_present
    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      session_id: "some-session",
    )
    rl = Sift::ReviewLoop.new(config: build_config)

    output = capture_cli_ui_output { rl.send(:display_card, item) }

    assert_includes output, "transcript"
    assert_includes output, "[session]"
  end

  def test_display_card_omits_transcript_without_session_id
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(config: build_config)
    item = @queue.all.first

    output = capture_cli_ui_output { rl.send(:display_card, item) }

    refute_includes output, "transcript"
    refute_includes output, "[session]"
  end

  # --- navigation tests ---

  def test_review_item_returns_next_on_n_key
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(config: build_config)
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
    rl = Sift::ReviewLoop.new(config: build_config)
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
    rl = Sift::ReviewLoop.new(config: build_config)
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
    rl = Sift::ReviewLoop.new(config: build_config)
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

  # --- agent_context tests ---

  def test_agent_context_includes_general_doc_and_prime
    rl = Sift::ReviewLoop.new(config: build_config)

    context = rl.send(:agent_context)

    assert_includes context, "sift"
    assert_includes context, @queue_path
    assert_includes context, "sq prime"
    assert_includes context, "`sq` Commands"
    refute_includes context, "{{queue_path}}"
  end

  # --- general agent key binding ---

  def test_review_item_loops_back_on_general
    @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(config: build_config)
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
    rl = Sift::ReviewLoop.new(config: build_config)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn_general("explore the CLI", "explore the CLI")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      items = @queue.filter(status: "pending")
      assert_equal 1, items.size

      new_item = items.first
      assert_equal "text", new_item.sources.first.type
      assert_equal "explore the CLI", new_item.sources.first.content
      assert_equal "general_agent", new_item.metadata["source"]
      assert_equal "explore the CLI", new_item.metadata["prompt"]
      assert new_item.session_id
    end
  end

  def test_process_completed_general_agent_error_does_not_create_item
    error_client = Object.new
    error_client.define_singleton_method(:prompt) do |text, session_id: nil, append_system_prompt: nil, cwd: nil|
      raise Sift::Client::Error, "API error"
    end

    rl = Sift::ReviewLoop.new(config: build_config)

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
    error_client.define_singleton_method(:prompt) do |text, session_id: nil, append_system_prompt: nil, cwd: nil|
      raise Sift::Client::Error, "No conversation found with session ID: bad-id"
    end

    item = @queue.push(
      sources: [{ type: "text", content: "original" }],
      session_id: "bad-id",
    )
    rl = Sift::ReviewLoop.new(config: build_config)

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

  def test_process_completed_agents_sets_session_id
    item = @queue.push(sources: [{ type: "text", content: "original" }])
    rl = Sift::ReviewLoop.new(config: build_config)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt text", "user question")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      assert_equal 1, updated.sources.size
      assert_equal "text", updated.sources.first.type
      assert updated.session_id
    end
  end

  def test_quit_saves_completed_agent_session_id
    item = @queue.push(sources: [{ type: "text", content: "original" }])
    rl = Sift::ReviewLoop.new(config: build_config)

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
      assert_equal 1, updated.sources.size
      assert updated.session_id
    end
  end

  # --- worktree integration tests ---

  def test_handle_agent_creates_worktree_and_spawns_with_cwd
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    rl = Sift::ReviewLoop.new(config: build_config)

    wt = Sift::Queue::Worktree.new(path: ".sift/worktrees/#{item.id}", branch: "sift/#{item.id}")
    worktree_created = false
    spawned_cwd = nil

    mock_client = Object.new
    mock_client.define_singleton_method(:prompt) do |text, session_id: nil, append_system_prompt: nil, cwd: nil|
      spawned_cwd = cwd
      Sift::Client::Result.new(response: "ok", session_id: "new-session", raw: {})
    end

    Sift::Worktree.stub(:create, ->(_id, base_branch:, setup_command:) {
      worktree_created = true
      wt
    }) do
      Sync do |task|
        runner = Sift::AgentRunner.new(client: mock_client, task: task)
        rl.instance_variable_set(:@agent_runner, runner)
        rl.instance_variable_set(:@client, mock_client)

        # Simulate typing "review" + Enter
        chars = "review\r".chars
        char_index = 0
        $stdin.stub(:getch, -> {
          c = chars[char_index] || "\r"
          char_index += 1
          c
        }) do
          capture_cli_ui_output { rl.send(:handle_agent, item) }
        end

        task.yield
      end
    end

    assert worktree_created, "Worktree should have been created"
    assert_equal ".sift/worktrees/#{item.id}", spawned_cwd

    # Verify worktree was persisted on the queue item
    updated = @queue.find(item.id)
    assert_equal ".sift/worktrees/#{item.id}", updated.worktree&.path
  end

  def test_handle_agent_uses_existing_worktree
    wt = Sift::Queue::Worktree.new(path: ".sift/worktrees/existing", branch: "sift/existing")
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    @queue.update(item.id, worktree: wt)
    item = @queue.find(item.id)

    rl = Sift::ReviewLoop.new(config: build_config)

    worktree_created = false
    spawned_cwd = nil

    mock_client = Object.new
    mock_client.define_singleton_method(:prompt) do |text, session_id: nil, append_system_prompt: nil, cwd: nil|
      spawned_cwd = cwd
      Sift::Client::Result.new(response: "ok", session_id: "new-session", raw: {})
    end

    Sift::Worktree.stub(:create, ->(*args, **kwargs) {
      worktree_created = true
      raise "Should not be called"
    }) do
      Sync do |task|
        runner = Sift::AgentRunner.new(client: mock_client, task: task)
        rl.instance_variable_set(:@agent_runner, runner)
        rl.instance_variable_set(:@client, mock_client)

        chars = "review\r".chars
        char_index = 0
        $stdin.stub(:getch, -> {
          c = chars[char_index] || "\r"
          char_index += 1
          c
        }) do
          capture_cli_ui_output { rl.send(:handle_agent, item) }
        end

        task.yield
      end
    end

    refute worktree_created, "Should not create worktree when one exists"
    assert_equal ".sift/worktrees/existing", spawned_cwd
  end

  def test_handle_general_agent_does_not_create_worktree
    rl = Sift::ReviewLoop.new(config: build_config)

    worktree_created = false

    Sift::Worktree.stub(:create, ->(*args, **kwargs) {
      worktree_created = true
      raise "Should not be called"
    }) do
      Sync do |task|
        runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
        rl.instance_variable_set(:@agent_runner, runner)

        # Stub getch to return Enter (empty prompt → no-op)
        $stdin.stub(:getch, "\r") do
          capture_cli_ui_output { rl.send(:handle_general_agent) }
        end
      end
    end

    refute worktree_created, "General agent should not create worktree"
  end

  # --- post-agent worktree source capture ---

  def test_completed_agent_adds_diff_and_directory_sources
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    wt = Sift::Queue::Worktree.new(path: ".sift/worktrees/abc", branch: "sift/abc")
    @queue.update(item.id, worktree: wt)

    fake_git = FakeGit.new(has_commits: true, diff_output: "+added line\n")

    rl = Sift::ReviewLoop.new(config: build_config)
    rl.instance_variable_set(:@git, fake_git)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt", "prompt")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      types = updated.sources.map(&:type)
      assert_includes types, "diff"
      assert_includes types, "directory"

      diff_src = updated.sources.find { |s| s.type == "diff" && s.path == "worktree" }
      assert_includes diff_src.content, "+added line"

      dir_src = updated.sources.find { |s| s.type == "directory" }
      assert_equal ".sift/worktrees/abc", dir_src.path
    end
  end

  def test_completed_agent_adds_only_directory_when_no_commits
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    wt = Sift::Queue::Worktree.new(path: ".sift/worktrees/abc", branch: "sift/abc")
    @queue.update(item.id, worktree: wt)

    fake_git = FakeGit.new(has_commits: false)

    rl = Sift::ReviewLoop.new(config: build_config)
    rl.instance_variable_set(:@git, fake_git)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt", "prompt")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      types = updated.sources.map(&:type)
      refute_includes types, "diff"
      assert_includes types, "directory"
    end
  end

  def test_completed_agent_no_sources_without_worktree
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    rl = Sift::ReviewLoop.new(config: build_config)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt", "prompt")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      assert_equal 1, updated.sources.size
      assert_equal "text", updated.sources.first.type
    end
  end

  def test_completed_agent_replaces_existing_auto_diff
    item = @queue.push(sources: [
      { type: "text", content: "test" },
      { type: "diff", path: "worktree", content: "old diff" },
    ])
    wt = Sift::Queue::Worktree.new(path: ".sift/worktrees/abc", branch: "sift/abc")
    @queue.update(item.id, worktree: wt)

    fake_git = FakeGit.new(has_commits: true, diff_output: "+new diff\n")

    rl = Sift::ReviewLoop.new(config: build_config)
    rl.instance_variable_set(:@git, fake_git)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt", "prompt")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      diff_sources = updated.sources.select { |s| s.type == "diff" }
      assert_equal 1, diff_sources.size
      assert_includes diff_sources.first.content, "+new diff"
    end
  end

  def test_completed_agent_does_not_duplicate_directory_source
    item = @queue.push(sources: [
      { type: "text", content: "test" },
      { type: "directory", path: ".sift/worktrees/abc" },
    ])
    wt = Sift::Queue::Worktree.new(path: ".sift/worktrees/abc", branch: "sift/abc")
    @queue.update(item.id, worktree: wt)

    fake_git = FakeGit.new(has_commits: false)

    rl = Sift::ReviewLoop.new(config: build_config)
    rl.instance_variable_set(:@git, fake_git)

    Sync do |task|
      runner = Sift::AgentRunner.new(client: Sift::DryClient.new, task: task)
      rl.instance_variable_set(:@agent_runner, runner)

      runner.spawn(item.id, "prompt", "prompt")
      task.yield

      capture_cli_ui_output { rl.send(:process_completed_agents) }

      updated = @queue.find(item.id)
      dir_sources = updated.sources.select { |s| s.type == "directory" }
      assert_equal 1, dir_sources.size
    end
  end

  private

  def build_config(dry: true, **overrides)
    config = Sift::Config.new({}, overrides.transform_keys(&:to_s))
    config.queue_path = @queue_path
    config.dry = dry
    config
  end

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
    $stdin.stub(:tty?, false) do
      ::CLI::UI::Prompt.stub(:read_char, -> {
        char = chars[index] || "q"
        index += 1
        char
      }) do
        yield
      end
    end
  end
end
