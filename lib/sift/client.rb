# frozen_string_literal: true

require "json"
require "open3"

module Sift
  # Client for calling Claude CLI and managing sessions
  class Client
    class Error < StandardError; end

    Result = Struct.new(:response, :session_id, :raw, keyword_init: true)

    def initialize(model: nil, system_prompt: nil)
      @model = model
      @system_prompt = system_prompt
    end

    # Send a prompt to Claude, optionally resuming a session.
    # system_prompt overrides the instance default when provided.
    # Returns Result with response text and session_id
    def prompt(text, session_id: nil, system_prompt: nil)
      args = build_args(session_id:, system_prompt:)
      Log.debug "client start cmd=#{args.join(" ")}"
      start = Time.now

      stdout, stderr, status = Open3.capture3(*args, stdin_data: text)
      elapsed = (Time.now - start).round(1)

      unless status.success?
        Log.error "client failed elapsed=#{elapsed}s stderr=#{stderr.lines.first&.chomp}"
        raise Error, "Claude CLI failed: #{stderr}"
      end

      Log.debug "client done elapsed=#{elapsed}s bytes=#{stdout.bytesize}"
      parse_response(stdout)
    end

    # Analyze a diff hunk with Claude
    def analyze_diff(hunk, file:, context: nil, session_id: nil)
      prompt_text = build_diff_prompt(hunk, file:, context:)
      prompt(prompt_text, session_id:)
    end

    private

    def build_args(session_id: nil, system_prompt: nil)
      effective_prompt = system_prompt || @system_prompt
      args = ["claude", "-p", "--output-format", "json"]
      args += ["--model", @model] if @model
      args += ["--system-prompt", effective_prompt] if effective_prompt
      args += ["--resume", session_id] if session_id
      args
    end

    def build_diff_prompt(hunk, file:, context: nil)
      parts = []
      parts << "File: #{file}"
      parts << "Context: #{context}" if context
      parts << ""
      parts << "Diff:"
      parts << "```diff"
      parts << hunk
      parts << "```"
      parts << ""
      parts << "Review this change. Be concise (1-2 sentences). Focus on potential issues, improvements, or confirm it looks good."
      parts.join("\n")
    end

    def parse_response(stdout)
      data = JSON.parse(stdout)
      Result.new(
        response: data["result"],
        session_id: data["session_id"],
        raw: data
      )
    rescue JSON::ParserError => e
      raise Error, "Failed to parse Claude response: #{e.message}"
    end
  end

  # No-op client for testing the review flow without API calls.
  # Returns a canned response and logs prompt details via Sift::Log.
  class DryClient
    def initialize(model: nil)
      @model = model
    end

    def prompt(text, session_id: nil, system_prompt: nil)
      Sift::Log.debug "[dry] model=#{@model || "default"} session=#{session_id || "new"}"
      Sift::Log.debug "[dry] prompt: #{text.lines.first&.chomp}"
      Client::Result.new(
        response: "[dry mode] No API call made.",
        session_id: session_id || "dry-#{SecureRandom.hex(4)}",
        raw: {},
      )
    end

    def analyze_diff(hunk, file:, context: nil, session_id: nil)
      prompt("File: #{file}\nDiff:\n#{hunk}", session_id: session_id)
    end
  end
end
