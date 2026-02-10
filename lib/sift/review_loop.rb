# frozen_string_literal: true

require "cli/ui"

module Sift
  class ReviewLoop
    def initialize(path:, base: "HEAD", model: "sonnet")
      @path = File.expand_path(path)
      @base = base
      @client = Client.new(model: model)
      @hunks = []
      @current = 0
      @decisions = []
      @sessions = {} # file -> session_id for continuity
      @analyses = {} # hunk index -> analysis result
    end

    def run
      setup_ui
      load_hunks
      return if @hunks.empty?

      show_header

      loop do
        break if @current >= @hunks.length

        hunk = @hunks[@current]
        display_hunk(hunk)

        action = prompt_action(has_analysis: @analyses.key?(@current))
        break if action == :quit

        case action
        when :analyze
          analysis = analyze_hunk(hunk)
          @analyses[@current] = analysis
          display_analysis(analysis)
          redo # Show prompt again for same hunk
        when :revise
          # Can only revise if we have analysis
          unless @analyses.key?(@current)
            puts ::CLI::UI.fmt("{{yellow:No analysis to revise. Press '?' first.}}")
            redo
          end
          feedback = ::CLI::UI::Prompt.ask("Revision feedback:")
          puts ::CLI::UI.fmt("{{magenta:↻ Revising...}}")
          revised = revise_analysis(hunk, feedback)
          @analyses[@current] = revised
          display_analysis(revised)
          redo
        else
          handle_action(action, hunk)
          @current += 1
        end
      end

      show_summary
    end

    private

    def setup_ui
      ::CLI::UI::StdoutRouter.enable
      ::CLI::UI.frame_style = :box
    end

    def load_hunks
      ::CLI::UI::Spinner.spin("Loading diff hunks...") do |spinner|
        @hunks = DiffParser.from_git(@path, base: @base)
        spinner.update_title("Found #{@hunks.length} hunks")
      end

      if @hunks.empty?
        puts ::CLI::UI.fmt("{{yellow:No changes found.}}")
      end
    end

    def show_header
      puts
      ::CLI::UI::Frame.open("{{bold:Sift Review}}", color: :blue) do
        puts ::CLI::UI.fmt("{{cyan:Reviewing #{@hunks.length} hunks in}} {{bold:#{@path}}}")
        puts ::CLI::UI.fmt("{{gray:Base: #{@base}}}")
      end
    end

    def display_hunk(hunk)
      source = Queue::Source.new(type: "diff", path: hunk.file, content: hunk.content)
      renderer = Source::Diff.new(source)
      lines = renderer.render(width: terminal_width)

      puts
      ::CLI::UI::Frame.open("{{bold:#{hunk.file}}} {{cyan:(#{@current + 1}/#{@hunks.length})}}", color: :yellow) do
        lines.each { |line| puts line }
      end
    end

    def terminal_width
      IO.console&.winsize&.last || 80
    rescue
      80
    end

    def display_analysis(analysis)
      puts
      ::CLI::UI::Frame.open("{{bold:Analysis}}", color: :magenta) do
        puts analysis.response
      end
    end

    def analyze_hunk(hunk)
      result = nil
      ::CLI::UI::Spinner.spin("Asking Claude...") do |spinner|
        session_id = @sessions[hunk.file]
        result = @client.analyze_diff(
          hunk.content,
          file: hunk.file,
          session_id: session_id
        )
        @sessions[hunk.file] = result.session_id
        spinner.update_title("Done")
      end
      result
    end

    def prompt_action(has_analysis:)
      puts
      if has_analysis
        puts ::CLI::UI.fmt("{{bold:Actions:}} [{{green:a}}]ccept  [{{red:r}}]eject  [{{yellow:c}}]omment  [{{magenta:v}}]revise  [{{blue:?}}]ask again  [{{cyan:q}}]uit")
      else
        puts ::CLI::UI.fmt("{{bold:Actions:}} [{{green:a}}]ccept  [{{red:r}}]eject  [{{yellow:c}}]omment  [{{blue:?}}]ask Claude  [{{cyan:q}}]uit")
      end
      print ::CLI::UI.fmt("{{bold:Choice:}} ")

      loop do
        char = ::CLI::UI::Prompt.read_char
        case char.downcase
        when "a"
          puts ::CLI::UI.fmt("{{green:✓ Accepted}}")
          return :accept
        when "r"
          puts ::CLI::UI.fmt("{{red:✗ Rejected}}")
          return :reject
        when "c"
          puts
          comment = ::CLI::UI::Prompt.ask("Enter comment:")
          puts ::CLI::UI.fmt("{{yellow:💬 Commented}}")
          return [:comment, comment]
        when "v"
          return :revise
        when "?"
          puts ::CLI::UI.fmt("{{blue:🤖 Analyzing...}}")
          return :analyze
        when "q"
          puts ::CLI::UI.fmt("{{cyan:Quitting...}}")
          return :quit
        end
      end
    end

    def handle_action(action, hunk)
      analysis = @analyses[@current]
      case action
      when :accept
        perform_git_action(:accept, hunk)
        @decisions << { file: hunk.file, action: :accept, response: analysis&.response }
      when :reject
        perform_git_action(:reject, hunk)
        @decisions << { file: hunk.file, action: :reject, response: analysis&.response }
      when Array
        type, content = action
        @decisions << { file: hunk.file, action: type, comment: content, response: analysis&.response }
      end
    end

    def perform_git_action(action, hunk)
      case action
      when :accept
        GitActions.stage_hunk(hunk, path: @path)
        puts ::CLI::UI.fmt("{{green:Staged hunk}}")
      when :reject
        GitActions.revert_hunk(hunk, path: @path)
        puts ::CLI::UI.fmt("{{red:Reverted hunk}}")
      end
    rescue GitActions::Error => e
      puts ::CLI::UI.fmt("{{red:Git error: #{e.message}}}")
    end

    def revise_analysis(hunk, feedback)
      result = nil
      ::CLI::UI::Spinner.spin("Re-analyzing with feedback...") do |spinner|
        session_id = @sessions[hunk.file]
        prompt = "User feedback on your analysis: #{feedback}\n\nPlease revise your review."
        result = @client.prompt(prompt, session_id: session_id)
        @sessions[hunk.file] = result.session_id
        spinner.update_title("Done")
      end
      result
    end

    def show_summary
      puts
      ::CLI::UI::Frame.open("{{bold:Review Summary}}", color: :green) do
        if @decisions.empty?
          puts ::CLI::UI.fmt("{{yellow:No decisions recorded.}}")
        else
          staged = @decisions.count { |d| d[:action] == :accept }
          reverted = @decisions.count { |d| d[:action] == :reject }
          commented = @decisions.count { |d| d[:action] == :comment }

          puts ::CLI::UI.fmt("{{green:Staged:}} #{staged}")
          puts ::CLI::UI.fmt("{{red:Reverted:}} #{reverted}")
          puts ::CLI::UI.fmt("{{yellow:Commented:}} #{commented}")
          puts ::CLI::UI.fmt("{{cyan:Remaining:}} #{@hunks.length - @current}")
        end
      end
    end
  end
end
