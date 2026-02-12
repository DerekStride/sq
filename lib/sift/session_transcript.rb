# frozen_string_literal: true

require "json"

module Sift
  # Parses a Claude Code session JSONL file into readable markdown.
  # Extracts user prompts, assistant reasoning, tool calls, and final responses.
  class SessionTranscript
    PROJECTS_DIR = File.join(Dir.home, ".claude", "projects")

    # Find and parse a session transcript for the given session_id.
    # Returns nil if the session file doesn't exist.
    def self.render(session_id, cwd: Dir.pwd)
      path = session_path(session_id, cwd: cwd)
      return nil unless path && File.exist?(path)

      new(path).render
    end

    def self.session_path(session_id, cwd: Dir.pwd)
      slug = cwd.gsub("/", "-")
      File.join(PROJECTS_DIR, slug, "#{session_id}.jsonl")
    end

    def initialize(path)
      @path = path
    end

    def render
      entries = parse_entries
      messages = group_messages(entries)
      render_messages(messages)
    end

    private

    def parse_entries
      entries = []
      File.foreach(@path) do |line|
        next if line.strip.empty?

        data = JSON.parse(line)
        next unless %w[user assistant].include?(data["type"])

        entries << data
      end
      entries
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

    def render_messages(messages)
      parts = []

      messages.each do |msg|
        case msg[:role]
        when "user"
          parts << "**User:** #{msg[:content]}"
        when "assistant"
          parts << render_assistant(msg[:blocks])
        end
        parts << ""
      end

      parts.join("\n").strip
    end

    def render_assistant(blocks)
      lines = ["**Assistant:**", ""]

      blocks.each do |block|
        case block["type"]
        when "text"
          lines << block["text"]
        when "tool_use"
          lines << render_tool_call(block)
        end
      end

      lines.join("\n")
    end

    def render_tool_call(block)
      name = block["name"]
      input = block["input"] || {}

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
        "> Write: `#{input["file_path"]}`"
      when "Task"
        desc = input["description"] || input["prompt"]&.lines&.first&.chomp
        "> Task: #{desc}"
      else
        "> #{name}"
      end

      summary
    end
  end
end
