# frozen_string_literal: true

require "json"
require "open3"
require "shellwords"

module Sift
  # Client for calling Claude CLI and managing sessions
  class Client
    class Error < Sift::Error; end

    Result = Struct.new(:response, :session_id, :raw, keyword_init: true)

    def initialize(config:)
      @config = config
    end

    # Send a prompt to Claude, optionally resuming a session.
    # Returns Result with response text and session_id.
    # Yields the subprocess PID if a block is given, enabling
    # callers to send signals (e.g. SIGINT for graceful stop).
    def prompt(text, session_id: nil, append_system_prompt: nil, cwd: nil, model: nil)
      args = build_args(session_id:, append_system_prompt:, model: model)
      Log.debug "client start cmd=#{args.join(" ")} cwd=#{cwd || "(inherit)"}"
      start = Time.now

      spawn_opts = {}
      spawn_opts[:chdir] = cwd if cwd

      stdout_data = stderr_data = nil
      status = nil

      Open3.popen3(*args, **spawn_opts) do |stdin, stdout, stderr, wait_thread|
        yield wait_thread.pid if block_given?
        # Read stdout/stderr concurrently with threads (same pattern
        # as capture3) to prevent deadlock when the subprocess fills
        # a pipe buffer while we're blocked reading the other pipe.
        out_reader = Thread.new { stdout.read }
        err_reader = Thread.new { stderr.read }
        stdin.write(text)
        stdin.close
        stdout_data = out_reader.value
        stderr_data = err_reader.value
        status = wait_thread.value
      end

      elapsed = (Time.now - start).round(1)

      unless status.success?
        Log.error "client failed elapsed=#{elapsed}s stderr=#{stderr_data.lines.first&.chomp}"
        raise Error, "Claude CLI failed: #{stderr_data}"
      end

      Log.debug "client done elapsed=#{elapsed}s bytes=#{stdout_data.bytesize}"
      parse_response(stdout_data)
    rescue Errno::ENOENT => e
      raise Error, "Command not found: #{e.message}"
    rescue SystemCallError => e
      raise Error, "Failed to execute agent: #{e.message}"
    end

    # Analyze a diff hunk with Claude
    def analyze_diff(hunk, file:, context: nil, session_id: nil)
      prompt_text = build_diff_prompt(hunk, file:, context:)
      prompt(prompt_text, session_id:)
    end

    private

    def build_args(session_id: nil, append_system_prompt: nil, model: nil)
      args = Array(@config.agent_command).flat_map { |s| s.to_s.shellsplit }
      args += ["-p", "--output-format", "json"]
      args += @config.agent_flags if @config.agent_flags&.any?
      @config.agent_allowed_tools&.each { |tool| args += ["--allowedTools", tool] }
      selected_model = model || @config.agent_model
      args += ["--model", selected_model] if selected_model
      args += ["--permission-mode", @config.agent_permission_mode] if @config.agent_permission_mode
      args += ["--append-system-prompt", append_system_prompt] if append_system_prompt
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
    def initialize(config: nil)
      @config = config
    end

    def prompt(text, session_id: nil, append_system_prompt: nil, cwd: nil, model: nil, &)
      selected_model = model || @config&.agent_model
      Sift::Log.debug "[dry] model=#{selected_model || "default"} session=#{session_id || "new"} cwd=#{cwd || "(inherit)"}"
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
