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
        { "type" => "tool_use", "id" => "t1", "name" => "Glob", "input" => { "pattern" => "*.rb" } },
      ]),
      # Tool result comes back as user message with array content
      { "type" => "user", "message" => {
        "role" => "user",
        "content" => [{ "tool_use_id" => "t1", "type" => "tool_result", "content" => "foo.rb\nbar.rb" }],
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

  # --- find_session fallback tests ---

  def test_find_session_returns_primary_path_when_exists
    with_projects_dir do |projects_dir|
      session_id = "sess-primary"
      slug = "/my/project".gsub("/", "-")
      dir = File.join(projects_dir, slug)
      FileUtils.mkdir_p(dir)
      session_file = File.join(dir, "#{session_id}.jsonl")
      File.write(session_file, "")

      result = Sift::SessionTranscript.find_session(session_id, cwd: "/my/project")

      assert_equal session_file, result
    end
  end

  def test_find_session_falls_back_to_other_project_dirs
    with_projects_dir do |projects_dir|
      session_id = "sess-worktree"

      # Session lives under a different slug (simulates work tree)
      other_dir = File.join(projects_dir, "-my-project-feature-branch")
      FileUtils.mkdir_p(other_dir)
      session_file = File.join(other_dir, "#{session_id}.jsonl")
      File.write(session_file, "")

      # Primary slug has no such session
      primary_dir = File.join(projects_dir, "-my-project")
      FileUtils.mkdir_p(primary_dir)

      result = Sift::SessionTranscript.find_session(session_id, cwd: "/my/project")

      assert_equal session_file, result
    end
  end

  def test_find_session_returns_nil_when_not_found_anywhere
    with_projects_dir do |projects_dir|
      FileUtils.mkdir_p(File.join(projects_dir, "-some-project"))

      result = Sift::SessionTranscript.find_session("nonexistent", cwd: "/some/project")

      assert_nil result
    end
  end

  def test_render_uses_fallback_to_find_session
    with_projects_dir do |projects_dir|
      session_id = "sess-render-fallback"

      # Place session under a different slug
      other_dir = File.join(projects_dir, "-my-project-other-branch")
      FileUtils.mkdir_p(other_dir)
      session_file = File.join(other_dir, "#{session_id}.jsonl")
      File.open(session_file, "w") do |f|
        f.puts(JSON.generate(user_entry("Hello from fallback")))
        f.puts(JSON.generate(assistant_entry("m1", [{ "type" => "text", "text" => "Found you." }])))
      end

      # Render from a cwd that doesn't contain the session
      transcript = Sift::SessionTranscript.render(session_id, cwd: "/my/project")

      assert_includes transcript, "**User:** Hello from fallback"
      assert_includes transcript, "Found you."
    end
  end

  def test_glob_result_shows_file_count
    write_session([
      user_entry("Find files"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Glob", "input" => { "pattern" => "**/*.rb" } },
      ]),
      tool_result_entry("t1", "lib/foo.rb\nlib/bar.rb\nlib/baz.rb"),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Glob: `**/*.rb` → 3 files"
  end

  def test_glob_result_singular_file
    write_session([
      user_entry("Find files"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Glob", "input" => { "pattern" => "Gemfile" } },
      ]),
      tool_result_entry("t1", "Gemfile"),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Glob: `Gemfile` → 1 file"
  end

  def test_read_result_shows_line_count
    write_session([
      user_entry("Read it"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Read", "input" => { "file_path" => "/foo/bar.rb" } },
      ]),
      tool_result_entry("t1", "line1\nline2\nline3\nline4\nline5"),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Read: `/foo/bar.rb` → 5 lines"
  end

  def test_grep_result_shows_match_count
    write_session([
      user_entry("Search"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Grep", "input" => { "pattern" => "def test" } },
      ]),
      tool_result_entry("t1", "test/a.rb\ntest/b.rb"),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Grep: `def test` → 2 matches"
  end

  def test_bash_result_shows_first_line
    write_session([
      user_entry("Run it"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Bash", "input" => { "command" => "ruby -v" } },
      ]),
      tool_result_entry("t1", "ruby 3.3.0 (2024-12-25)"),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Bash: `ruby -v` → `ruby 3.3.0 (2024-12-25)`"
  end

  def test_edit_result_shows_ok
    write_session([
      user_entry("Fix it"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Edit", "input" => { "file_path" => "/foo.rb" } },
      ]),
      tool_result_entry("t1", "The file has been updated successfully."),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Edit: `/foo.rb` → ok"
  end

  def test_edit_result_shows_error_when_is_error_set
    write_session([
      user_entry("Fix it"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Edit", "input" => { "file_path" => "/foo.rb" } },
      ]),
      tool_result_entry("t1", "Claude requested permissions to write to /foo.rb, but you haven't granted it yet.", is_error: true),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "→ ERROR:"
    assert_includes transcript, "permission"
    refute_includes transcript, "→ ok"
  end

  def test_task_result_shows_first_line
    write_session([
      user_entry("Explore"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Task", "input" => { "description" => "Explore codebase" } },
      ]),
      tool_result_entry("t1", "Found 12 relevant files in the project."),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Task: Explore codebase → Found 12 relevant files in the project."
  end

  def test_tool_result_with_array_content
    write_session([
      user_entry("Find files"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Glob", "input" => { "pattern" => "*.rb" } },
      ]),
      { "type" => "user", "message" => {
        "role" => "user",
        "content" => [{ "tool_use_id" => "t1", "type" => "tool_result",
          "content" => [{ "type" => "text", "text" => "foo.rb\nbar.rb" }] }],
      } },
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Glob: `*.rb` → 2 files"
  end

  def test_no_result_suffix_without_tool_result
    write_session([
      user_entry("Find files"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "id" => "t1", "name" => "Glob", "input" => { "pattern" => "*.rb" } },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Glob: `*.rb`"
    refute_includes transcript, "→"
  end

  # --- Plan extraction tests ---

  def test_extract_plan_paths_from_write_tool_call
    plan_path = File.join(Dir.home, ".claude", "plans", "my-plan.md")
    write_session([
      user_entry("Plan this"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Write", "input" => { "file_path" => plan_path, "content" => "# Plan" } },
      ]),
    ])

    instance = Sift::SessionTranscript.new(@session_path)
    paths = instance.plan_paths

    assert_equal [plan_path], paths
  end

  def test_extract_plan_paths_from_file_history_snapshot
    plan_path = File.join(Dir.home, ".claude", "plans", "snapshot-plan.md")
    write_session([
      user_entry("Hello"),
      { "type" => "file-history-snapshot", "trackedFileBackups" => { plan_path => "backup-data" } },
      assistant_entry("msg1", [{ "type" => "text", "text" => "Done." }]),
    ])

    instance = Sift::SessionTranscript.new(@session_path)
    paths = instance.plan_paths

    assert_equal [plan_path], paths
  end

  def test_extract_plan_paths_deduplicates
    plan_path = File.join(Dir.home, ".claude", "plans", "dup-plan.md")
    write_session([
      user_entry("Plan"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Write", "input" => { "file_path" => plan_path, "content" => "# Plan" } },
      ]),
      { "type" => "file-history-snapshot", "trackedFileBackups" => { plan_path => "backup" } },
    ])

    instance = Sift::SessionTranscript.new(@session_path)
    paths = instance.plan_paths

    assert_equal 1, paths.length
    assert_equal plan_path, paths.first
  end

  def test_extract_plan_paths_ignores_non_plan_writes
    write_session([
      user_entry("Write file"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Write", "input" => { "file_path" => "/tmp/foo.rb", "content" => "code" } },
      ]),
    ])

    instance = Sift::SessionTranscript.new(@session_path)
    paths = instance.plan_paths

    assert_empty paths
  end

  def test_extract_plan_paths_empty_when_no_plans
    write_session([
      user_entry("Hello"),
      assistant_entry("msg1", [{ "type" => "text", "text" => "Hi." }]),
    ])

    instance = Sift::SessionTranscript.new(@session_path)
    paths = instance.plan_paths

    assert_empty paths
  end

  def test_parse_returns_transcript_and_plan_paths
    plan_path = File.join(Dir.home, ".claude", "plans", "parse-plan.md")
    with_projects_dir do |projects_dir|
      session_id = "sess-parse-test"
      slug = "/my/project".gsub("/", "-")
      dir = File.join(projects_dir, slug)
      FileUtils.mkdir_p(dir)
      session_file = File.join(dir, "#{session_id}.jsonl")

      File.open(session_file, "w") do |f|
        f.puts(JSON.generate(user_entry("Plan this")))
        f.puts(JSON.generate(assistant_entry("msg1", [
          { "type" => "tool_use", "name" => "Write", "input" => { "file_path" => plan_path, "content" => "# Plan" } },
        ])))
      end

      result = Sift::SessionTranscript.parse(session_id, cwd: "/my/project")

      refute_nil result
      assert_includes result[:transcript], "**User:** Plan this"
      assert_equal [plan_path], result[:plan_paths]
    end
  end

  def test_parse_returns_nil_for_missing_session
    result = Sift::SessionTranscript.parse("nonexistent", cwd: @tmpdir)

    assert_nil result
  end

  # --- Plan-aware tool rendering tests ---

  def test_render_write_to_plan_shows_plan_label
    plan_path = File.join(Dir.home, ".claude", "plans", "my-plan.md")
    write_session([
      user_entry("Plan"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "Write", "input" => { "file_path" => plan_path, "content" => "# Plan" } },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Plan: `my-plan.md`"
    refute_includes transcript, "> Write:"
  end

  def test_render_enter_plan_mode
    write_session([
      user_entry("Start planning"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "EnterPlanMode", "input" => {} },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Enter plan mode"
  end

  def test_render_exit_plan_mode
    write_session([
      user_entry("Done planning"),
      assistant_entry("msg1", [
        { "type" => "tool_use", "name" => "ExitPlanMode", "input" => {} },
      ]),
    ])

    transcript = Sift::SessionTranscript.new(@session_path).render

    assert_includes transcript, "> Exit plan mode"
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

  def tool_result_entry(tool_use_id, content, is_error: false)
    block = { "tool_use_id" => tool_use_id, "type" => "tool_result", "content" => content }
    block["is_error"] = true if is_error
    {
      "type" => "user",
      "message" => {
        "role" => "user",
        "content" => [block],
      },
    }
  end

  # Temporarily swap PROJECTS_DIR to a temp directory for isolation
  def with_projects_dir
    dir = Dir.mktmpdir("sift_projects_test_")
    original = Sift::SessionTranscript::PROJECTS_DIR
    Sift::SessionTranscript.send(:remove_const, :PROJECTS_DIR)
    Sift::SessionTranscript.const_set(:PROJECTS_DIR, dir)
    yield(dir)
  ensure
    Sift::SessionTranscript.send(:remove_const, :PROJECTS_DIR)
    Sift::SessionTranscript.const_set(:PROJECTS_DIR, original)
    FileUtils.rm_rf(dir)
  end
end
