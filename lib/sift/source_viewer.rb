# frozen_string_literal: true

require "cli/ui"

module Sift
  # Navigates between multiple sources within a queue item.
  # Mix into a class that provides @sources (array of Queue::Source)
  # and @source_index (current position).
  module SourceViewer
    def display_current_source(width: 80, height: nil)
      source = current_source
      return puts "(no sources)" unless source

      renderer = Source::Base.for(source)
      lines = renderer.render(width: width, height: height)

      puts
      ::CLI::UI::Frame.open(source_frame_title(renderer), color: :yellow) do
        lines.each { |line| puts line }
      end
    end

    def status_bar
      return "" if sources_list.empty?

      source = current_source
      renderer = Source::Base.for(source)
      "[#{@source_index + 1}/#{sources_list.length}] #{source.type}: #{renderer.label}"
    end

    def next_source
      return false if sources_list.length <= 1

      @source_index = (@source_index + 1) % sources_list.length
      true
    end

    def prev_source
      return false if sources_list.length <= 1

      @source_index = (@source_index - 1) % sources_list.length
      true
    end

    def jump_to_source(index)
      return false if index < 0 || index >= sources_list.length

      @source_index = index
      true
    end

    def current_source
      sources_list[@source_index]
    end

    def multi_source?
      sources_list.length > 1
    end

    # Drill-down: show full diff for current file (all hunks)
    def drill_down_diff
      source = current_source
      return false unless source&.type == "diff"

      renderer = Source::Diff.new(source)
      lines = renderer.render(width: terminal_width)

      puts
      ::CLI::UI::Frame.open("{{bold:Full Diff}} {{cyan:#{renderer.label}}}", color: :magenta) do
        lines.each { |line| puts line }
      end
      true
    end

    # Drill-down: show full transcript
    def drill_down_transcript
      source = current_source
      return false unless source&.type == "transcript"

      renderer = Source::Transcript.new(source)
      lines = renderer.render(width: terminal_width)

      puts
      ::CLI::UI::Frame.open("{{bold:Full Transcript}} {{cyan:#{renderer.label}}}", color: :magenta) do
        lines.each { |line| puts line }
      end
      true
    end

    # Drill-down: file browser - list all sources, return selected index or nil
    def drill_down_file_browser
      return nil if sources_list.empty?

      puts
      ::CLI::UI::Frame.open("{{bold:Sources}}", color: :cyan) do
        sources_list.each_with_index do |source, i|
          renderer = Source::Base.for(source)
          marker = i == @source_index ? "{{green:▸}}" : " "
          puts ::CLI::UI.fmt("  #{marker} {{yellow:[#{i}]}} {{bold:#{source.type}}} {{gray:#{renderer.label}}}")
        end
        puts
        puts ::CLI::UI.fmt("{{gray:Enter number to jump, or any key to return}}")
      end

      char = ::CLI::UI::Prompt.read_char
      index = char.to_i
      if char =~ /\d/ && index >= 0 && index < sources_list.length
        jump_to_source(index)
        index
      end
    end

    private

    # Override in including class if sources are stored differently
    def sources_list
      @sources || []
    end

    def source_frame_title(renderer)
      if multi_source?
        "{{bold:#{renderer.label}}} {{cyan:(#{status_bar})}}"
      else
        "{{bold:#{renderer.label}}}"
      end
    end

    def terminal_width
      IO.console&.winsize&.last || 80
    rescue
      80
    end
  end
end
