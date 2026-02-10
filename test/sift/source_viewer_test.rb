# frozen_string_literal: true

require "test_helper"

# Test harness that includes SourceViewer
class ViewerHarness
  include Sift::SourceViewer

  attr_accessor :sources, :source_index

  def initialize(sources)
    @sources = sources.map { |s| Sift::Queue::Source.from_h(s) }
    @source_index = 0
  end

  private

  def sources_list
    @sources
  end
end

class Sift::SourceViewerTest < Minitest::Test
  def test_status_bar_format
    viewer = ViewerHarness.new([
      { type: "diff", path: "src/foo.rb", content: "+x" },
      { type: "file", path: "src/bar.rb" },
    ])

    assert_equal "[1/2] diff: src/foo.rb", viewer.status_bar
  end

  def test_status_bar_updates_on_navigation
    viewer = ViewerHarness.new([
      { type: "diff", path: "a.rb", content: "+x" },
      { type: "text", content: "hello" },
    ])

    viewer.next_source
    assert_equal "[2/2] text: text", viewer.status_bar
  end

  def test_next_source_wraps_around
    viewer = ViewerHarness.new([
      { type: "diff", content: "+a" },
      { type: "text", content: "b" },
    ])

    viewer.next_source  # -> index 1
    viewer.next_source  # -> index 0 (wrap)
    assert_equal 0, viewer.source_index
  end

  def test_prev_source_wraps_around
    viewer = ViewerHarness.new([
      { type: "diff", content: "+a" },
      { type: "text", content: "b" },
    ])

    viewer.prev_source  # -> index 1 (wrap)
    assert_equal 1, viewer.source_index
  end

  def test_next_source_noop_with_single_source
    viewer = ViewerHarness.new([{ type: "text", content: "only" }])

    refute viewer.next_source
    assert_equal 0, viewer.source_index
  end

  def test_prev_source_noop_with_single_source
    viewer = ViewerHarness.new([{ type: "text", content: "only" }])

    refute viewer.prev_source
    assert_equal 0, viewer.source_index
  end

  def test_jump_to_source
    viewer = ViewerHarness.new([
      { type: "diff", content: "+a" },
      { type: "text", content: "b" },
      { type: "file", content: "c" },
    ])

    assert viewer.jump_to_source(2)
    assert_equal 2, viewer.source_index
  end

  def test_jump_to_invalid_index
    viewer = ViewerHarness.new([{ type: "text", content: "only" }])

    refute viewer.jump_to_source(-1)
    refute viewer.jump_to_source(1)
    assert_equal 0, viewer.source_index
  end

  def test_current_source
    viewer = ViewerHarness.new([
      { type: "diff", path: "x.rb", content: "+a" },
      { type: "text", content: "b" },
    ])

    assert_equal "diff", viewer.current_source.type
    viewer.next_source
    assert_equal "text", viewer.current_source.type
  end

  def test_multi_source_true
    viewer = ViewerHarness.new([
      { type: "diff", content: "+a" },
      { type: "text", content: "b" },
    ])

    assert viewer.multi_source?
  end

  def test_multi_source_false
    viewer = ViewerHarness.new([{ type: "text", content: "only" }])

    refute viewer.multi_source?
  end

  def test_empty_sources
    viewer = ViewerHarness.new([])

    assert_equal "", viewer.status_bar
    refute viewer.multi_source?
    assert_nil viewer.current_source
  end

  def test_factory_dispatches_correctly
    diff = Sift::Queue::Source.new(type: "diff", content: "+x")
    file = Sift::Queue::Source.new(type: "file", content: "x")
    text = Sift::Queue::Source.new(type: "text", content: "x")
    transcript = Sift::Queue::Source.new(type: "transcript", content: "H: x")

    assert_instance_of Sift::Source::Diff, Sift::Source::Base.for(diff)
    assert_instance_of Sift::Source::File, Sift::Source::Base.for(file)
    assert_instance_of Sift::Source::Text, Sift::Source::Base.for(text)
    assert_instance_of Sift::Source::Transcript, Sift::Source::Base.for(transcript)
  end

  def test_factory_raises_on_unknown_type
    unknown = Sift::Queue::Source.new(type: "unknown", content: "x")

    assert_raises(ArgumentError) { Sift::Source::Base.for(unknown) }
  end
end
