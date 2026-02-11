# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Sift::EditorTest < Minitest::Test
  def setup
    @original_editor = ENV["EDITOR"]
    @original_visual = ENV["VISUAL"]
  end

  def teardown
    ENV["EDITOR"] = @original_editor
    ENV["VISUAL"] = @original_visual
  end

  # --- resolve_editor ---

  def test_resolve_editor_uses_editor_env
    ENV["EDITOR"] = "nano"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal "nano", editor.resolve_editor
  end

  def test_resolve_editor_falls_back_to_visual
    ENV.delete("EDITOR")
    ENV["VISUAL"] = "emacs"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal "emacs", editor.resolve_editor
  end

  def test_resolve_editor_falls_back_to_vi
    ENV.delete("EDITOR")
    ENV.delete("VISUAL")
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal "vi", editor.resolve_editor
  end

  # --- editor_command ---

  def test_editor_command_adds_wait_for_code
    ENV["EDITOR"] = "code"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["code", "--wait"], editor.editor_command
  end

  def test_editor_command_adds_wait_for_subl
    ENV["EDITOR"] = "subl"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["subl", "--wait"], editor.editor_command
  end

  def test_editor_command_adds_tab_flag_for_vim
    ENV["EDITOR"] = "vim"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["vim", "-p"], editor.editor_command
  end

  def test_editor_command_adds_tab_flag_for_nvim
    ENV["EDITOR"] = "nvim"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["nvim", "-p"], editor.editor_command
  end

  def test_editor_command_adds_tab_flag_for_vi
    ENV["EDITOR"] = "vi"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["vi", "-p"], editor.editor_command
  end

  def test_editor_command_no_duplicate_tab_flag
    ENV["EDITOR"] = "nvim -p"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["nvim", "-p"], editor.editor_command
  end

  def test_editor_command_no_flags_for_nano
    ENV["EDITOR"] = "nano"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["nano"], editor.editor_command
  end

  def test_editor_command_no_duplicate_wait
    ENV["EDITOR"] = "code --wait"
    editor = Sift::Editor.new(sources: [], item_id: "test")
    assert_equal ["code", "--wait"], editor.editor_command
  end

  # --- collect_paths ---

  def test_collect_paths_diff_source_with_existing_file
    Dir.mktmpdir("sift_test_") do |dir|
      file_path = File.join(dir, "foo.rb")
      File.write(file_path, "original content")

      source = Sift::Queue::Source.new(type: "diff", path: file_path, content: "+new line\n")
      editor = Sift::Editor.new(sources: [source], item_id: "abc")
      paths = editor.collect_paths

      assert_equal 2, paths.length
      assert_equal file_path, paths[0]
      assert paths[1].end_with?(".diff")
      assert_includes paths[1], "sift-abc-foo.rb"
    end
  end

  def test_collect_paths_diff_source_without_path
    source = Sift::Queue::Source.new(type: "diff", content: "+new line\n")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert paths[0].end_with?(".diff")
    assert_includes paths[0], "sift-abc-changes"
  end

  def test_collect_paths_file_source
    Dir.mktmpdir("sift_test_") do |dir|
      file_path = File.join(dir, "bar.rb")
      File.write(file_path, "class Bar; end")

      source = Sift::Queue::Source.new(type: "file", path: file_path, content: "class Bar; end")
      editor = Sift::Editor.new(sources: [source], item_id: "abc")
      paths = editor.collect_paths

      assert_equal 1, paths.length
      assert_equal file_path, paths[0]
    end
  end

  def test_collect_paths_file_source_missing_file
    source = Sift::Queue::Source.new(type: "file", path: "/nonexistent/bar.rb", content: "class Bar; end")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_empty paths
  end

  def test_collect_paths_text_source
    source = Sift::Queue::Source.new(type: "text", content: "some notes")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert paths[0].end_with?(".md")
    assert_includes paths[0], "sift-abc"
    assert_equal "some notes", File.read(paths[0])
  end

  def test_collect_paths_transcript_source
    source = Sift::Queue::Source.new(type: "transcript", content: "H: Hello\nA: Hi")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert paths[0].end_with?(".md")
    assert_includes paths[0], "sift-abc"
    assert_equal "H: Hello\nA: Hi", File.read(paths[0])
  end

  def test_collect_paths_transcript_source_with_path
    source = Sift::Queue::Source.new(type: "transcript", path: "chat.md", content: "H: Hello")
    editor = Sift::Editor.new(sources: [source], item_id: "abc")
    paths = editor.collect_paths

    assert_equal 1, paths.length
    assert_includes paths[0], "sift-abc-chat.md"
  end

  def test_temp_file_naming
    source = Sift::Queue::Source.new(type: "diff", path: "lib/foo.rb", content: "+line\n")
    editor = Sift::Editor.new(sources: [source], item_id: "x1")
    paths = editor.collect_paths

    temp_path = paths.find { |p| p.end_with?(".diff") }
    assert_includes File.basename(temp_path), "sift-x1-foo.rb.diff"
  end
end
