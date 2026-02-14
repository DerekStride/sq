# frozen_string_literal: true

require "async"
require "async/semaphore"

module Sift
  # Manages background agent tasks using Async structured concurrency.
  # Each agent runs as a child fiber of the parent Async task, gated
  # by a semaphore for future concurrency limiting.
  class AgentRunner
    def initialize(client:, task:, queue: nil, limit: 1000)
      @client = client
      @task = task
      @queue = queue
      @semaphore = Async::Semaphore.new(limit, parent: task)
      @agents = {} # item_id -> { task:, prompt:, started_at:, general: }
      @general_counter = 0
    end

    # Spawn a background agent for the given item.
    # Returns immediately — the agent runs as a child fiber.
    def spawn(item_id, prompt_text, user_prompt, session_id: nil, append_system_prompt: nil, cwd: nil)
      Log.debug "agent spawn item=#{item_id} session=#{session_id || "new"} cwd=#{cwd || "(inherit)"} prompt=#{user_prompt.lines.first&.chomp}"

      agent_task = @semaphore.async do
        Log.debug "agent running item=#{item_id}"
        if @queue
          @queue.claim(item_id) do |claimed_item|
            next nil unless claimed_item
            @client.prompt(prompt_text, session_id: session_id,
              append_system_prompt: append_system_prompt, cwd: cwd)
          end
        else
          @client.prompt(prompt_text, session_id: session_id,
            append_system_prompt: append_system_prompt, cwd: cwd)
        end
      rescue Client::Error => e
        Log.warn "agent error item=#{item_id}: #{e.message}"
        e
      end

      @agents[item_id] = { task: agent_task, prompt: user_prompt, started_at: Time.now, general: false }
    end

    # Spawn a general-purpose agent not tied to any queue item.
    # Returns immediately — the agent runs as a child fiber.
    def spawn_general(prompt_text, user_prompt, append_system_prompt: nil)
      @general_counter += 1
      key = format("_gen_%03d", @general_counter)

      Log.debug "agent spawn_general key=#{key} prompt=#{user_prompt.lines.first&.chomp}"

      agent_task = @semaphore.async do
        Log.debug "agent running general key=#{key}"
        @client.prompt(prompt_text, append_system_prompt: append_system_prompt)
      rescue Client::Error => e
        Log.warn "agent error general key=#{key}: #{e.message}"
        e
      end

      @agents[key] = { task: agent_task, prompt: user_prompt, started_at: Time.now, general: true }
    end

    # Check for completed agents. Returns a hash of completed results:
    #   { item_id => { result: Client::Result | nil, error: String | nil, prompt: String } }
    # When the agent catches a Client::Error, result is nil and error contains the message.
    # Removes completed agents from tracking.
    def poll
      completed = {}

      @agents.each do |item_id, agent|
        task = agent[:task]
        elapsed = (Time.now - agent[:started_at]).round(1)
        if task.completed?
          result = task.result
          if result.is_a?(Client::Error)
            Log.debug "agent error item=#{item_id} elapsed=#{elapsed}s"
            completed[item_id] = { result: nil, error: result.message, prompt: agent[:prompt], general: agent[:general] }
          elsif result.nil?
            Log.debug "agent claim failed item=#{item_id} elapsed=#{elapsed}s"
            completed[item_id] = { result: nil, error: nil, prompt: agent[:prompt], general: agent[:general], claim_failed: true }
          else
            Log.debug "agent completed item=#{item_id} elapsed=#{elapsed}s"
            completed[item_id] = { result: result, prompt: agent[:prompt], general: agent[:general] }
          end
        elsif task.failed?
          Log.debug "agent failed item=#{item_id} elapsed=#{elapsed}s"
          completed[item_id] = { result: nil, error: "Task failed unexpectedly", prompt: agent[:prompt], general: agent[:general] }
        else
          Log.debug "agent still running item=#{item_id} elapsed=#{elapsed}s"
        end
      end

      completed.each_key { |id| @agents.delete(id) }
      completed
    end

    # Is an agent currently running for this item?
    def running?(item_id)
      @agents.key?(item_id)
    end

    # How many agents are currently running?
    def running_count
      @agents.size
    end

    # How many tracked agents are still actively running?
    # Unlike running_count, this checks actual task status without
    # polling or logging — safe to call from the input loop.
    def active_count
      @agents.count { |_, a| !a[:task].completed? && !a[:task].failed? }
    end

    # How many tracked agents have finished (completed or failed)
    # but haven't been poll'd yet?
    def finished_count
      @agents.count { |_, a| a[:task].completed? || a[:task].failed? }
    end

    # How many general agents are currently running?
    def general_running_count
      @agents.count { |_, a| a[:general] }
    end

    # Stop all running agents.
    def stop_all
      Log.debug "agent stop_all count=#{@agents.size}"
      @agents.each_value { |a| a[:task].stop }
      @agents.clear
    end
  end
end
