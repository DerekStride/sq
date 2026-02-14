# frozen_string_literal: true

require_relative "../queue_test_helper"

class Sift::CLI::Queue::AddTest < Minitest::Test
  include QueueTestHelper

  def test_add_with_text_flag
    exit_code = run_command(["add", "--text", "Hello world"])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    assert_match(/\A[a-z0-9]{3}\z/, id)

    item = queue.find(id)
    assert item
    assert_equal "pending", item.status
    assert_equal "text", item.sources.first.type
    assert_equal "Hello world", item.sources.first.content
  end

  def test_add_with_file_flag
    exit_code = run_command(["add", "--file", "/path/to/code.rb"])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_equal "file", item.sources.first.type
    assert_equal "/path/to/code.rb", item.sources.first.path
  end

  def test_add_with_diff_flag
    exit_code = run_command(["add", "--diff", "/changes.patch"])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_equal "diff", item.sources.first.type
    assert_equal "/changes.patch", item.sources.first.path
  end

  def test_add_with_stdin_flag
    content = "Content from stdin\nLine 2"
    exit_code = run_command(["add", "--stdin", "text"], stdin_content: content)

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_equal "text", item.sources.first.type
    assert_equal content, item.sources.first.content
  end

  def test_add_with_stdin_diff
    diff_content = "--- a/file.rb\n+++ b/file.rb\n@@ -1 +1 @@\n-old\n+new"
    exit_code = run_command(["add", "--stdin", "diff"], stdin_content: diff_content)

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_equal "diff", item.sources.first.type
    assert_equal diff_content, item.sources.first.content
  end

  def test_add_with_multiple_sources
    exit_code = run_command([
      "add",
      "--text", "Summary text",
      "--file", "/code.rb",
      "--diff", "/changes.patch",
    ])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
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
      "--metadata", '{"workflow":"analyze","priority":1}',
    ])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_equal "analyze", item.metadata["workflow"]
    assert_equal 1, item.metadata["priority"]
  end

  def test_add_with_title_flag
    exit_code = run_command(["add", "--title", "Fix login bug", "--text", "The login form crashes"])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_equal "Fix login bug", item.title
  end

  def test_add_without_title_has_nil_title
    exit_code = run_command(["add", "--text", "test"])

    assert_equal 0, exit_code

    id = @stdout.lines.first.strip
    item = queue.find(id)
    assert_nil item.title
  end

  def test_add_with_no_sources_returns_error
    exit_code = run_command(["add"])

    assert_equal 1, exit_code
    assert_match(/at least one source/i, @stderr)
  end

  def test_add_with_invalid_stdin_type_returns_error
    exit_code = run_command(["add", "--stdin", "invalid"], stdin_content: "test")

    assert_equal 1, exit_code
    assert_match(/invalid argument/i, @stderr)
  end

  def test_add_with_invalid_metadata_json_returns_error
    exit_code = run_command([
      "add",
      "--text", "test",
      "--metadata", "not valid json",
    ])

    assert_equal 1, exit_code
    assert_match(/invalid.*json/i, @stderr)
  end
end
