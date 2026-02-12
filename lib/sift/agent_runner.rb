# frozen_string_literal: true

require "async"
require "async/semaphore"

module Sift
  # Manages background agent tasks using Async structured concurrency.
  # Each agent runs as a child fiber of the parent Async task, gated
  # by a semaphore for future concurrency limiting.
  class AgentRunner
    def initialize(client:, task:, limit: 1000)
      @client = client
      @task = task
      @semaphore = Async::Semaphore.new(limit, parent: task)
      @agents = {} # item_id -> { task:, prompt:, started_at: }
    end

    # Spawn a background agent for the given item.
    # Returns immediately — the agent runs as a child fiber.
    def spawn(item_id, prompt_text, user_prompt, session_id: nil)
      Log.debug "agent spawn item=#{item_id} session=#{session_id || "new"} prompt=#{user_prompt.lines.first&.chomp}"

      agent_task = @semaphore.async do
        Log.debug "agent running item=#{item_id}"
        @client.prompt(prompt_text, session_id: session_id)
      end

      @agents[item_id] = { task: agent_task, prompt: user_prompt, started_at: Time.now }
    end

    # Check for completed agents. Returns a hash of completed results:
    #   { item_id => { result: Client::Result, prompt: String } }
    # Removes completed agents from tracking.
    def poll
      completed = {}

      @agents.each do |item_id, agent|
        task = agent[:task]
        elapsed = (Time.now - agent[:started_at]).round(1)
        if task.completed?
          Log.debug "agent completed item=#{item_id} elapsed=#{elapsed}s"
          completed[item_id] = { result: task.result, prompt: agent[:prompt] }
        elsif task.failed?
          Log.debug "agent failed item=#{item_id} elapsed=#{elapsed}s"
          completed[item_id] = { result: nil, prompt: agent[:prompt] }
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

    # Stop all running agents.
    def stop_all
      Log.debug "agent stop_all count=#{@agents.size}"
      @agents.each_value { |a| a[:task].stop }
      @agents.clear
    end
  end
end
