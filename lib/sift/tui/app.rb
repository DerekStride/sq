# frozen_string_literal: true

require "bubbletea"
require "bubbles"
require "lipgloss"
require "async"
require "tempfile"

require_relative "exec_command"
require_relative "messages"
require_relative "styles"
require_relative "keymap"
require_relative "card"

module Sift
  module TUI
    class App
      include Bubbletea::Model

      AGENT_DOCS_DIR = File.expand_path("../../../../agent-docs", __FILE__)
      PROMPT_PREFIX_WIDTH = 45 # "  Prompt (Ctrl-G for editor, Esc to cancel): "

      attr_reader :mode, :items, :index, :flash, :flash_style,
        :prompt_target, :width, :height

      def initialize(config:)
        @config = config
        @queue = Queue.new(config.queue_path)
        @client = config.dry? ? DryClient.new(config: config) : Client.new(config: config)
        @git = Git.new
        @prime = Prime.run!

        # Core state
        @mode = :reviewing
        @items = []
        @index = 0

        # Sub-components
        @spinner = Bubbles::Spinner.new
        @spinner.spinner = Bubbles::Spinners::DOT
        @text_input = Bubbles::TextInput.new
        @text_input.placeholder = "Enter prompt..."

        # Prompt context
        @prompt_target = nil
        @prompt_item = nil

        # Notifications
        @flash = nil
        @flash_style = :info

        # Layout
        @width = 80
        @height = 24

        # Agent runner (initialized in init via Thread)
        @agent_runner = nil
        @async_thread = nil
        @async_task = nil
      end

      def init
        start_async_reactor
        refresh_items
        warn_stale_items

        # Nothing to do — exit immediately
        if @items.empty? && running_count == 0
          stop_async_reactor
          return [self, Bubbletea.quit]
        end

        spinner_cmd = @spinner.init[1]
        cmds = [schedule_poll]
        cmds.unshift(spinner_cmd) if spinner_cmd
        [self, Bubbletea.batch(*cmds)]
      end

      def update(message)
        case message
        when Bubbletea::WindowSizeMessage
          @width = message.width
          @height = message.height
          @text_input.width = [@width - PROMPT_PREFIX_WIDTH, 10].max if @mode == :prompting
          [self, nil]

        when AgentPollMessage
          cmd = handle_agent_poll
          [self, cmd]

        when AgentCompletedMessage
          handle_agent_completed(message)

        when FlashClearMessage
          @flash = nil
          [self, nil]

        when WorktreeRefreshedMessage
          handle_worktree_refreshed(message)
          [self, nil]

        when ViewDoneMessage
          @mode = :reviewing
          refresh_items
          [self, nil]

        when Bubbletea::KeyMessage
          handle_key(message)

        else
          # Delegate to sub-components
          cmd = update_subcomponents(message)
          [self, cmd]
        end
      end

      def view
        case @mode
        when :reviewing
          view_reviewing
        when :prompting
          view_prompting
        when :waiting
          view_waiting
        end
      end

      # --- View helpers (public for testing) ---

      def current_item
        return nil if @items.empty?
        @items[@index]
      end

      private

      # --- Async reactor management ---

      def start_async_reactor
        @spawn_queue = Thread::Queue.new
        @async_thread = Thread.new do
          Sync do |task|
            @async_task = task
            @agent_runner = AgentRunner.new(
              client: @client, task: task, queue: @queue,
              limit: @config.concurrency
            )
            # Keep the reactor alive until the thread is killed
            loop do
              drain_spawn_queue
              task.yield
              sleep 0.1
            end
          end
        end

        # Wait for agent_runner to be initialized
        sleep 0.05 until @agent_runner
      end

      def drain_spawn_queue
        while (req = @spawn_queue.pop(true) rescue nil)
          case req[:type]
          when :spawn
            @agent_runner.spawn(req[:item_id], req[:prompt_text], req[:user_prompt], **req[:opts])
          when :spawn_general
            @agent_runner.spawn_general(req[:prompt_text], req[:user_prompt], **req[:opts])
          end
        end
      end

      def stop_async_reactor
        @agent_runner&.stop_all
        @async_thread&.kill
        @async_thread&.join(1)
      end

      # --- Polling ---

      def schedule_poll
        Bubbletea.tick(0.5) { AgentPollMessage.new }
      end

      def handle_agent_poll
        return schedule_poll unless @agent_runner

        completed = @agent_runner.poll
        cmds = [schedule_poll]

        completed.each do |item_id, data|
          cmds << Bubbletea.send_message(
            AgentCompletedMessage.new(item_id: item_id, data: data)
          )
        end

        Bubbletea.batch(*cmds)
      end

      # --- Agent completion ---

      def handle_agent_completed(message)
        item_id = message.item_id
        data = message.data

        if data[:general]
          handle_completed_general_agent(item_id, data)
        else
          handle_completed_item_agent(item_id, data)
        end

        done = refresh_items
        if done
          stop_async_reactor
          [self, Bubbletea.quit]
        else
          [self, schedule_flash_clear]
        end
      end

      def handle_completed_item_agent(item_id, data)
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

          updates = { session_id: result.session_id }

          if item.worktree && Sift::Worktree.exists?(item.id) && @git.worktree_valid?(item.worktree.path)
            updates[:sources] = add_worktree_sources(item)
          end

          @queue.update(item_id, **updates)
          set_flash("Agent finished for item #{item_id}", :success)
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
          set_flash("Agent failed for item #{item_id}: #{error}", :error)
        end
      end

      def handle_completed_general_agent(key, data)
        result = data[:result]
        error = data[:error]
        user_prompt = data[:prompt]

        if result
          text_source = { type: "text", content: user_prompt }
          metadata = { "source" => "general_agent", "prompt" => user_prompt }

          @queue.push(sources: [text_source], metadata: metadata, session_id: result.session_id)
          set_flash("General agent finished — new item added", :success)
        else
          Log.warn "general agent failed key=#{key}: #{error}"
          set_flash("General agent failed: #{error}", :error)
        end
      end

      # --- Worktree sources ---

      def add_worktree_sources(item)
        base = @config.worktree_base_branch
        sources = item.sources.map(&:to_h)

        has_commits = @git.has_commits_beyond?(item.worktree.branch, base)
        has_local = @git.worktree_dirty?(item.worktree.path, base)

        if has_commits || has_local
          diff_content = @git.worktree_diff(item.worktree.path, base)
          entry = { type: "diff", path: "worktree", content: diff_content }
          idx = sources.index { |s| s[:type] == "diff" && s[:path] == "worktree" }
          idx ? sources[idx] = entry : sources << entry
        end

        unless sources.any? { |s| s[:type] == "directory" && s[:path] == item.worktree.path }
          sources << { type: "directory", path: item.worktree.path }
        end

        sources.map { |s| Queue::Source.from_h(s) }
      end

      def refresh_worktree_sources(item)
        return item unless item.worktree
        return item unless Sift::Worktree.exists?(item.id)
        return item unless @git.worktree_valid?(item.worktree.path)

        updated_sources = add_worktree_sources(item)
        @queue.update(item.id, sources: updated_sources)
        @queue.find(item.id)
      end

      def handle_worktree_refreshed(message)
        item = @queue.find(message.item_id)
        return unless item
        @queue.update(message.item_id, sources: message.sources)
        refresh_items
      end

      # --- Key handling ---

      def handle_key(message)
        case @mode
        when :reviewing
          handle_key_reviewing(message)
        when :prompting
          handle_key_prompting(message)
        when :waiting
          handle_key_waiting(message)
        end
      end

      def handle_key_reviewing(message)
        key = message.to_s

        case key
        when "q", "ctrl+c"
          stop_async_reactor
          [self, Bubbletea.quit]
        when "v"
          handle_view
        when "a"
          return [self, nil] unless current_item
          enter_prompt_mode(:item_agent, current_item)
          [self, nil]
        when "c"
          return [self, nil] unless current_item
          done = handle_close(current_item)
          if done
            stop_async_reactor
            [self, Bubbletea.quit]
          else
            [self, nil]
          end
        when "g"
          enter_prompt_mode(:general_agent, nil)
          [self, nil]
        when "n"
          return [self, nil] if @items.size <= 1
          @index = (@index + 1) % @items.size
          [self, nil]
        when "p"
          return [self, nil] if @items.size <= 1
          @index = (@index - 1) % @items.size
          [self, nil]
        else
          [self, nil]
        end
      end

      def handle_key_prompting(message)
        key = message.to_s

        case key
        when "enter"
          submit_prompt
        when "ctrl+g"
          submit_prompt_via_editor
        when "esc", "ctrl+c"
          cancel_prompt
          [self, nil]
        else
          @text_input, cmd = @text_input.update(message)
          [self, cmd]
        end
      end

      def handle_key_waiting(message)
        key = message.to_s

        case key
        when "q", "ctrl+c"
          stop_async_reactor
          [self, Bubbletea.quit]
        when "g"
          enter_prompt_mode(:general_agent, nil)
          [self, nil]
        else
          [self, nil]
        end
      end

      # --- Prompt mode ---

      def enter_prompt_mode(target, item)
        @mode = :prompting
        @prompt_target = target
        @prompt_item = item
        @text_input = Bubbles::TextInput.new
        @text_input.placeholder = target == :general_agent ? "Ask anything..." : "Agent instruction..."
        @text_input.width = [@width - PROMPT_PREFIX_WIDTH, 10].max
        @text_input.focus
      end

      def cancel_prompt
        @mode = @items.empty? ? :waiting : :reviewing
        @prompt_target = nil
        @prompt_item = nil
      end

      def submit_prompt
        text = @text_input.value.strip
        if text.empty?
          cancel_prompt
          return [self, nil]
        end

        dispatch_agent(text)
        cancel_prompt
        [self, nil]
      end

      def submit_prompt_via_editor
        existing = @text_input.value
        text = read_from_editor(existing)
        if text.nil? || text.strip.empty?
          cancel_prompt
          return [self, nil]
        end

        dispatch_agent(text)
        cancel_prompt
        [self, nil]
      end

      def dispatch_agent(user_prompt)
        case @prompt_target
        when :item_agent
          dispatch_item_agent(@prompt_item, user_prompt)
        when :general_agent
          dispatch_general_agent(user_prompt)
        end
      end

      def dispatch_item_agent(item, user_prompt)
        return unless item

        # Auto-create worktree on first agent invocation
        if item.worktree.nil?
          wt = Sift::Worktree.create(item.id,
            base_branch: @config.worktree_base_branch,
            setup_command: @config.worktree_setup_command)
          @queue.update(item.id, worktree: wt)
          item = @queue.find(item.id)
        end

        prompt_text = build_agent_prompt(item, user_prompt)
        @spawn_queue.push(
          type: :spawn, item_id: item.id, prompt_text: prompt_text,
          user_prompt: user_prompt, opts: {
            session_id: item.session_id,
            append_system_prompt: agent_context, cwd: item.worktree&.path,
          }
        )
        set_flash("Agent started for item #{item.id}", :info)
      end

      def dispatch_general_agent(user_prompt)
        @spawn_queue.push(
          type: :spawn_general, prompt_text: user_prompt,
          user_prompt: user_prompt, opts: { append_system_prompt: agent_context }
        )
        set_flash("General agent started", :info)
      end

      def agent_context
        @agent_context ||= begin
          parts = []
          path = File.join(AGENT_DOCS_DIR, "general.md")
          if File.exist?(path)
            template = File.read(path)
            parts << template.gsub("{{queue_path}}", @queue.path)
          end
          parts << @prime.to_s
          parts.join("\n")
        end
      end

      def build_agent_prompt(item, user_prompt)
        return user_prompt if item.session_id

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

      # --- View / Editor ---

      def handle_view
        item = current_item
        return [self, nil] unless item

        callable = -> {
          editor = Editor.new(sources: item.sources, item_id: item.id, session_id: item.session_id, restore_tty: false)
          editor.open
        }
        [self, Bubbletea.exec(callable, message: ViewDoneMessage.new)]
      end

      def handle_close(item)
        @queue.update(item.id, status: "closed")
        refresh_items
      end

      # --- Flash notifications ---

      def set_flash(message, style = :info)
        @flash = message
        @flash_style = style
      end

      def schedule_flash_clear
        Bubbletea.tick(3.0) { FlashClearMessage.new }
      end

      # --- State management ---

      # Returns true if the app should quit (nothing left to do).
      def refresh_items
        all_pending = @queue.filter(status: "pending")
        @items = if @agent_runner
          all_pending.reject { |item| @agent_runner.running?(item.id) }
        else
          all_pending
        end
        @index = @index.clamp(0, [@items.size - 1, 0].max)

        @mode = :waiting if @items.empty? && @mode == :reviewing && running_count > 0
        @mode = :reviewing if !@items.empty? && @mode == :waiting

        @items.empty? && running_count == 0
      end

      def running_count
        @agent_runner&.running_count || 0
      end

      def active_count
        @agent_runner&.active_count || 0
      end

      def finished_count
        @agent_runner&.finished_count || 0
      end

      def pending_count
        @queue.count(status: "pending")
      end

      def warn_stale_items
        stale = @queue.filter(status: "in_progress")
        return if stale.empty?

        Log.warn "#{stale.size} item(s) still in_progress from a previous session"
        stale.each { |item| Log.warn "  #{item.id} (updated: #{item.updated_at})" }
        Log.warn "Release with: sq edit <id> --set-status pending"
      end

      # --- Sub-component delegation ---

      def update_subcomponents(message)
        @spinner, cmd = @spinner.update(message)
        cmd
      end

      # --- Editor helper ---

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

      # --- View rendering ---

      def view_reviewing
        return view_empty if @items.empty?

        item = current_item
        parts = []

        # Refresh worktree sources synchronously for display
        # (This is fast for items without worktrees)
        if item&.worktree
          item = refresh_worktree_sources(item)
        end

        # Card
        parts << Card.render(item, position: @index + 1, total: @items.size, width: @width)
        parts << ""

        # Action bar
        parts << "  #{Keymap.reviewing_bar(show_nav: @items.size > 1)}"
        parts << ""

        # Status bar
        parts << "  #{render_status_bar}"

        # Flash
        parts << "" << "  #{render_flash}" if @flash

        parts.join("\n")
      end

      def view_prompting
        parts = []

        if @prompt_item
          parts << Card.render(@prompt_item, position: @index + 1, total: @items.size, width: @width)
          parts << ""
        end

        # Prompt input
        label = Styles::PROMPT_LABEL.render("Prompt")
        hint = Styles::PROMPT_HINT.render("(Ctrl-G for editor, Esc to cancel)")
        parts << "  #{label} #{hint}: #{@text_input.view}"
        parts << ""

        # Status bar
        parts << "  #{render_status_bar}"

        # Flash
        parts << "" << "  #{render_flash}" if @flash

        parts.join("\n")
      end

      def view_waiting
        parts = []
        running = running_count
        msg = Styles::WAITING_TEXT.render(
          "Waiting for #{running} agent#{"s" if running != 1}..."
        )
        parts << "  #{msg}"
        parts << ""

        # Action bar
        parts << "  #{Keymap.waiting_bar}"
        parts << ""

        # Status bar
        parts << "  #{render_status_bar}"

        # Flash
        parts << "" << "  #{render_flash}" if @flash

        parts.join("\n")
      end

      def view_empty
        parts = []
        parts << "  #{Styles::WAITING_TEXT.render("No pending items.")}"
        parts << ""
        parts << "  #{render_status_bar}"
        parts.join("\n")
      end

      def render_status_bar
        pending = pending_count
        active = active_count
        finished = finished_count

        parts = ["#{pending} pending"]
        parts << "#{@spinner.view} #{active} running" if active > 0
        parts << "#{finished} finished" if finished > 0

        Styles::STATUS_TEXT.render(parts.join(" | "))
      end

      def render_flash
        return "" unless @flash

        style = case @flash_style
        when :success then Styles::FLASH_SUCCESS
        when :error then Styles::FLASH_ERROR
        else Styles::FLASH_INFO
        end

        icon = case @flash_style
        when :success then "✓ "
        when :error then "✗ "
        else "● "
        end

        style.render("#{icon}#{@flash}")
      end
    end
  end
end
