# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Sift::QueueTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @queue_path = File.join(@temp_dir, "queue.jsonl")
    @queue = Sift::Queue.new(@queue_path)
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  # --- Source struct tests ---

  def test_source_to_h_includes_all_fields
    source = Sift::Queue::Source.new(
      type: "file",
      path: "/path/to/file.rb",
      content: "content here",
      session_id: "sess123"
    )

    hash = source.to_h
    assert_equal "file", hash[:type]
    assert_equal "/path/to/file.rb", hash[:path]
    assert_equal "content here", hash[:content]
    assert_equal "sess123", hash[:session_id]
  end

  def test_source_to_h_omits_nil_values
    source = Sift::Queue::Source.new(type: "text", content: "hello")

    hash = source.to_h
    assert_equal "text", hash[:type]
    assert_equal "hello", hash[:content]
    refute hash.key?(:path)
    refute hash.key?(:session_id)
  end

  def test_source_from_h_with_string_keys
    hash = { "type" => "diff", "path" => "/diff.patch", "session_id" => "abc" }
    source = Sift::Queue::Source.from_h(hash)

    assert_equal "diff", source.type
    assert_equal "/diff.patch", source.path
    assert_equal "abc", source.session_id
  end

  def test_source_from_h_with_symbol_keys
    hash = { type: "transcript", path: "/chat.txt" }
    source = Sift::Queue::Source.from_h(hash)

    assert_equal "transcript", source.type
    assert_equal "/chat.txt", source.path
  end

  # --- Item struct tests ---

  def test_item_to_h_includes_all_fields
    source = Sift::Queue::Source.new(type: "text", content: "test")
    item = Sift::Queue::Item.new(
      id: "abc",
      status: "pending",
      sources: [source],
      metadata: { key: "value" },
      session_id: "sess",
      created_at: "2025-01-01T00:00:00Z",
      updated_at: "2025-01-01T00:00:00Z"
    )

    hash = item.to_h
    assert_equal "abc", hash[:id]
    assert_equal "pending", hash[:status]
    assert_equal 1, hash[:sources].length
    assert_equal "text", hash[:sources].first[:type]
    assert_equal({ key: "value" }, hash[:metadata])
  end

  def test_item_from_h_with_string_keys
    hash = {
      "id" => "xyz",
      "status" => "closed",
      "sources" => [{ "type" => "file", "path" => "/test.rb" }],
      "metadata" => { "foo" => "bar" },
      "session_id" => "s1",
      "created_at" => "2025-01-01",
      "updated_at" => "2025-01-02"
    }

    item = Sift::Queue::Item.from_h(hash)
    assert_equal "xyz", item.id
    assert_equal "closed", item.status
    assert_equal 1, item.sources.length
    assert_equal "file", item.sources.first.type
    assert_equal({ "foo" => "bar" }, item.metadata)
  end

  def test_item_errors_default_to_empty_array
    item = Sift::Queue::Item.from_h({ "id" => "abc", "status" => "pending", "sources" => [] })
    assert_equal [], item.errors
  end

  def test_item_errors_roundtrip_through_queue
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    errors = [{ "message" => "session not found", "prompt" => "fix it", "timestamp" => "2025-01-01T00:00:00Z" }]
    @queue.update(item.id, errors: errors)

    reloaded = @queue.find(item.id)
    assert_equal 1, reloaded.errors.size
    assert_equal "session not found", reloaded.errors.first["message"]
  end

  def test_item_to_h_omits_errors_when_empty
    source = Sift::Queue::Source.new(type: "text", content: "test")
    item = Sift::Queue::Item.new(id: "abc", status: "pending", sources: [source], errors: [])
    refute item.to_h.key?(:errors)
  end

  def test_item_status_predicates
    item = Sift::Queue::Item.new(id: "1", status: "pending", sources: [])
    assert item.pending?
    refute item.in_progress?

    item = Sift::Queue::Item.new(id: "2", status: "in_progress", sources: [])
    assert item.in_progress?
    refute item.pending?

    item = Sift::Queue::Item.new(id: "3", status: "closed", sources: [])
    assert item.closed?
  end

  # --- push tests ---

  def test_push_creates_item_with_pending_status
    item = @queue.push(sources: [{ type: "text", content: "hello" }])

    assert item.id
    assert_equal "pending", item.status
    assert_equal 1, item.sources.length
    assert item.created_at
    assert item.updated_at
  end

  def test_push_with_metadata
    item = @queue.push(
      sources: [{ type: "file", path: "/test.rb" }],
      metadata: { workflow: "analyze", priority: 1 }
    )

    assert_equal "analyze", item.metadata[:workflow]
    assert_equal 1, item.metadata[:priority]
  end

  def test_push_with_session_id
    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      session_id: "my-session"
    )

    assert_equal "my-session", item.session_id
  end

  def test_push_with_multiple_sources
    item = @queue.push(sources: [
      { type: "diff", path: "/changes.diff" },
      { type: "text", content: "Summary" },
      { type: "file", path: "/main.rb" }
    ])

    assert_equal 3, item.sources.length
    assert_equal "diff", item.sources[0].type
    assert_equal "text", item.sources[1].type
    assert_equal "file", item.sources[2].type
  end

  def test_push_generates_unique_ids
    ids = 20.times.map do
      @queue.push(sources: [{ type: "text", content: "test" }]).id
    end

    assert_equal 20, ids.uniq.length, "All IDs should be unique"
  end

  def test_push_with_source_struct
    source = Sift::Queue::Source.new(type: "text", content: "test")
    item = @queue.push(sources: [source])

    assert_equal "text", item.sources.first.type
  end

  # --- find tests ---

  def test_find_returns_item_by_id
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    found = @queue.find(item.id)

    assert_equal item.id, found.id
    assert_equal item.status, found.status
  end

  def test_find_returns_nil_for_nonexistent_id
    assert_nil @queue.find("nonexistent")
  end

  # --- update tests ---

  def test_update_changes_status
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    updated = @queue.update(item.id, status: "in_progress")

    assert_equal "in_progress", updated.status
    assert_equal "in_progress", @queue.find(item.id).status
  end

  def test_update_changes_metadata
    item = @queue.push(
      sources: [{ type: "text", content: "test" }],
      metadata: { old: true }
    )

    updated = @queue.update(item.id, metadata: { new: true })

    assert_equal({ new: true }, updated.metadata)
  end

  def test_update_sets_updated_at
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    original_updated = item.updated_at

    sleep 1.1 # ensure time difference (iso8601 has second precision)
    updated = @queue.update(item.id, status: "closed")

    refute_equal original_updated, updated.updated_at
  end

  def test_update_returns_nil_for_nonexistent_id
    result = @queue.update("nonexistent", status: "closed")
    assert_nil result
  end

  # --- filter tests ---

  def test_filter_by_status
    @queue.push(sources: [{ type: "text", content: "1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "2" }])
    @queue.update(item2.id, status: "closed")
    @queue.push(sources: [{ type: "text", content: "3" }])

    pending = @queue.filter(status: "pending")
    closed = @queue.filter(status: "closed")

    assert_equal 2, pending.length
    assert_equal 1, closed.length
    assert_equal item2.id, closed.first.id
  end

  def test_filter_without_status_returns_all
    3.times { @queue.push(sources: [{ type: "text", content: "test" }]) }

    all_items = @queue.filter
    assert_equal 3, all_items.length
  end

  def test_filter_with_symbol_status
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    @queue.update(item.id, status: "closed")

    closed = @queue.filter(status: :closed)
    assert_equal 1, closed.length
  end

  # --- each_pending tests ---

  def test_each_pending_iterates_over_pending_items
    @queue.push(sources: [{ type: "text", content: "1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "2" }])
    @queue.update(item2.id, status: "closed")
    @queue.push(sources: [{ type: "text", content: "3" }])

    pending_ids = []
    @queue.each_pending { |item| pending_ids << item.id }

    assert_equal 2, pending_ids.length
    refute_includes pending_ids, item2.id
  end

  # --- count tests ---

  def test_count_returns_total_items
    3.times { @queue.push(sources: [{ type: "text", content: "test" }]) }
    assert_equal 3, @queue.count
  end

  def test_count_with_status_filter
    @queue.push(sources: [{ type: "text", content: "1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "2" }])
    @queue.update(item2.id, status: "closed")

    assert_equal 1, @queue.count(status: "pending")
    assert_equal 1, @queue.count(status: "closed")
  end

  # --- remove tests ---

  def test_remove_deletes_item
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    removed = @queue.remove(item.id)

    assert_equal item.id, removed.id
    assert_nil @queue.find(item.id)
    assert_equal 0, @queue.count
  end

  def test_remove_returns_nil_for_nonexistent_id
    result = @queue.remove("nonexistent")
    assert_nil result
  end

  def test_remove_preserves_other_items
    item1 = @queue.push(sources: [{ type: "text", content: "1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "2" }])
    item3 = @queue.push(sources: [{ type: "text", content: "3" }])

    @queue.remove(item2.id)

    assert @queue.find(item1.id)
    assert_nil @queue.find(item2.id)
    assert @queue.find(item3.id)
    assert_equal 2, @queue.count
  end

  # --- clear tests ---

  def test_clear_removes_all_items
    3.times { @queue.push(sources: [{ type: "text", content: "test" }]) }

    @queue.clear

    assert_equal 0, @queue.count
    assert_empty @queue.all
  end

  # --- Validation errors ---

  def test_push_raises_on_empty_sources
    error = assert_raises(Sift::Queue::Error) do
      @queue.push(sources: [])
    end
    assert_match(/cannot be empty/i, error.message)
  end

  def test_push_raises_on_nil_sources
    error = assert_raises(Sift::Queue::Error) do
      @queue.push(sources: nil)
    end
    assert_match(/cannot be empty/i, error.message)
  end

  def test_push_raises_on_invalid_source_type
    error = assert_raises(Sift::Queue::Error) do
      @queue.push(sources: [{ type: "invalid", content: "test" }])
    end
    assert_match(/invalid source type/i, error.message)
    assert_match(/invalid/i, error.message)
  end

  def test_update_raises_on_invalid_status
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    error = assert_raises(Sift::Queue::Error) do
      @queue.update(item.id, status: "invalid_status")
    end
    assert_match(/invalid status/i, error.message)
  end

  # --- JSONL persistence tests ---

  def test_persistence_write_and_read
    item1 = @queue.push(sources: [{ type: "text", content: "first" }])
    item2 = @queue.push(
      sources: [{ type: "file", path: "/test.rb" }],
      metadata: { key: "value" }
    )

    # Create a new queue instance to read from the same file
    new_queue = Sift::Queue.new(@queue_path)

    items = new_queue.all
    assert_equal 2, items.length

    found1 = new_queue.find(item1.id)
    assert_equal "text", found1.sources.first.type
    assert_equal "first", found1.sources.first.content

    found2 = new_queue.find(item2.id)
    assert_equal "/test.rb", found2.sources.first.path
    assert_equal "value", found2.metadata["key"]
  end

  def test_persistence_handles_updates
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    @queue.update(item.id, status: "closed")

    new_queue = Sift::Queue.new(@queue_path)
    found = new_queue.find(item.id)

    assert_equal "closed", found.status
  end

  def test_all_returns_empty_array_when_file_not_exists
    queue = Sift::Queue.new("/nonexistent/path/queue.jsonl")
    assert_empty queue.all
  end

  def test_persistence_creates_directory
    nested_path = File.join(@temp_dir, "nested", "deep", "queue.jsonl")
    queue = Sift::Queue.new(nested_path)

    queue.push(sources: [{ type: "text", content: "test" }])

    assert File.exist?(nested_path)
  end

  # --- Corrupt line recovery tests ---

  def test_all_skips_corrupt_line_in_middle
    with_log_level("FATAL") do
      item1 = @queue.push(sources: [{ type: "text", content: "first" }])
      # Inject a corrupt line between valid items
      File.open(@queue_path, "a") { |f| f.puts("not valid json{{{") }
      item3 = @queue.push(sources: [{ type: "text", content: "third" }])

      items = @queue.all
      assert_equal 2, items.length
      assert_equal item1.id, items[0].id
      assert_equal item3.id, items[1].id
    end
  end

  def test_all_skips_corrupt_trailing_line
    with_log_level("FATAL") do
      item1 = @queue.push(sources: [{ type: "text", content: "valid" }])
      File.open(@queue_path, "a") { |f| f.print('{"id":"x","status":"pending"') } # truncated JSON

      items = @queue.all
      assert_equal 1, items.length
      assert_equal item1.id, items[0].id
    end
  end

  def test_all_logs_warning_for_corrupt_lines
    @queue.push(sources: [{ type: "text", content: "valid" }])
    File.open(@queue_path, "a") { |f| f.puts("corrupt line") }

    with_log_level("WARN") do
      output = capture_io { @queue.all }
      assert_match(/corrupt line 2/i, output[1])
    end
  end

  def test_all_recovers_all_valid_lines_from_mixed_file
    with_log_level("FATAL") do
      # Build a file with valid, corrupt, valid, blank, corrupt, valid
      lines = [
        '{"id":"aaa","status":"pending","sources":[{"type":"text","content":"one"}],"metadata":{},"created_at":"2025-01-01","updated_at":"2025-01-01"}',
        "bad json 1",
        '{"id":"bbb","status":"pending","sources":[{"type":"text","content":"two"}],"metadata":{},"created_at":"2025-01-01","updated_at":"2025-01-01"}',
        "",
        "{truncated",
        '{"id":"ccc","status":"pending","sources":[{"type":"text","content":"three"}],"metadata":{},"created_at":"2025-01-01","updated_at":"2025-01-01"}',
      ]
      File.write(@queue_path, lines.join("\n") + "\n")

      items = @queue.all
      assert_equal 3, items.length
      assert_equal %w[aaa bbb ccc], items.map(&:id)
    end
  end

  # --- claim tests ---

  def test_claim_pending_item
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    claimed = @queue.claim(item.id)

    assert_equal item.id, claimed.id
    assert_equal "in_progress", claimed.status
    assert_equal "in_progress", @queue.find(item.id).status
  end

  def test_claim_already_in_progress
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    @queue.update(item.id, status: "in_progress")

    result = @queue.claim(item.id)

    assert_nil result
  end

  def test_claim_closed_item
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    @queue.update(item.id, status: "closed")

    result = @queue.claim(item.id)

    assert_nil result
  end

  def test_claim_nonexistent_item
    result = @queue.claim("nonexistent")

    assert_nil result
  end

  def test_claim_with_block_releases
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    @queue.claim(item.id) do |claimed|
      assert_equal "in_progress", @queue.find(item.id).status
    end

    assert_equal "pending", @queue.find(item.id).status
  end

  def test_claim_with_block_releases_on_error
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    assert_raises(RuntimeError) do
      @queue.claim(item.id) do |claimed|
        raise "boom"
      end
    end

    assert_equal "pending", @queue.find(item.id).status
  end

  def test_claim_block_yields_item
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    yielded = nil

    @queue.claim(item.id) do |claimed|
      yielded = claimed
    end

    assert_equal item.id, yielded.id
    assert_equal "in_progress", yielded.status
  end

  def test_concurrent_claims
    item = @queue.push(sources: [{ type: "text", content: "test" }])

    r1, w1 = IO.pipe
    r2, w2 = IO.pipe

    pid1 = fork do
      r1.close; r2.close
      queue = Sift::Queue.new(@queue_path)
      result = queue.claim(item.id)
      w1.puts(result ? "claimed" : "nil")
      w1.close; w2.close
    end

    pid2 = fork do
      r1.close; r2.close
      queue = Sift::Queue.new(@queue_path)
      result = queue.claim(item.id)
      w2.puts(result ? "claimed" : "nil")
      w1.close; w2.close
    end

    w1.close; w2.close

    result1 = r1.gets&.strip
    result2 = r2.gets&.strip
    r1.close; r2.close

    Process.waitpid(pid1)
    Process.waitpid(pid2)

    results = [result1, result2].sort
    assert_equal ["claimed", "nil"], results, "Exactly one process should claim the item"
  end

  # --- File locking tests ---

  def test_concurrent_pushes_produce_unique_ids
    # Fork multiple processes that push concurrently
    num_processes = 5
    items_per_process = 10

    pids = num_processes.times.map do
      fork do
        queue = Sift::Queue.new(@queue_path)
        items_per_process.times do
          queue.push(sources: [{ type: "text", content: "from pid #{Process.pid}" }])
        end
      end
    end

    pids.each { |pid| Process.waitpid(pid) }

    items = @queue.all
    assert_equal num_processes * items_per_process, items.length,
      "Expected #{num_processes * items_per_process} items, got #{items.length}"
    assert_equal items.length, items.map(&:id).uniq.length,
      "All IDs should be unique"
  end

  def test_concurrent_push_and_update_no_data_loss
    # Pre-populate with items to update
    initial_items = 5.times.map do
      @queue.push(sources: [{ type: "text", content: "initial" }])
    end

    pids = []

    # Process 1: push new items
    pids << fork do
      queue = Sift::Queue.new(@queue_path)
      10.times do
        queue.push(sources: [{ type: "text", content: "new" }])
      end
    end

    # Process 2: update existing items
    pids << fork do
      queue = Sift::Queue.new(@queue_path)
      initial_items.each do |item|
        queue.update(item.id, status: "closed")
      end
    end

    pids.each { |pid| Process.waitpid(pid) }

    items = @queue.all
    assert_equal 15, items.length, "Should have 5 initial + 10 new items"

    closed = items.select(&:closed?)
    assert_equal 5, closed.length, "All initial items should be closed"
  end

  def test_concurrent_push_and_remove_consistency
    # Pre-populate
    to_remove = @queue.push(sources: [{ type: "text", content: "remove me" }])

    pids = []

    # Process 1: push items
    pids << fork do
      queue = Sift::Queue.new(@queue_path)
      10.times do
        queue.push(sources: [{ type: "text", content: "keep" }])
      end
    end

    # Process 2: remove the item
    pids << fork do
      queue = Sift::Queue.new(@queue_path)
      queue.remove(to_remove.id)
    end

    pids.each { |pid| Process.waitpid(pid) }

    items = @queue.all
    assert_equal 10, items.length, "Should have exactly 10 items (removed one)"
    assert_nil @queue.find(to_remove.id), "Removed item should be gone"
  end

  def test_shared_lock_allows_concurrent_reads
    @queue.push(sources: [{ type: "text", content: "test" }])

    # Two readers should not block each other
    r1, w1 = IO.pipe
    r2, w2 = IO.pipe

    pid1 = fork do
      r1.close
      r2.close
      queue = Sift::Queue.new(@queue_path)
      items = queue.all
      w1.puts items.length
      w1.close
      w2.close
    end

    pid2 = fork do
      r1.close
      r2.close
      queue = Sift::Queue.new(@queue_path)
      items = queue.all
      w2.puts items.length
      w1.close
      w2.close
    end

    w1.close
    w2.close

    # Both should complete without deadlock (timeout protects against hangs)
    result1 = r1.gets
    result2 = r2.gets
    r1.close
    r2.close

    Process.waitpid(pid1)
    Process.waitpid(pid2)

    assert_equal "1", result1&.strip
    assert_equal "1", result2&.strip
  end
end
