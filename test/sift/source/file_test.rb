# frozen_string_literal: true

require "test_helper"
require "tmpdir"

class Sift::Source::FileTest < Minitest::Test
  def make_source(content: nil, path: nil)
    Sift::Queue::Source.new(type: "file", path: path, content: content)
  end

  def test_renders_inline_content_with_line_numbers
    source = make_source(content: "line one\nline two\nline three\n")
    lines = Sift::Source::File.new(source).render

    assert_equal 3, lines.length
    assert_includes lines[0], "1"
    assert_includes lines[0], "line one"
    assert_includes lines[1], "2"
    assert_includes lines[1], "line two"
  end

  def test_line_number_gutter_width
    content = (1..100).map { |i| "line #{i}" }.join("\n")
    source = make_source(content: content)
    lines = Sift::Source::File.new(source).render

    # 3-digit gutter for 100 lines
    assert_match(/\s+1\e\[0m  line 1$/, lines[0])
    assert_match(/100\e\[0m  line 100$/, lines[99])
  end

  def test_reads_from_path
    Dir.mktmpdir("sift_test_") do |dir|
      path = File.join(dir, "test.txt")
      File.write(path, "hello from file\n")

      source = make_source(path: path)
      lines = Sift::Source::File.new(source).render

      assert_equal 1, lines.length
      assert_includes lines[0], "hello from file"
    end
  end

  def test_inline_content_preferred_over_path
    Dir.mktmpdir("sift_test_") do |dir|
      path = File.join(dir, "test.txt")
      File.write(path, "from file\n")

      source = make_source(content: "from inline\n", path: path)
      lines = Sift::Source::File.new(source).render

      assert_includes lines[0], "from inline"
    end
  end

  def test_missing_path_returns_empty
    source = make_source(path: "/nonexistent/file.txt")
    lines = Sift::Source::File.new(source).render

    assert_equal ["(empty)"], lines
  end

  def test_empty_content
    source = make_source(content: "")
    lines = Sift::Source::File.new(source).render

    assert_equal ["(empty)"], lines
  end

  def test_nil_content_no_path
    source = make_source
    lines = Sift::Source::File.new(source).render

    assert_equal ["(empty)"], lines
  end

  def test_height_truncates
    source = make_source(content: "a\nb\nc\nd\n")
    lines = Sift::Source::File.new(source).render(height: 2)

    assert_equal 2, lines.length
  end

  def test_label_with_path
    source = make_source(path: "lib/foo.rb")
    assert_equal "lib/foo.rb", Sift::Source::File.new(source).label
  end

  def test_label_without_path
    source = make_source(content: "x")
    assert_equal "file", Sift::Source::File.new(source).label
  end
end
