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
      "status" => "approved",
      "sources" => [{ "type" => "file", "path" => "/test.rb" }],
      "metadata" => { "foo" => "bar" },
      "session_id" => "s1",
      "created_at" => "2025-01-01",
      "updated_at" => "2025-01-02"
    }

    item = Sift::Queue::Item.from_h(hash)
    assert_equal "xyz", item.id
    assert_equal "approved", item.status
    assert_equal 1, item.sources.length
    assert_equal "file", item.sources.first.type
    assert_equal({ "foo" => "bar" }, item.metadata)
  end

  def test_item_status_predicates
    item = Sift::Queue::Item.new(id: "1", status: "pending", sources: [])
    assert item.pending?
    refute item.in_progress?

    item = Sift::Queue::Item.new(id: "2", status: "in_progress", sources: [])
    assert item.in_progress?
    refute item.pending?

    item = Sift::Queue::Item.new(id: "3", status: "approved", sources: [])
    assert item.approved?

    item = Sift::Queue::Item.new(id: "4", status: "rejected", sources: [])
    assert item.rejected?

    item = Sift::Queue::Item.new(id: "5", status: "failed", sources: [])
    assert item.failed?
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
    updated = @queue.update(item.id, status: "approved")

    refute_equal original_updated, updated.updated_at
  end

  def test_update_returns_nil_for_nonexistent_id
    result = @queue.update("nonexistent", status: "approved")
    assert_nil result
  end

  # --- filter tests ---

  def test_filter_by_status
    @queue.push(sources: [{ type: "text", content: "1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "2" }])
    @queue.update(item2.id, status: "approved")
    @queue.push(sources: [{ type: "text", content: "3" }])

    pending = @queue.filter(status: "pending")
    approved = @queue.filter(status: "approved")

    assert_equal 2, pending.length
    assert_equal 1, approved.length
    assert_equal item2.id, approved.first.id
  end

  def test_filter_without_status_returns_all
    3.times { @queue.push(sources: [{ type: "text", content: "test" }]) }

    all_items = @queue.filter
    assert_equal 3, all_items.length
  end

  def test_filter_with_symbol_status
    item = @queue.push(sources: [{ type: "text", content: "test" }])
    @queue.update(item.id, status: "rejected")

    rejected = @queue.filter(status: :rejected)
    assert_equal 1, rejected.length
  end

  # --- each_pending tests ---

  def test_each_pending_iterates_over_pending_items
    @queue.push(sources: [{ type: "text", content: "1" }])
    item2 = @queue.push(sources: [{ type: "text", content: "2" }])
    @queue.update(item2.id, status: "approved")
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
    @queue.update(item2.id, status: "approved")

    assert_equal 1, @queue.count(status: "pending")
    assert_equal 1, @queue.count(status: "approved")
    assert_equal 0, @queue.count(status: "rejected")
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
    @queue.update(item.id, status: "approved")

    new_queue = Sift::Queue.new(@queue_path)
    found = new_queue.find(item.id)

    assert_equal "approved", found.status
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
end
