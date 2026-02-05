# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "json"
require "stringio"

class Sift::CLI::QueueCommandTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @queue_path = File.join(@temp_dir, "queue.jsonl")
    @stdout = StringIO.new
    @stderr = StringIO.new
  end

  def teardown
    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def run_command(args, stdin_content: nil)
    stdin = stdin_content ? StringIO.new(stdin_content) : StringIO.new
    cmd = Sift::CLI::QueueCommand.new(
      args,
      queue_path: @queue_path,
      stdin: stdin,
      stdout: @stdout,
      stderr: @stderr
    )
    cmd.run
  end

  def queue
    @queue ||= Sift::Queue.new(@queue_path)
  end

  def stdout_output
    @stdout.string
  end

  def stderr_output
    @stderr.string
  end

  # --- Help tests ---

  def test_shows_help_with_no_args
    exit_code = run_command([])

    assert_equal 0, exit_code
    assert_match(/Usage:.*sift queue/i, stdout_output)
    assert_match(/add/i, stdout_output)
    assert_match(/list/i, stdout_output)
  end

  def test_shows_help_with_help_flag
    exit_code = run_command(["--help"])

    assert_equal 0, exit_code
    assert_match(/Usage:/i, stdout_output)
  end

  def test_unknown_subcommand_returns_error
    exit_code = run_command(["unknown"])

    assert_equal 1, exit_code
    assert_match(/unknown subcommand/i, stderr_output)
  end

  # --- Add subcommand tests ---

  def test_add_with_text_flag
    exit_code = run_command(["add", "--text", "Hello world"])

    assert_equal 0, exit_code

    # Output should contain the item ID
    id = stdout_output.lines.first.strip
    assert_match(/\A[a-z0-9]{3}\z/, id)

    # Verify item was created
    item = queue.find(id)
    assert item
    assert_equal "pending", item.status
    assert_equal "text", item.sources.first.type
    assert_equal "Hello world", item.sources.first.content
  end

  def test_add_with_file_flag
    exit_code = run_command(["add", "--file", "/path/to/code.rb"])

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal "file", item.sources.first.type
    assert_equal "/path/to/code.rb", item.sources.first.path
  end

  def test_add_with_diff_flag
    exit_code = run_command(["add", "--diff", "/changes.patch"])

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal "diff", item.sources.first.type
    assert_equal "/changes.patch", item.sources.first.path
  end

  def test_add_with_transcript_flag
    exit_code = run_command(["add", "--transcript", "/chat.log"])

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal "transcript", item.sources.first.type
    assert_equal "/chat.log", item.sources.first.path
  end

  def test_add_with_stdin_flag
    content = "Content from stdin\nLine 2"
    exit_code = run_command(["add", "--stdin", "text"], stdin_content: content)

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal "text", item.sources.first.type
    assert_equal content, item.sources.first.content
  end

  def test_add_with_stdin_diff
    diff_content = "--- a/file.rb\n+++ b/file.rb\n@@ -1 +1 @@\n-old\n+new"
    exit_code = run_command(["add", "--stdin", "diff"], stdin_content: diff_content)

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal "diff", item.sources.first.type
    assert_equal diff_content, item.sources.first.content
  end

  def test_add_with_multiple_sources
    exit_code = run_command([
      "add",
      "--text", "Summary text",
      "--file", "/code.rb",
      "--diff", "/changes.patch"
    ])

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal 3, item.sources.length
    assert_equal "text", item.sources[0].type
    assert_equal "file", item.sources[1].type
    assert_equal "diff", item.sources[2].type
  end

  def test_add_with_metadata
    exit_code = run_command([
      "add",
      "--text", "test",
      "--metadata", '{"workflow":"analyze","priority":1}'
    ])

    assert_equal 0, exit_code

    id = stdout_output.lines.first.strip
    item = queue.find(id)
    assert_equal "analyze", item.metadata["workflow"]
    assert_equal 1, item.metadata["priority"]
  end

  def test_add_with_no_sources_returns_error
    exit_code = run_command(["add"])

    assert_equal 1, exit_code
    assert_match(/at least one source/i, stderr_output)
  end

  def test_add_with_invalid_stdin_type_returns_error
    exit_code = run_command(["add", "--stdin", "invalid"], stdin_content: "test")

    assert_equal 1, exit_code
    assert_match(/invalid argument/i, stderr_output)
  end

  def test_add_with_invalid_metadata_json_returns_error
    exit_code = run_command([
      "add",
      "--text", "test",
      "--metadata", "not valid json"
    ])

    assert_equal 1, exit_code
    assert_match(/invalid.*json/i, stderr_output)
  end

  # --- List subcommand tests ---

  def test_list_shows_items
    queue.push(sources: [{ type: "text", content: "first" }])
    queue.push(sources: [{ type: "file", path: "/test.rb" }])

    exit_code = run_command(["list"])

    assert_equal 0, exit_code
    assert_match(/2 item/, stderr_output)
  end

  def test_list_with_status_filter
    queue.push(sources: [{ type: "text", content: "1" }])
    item2 = queue.push(sources: [{ type: "text", content: "2" }])
    queue.update(item2.id, status: "approved")

    exit_code = run_command(["list", "--status", "pending"])

    assert_equal 0, exit_code
    assert_match(/1 item/, stderr_output)
    refute_match(/#{item2.id}/, stdout_output)
  end

  def test_list_json_output
    item1 = queue.push(sources: [{ type: "text", content: "first" }])
    item2 = queue.push(sources: [{ type: "file", path: "/test.rb" }])

    exit_code = run_command(["list", "--json"])

    assert_equal 0, exit_code

    data = JSON.parse(stdout_output)
    assert_equal 2, data.length
    ids = data.map { |d| d["id"] }
    assert_includes ids, item1.id
    assert_includes ids, item2.id
  end

  def test_list_empty_queue
    exit_code = run_command(["list"])

    assert_equal 0, exit_code
    assert_match(/no items/i, stderr_output)
  end

  def test_list_json_empty
    exit_code = run_command(["list", "--json"])

    assert_equal 0, exit_code
    data = JSON.parse(stdout_output)
    assert_empty data
  end

  # --- Show subcommand tests ---

  def test_show_displays_item
    item = queue.push(
      sources: [{ type: "text", content: "test content" }],
      metadata: { key: "value" }
    )

    exit_code = run_command(["show", item.id])

    assert_equal 0, exit_code
    assert_match(/pending/i, stdout_output)
    assert_match(/key.*value/i, stdout_output)
    assert_match(/text/i, stdout_output)
  end

  def test_show_json_output
    item = queue.push(
      sources: [{ type: "file", path: "/test.rb" }],
      metadata: { workflow: "review" }
    )

    exit_code = run_command(["show", item.id, "--json"])

    assert_equal 0, exit_code

    data = JSON.parse(stdout_output)
    assert_equal item.id, data["id"]
    assert_equal "pending", data["status"]
    assert_equal 1, data["sources"].length
    assert_equal "file", data["sources"].first["type"]
    assert_equal "review", data["metadata"]["workflow"]
  end

  def test_show_nonexistent_item_returns_error
    exit_code = run_command(["show", "xyz"])

    assert_equal 1, exit_code
    assert_match(/not found/i, stderr_output)
  end

  def test_show_without_id_returns_error
    exit_code = run_command(["show"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, stderr_output)
  end

  # --- Edit subcommand tests ---

  def test_edit_set_status
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-status", "approved"])

    assert_equal 0, exit_code

    updated = queue.find(item.id)
    assert_equal "approved", updated.status
  end

  def test_edit_set_status_to_all_valid_statuses
    Sift::Queue::VALID_STATUSES.each do |status|
      item = queue.push(sources: [{ type: "text", content: status }])

      @stdout = StringIO.new
      @stderr = StringIO.new

      exit_code = run_command(["edit", item.id, "--set-status", status])

      assert_equal 0, exit_code, "Failed for status: #{status}"
      assert_equal status, queue.find(item.id).status
    end
  end

  def test_edit_invalid_status_returns_error
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id, "--set-status", "invalid"])

    assert_equal 1, exit_code
    assert_match(/invalid argument/i, stderr_output)
  end

  def test_edit_nonexistent_item_returns_error
    exit_code = run_command(["edit", "xyz", "--set-status", "approved"])

    assert_equal 1, exit_code
    assert_match(/not found/i, stderr_output)
  end

  def test_edit_without_id_returns_error
    exit_code = run_command(["edit", "--set-status", "approved"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, stderr_output)
  end

  def test_edit_without_changes_returns_error
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["edit", item.id])

    assert_equal 1, exit_code
    assert_match(/no changes/i, stderr_output)
  end

  # --- Rm subcommand tests ---

  def test_rm_removes_item
    item = queue.push(sources: [{ type: "text", content: "test" }])

    exit_code = run_command(["rm", item.id])

    assert_equal 0, exit_code
    assert_nil queue.find(item.id)
    assert_match(/#{item.id}/, stdout_output)
    assert_match(/removed/i, stderr_output)
  end

  def test_rm_nonexistent_item_returns_error
    exit_code = run_command(["rm", "xyz"])

    assert_equal 1, exit_code
    assert_match(/not found/i, stderr_output)
  end

  def test_rm_without_id_returns_error
    exit_code = run_command(["rm"])

    assert_equal 1, exit_code
    assert_match(/id.*required/i, stderr_output)
  end
end
