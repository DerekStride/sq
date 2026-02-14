# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::ListTest < Minitest::Test
  include QueueTestHelper

  def test_list_shows_items
    queue.push(sources: [{ type: "text", content: "first" }])
    queue.push(sources: [{ type: "file", path: "/test.rb" }])

    exit_code = run_command(["list"])

    assert_equal 0, exit_code
    assert_match(/2 item/, @stderr)
  end

  def test_list_with_status_filter
    queue.push(sources: [{ type: "text", content: "1" }])
    item2 = queue.push(sources: [{ type: "text", content: "2" }])
    queue.update(item2.id, status: "closed")

    exit_code = run_command(["list", "--status", "pending"])

    assert_equal 0, exit_code
    assert_match(/1 item/, @stderr)
    refute_match(/#{item2.id}/, @stdout)
  end

  def test_list_json_output
    item1 = queue.push(sources: [{ type: "text", content: "first" }])
    item2 = queue.push(sources: [{ type: "file", path: "/test.rb" }])

    exit_code = run_command(["list", "--json"])

    assert_equal 0, exit_code

    data = JSON.parse(@stdout)
    assert_equal 2, data.length
    ids = data.map { |d| d["id"] }
    assert_includes ids, item1.id
    assert_includes ids, item2.id
  end

  def test_list_shows_title_when_present
    queue.push(sources: [{ type: "text", content: "test" }], title: "Fix login bug")

    exit_code = run_command(["list"])

    assert_equal 0, exit_code
    assert_match(/Fix login bug/, @stdout)
  end

  def test_list_empty_queue
    exit_code = run_command(["list"])

    assert_equal 0, exit_code
    assert_match(/no items/i, @stderr)
  end

  def test_list_json_empty
    exit_code = run_command(["list", "--json"])

    assert_equal 0, exit_code
    data = JSON.parse(@stdout)
    assert_empty data
  end
end
