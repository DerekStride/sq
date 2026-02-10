# frozen_string_literal: true

require "test_helper"

class Sift::Source::TextTest < Minitest::Test
  def make_source(content:)
    Sift::Queue::Source.new(type: "text", content: content)
  end

  def test_renders_plain_text
    source = make_source(content: "hello world")
    lines = Sift::Source::Text.new(source).render

    assert_equal ["hello world"], lines
  end

  def test_renders_multiline_text
    source = make_source(content: "line one\nline two\n")
    lines = Sift::Source::Text.new(source).render

    assert_equal ["line one", "line two"], lines
  end

  def test_wraps_long_lines_at_word_boundary
    long = "word " * 20  # 100 chars
    source = make_source(content: long.strip)
    lines = Sift::Source::Text.new(source).render(width: 40)

    lines.each do |line|
      assert line.length <= 40, "Line too long: #{line.length} chars"
    end
    assert lines.length > 1
  end

  def test_wraps_at_width_when_no_spaces
    source = make_source(content: "a" * 100)
    lines = Sift::Source::Text.new(source).render(width: 30)

    assert_equal 30, lines[0].length
  end

  def test_height_truncates
    source = make_source(content: "a\nb\nc\nd\n")
    lines = Sift::Source::Text.new(source).render(height: 2)

    assert_equal 2, lines.length
  end

  def test_empty_content
    source = make_source(content: "")
    lines = Sift::Source::Text.new(source).render

    assert_equal [], lines
  end

  def test_nil_content
    source = Sift::Queue::Source.new(type: "text", content: nil)
    lines = Sift::Source::Text.new(source).render

    assert_equal [], lines
  end

  def test_label
    source = make_source(content: "x")
    assert_equal "text", Sift::Source::Text.new(source).label
  end

  def test_label_with_path
    source = Sift::Queue::Source.new(type: "text", path: "notes.md", content: "x")
    assert_equal "notes.md", Sift::Source::Text.new(source).label
  end
end
