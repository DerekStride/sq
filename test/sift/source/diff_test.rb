# frozen_string_literal: true

require "test_helper"

class Sift::Source::DiffTest < Minitest::Test
  def make_source(content:, path: nil)
    Sift::Queue::Source.new(type: "diff", path: path, content: content)
  end

  def test_renders_added_lines_in_green
    source = make_source(content: "+added line\n")
    renderer = Sift::Source::Diff.new(source)
    lines = renderer.render

    assert_equal 1, lines.length
    assert_includes lines[0], "\e[32m"
    assert_includes lines[0], "+added line"
  end

  def test_renders_removed_lines_in_red
    source = make_source(content: "-removed line\n")
    renderer = Sift::Source::Diff.new(source)
    lines = renderer.render

    assert_equal 1, lines.length
    assert_includes lines[0], "\e[31m"
    assert_includes lines[0], "-removed line"
  end

  def test_renders_hunk_headers_in_cyan
    source = make_source(content: "@@ -1,3 +1,4 @@\n")
    renderer = Sift::Source::Diff.new(source)
    lines = renderer.render

    assert_includes lines[0], "\e[36m"
    assert_includes lines[0], "@@"
  end

  def test_renders_context_lines_plain
    source = make_source(content: " context line\n")
    renderer = Sift::Source::Diff.new(source)
    lines = renderer.render

    assert_equal " context line", lines[0]
  end

  def test_renders_mixed_diff
    content = <<~DIFF
      @@ -1,3 +1,4 @@
       context
      -old
      +new
      +added
    DIFF
    source = make_source(content: content)
    lines = Sift::Source::Diff.new(source).render

    assert_equal 5, lines.length
    assert_includes lines[0], "\e[36m"  # header
    assert_equal " context", lines[1]   # context
    assert_includes lines[2], "\e[31m"  # removed
    assert_includes lines[3], "\e[32m"  # added
    assert_includes lines[4], "\e[32m"  # added
  end

  def test_height_truncates
    content = "+line1\n+line2\n+line3\n+line4\n"
    source = make_source(content: content)
    lines = Sift::Source::Diff.new(source).render(height: 2)

    assert_equal 2, lines.length
  end

  def test_empty_content
    source = make_source(content: "")
    lines = Sift::Source::Diff.new(source).render

    assert_equal [], lines
  end

  def test_nil_content
    source = make_source(content: nil)
    lines = Sift::Source::Diff.new(source).render

    assert_equal [], lines
  end

  def test_label_with_path
    source = make_source(content: "+x\n", path: "src/foo.rb")
    renderer = Sift::Source::Diff.new(source)

    assert_equal "src/foo.rb", renderer.label
  end

  def test_label_without_path
    source = make_source(content: "+x\n")
    renderer = Sift::Source::Diff.new(source)

    assert_equal "diff", renderer.label
  end
end
