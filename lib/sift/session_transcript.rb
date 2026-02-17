# frozen_string_literal: true

require "json"
require "set"

module Sift
  # Parses a Claude Code session JSONL file into readable markdown.
  # Extracts user prompts, assistant reasoning, tool calls, and final responses.
  class SessionTranscript
    PROJECTS_DIR = File.join(Dir.home, ".claude", "projects")
    PLANS_DIR_PATTERN = File.join(Dir.home, ".claude", "plans", "")

    # Find and parse a session transcript for the given session_id.
    # Returns nil if the session file doesn't exist.
    def self.render(session_id, cwd: Dir.pwd)
      path = find_session(session_id, cwd: cwd)
      return nil unless path

      new(path).render
    end

    # Returns { transcript: String, plan_paths: Array<String> } or nil.
    def self.parse(session_id, cwd: Dir.pwd)
      path = find_session(session_id, cwd: cwd)
      return nil unless path

      instance = new(path)
      { transcript: instance.render, plan_paths: instance.plan_paths }
    end

    # Locate a session JSONL file. Tries the cwd-derived path first,
    # then falls back to scanning all project directories. This handles
    # work trees where the session was created under a different slug.
    def self.find_session(session_id, cwd: Dir.pwd)
      primary = session_path(session_id, cwd: cwd)
      return primary if File.exist?(primary)

      return nil unless Dir.exist?(PROJECTS_DIR)

      filename = "#{session_id}.jsonl"
      Dir.children(PROJECTS_DIR).each do |dir|
        path = File.join(PROJECTS_DIR, dir, filename)
        if File.exist?(path)
          Log.debug "session #{session_id} found via fallback in #{dir}"
          return path
        end
      end
      nil
    end

    def self.session_path(session_id, cwd: Dir.pwd)
      slug = cwd.gsub("/", "-")
      File.join(PROJECTS_DIR, slug, "#{session_id}.jsonl")
    end

    def initialize(path)
      @path = path
    end

    def render
      entries = parse_all_entries
      tool_results = extract_tool_results(entries)
      messages = group_messages(entries)
      render_messages(messages, tool_results)
    end

    def plan_paths
      entries = parse_all_entries
      extract_plan_paths(entries)
    end

    private

    def parse_all_entries
      @all_entries ||= begin
        entries = []
        File.foreach(@path) do |line|
          next if line.strip.empty?
          data = JSON.parse(line)
          entries << data
        rescue JSON::ParserError
          next
        end
        entries
      end
    end

    def parse_entries
      parse_all_entries.select { |data| %w[user assistant].include?(data["type"]) }
    end

    def extract_plan_paths(entries)
      paths = Set.new

      entries.each do |entry|
        # Strategy 1: Write tool calls targeting ~/.claude/plans/
        if entry["type"] == "assistant"
          msg = entry["message"]
          next unless msg
          content = msg["content"]
          next unless content.is_a?(Array)

          content.each do |block|
            next unless block.is_a?(Hash) && block["type"] == "tool_use" && block["name"] == "Write"
            file_path = block.dig("input", "file_path")
            paths << file_path if file_path&.include?("/.claude/plans/")
          end
        end

        # Strategy 2: file-history-snapshot entries with trackedFileBackups
        if entry["type"] == "file-history-snapshot"
          backups = entry["trackedFileBackups"]
          next unless backups.is_a?(Hash)

          backups.each_key do |key|
            paths << key if key.include?("/.claude/plans/")
          end
        end
      end

      paths.to_a
    end

    def extract_tool_results(entries)
      results = {}
      entries.each do |entry|
        msg = entry["message"]
        next unless msg

        content = msg["content"]
        next unless content.is_a?(Array)

        content.each do |block|
          next unless block.is_a?(Hash) && block["type"] == "tool_result"

          results[block["tool_use_id"]] = { content: block["content"], is_error: block["is_error"] }
        end
      end
      results
    end

    def group_messages(entries)
      messages = []

      entries.each do |entry|
        msg = entry["message"]
        next unless msg

        role = msg["role"] || entry["type"]
        msg_id = msg["id"]
        content = msg["content"]

        if role == "user"
          # String content = real user prompt; array = tool results (skip)
          if content.is_a?(String)
            messages << { role: "user", content: content }
          end
        elsif role == "assistant" && msg_id
          # Group assistant content blocks by message ID
          existing = messages.reverse.find { |m| m[:msg_id] == msg_id }
          if existing
            existing[:blocks].concat(Array(content))
          else
            messages << { role: "assistant", msg_id: msg_id, blocks: Array(content) }
          end
        end
      end

      messages
    end

    def render_messages(messages, tool_results)
      parts = []

      messages.each do |msg|
        case msg[:role]
        when "user"
          parts << "**User:** #{msg[:content]}"
        when "assistant"
          parts << render_assistant(msg[:blocks], tool_results)
        end
        parts << ""
      end

      parts.join("\n").strip
    end

    def render_assistant(blocks, tool_results)
      lines = ["**Assistant:**", ""]

      blocks.each do |block|
        case block["type"]
        when "text"
          lines << block["text"]
        when "tool_use"
          lines << render_tool_call(block, tool_results)
        end
      end

      lines.join("\n")
    end

    def render_tool_call(block, tool_results)
      name = block["name"]
      input = block["input"] || {}
      result_entry = tool_results[block["id"]]
      result_content = result_entry&.fetch(:content, nil)
      is_error = result_entry&.fetch(:is_error, false)

      summary = case name
      when "Read"
        "> Read: `#{input["file_path"]}`"
      when "Glob"
        "> Glob: `#{input["pattern"]}`"
      when "Grep"
        "> Grep: `#{input["pattern"]}`"
      when "Bash"
        "> Bash: `#{input["command"]&.lines&.first&.chomp}`"
      when "Edit"
        "> Edit: `#{input["file_path"]}`"
      when "Write"
        file_path = input["file_path"]
        if file_path&.include?("/.claude/plans/")
          "> Plan: `#{File.basename(file_path)}`"
        else
          "> Write: `#{file_path}`"
        end
      when "EnterPlanMode"
        "> Enter plan mode"
      when "ExitPlanMode"
        "> Exit plan mode"
      when "Task"
        desc = input["description"] || input["prompt"]&.lines&.first&.chomp
        "> Task: #{desc}"
      else
        "> #{name}"
      end

      result_suffix = summarize_result(name, result_content, is_error: is_error)
      summary += " #{result_suffix}" if result_suffix

      summary
    end

    def summarize_result(tool_name, result, is_error: false)
      return nil unless result

      text = result_to_text(result)
      return nil if text.nil? || text.empty?

      if is_error
        first = text.lines.first&.chomp
        return "→ ERROR: #{first[0, 80]}"
      end

      case tool_name
      when "Glob"
        count = text.lines.count { |l| !l.strip.empty? }
        "→ #{count} file#{"s" unless count == 1}"
      when "Grep"
        count = text.lines.count { |l| !l.strip.empty? }
        "→ #{count} match#{"es" unless count == 1}"
      when "Read"
        count = text.lines.count
        "→ #{count} line#{"s" unless count == 1}"
      when "Bash"
        first = text.lines.first&.chomp
        if first && first.length > 60
          "→ `#{first[0, 57]}...`"
        elsif first
          "→ `#{first}`"
        end
      when "Edit", "Write"
        "→ ok"
      when "Task"
        first = text.lines.first&.chomp
        if first && first.length > 60
          "→ #{first[0, 57]}..."
        elsif first
          "→ #{first}"
        end
      end
    end

    def result_to_text(result)
      case result
      when String
        result
      when Array
        result.filter_map { |b| b["text"] if b.is_a?(Hash) && b["type"] == "text" }.join("\n")
      end
    end
  end
end
