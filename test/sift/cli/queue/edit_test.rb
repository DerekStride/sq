# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::EditTest < Minitest::Test
  include QueueTestHelper

  def test_edit_set_status
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-status", "closed"])

    assert_equal 0, exit_code

    updated = queue.find(item.id)
    assert_equal "closed", updated.status
  end

  def test_edit_set_status_to_all_valid_statuses
    Sift::Queue::VALID_STATUSES.each do |status|
      item = queue.push(sources: [{ type: "text", content: status }])

      exit_code = run_command(["edit", item.id, "--set-status", status])

      assert_equal 0, exit_code, "Failed for status: #{status}"
      assert_equal status, queue.find(item.id).status
    end
  end

  def test_edit_invalid_status_returns_error
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-status", "invalid"])

    assert_equal 1, exit_code
    assert_match(/invalid argument/i, @stderr)
  end

  def test_edit_nonexistent_item_returns_error
    exit_code = run_command(["edit", "xyz", "--set-status", "closed"])

    assert_equal 1, exit_code
    assert_match(/not found/i, @stderr)
  end

  def test_edit_without_id_returns_error
    exit_code = run_command(["edit", "--set-status", "closed"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, @stderr)
  end

  def test_edit_set_system_prompt
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-system-prompt", "/path/to/prompt.md"])

    assert_equal 0, exit_code

    updated = queue.find(item.id)
    assert_equal "/path/to/prompt.md", updated.metadata["system_prompt"]
  end

  def test_edit_set_system_prompt_preserves_existing_metadata
    item = queue.push(
      sources: [{ type: "text", content: "test" }],
      metadata: { "workflow" => "analyze" },
    )

    exit_code = run_command(["edit", item.id, "--set-system-prompt", "/prompt.md"])

    assert_equal 0, exit_code

    updated = queue.find(item.id)
    assert_equal "/prompt.md", updated.metadata["system_prompt"]
    assert_equal "analyze", updated.metadata["workflow"]
  end

  def test_edit_set_system_prompt_with_set_metadata
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command([
      "edit", item.id,
      "--set-system-prompt", "/prompt.md",
      "--set-metadata", '{"workflow":"review"}',
    ])

    assert_equal 0, exit_code

    updated = queue.find(item.id)
    assert_equal "/prompt.md", updated.metadata["system_prompt"]
    assert_equal "review", updated.metadata["workflow"]
  end

  def test_edit_without_changes_returns_error
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id])

    assert_equal 1, exit_code
    assert_match(/no changes/i, @stderr)
  end
end
