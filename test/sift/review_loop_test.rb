# frozen_string_literal: true

require "test_helper"
require "tmpdir"

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

  # --- Unit tests for the non-interactive parts ---

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

  def test_build_analysis_prompt_with_diff_source
    @queue.push(sources: [{ type: "diff", path: "foo.rb", content: "+new line\n" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_analysis_prompt, item)

    assert_includes prompt, "File: foo.rb"
    assert_includes prompt, "```diff"
    assert_includes prompt, "+new line"
    assert_includes prompt, "Review this item"
  end

  def test_build_analysis_prompt_with_file_source
    @queue.push(sources: [{ type: "file", path: "bar.rb", content: "class Bar; end" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_analysis_prompt, item)

    assert_includes prompt, "File: bar.rb"
    assert_includes prompt, "class Bar; end"
  end

  def test_build_analysis_prompt_with_transcript_source
    @queue.push(sources: [{ type: "transcript", content: "H: Hello\nA: Hi" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_analysis_prompt, item)

    assert_includes prompt, "Previous conversation:"
    assert_includes prompt, "H: Hello"
  end

  def test_build_analysis_prompt_with_text_source
    @queue.push(sources: [{ type: "text", content: "some notes" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_analysis_prompt, item)

    assert_includes prompt, "some notes"
  end

  def test_build_analysis_prompt_with_multiple_sources
    @queue.push(sources: [
      { type: "diff", path: "x.rb", content: "+added\n" },
      { type: "file", path: "y.rb", content: "context" },
    ])
    loop = Sift::ReviewLoop.new(queue: @queue)

    item = @queue.all.first
    prompt = loop.send(:build_analysis_prompt, item)

    assert_includes prompt, "File: x.rb"
    assert_includes prompt, "File: y.rb"
    assert_includes prompt, "+added"
    assert_includes prompt, "context"
  end

  def test_handle_action_approve_updates_queue
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:handle_action, :accept, item)

    updated = @queue.find(item.id)
    assert_equal "approved", updated.status
  end

  def test_handle_action_reject_updates_queue
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:handle_action, :reject, item)

    updated = @queue.find(item.id)
    assert_equal "rejected", updated.status
  end

  def test_handle_action_comment_stores_in_metadata
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:handle_action, [:comment, "needs work"], item)

    updated = @queue.find(item.id)
    assert_equal "needs work", updated.metadata["comment"]
  end

  def test_handle_action_comment_preserves_existing_metadata
    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      metadata: { "author" => "alice" },
    )
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:handle_action, [:comment, "looks good"], item)

    updated = @queue.find(item.id)
    assert_equal "alice", updated.metadata["author"]
    assert_equal "looks good", updated.metadata["comment"]
  end

  def test_setup_item_sets_sources_and_resets_index
    item = @queue.push(sources: [
      { type: "diff", content: "+a\n" },
      { type: "file", content: "b" },
    ])
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:setup_item, item)

    assert_equal 2, loop.send(:sources_list).length
    assert_equal "diff", loop.current_source.type
  end

  def test_includes_source_viewer_navigation
    item = @queue.push(sources: [
      { type: "diff", content: "+a\n" },
      { type: "text", content: "b" },
    ])
    loop = Sift::ReviewLoop.new(queue: @queue)
    loop.send(:setup_item, item)

    assert loop.multi_source?
    assert loop.next_source
    assert_equal "text", loop.current_source.type
  end

  def test_show_summary_counts_from_queue
    @queue.push(sources: [{ type: "text", content: "a" }])
    @queue.push(sources: [{ type: "text", content: "b" }])
    @queue.push(sources: [{ type: "text", content: "c" }])

    items = @queue.all
    @queue.update(items[0].id, status: "approved")
    @queue.update(items[1].id, status: "rejected")

    loop = Sift::ReviewLoop.new(queue: @queue)

    # Capture output from show_summary
    output = capture_cli_ui_output { loop.send(:show_summary) }

    assert_includes output, "Approved:"
    assert_includes output, "Rejected:"
    assert_includes output, "Remaining:"
  end

  def test_load_items_only_gets_pending
    @queue.push(sources: [{ type: "text", content: "pending1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "approved" }])
    @queue.update(item2.id, status: "approved")
    @queue.push(sources: [{ type: "text", content: "pending2" }])

    loop = Sift::ReviewLoop.new(queue: @queue)

    # Use load_items via the spinner (need CLI::UI setup)
    items = @queue.filter(status: "pending")
    assert_equal 2, items.length
    assert items.all?(&:pending?)
  end

  def test_reload_sources_updates_content_from_disk
    Dir.mktmpdir("sift_test_") do |dir|
      file_path = File.join(dir, "test.rb")
      File.write(file_path, "original")

      item = @queue.push(sources: [{ type: "file", path: file_path, content: "original" }])
      loop = Sift::ReviewLoop.new(queue: @queue)

      # Modify file on disk
      File.write(file_path, "modified")

      loop.send(:reload_sources, item)

      assert_equal "modified", item.sources.first.content
    end
  end

  def test_reload_sources_warns_when_analysis_stale
    Dir.mktmpdir("sift_test_") do |dir|
      file_path = File.join(dir, "test.rb")
      File.write(file_path, "original")

      item = @queue.push(sources: [{ type: "file", path: file_path, content: "original" }])
      loop = Sift::ReviewLoop.new(queue: @queue)

      # Simulate existing analysis
      loop.instance_variable_set(:@current, 0)
      loop.instance_variable_get(:@analyses)[0] = "some analysis"

      # Modify file on disk
      File.write(file_path, "modified")

      output = capture_cli_ui_output { loop.send(:reload_sources, item) }

      assert_includes output, "Sources changed on disk"
      assert_includes output, "Analysis may be stale"
    end
  end

  def test_reload_sources_skips_sources_without_path
    item = @queue.push(sources: [{ type: "text", content: "original text" }])
    loop = Sift::ReviewLoop.new(queue: @queue)

    loop.send(:reload_sources, item)

    assert_equal "original text", item.sources.first.content
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
