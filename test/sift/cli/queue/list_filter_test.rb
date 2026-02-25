# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::ListFilterTest < Minitest::Test
  include QueueTestHelper

  # --filter basics

  def test_filter_by_metadata_field
    queue.push(sources: [{ type: "text", content: "high" }],
      metadata: { "track" => { "priority" => 0 } })
    queue.push(sources: [{ type: "text", content: "low" }],
      metadata: { "track" => { "priority" => 2 } })

    exit_code = run_command(["list", "--filter", "select(.metadata.track.priority == 0)"])

    assert_equal 0, exit_code
    assert_match(/1 item/, @stderr)
  end

  def test_filter_json_output
    high = queue.push(sources: [{ type: "text", content: "high" }],
      metadata: { "track" => { "priority" => 0 } })
    queue.push(sources: [{ type: "text", content: "low" }],
      metadata: { "track" => { "priority" => 2 } })

    exit_code = run_command(["list", "--json", "--filter", "select(.metadata.track.priority == 0)"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
    assert_equal high.id, data.first["id"]
  end

  def test_filter_combined_with_status
    queue.push(sources: [{ type: "text", content: "open high" }],
      metadata: { "track" => { "priority" => 0 } })
    closed = queue.push(sources: [{ type: "text", content: "closed high" }],
      metadata: { "track" => { "priority" => 0 } })
    queue.update(closed.id, status: "closed")

    exit_code = run_command(["list", "--json", "--status", "pending",
      "--filter", "select(.metadata.track.priority == 0)"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
    assert_equal "pending", data.first["status"]
  end

  def test_filter_no_matches
    queue.push(sources: [{ type: "text", content: "low" }],
      metadata: { "track" => { "priority" => 2 } })

    exit_code = run_command(["list", "--filter", "select(.metadata.track.priority == 0)"])

    assert_equal 0, exit_code
    assert_match(/no items/i, @stderr)
  end

  def test_filter_items_without_metadata_are_excluded
    queue.push(sources: [{ type: "text", content: "no meta" }])
    queue.push(sources: [{ type: "text", content: "has meta" }],
      metadata: { "track" => { "priority" => 0 } })

    exit_code = run_command(["list", "--json", "--filter", "select(.metadata.track.priority == 0)"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
  end

  def test_filter_invalid_jq_expression
    queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["list", "--filter", "invalid jq {{["])

    assert_equal 1, exit_code
    assert_match(/filter/i, @stderr)
  end

  def test_filter_by_has_key
    queue.push(sources: [{ type: "text", content: "tracked" }],
      metadata: { "track" => { "priority" => 1 } })
    queue.push(sources: [{ type: "text", content: "untracked" }],
      metadata: { "workflow" => "ci" })

    exit_code = run_command(["list", "--json", "--filter", "select(.metadata.track != null)"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
  end

  # --ready flag (top-level blocked_by)

  def test_ready_shows_unblocked_pending
    free = queue.push(sources: [{ type: "text", content: "free" }], title: "Free task")
    queue.push(sources: [{ type: "text", content: "blocked" }], title: "Blocked task",
      blocked_by: [free.id])

    exit_code = run_command(["list", "--json", "--ready"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
    assert_equal "Free task", data.first["title"]
  end

  def test_ready_unblocks_when_blocker_closed
    blocker = queue.push(sources: [{ type: "text", content: "a" }], title: "Blocker")
    blocked = queue.push(sources: [{ type: "text", content: "b" }], title: "Blocked",
      blocked_by: [blocker.id])
    queue.update(blocker.id, status: "closed")

    exit_code = run_command(["list", "--json", "--ready"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
    assert_equal blocked.id, data.first["id"]
  end

  def test_ready_combined_with_filter
    queue.push(sources: [{ type: "text", content: "p0" }], title: "P0",
      metadata: { "track" => { "priority" => 0 } })
    queue.push(sources: [{ type: "text", content: "p2" }], title: "P2",
      metadata: { "track" => { "priority" => 2 } })

    exit_code = run_command(["list", "--json", "--ready",
      "--filter", "select(.metadata.track.priority == 0)"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
    assert_equal "P0", data.first["title"]
  end

  def test_filter_by_blocked_by_field
    queue.push(sources: [{ type: "text", content: "free" }], title: "Free")
    queue.push(sources: [{ type: "text", content: "blocked" }], title: "Blocked",
      blocked_by: ["abc"])

    exit_code = run_command(["list", "--json",
      "--filter", "select((.blocked_by // []) | length > 0)"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal 1, data.length
    assert_equal "Blocked", data.first["title"]
  end

  # --sort basics

  def test_sort_by_metadata_field
    queue.push(sources: [{ type: "text", content: "low" }], title: "Low",
      metadata: { "track" => { "priority" => 2 } })
    queue.push(sources: [{ type: "text", content: "high" }], title: "High",
      metadata: { "track" => { "priority" => 0 } })
    queue.push(sources: [{ type: "text", content: "med" }], title: "Med",
      metadata: { "track" => { "priority" => 1 } })

    exit_code = run_command(["list", "--json", "--sort", ".metadata.track.priority"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal %w[High Med Low], data.map { |d| d["title"] }
  end

  def test_sort_descending
    queue.push(sources: [{ type: "text", content: "low" }], title: "Low",
      metadata: { "track" => { "priority" => 2 } })
    queue.push(sources: [{ type: "text", content: "high" }], title: "High",
      metadata: { "track" => { "priority" => 0 } })

    exit_code = run_command(["list", "--json", "--sort", ".metadata.track.priority", "--reverse"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal %w[Low High], data.map { |d| d["title"] }
  end

  def test_sort_combined_with_filter
    queue.push(sources: [{ type: "text", content: "p2" }], title: "P2",
      metadata: { "track" => { "priority" => 2 } })
    queue.push(sources: [{ type: "text", content: "p0" }], title: "P0",
      metadata: { "track" => { "priority" => 0 } })
    queue.push(sources: [{ type: "text", content: "p1" }], title: "P1",
      metadata: { "track" => { "priority" => 1 } })

    exit_code = run_command(["list", "--json",
      "--filter", "select(.metadata.track.priority <= 1)",
      "--sort", ".metadata.track.priority"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal %w[P0 P1], data.map { |d| d["title"] }
  end

  def test_sort_by_created_at
    first = queue.push(sources: [{ type: "text", content: "first" }], title: "First")
    sleep 0.01
    second = queue.push(sources: [{ type: "text", content: "second" }], title: "Second")

    exit_code = run_command(["list", "--json", "--sort", ".created_at", "--reverse"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_equal [second.id, first.id], data.map { |d| d["id"] }
  end

  def test_sort_missing_field_sorts_to_end
    queue.push(sources: [{ type: "text", content: "no priority" }], title: "NoPri")
    queue.push(sources: [{ type: "text", content: "has priority" }], title: "HasPri",
      metadata: { "track" => { "priority" => 1 } })

    exit_code = run_command(["list", "--json", "--sort", ".metadata.track.priority"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    # Items with the field come first, missing-field items sort to end
    assert_equal "HasPri", data.first["title"]
    assert_equal "NoPri", data.last["title"]
  end
end
