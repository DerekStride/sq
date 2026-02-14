# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::ShowTest < Minitest::Test
  include QueueTestHelper

  def test_show_displays_item
    item = queue.push(
      sources: [{ type: "text", content: "test content" }],
      metadata: { key: "value" },
    )

    exit_code = run_command(["show", item.id])

    assert_equal 0, exit_code
    assert_match(/pending/i, @stdout)
    assert_match(/key.*value/i, @stdout)
    assert_match(/text/i, @stdout)
  end

  def test_show_displays_title_when_present
    item = queue.push(
      sources: [{ type: "text", content: "test" }],
      title: "Fix login bug",
    )

    exit_code = run_command(["show", item.id])

    assert_equal 0, exit_code
    assert_match(/Fix login bug/, @stdout)
  end

  def test_show_json_output
    item = queue.push(
      sources: [{ type: "file", path: "/test.rb" }],
      metadata: { workflow: "review" },
    )

    exit_code = run_command(["show", item.id, "--json"])

    assert_equal 0, exit_code

    data = JSON.parse(@stdout)
    assert_equal item.id, data["id"]
    assert_equal "pending", data["status"]
    assert_equal 1, data["sources"].length
    assert_equal "file", data["sources"].first["type"]
    assert_equal "review", data["metadata"]["workflow"]
  end

  def test_show_nonexistent_item_returns_error
    exit_code = run_command(["show", "xyz"])

    assert_equal 1, exit_code
    assert_match(/not found/i, @stderr)
  end

  def test_show_without_id_returns_error
    exit_code = run_command(["show"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, @stderr)
  end
end
