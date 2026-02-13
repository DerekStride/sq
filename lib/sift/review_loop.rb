# frozen_string_literal: true

require "async"
require "cli/ui"
require "io/console"
require "tempfile"
require_relative "statusline"

module Sift
  class ReviewLoop
    AGENT_DOCS_DIR = File.expand_path("../../../agent-docs", __FILE__)

    def initialize(config:)
      @config = config
      @queue = Queue.new(config.queue_path)
      @client = config.dry? ? DryClient.new(config: config) : Client.new(config: config)
      @concurrency = config.concurrency
    end

    def run
      Sync do |task|
        setup_ui
        @agent_runner = AgentRunner.new(client: @client, task: task, queue: @queue, limit: @concurrency)
        Statusline.with do |sl|
          @statusline = sl
          refresh_statusline
          main_loop
        end
      end
    end

    private

    def setup_ui
      ::CLI::UI::StdoutRouter.enable
      ::CLI::UI.frame_style = :box
    end

    def main_loop
      warn_stale_items
      index = 0

      loop do
        process_completed_agents

        items = @queue.filter(status: "pending")
        eligible = items.reject { |item| @agent_runner.running?(item.id) }

        break if eligible.empty? && @agent_runner.running_count == 0

        if eligible.empty?
          action = wait_with_input
          return if action == :quit
          next
        end

        index = index.clamp(0, eligible.size - 1)
        item = eligible[index]
        result = review_item(item, position: index + 1, total: eligible.size)

        case result
        when :quit
          return
        when :next
          index += 1
          index = 0 if index >= eligible.size
        when :prev
          index -= 1
          index = eligible.size - 1 if index < 0
        when :acted
          # Item was closed/agent started — stay at same index (next item slides in)
        end
      end
    end

    def review_item(item, position: nil, total: nil)
      loop do
        process_completed_agents
        display_card(item, position: position, total: total)
        action = prompt_action(item, show_nav: total && total > 1)

        case action
        when :view
          handle_view(item)
        when :agent
          handle_agent(item)
          return :acted
        when :general
          handle_general_agent
        when :close
          handle_close(item)
          return :acted
        when :next
          return :next
        when :prev
          return :prev
        when :quit
          process_completed_agents
          @agent_runner.stop_all
          return :quit
        end
      end
    end

    def display_card(item, position: nil, total: nil)
      puts
      title = "{{bold:Item #{item.id}}}"
      title += " {{gray:[#{position}/#{total}]}}" if position && total
      ::CLI::UI::Frame.open(title, color: :blue) do
        grouped = item.sources.group_by(&:type)
        grouped.each do |type, sources|
          puts ::CLI::UI.fmt("  {{yellow:#{type}}}")
          sources.each do |source|
            label = source.path || "[inline]"
            puts ::CLI::UI.fmt("    {{gray:#{label}}}")
          end
        end
        if item.session_id
          puts ::CLI::UI.fmt("  {{yellow:transcript}}")
          puts ::CLI::UI.fmt("    {{gray:[session]}}")
        end
      end
    end

    def prompt_action(item, show_nav: false)
      puts

      parts = [
        "[{{cyan:v}}]iew",
        "[{{blue:a}}]gent",
        "[{{green:c}}]lose",
        "[{{magenta:g}}]eneral",
      ]
      parts << "[{{yellow:n}}]ext  [{{yellow:p}}]rev" if show_nav
      parts << "[{{gray:q}}]uit"

      puts ::CLI::UI.fmt("{{bold:Actions:}} #{parts.join("  ")}")
      print ::CLI::UI.fmt("{{bold:Choice:}} ")

      read_action_char(show_nav: show_nav)
    end

    # Non-blocking input loop. Ticks the statusline spinner every 100ms
    # while waiting for a keypress. Does NOT call process_completed_agents —
    # that happens when the user takes an action and the main flow resumes.
    # Suppresses debug/info logs so $stderr doesn't corrupt the prompt.
    def read_action_char(show_nav: false)
      Log.quiet do
        loop do
          char = read_char
          next unless char
          action = resolve_action(char.downcase, show_nav: show_nav)
          return action if action
        end
      end
    end

    # Read a single character, ticking the statusline while waiting.
    # Returns nil on timeout (no input within 100ms tick interval).
    def read_char
      if $stdin.tty?
        $stdin.raw do |io|
          if io.wait_readable(0.1)
            io.getc
          else
            @statusline&.tick && refresh_statusline
            nil
          end
        end
      else
        ::CLI::UI::Prompt.read_char
      end
    end

    def resolve_action(char, show_nav: false)
      case char
      when "v"
        puts "view"
        :view
      when "a"
        puts "agent"
        :agent
      when "c"
        puts ::CLI::UI.fmt("{{green:closed}}")
        :close
      when "g"
        puts "general"
        :general
      when "n"
        return nil unless show_nav
        puts "next"
        :next
      when "p"
        return nil unless show_nav
        puts "prev"
        :prev
      when "q"
        puts "quit"
        :quit
      end
    end

    def refresh_statusline
      return unless @statusline && @agent_runner

      pending = @queue.count(status: "pending")
      active = @agent_runner.active_count
      finished = @agent_runner.finished_count

      parts = ["#{pending} pending"]
      parts << "#{@statusline.spinner} #{active} running" if active > 0
      parts << "#{finished} finished" if finished > 0

      @statusline.update("{{gray:#{parts.join(" | ")}}}")
    end

    def wait_with_input
      running = @agent_runner.running_count
      puts ::CLI::UI.fmt("\n{{gray:Waiting for #{running} agent#{"s" if running != 1}...}}")
      puts ::CLI::UI.fmt("{{bold:Actions:}} [{{magenta:g}}]eneral  [{{gray:q}}]uit")
      print ::CLI::UI.fmt("{{bold:Choice:}} ")

      ready = IO.select([$stdin], nil, nil, 1)
      return nil unless ready

      char = $stdin.getch
      case char.downcase
      when "g"
        puts "general"
        handle_general_agent
        nil
      when "q"
        puts "quit"
        :quit
      end
    end

    # Tick the statusline while waiting for agents to finish.
    # Returns after ~1s so main_loop can re-evaluate.
    def wait_for_agents
      10.times do # ~1 second total (10 × 0.1s)
        if @statusline&.tick
          refresh_statusline
        end
        sleep 0.1
      end
    end

    def handle_view(item)
      editor = Editor.new(sources: item.sources, item_id: item.id, session_id: item.session_id)
      editor.open
    end

    def handle_general_agent
      print ::CLI::UI.fmt("{{bold:Prompt}} {{gray:(Ctrl-G for editor):}} ")
      user_prompt = read_agent_prompt
      return if user_prompt.nil? || user_prompt.strip.empty?

      @agent_runner.spawn_general(user_prompt, user_prompt, system_prompt: general_agent_system_prompt)
      puts ::CLI::UI.fmt("{{magenta:General agent started in background}}")
    end

    def general_agent_system_prompt
      path = File.join(AGENT_DOCS_DIR, "general.md")
      template = File.read(path)
      template.gsub("{{queue_path}}", @queue.path)
    rescue Errno::ENOENT
      Log.warn "agent doc not found: #{path}"
      nil
    end

    def handle_agent(item)
      print ::CLI::UI.fmt("{{bold:Prompt}} {{gray:(Ctrl-G for editor):}} ")
      # Note: getch blocks the current fiber; same caveat as read_char.
      user_prompt = read_agent_prompt
      return if user_prompt.nil? || user_prompt.strip.empty?

      # Auto-create worktree on first agent invocation
      if item.worktree.nil?
        wt = Sift::Worktree.create(item.id,
          base_branch: @config.worktree_base_branch,
          setup_command: @config.worktree_setup_command)
        @queue.update(item.id, worktree: wt)
        item = @queue.find(item.id)
      end

      prompt_text = build_agent_prompt(item, user_prompt)
      system_prompt = resolve_system_prompt(item)
      @agent_runner.spawn(item.id, prompt_text, user_prompt,
        session_id: item.session_id, system_prompt: system_prompt,
        cwd: item.worktree&.path)
      refresh_statusline
      puts ::CLI::UI.fmt("{{blue:Agent started in background}}")
    end

    def process_completed_agents
      completed = @agent_runner.poll
      refresh_statusline unless completed.empty?
      completed.each do |item_id, data|
        if data[:general]
          process_completed_general_agent(item_id, data)
        else
          process_completed_item_agent(item_id, data)
        end
      end
    end

    def process_completed_item_agent(item_id, data)
      if data[:claim_failed]
        Log.debug "agent claim failed for item=#{item_id}, skipping"
        return
      end

      result = data[:result]
      error = data[:error]
      user_prompt = data[:prompt]

      if result
        item = @queue.find(item_id)
        return unless item

        @queue.update(item_id, session_id: result.session_id)
        puts ::CLI::UI.fmt("\n{{blue:Agent finished for item #{item_id}}}")
      else
        item = @queue.find(item_id)
        if item
          error_entry = {
            "message" => error || "Unknown error",
            "prompt" => user_prompt,
            "timestamp" => Time.now.utc.iso8601,
          }
          errors = (item.errors || []) + [error_entry]
          @queue.update(item_id, errors: errors)
        end
        Log.warn "agent failed item=#{item_id}: #{error}"
        puts ::CLI::UI.fmt("\n{{red:Agent failed for item #{item_id}: #{error}}}")
      end
    end

    def process_completed_general_agent(key, data)
      result = data[:result]
      error = data[:error]
      user_prompt = data[:prompt]

      if result
        text_source = { type: "text", content: user_prompt }
        metadata = { "source" => "general_agent", "prompt" => user_prompt }

        @queue.push(sources: [text_source], metadata: metadata, session_id: result.session_id)
        puts ::CLI::UI.fmt("\n{{magenta:General agent finished — new item added to queue}}")
      else
        Log.warn "general agent failed key=#{key}: #{error}"
        puts ::CLI::UI.fmt("\n{{red:General agent failed: #{error}}}")
      end
    end

    def handle_close(item)
      @queue.update(item.id, status: "closed")
      refresh_statusline
    end

    def warn_stale_items
      stale = @queue.filter(status: "in_progress")
      return if stale.empty?

      Log.warn "#{stale.size} item(s) still in_progress from a previous session"
      stale.each { |item| Log.warn "  #{item.id} (updated: #{item.updated_at})" }
      Log.warn "Release with: sq edit <id> --set-status pending"
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
        when "text"
          parts << (source.content || "")
        when "directory"
          parts << "Directory: #{source.path}" if source.path
        end
        parts << ""
      end
      parts << user_prompt
      parts.join("\n")
    end

    # Resolve the system prompt for an item.
    # Per-item system_prompt (from metadata) overrides the session default.
    def resolve_system_prompt(item)
      path = item.metadata&.dig("system_prompt")
      return nil unless path

      File.read(path)
    rescue Errno::ENOENT
      Log.warn "system prompt file not found: #{path}"
      nil
    end
  end
end
