# frozen_string_literal: true

require "cli/ui"

module Sift
  class ReviewLoop
    include SourceViewer

    def initialize(queue:, model: "sonnet", dry: false)
      @queue = queue
      @client = dry ? DryClient.new(model: model) : Client.new(model: model)
      @items = []
      @current = 0
      @source_index = 0
      @analyses = {} # item index -> analysis result
    end

    def run
      setup_ui
      load_items
      return if @items.empty?

      show_header

      while @current < @items.length
        item = @items[@current]
        setup_item(item)
        break if review_item(item) == :quit
      end

      show_summary
    end

    private

    def review_item(item)
      loop do
        display_current_source(width: terminal_width)

        action = prompt_action(
          has_analysis: @analyses.key?(@current),
          multi_source: multi_source?,
        )
        return :quit if action == :quit

        case action
        when :next_source
          next_source
        when :prev_source
          prev_source
        when :browse_sources
          drill_down_file_browser
        when :edit
          open_in_editor(item)
          reload_sources(item)
        when :analyze
          analysis = analyze_item(item)
          @analyses[@current] = analysis
          display_analysis(analysis)
        when :revise
          unless @analyses.key?(@current)
            puts ::CLI::UI.fmt("{{yellow:No analysis to revise. Press '?' first.}}")
            next
          end
          feedback = ::CLI::UI::Prompt.ask("Revision feedback:")
          puts ::CLI::UI.fmt("{{magenta:↻ Revising...}}")
          revised = revise_analysis(item, feedback)
          @analyses[@current] = revised
          display_analysis(revised)
        else
          handle_action(action, item)
          @current += 1
          return :next
        end
      end
    end

    def setup_ui
      ::CLI::UI::StdoutRouter.enable
      ::CLI::UI.frame_style = :box
    end

    def load_items
      ::CLI::UI::Spinner.spin("Loading queue items...") do |spinner|
        @items = @queue.filter(status: "pending")
        spinner.update_title("Found #{@items.length} pending items")
      end

      if @items.empty?
        puts ::CLI::UI.fmt("{{yellow:No pending items in queue.}}")
      end
    end

    def setup_item(item)
      @sources = item.sources
      @source_index = 0
    end

    # Override SourceViewer's sources_list to use @sources set by setup_item
    def sources_list
      @sources || []
    end

    def show_header
      puts
      ::CLI::UI::Frame.open("{{bold:Sift Review}}", color: :blue) do
        puts ::CLI::UI.fmt("{{cyan:Reviewing}} {{bold:#{@items.length}}} {{cyan:pending items}}")
        puts ::CLI::UI.fmt("{{gray:Queue: #{@queue.path}}}")
      end
    end

    def display_analysis(analysis)
      puts
      ::CLI::UI::Frame.open("{{bold:Analysis}}", color: :magenta) do
        puts analysis.response
      end
    end

    def prompt_action(has_analysis:, multi_source: false)
      puts
      parts = []
      parts << "[{{green:a}}]ccept"
      parts << "[{{red:r}}]eject"
      parts << "[{{yellow:c}}]omment"
      parts << "[{{cyan:e}}]dit"

      if has_analysis
        parts << "[{{magenta:v}}]revise"
        parts << "[{{blue:?}}]ask again"
      else
        parts << "[{{blue:?}}]ask Claude"
      end

      if multi_source
        parts << "[{{cyan:n}}]ext source"
        parts << "[{{cyan:p}}]rev source"
        parts << "[{{cyan:s}}]ources"
      end

      parts << "[{{gray:q}}]uit"

      puts ::CLI::UI.fmt("{{bold:Actions:}} #{parts.join("  ")}")
      puts ::CLI::UI.fmt("{{gray:Item #{@items[@current].id} (#{@current + 1}/#{@items.length})}}")
      print ::CLI::UI.fmt("{{bold:Choice:}} ")

      loop do
        char = ::CLI::UI::Prompt.read_char
        case char.downcase
        when "a"
          puts ::CLI::UI.fmt("{{green:✓ Approved}}")
          return :accept
        when "r"
          puts ::CLI::UI.fmt("{{red:✗ Rejected}}")
          return :reject
        when "c"
          puts
          comment = ::CLI::UI::Prompt.ask("Enter comment:")
          puts ::CLI::UI.fmt("{{yellow:💬 Commented}}")
          return [:comment, comment]
        when "e"
          return :edit
        when "v"
          return :revise if has_analysis
        when "?"
          puts ::CLI::UI.fmt("{{blue:🤖 Analyzing...}}")
          return :analyze
        when "n"
          return :next_source if multi_source
        when "p"
          return :prev_source if multi_source
        when "s"
          return :browse_sources if multi_source
        when "q"
          puts ::CLI::UI.fmt("{{cyan:Quitting...}}")
          return :quit
        end
      end
    end

    def handle_action(action, item)
      case action
      when :accept
        @queue.update(item.id, status: "approved")
      when :reject
        @queue.update(item.id, status: "rejected")
      when Array
        type, content = action
        if type == :comment
          metadata = (item.metadata || {}).merge("comment" => content)
          @queue.update(item.id, metadata: metadata)
        end
      end
    end

    def analyze_item(item)
      result = nil
      ::CLI::UI::Spinner.spin("Asking Claude...") do |spinner|
        prompt_text = build_analysis_prompt(item)
        result = @client.prompt(prompt_text, session_id: item.session_id)
        @queue.update(item.id, session_id: result.session_id)
        spinner.update_title("Done")
      end
      result
    end

    def revise_analysis(item, feedback)
      result = nil
      ::CLI::UI::Spinner.spin("Re-analyzing with feedback...") do |spinner|
        prompt_text = "User feedback on your analysis: #{feedback}\n\nPlease revise your review."
        result = @client.prompt(prompt_text, session_id: item.session_id)
        @queue.update(item.id, session_id: result.session_id)
        spinner.update_title("Done")
      end
      result
    end

    def build_analysis_prompt(item)
      parts = []
      item.sources.each do |source|
        case source.type
        when "diff"
          parts << "File: #{source.path}" if source.path
          parts << "Diff:"
          parts << "```diff"
          parts << source.content
          parts << "```"
        when "file"
          parts << "File: #{source.path}" if source.path
          parts << "```"
          parts << (source.content || "")
          parts << "```"
        when "transcript"
          parts << "Previous conversation:"
          parts << (source.content || "")
        when "text"
          parts << (source.content || "")
        end
        parts << ""
      end
      parts << "Review this item. Be concise (1-2 sentences). Focus on potential issues, improvements, or confirm it looks good."
      parts.join("\n")
    end

    def open_in_editor(item)
      editor = Editor.new(sources: item.sources, item_id: item.id)
      editor.open
    end

    def reload_sources(item)
      changed = false
      item.sources.each do |source|
        next unless source.path && ::File.exist?(source.path)

        new_content = ::File.read(source.path)
        if new_content != source.content
          source.content = new_content
          changed = true
        end
      end

      if changed && @analyses.key?(@current)
        puts ::CLI::UI.fmt("{{yellow:Sources changed on disk. Analysis may be stale.}}")
      end
    end

    def show_summary
      items = @queue.all
      approved = items.count(&:approved?)
      rejected = items.count(&:rejected?)
      pending = items.count(&:pending?)

      puts
      ::CLI::UI::Frame.open("{{bold:Review Summary}}", color: :green) do
        puts ::CLI::UI.fmt("{{green:Approved:}} #{approved}")
        puts ::CLI::UI.fmt("{{red:Rejected:}} #{rejected}")
        puts ::CLI::UI.fmt("{{cyan:Remaining:}} #{pending}")
      end
    end
  end
end
