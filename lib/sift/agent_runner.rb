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
      @agents = {} # item_id -> { task:, prompt: }
    end

    # Spawn a background agent for the given item.
    # Returns immediately — the agent runs as a child fiber.
    def spawn(item_id, prompt_text, user_prompt, session_id: nil)
      agent_task = @semaphore.async do
        @client.prompt(prompt_text, session_id: session_id)
      end

      @agents[item_id] = { task: agent_task, prompt: user_prompt }
    end

    # Check for completed agents. Returns a hash of completed results:
    #   { item_id => { result: Client::Result, prompt: String } }
    # Removes completed agents from tracking.
    def poll
      completed = {}

      @agents.each do |item_id, agent|
        task = agent[:task]
        if task.completed?
          completed[item_id] = { result: task.result, prompt: agent[:prompt] }
        elsif task.failed?
          completed[item_id] = { result: nil, prompt: agent[:prompt] }
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
      @agents.each_value { |a| a[:task].stop }
      @agents.clear
    end
  end
end
