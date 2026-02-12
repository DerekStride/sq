# frozen_string_literal: true

require "async"
require "cli/ui"
require "io/console"
require "tempfile"

module Sift
  class ReviewLoop
    def initialize(queue:, model: "sonnet", dry: false)
      @queue = queue
      @client = dry ? DryClient.new(model: model) : Client.new(model: model)
    end

    def run
      Sync do |task|
        setup_ui
        @agent_runner = AgentRunner.new(client: @client, task: task)
        main_loop
      end
    end

    private

    def setup_ui
      ::CLI::UI::StdoutRouter.enable
      ::CLI::UI.frame_style = :box
    end

    def main_loop
      loop do
        process_completed_agents

        items = @queue.filter(status: "pending")
        eligible = items.reject { |item| @agent_runner.running?(item.id) }

        break if eligible.empty? && @agent_runner.running_count == 0

        if eligible.empty?
          display_waiting_status
          sleep 1
          next
        end

        eligible.each do |item|
          result = review_item(item)
          return if result == :quit
        end
      end
    end

    def review_item(item)
      loop do
        display_card(item)
        action = prompt_action(item)

        case action
        when :view
          handle_view(item)
        when :agent
          handle_agent(item)
          return :next
        when :close
          handle_close(item)
          return :next
        when :quit
          @agent_runner.stop_all
          return :quit
        end
      end
    end

    def display_card(item)
      puts
      ::CLI::UI::Frame.open("{{bold:Item #{item.id}}}", color: :blue) do
        grouped = item.sources.group_by(&:type)
        grouped.each do |type, sources|
          puts ::CLI::UI.fmt("  {{yellow:#{type}}}")
          sources.each do |source|
            label = source.path || "[inline]"
            puts ::CLI::UI.fmt("    {{gray:#{label}}}")
          end
        end
      end
    end

    def prompt_action(item)
      puts
      status = status_line
      puts ::CLI::UI.fmt(status) if status

      parts = [
        "[{{cyan:v}}]iew",
        "[{{blue:a}}]gent",
        "[{{green:c}}]lose",
        "[{{gray:q}}]uit",
      ]

      puts ::CLI::UI.fmt("{{bold:Actions:}} #{parts.join("  ")}")
      print ::CLI::UI.fmt("{{bold:Choice:}} ")

      loop do
        # Note: read_char blocks the current fiber; agent fibers won't
        # progress while waiting for input. Acceptable for now — revisit
        # with IO#wait_readable if needed.
        char = ::CLI::UI::Prompt.read_char
        case char.downcase
        when "v"
          puts "view"
          return :view
        when "a"
          puts "agent"
          return :agent
        when "c"
          puts ::CLI::UI.fmt("{{green:closed}}")
          return :close
        when "q"
          puts "quit"
          return :quit
        end
      end
    end

    def status_line
      pending = @queue.count(status: "pending")
      running = @agent_runner.running_count
      return nil if running == 0

      "{{gray:[#{pending} pending | #{running} running]}}"
    end

    def display_waiting_status
      running = @agent_runner.running_count
      puts ::CLI::UI.fmt("\n{{gray:Waiting for #{running} agent#{"s" if running != 1}...}}")
    end

    def handle_view(item)
      editor = Editor.new(sources: item.sources, item_id: item.id)
      editor.open
    end

    def handle_agent(item)
      print ::CLI::UI.fmt("{{bold:Prompt}} {{gray:(Ctrl-G for editor):}} ")
      # Note: getch blocks the current fiber; same caveat as read_char.
      user_prompt = read_agent_prompt
      return if user_prompt.nil? || user_prompt.strip.empty?

      prompt_text = build_agent_prompt(item, user_prompt)
      @agent_runner.spawn(item.id, prompt_text, user_prompt, session_id: item.session_id)
      puts ::CLI::UI.fmt("{{blue:Agent started in background}}")
    end

    def process_completed_agents
      completed = @agent_runner.poll
      completed.each do |item_id, data|
        result = data[:result]
        user_prompt = data[:prompt]

        if result
          transcript_source = Queue::Source.new(
            type: "transcript",
            content: "User: #{user_prompt}\n\nAssistant: #{result.response}",
          )
          item = @queue.find(item_id)
          next unless item

          updated_sources = item.sources + [transcript_source]
          @queue.update(item_id, sources: updated_sources, session_id: result.session_id)
          puts ::CLI::UI.fmt("\n{{blue:Agent finished for item #{item_id}}}")
        else
          puts ::CLI::UI.fmt("\n{{red:Agent failed for item #{item_id}}}")
        end
      end
    end

    def handle_close(item)
      @queue.update(item.id, status: "closed")
    end

    def read_agent_prompt
      chars = []

      loop do
        char = $stdin.getch

        case char
        when "\r", "\n" # Enter
          puts
          return chars.join
        when "\a" # Ctrl-G
          puts
          return read_from_editor(chars.join)
        when "\u007F", "\b" # Backspace
          if chars.any?
            chars.pop
            print "\b \b"
          end
        when "\u0003" # Ctrl-C
          puts
          return nil
        else
          chars << char
          print char
        end
      end
    end

    def read_from_editor(existing_text)
      tmpfile = Tempfile.new(["sift-prompt-", ".md"])
      tmpfile.write(existing_text)
      tmpfile.close

      editor = ENV["EDITOR"] || ENV["VISUAL"] || "vi"
      system(editor, tmpfile.path)

      content = File.read(tmpfile.path)
      content.strip.empty? ? nil : content
    ensure
      tmpfile&.unlink
    end

    def build_agent_prompt(item, user_prompt)
      # Subsequent turns: just the user prompt (session handles context)
      return user_prompt if item.session_id

      # First turn: include all sources
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
      parts << user_prompt
      parts.join("\n")
    end
  end
end
