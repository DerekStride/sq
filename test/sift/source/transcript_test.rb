# frozen_string_literal: true

require "test_helper"

class Sift::Source::TranscriptTest < Minitest::Test
  def make_source(content:, path: nil)
    Sift::Queue::Source.new(type: "transcript", content: content, path: path)
  end

  def test_formats_speaker_labels
    content = "H: Hello\nA: Hi there\n"
    source = make_source(content: content)
    lines = Sift::Source::Transcript.new(source).render

    assert lines.any? { |l| l.include?("Human:") }
    assert lines.any? { |l| l.include?("Assistant:") }
  end

  def test_normalizes_speaker_prefixes
    content = "Human: Hello\nAssistant: Hi\nUser: Also me\n"
    source = make_source(content: content)
    lines = Sift::Source::Transcript.new(source).render

    # Human and User both normalize to "Human" but show label again after Assistant
    human_labels = lines.select { |l| l.include?("Human:") }
    assert_equal 2, human_labels.length
  end

  def test_groups_consecutive_same_speaker
    content = "H: First line\nH: Second line\n"
    source = make_source(content: content)
    lines = Sift::Source::Transcript.new(source).render

    human_labels = lines.count { |l| l.include?("Human:") }
    assert_equal 1, human_labels  # single label for grouped messages
  end

  def test_colors_speakers
    content = "H: Hello\nA: Hi\nSystem: Notice\n"
    source = make_source(content: content)
    lines = Sift::Source::Transcript.new(source).render

    human_line = lines.find { |l| l.include?("Human:") }
    assistant_line = lines.find { |l| l.include?("Assistant:") }
    system_line = lines.find { |l| l.include?("System:") }

    assert_includes human_line, "\e[34m"     # blue
    assert_includes assistant_line, "\e[35m"  # magenta
    assert_includes system_line, "\e[33m"     # yellow
  end

  def test_indents_message_content
    content = "H: Hello world\n"
    source = make_source(content: content)
    lines = Sift::Source::Transcript.new(source).render

    message_line = lines.find { |l| l.include?("Hello world") }
    assert message_line.start_with?("  "), "Message should be indented"
  end

  def test_reads_from_path
    Dir.mktmpdir("sift_test_") do |dir|
      path = File.join(dir, "chat.txt")
      File.write(path, "H: Hello\nA: Hi\n")

      source = make_source(content: nil, path: path)
      lines = Sift::Source::Transcript.new(source).render

      assert lines.any? { |l| l.include?("Human:") }
    end
  end

  def test_empty_content
    source = make_source(content: "")
    lines = Sift::Source::Transcript.new(source).render

    assert_equal ["(empty transcript)"], lines
  end

  def test_nil_content_no_path
    source = Sift::Queue::Source.new(type: "transcript")
    lines = Sift::Source::Transcript.new(source).render

    assert_equal ["(empty transcript)"], lines
  end

  def test_height_truncates
    content = "H: Line1\nH: Line2\nH: Line3\nA: Line4\nA: Line5\n"
    source = make_source(content: content)
    lines = Sift::Source::Transcript.new(source).render(height: 3)

    assert_equal 3, lines.length
  end

  def test_label_with_path
    source = make_source(content: "H: x", path: "chat.log")
    assert_equal "chat.log", Sift::Source::Transcript.new(source).label
  end

  def test_label_without_path
    source = make_source(content: "H: x")
    assert_equal "transcript", Sift::Source::Transcript.new(source).label
  end
end
