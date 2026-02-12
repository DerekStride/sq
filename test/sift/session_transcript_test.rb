# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Sift::SessionTranscriptTest < Minitest::Test
  def setup
    @tmpdir = Dir.mktmpdir("sift_session_test_")
    @session_path = File.join(@tmpdir, "test-session.jsonl")
  end

  def teardown
    FileUtils.rm_rf(@tmpdir)
  end

  def test_render_user_and_assistant_text
    write_session([
      user_entry("What is this?"),
      assistant_entry("msg1", [{ "type" => "text", "text" => "It's a test." }]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "**User:** What is this?"
    assert_includes transcript, "**Assistant:**"
    assert_includes transcript, "It's a test."
  end

  def test_render_tool_calls
    write_session([
      user_entry("Find the file"),
      assistant_entry("msg1", [
        { "type" => "text", "text" => "Let me search." },
        { "type" => "tool_use", "name" => "Glob", "input" => { "pattern" => "**/*.rb" } },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Glob: `**/*.rb`"
  end

  def test_render_read_tool
    write_session([
      user_entry("Read it"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Read", "input" => { "file_path" => "/foo/bar.rb" } },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Read: `/foo/bar.rb`"
  end

  def test_render_bash_tool
    write_session([
      user_entry("Run tests"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Bash", "input" => { "command" => "bundle exec rake test" } },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Bash: `bundle exec rake test`"
  end

  def test_render_task_tool
    write_session([
      user_entry("Explore"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Task", "input" => { "description" => "Explore codebase" } },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Task: Explore codebase"
  end

  def test_skips_tool_result_user_messages
    write_session([
      user_entry("Hello"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Glob", "input" => { "pattern" => "*.rb" } },
      ]),
      # Tool result comes back as user message with array content
      { "type" => "user", "message" => {
        "role" => "user",
        "content" => [{ "tool_use_id" => "123", "type" => "tool_result", "content" => "result" }],
      } },
      assistant_entry("msg2", [{ "type" => "text", "text" => "Found it." }]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "**User:** Hello"
    refute_includes transcript, "tool_result"
    assert_includes transcript, "Found it."
  end

  def test_groups_assistant_blocks_by_message_id
    write_session([
      user_entry("Check this"),
      assistant_entry("msg1", [{ "type" => "text", "text" => "First part." }]),
      assistant_entry("msg1", [{ "type" => "tool_use", "name" => "Glob", "input" => { "pattern" => "*.rb" } }]),
      assistant_entry("msg1", [{ "type" => "text", "text" => "Second part." }]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    # Should only have one "Assistant:" section
    assert_equal 1, transcript.scan("**Assistant:**").count
    assert_includes transcript, "First part."
    assert_includes transcript, "> Glob:"
    assert_includes transcript, "Second part."
  end

  def test_skips_queue_operation_entries
    write_session([
      { "type" => "queue-operation", "operation" => "dequeue" },
      user_entry("Hello"),
      assistant_entry("msg1", [{ "type" => "text", "text" => "Hi." }]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    refute_includes transcript, "queue-operation"
    assert_includes transcript, "**User:** Hello"
  end

  def test_returns_nil_for_missing_file
    result = Sift::SessionTranscript.render("nonexistent-session", cwd: @tmpdir)

    assert_nil result
  end

  def test_session_path_derives_from_cwd
    path = Sift::SessionTranscript.session_path("abc-123", cwd: "/Users/me/project")

    assert_includes path, "-Users-me-project"
    assert path.end_with?("abc-123.jsonl")
  end

  def test_render_unknown_tool
    write_session([
      user_entry("Do something"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "CustomTool", "input" => {} },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> CustomTool"
  end

  private

  def write_session(entries)
    File.open(@session_path, "w") do |f|
      entries.each { |e| f.puts(JSON.generate(e)) }
    end
  end

  def user_entry(content)
    { "type" => "user", "message" => { "role" => "user", "content" => content } }
  end

  def assistant_entry(msg_id, content_blocks)
    {
      "type" => "assistant",
      "message" => {
        "role" => "assistant",
        "id" => msg_id,
        "content" => content_blocks,
      },
    }
  end
end
