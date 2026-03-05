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
      @agents = {} # item_id -> { task:, pid:, prompt:, started_at:, general: }
      @general_counter = 0
    end

    # Spawn a background agent for the given item.
    # Returns immediately — the agent runs as a child fiber.
    def spawn(item_id, prompt_text, user_prompt, session_id: nil, append_system_prompt: nil, cwd: nil, model: nil)
      Log.debug "agent spawn item=#{item_id} model=#{model || "default"} session=#{session_id || "new"} cwd=#{cwd || "(inherit)"} prompt=#{user_prompt.lines.first&.chomp}"

      pid_callback = proc { |pid| @agents[item_id][:pid] = pid if @agents[item_id] }

      agent_task = @semaphore.async do
        Log.debug "agent running item=#{item_id}"
        if @queue
          @queue.claim(item_id) do |claimed_item|
            next nil unless claimed_item
            @client.prompt(prompt_text, session_id: session_id,
              append_system_prompt: append_system_prompt, cwd: cwd, model: model, &pid_callback)
          end
        else
          @client.prompt(prompt_text, session_id: session_id,
            append_system_prompt: append_system_prompt, cwd: cwd, model: model, &pid_callback)
        end
      rescue Client::Error => e
        Log.warn "agent error item=#{item_id}: #{e.message}"
        e
      end

      @agents[item_id] = { task: agent_task, pid: nil, prompt: user_prompt, started_at: Time.now, general: false }
    end

    # Spawn a general-purpose agent not tied to any queue item.
    # Returns immediately — the agent runs as a child fiber.
    def spawn_general(prompt_text, user_prompt, append_system_prompt: nil, model: nil)
      @general_counter += 1
      key = format("_gen_%03d", @general_counter)

      Log.debug "agent spawn_general key=#{key} model=#{model || "default"} prompt=#{user_prompt.lines.first&.chomp}"

      pid_callback = proc { |pid| @agents[key][:pid] = pid if @agents[key] }

      agent_task = @semaphore.async do
        Log.debug "agent running general key=#{key}"
        @client.prompt(prompt_text, append_system_prompt: append_system_prompt, model: model, &pid_callback)
      rescue Client::Error => e
        Log.warn "agent error general key=#{key}: #{e.message}"
        e
      end

      @agents[key] = { task: agent_task, pid: nil, prompt: user_prompt, started_at: Time.now, general: true }
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

    # Send SIGINT to running agent subprocesses. Claude CLI handles
    # SIGINT gracefully — it wraps up, saves session state, and exits
    # with a valid response. Agents remain tracked so poll can pick
    # up their results and save session_ids for later resumption.
    def interrupt_agents
      count = 0
      @agents.each_value do |a|
        next if a[:task].completed? || a[:task].failed?
        next unless a[:pid]
        Process.kill("INT", a[:pid])
        count += 1
      rescue Errno::ESRCH, Errno::EPERM
        # Process already exited or not permitted
      end
      Log.debug "agent interrupt count=#{count}/#{@agents.size}"
    end

    # Force-stop all running agents and clear tracking immediately.
    def stop_all
      Log.debug "agent stop_all count=#{@agents.size}"
      @agents.each_value do |a|
        begin
          Process.kill("KILL", a[:pid]) if a[:pid]
        rescue Errno::ESRCH, Errno::EPERM
          # already gone
        end
        a[:task].stop
      end
      @agents.clear
    end
  end
end
