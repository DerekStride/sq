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
    end

    def run
      setup_ui
      load_hunks
      return if @hunks.empty?

      show_header

      loop do
        break if @current >= @hunks.length

        hunk = @hunks[@current]
        analysis = analyze_hunk(hunk)
        display_review(hunk, analysis)

        action = prompt_action
        break if action == :quit

        handle_action(action, hunk, analysis)
        @current += 1
      end

      show_summary
    end

    private

    def setup_ui
      CLI::UI::StdoutRouter.enable
      CLI::UI.frame_style = :box
    end

    def load_hunks
      CLI::UI::Spinner.spin("Loading diff hunks...") do |spinner|
        @hunks = DiffParser.from_git(@path, base: @base)
        spinner.update_title("Found #{@hunks.length} hunks")
      end

      if @hunks.empty?
        puts CLI::UI.fmt("{{yellow:No changes found.}}")
      end
    end

    def show_header
      puts
      CLI::UI::Frame.open("{{bold:Sift Review}}", color: :blue) do
        puts CLI::UI.fmt("{{cyan:Reviewing #{@hunks.length} hunks in}} {{bold:#{@path}}}")
        puts CLI::UI.fmt("{{gray:Base: #{@base}}}")
      end
    end

    def analyze_hunk(hunk)
      result = nil
      CLI::UI::Spinner.spin("Analyzing #{hunk.file}...") do |spinner|
        session_id = @sessions[hunk.file]
        result = @client.analyze_diff(
          hunk.content,
          file: hunk.file,
          session_id: session_id
        )
        @sessions[hunk.file] = result.session_id
        spinner.update_title("Analysis complete")
      end
      result
    end

    def display_review(hunk, analysis)
      puts
      CLI::UI::Frame.open("{{bold:#{hunk.file}}} {{cyan:(#{@current + 1}/#{@hunks.length})}}", color: :yellow) do
        puts CLI::UI.fmt("{{bold:Diff:}}")
        hunk.content.each_line do |line|
          formatted = case line[0]
          when "+" then CLI::UI.fmt("{{green:#{line.chomp}}}")
          when "-" then CLI::UI.fmt("{{red:#{line.chomp}}}")
          when "@" then CLI::UI.fmt("{{cyan:#{line.chomp}}}")
          else line.chomp
          end
          puts formatted
        end

        puts
        puts CLI::UI.fmt("{{bold:Analysis:}}")
        puts analysis.response
      end
    end

    def prompt_action
      puts
      puts CLI::UI.fmt("{{bold:Actions:}} [{{green:a}}]ccept  [{{red:r}}]eject  [{{yellow:c}}]omment  [{{magenta:v}}]revise  [{{cyan:q}}]uit")
      print CLI::UI.fmt("{{bold:Choice:}} ")

      loop do
        char = CLI::UI::Prompt.read_char
        case char.downcase
        when "a"
          puts CLI::UI.fmt("{{green:✓ Accepted}}")
          return :accept
        when "r"
          puts CLI::UI.fmt("{{red:✗ Rejected}}")
          return :reject
        when "c"
          puts
          comment = CLI::UI::Prompt.ask("Enter comment:")
          puts CLI::UI.fmt("{{yellow:💬 Commented}}")
          return [:comment, comment]
        when "v"
          puts
          feedback = CLI::UI::Prompt.ask("Revision feedback:")
          puts CLI::UI.fmt("{{magenta:↻ Revising...}}")
          return [:revise, feedback]
        when "q"
          puts CLI::UI.fmt("{{cyan:Quitting...}}")
          return :quit
        end
      end
    end

    def handle_action(action, hunk, analysis)
      case action
      when :accept, :reject
        @decisions << { file: hunk.file, action: action, response: analysis.response }
      when Array
        type, content = action
        if type == :revise
          # Re-analyze with feedback, don't advance
          revised = revise_analysis(hunk, content)
          display_review(hunk, revised)
          new_action = prompt_action
          return :quit if new_action == :quit
          handle_action(new_action, hunk, revised)
          @current -= 1 # Will be incremented back in main loop
        else
          @decisions << { file: hunk.file, action: type, comment: content, response: analysis.response }
        end
      end
    end

    def revise_analysis(hunk, feedback)
      result = nil
      CLI::UI::Spinner.spin("Re-analyzing with feedback...") do |spinner|
        session_id = @sessions[hunk.file]
        prompt = "User feedback on your analysis: #{feedback}\n\nPlease revise your review."
        result = @client.prompt(prompt, session_id: session_id)
        @sessions[hunk.file] = result.session_id
        spinner.update_title("Revised analysis complete")
      end
      result
    end

    def show_summary
      puts
      CLI::UI::Frame.open("{{bold:Review Summary}}", color: :green) do
        if @decisions.empty?
          puts CLI::UI.fmt("{{yellow:No decisions recorded.}}")
        else
          accepted = @decisions.count { |d| d[:action] == :accept }
          rejected = @decisions.count { |d| d[:action] == :reject }
          commented = @decisions.count { |d| d[:action] == :comment }

          puts CLI::UI.fmt("{{green:Accepted:}} #{accepted}")
          puts CLI::UI.fmt("{{red:Rejected:}} #{rejected}")
          puts CLI::UI.fmt("{{yellow:Commented:}} #{commented}")
          puts CLI::UI.fmt("{{cyan:Remaining:}} #{@hunks.length - @current}")
        end
      end
    end
  end
end
