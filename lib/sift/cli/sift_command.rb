# frozen_string_literal: true

module Sift
  module CLI
    class SiftCommand < Base
      command_name "sift"
      summary "Interactive review loop for queue items"
      description "Launch the interactive review loop TUI. Reads pending queue items and presents them for human review."
      examples(
        "sift",
        "sift --queue .sift/queue.jsonl",
        "sift --model opus",
        "sift --system-prompt prompts/review.md",
        "sift --dry"
      )

      def define_flags(parser, options)
        options[:queue_path] ||= ENV.fetch("SIFT_QUEUE_PATH", DEFAULT_QUEUE_PATH)
        options[:model] ||= "sonnet"
        options[:concurrency] ||= 5

        parser.on("-q", "--queue PATH", "Queue file path (default: #{DEFAULT_QUEUE_PATH})") do |v|
          options[:queue_path] = v
        end
        parser.on("-m", "--model MODEL", "Claude model (default: sonnet)") do |v|
          options[:model] = v
        end
        parser.on("-c", "--concurrency N", Integer, "Max concurrent agents (default: 5)") do |v|
          options[:concurrency] = v
        end
        parser.on("-s", "--system-prompt PATH", "System prompt file for agent invocations") do |v|
          options[:system_prompt_path] = v
        end
        parser.on("--dry", "Dry mode: skip Claude API calls, print prompts instead") do
          options[:dry] = true
        end
        parser.on("--version", "Show version") do
          puts "sift #{Sift::VERSION}"
          exit
        end
        super
      end

      def execute
        system_prompt = read_system_prompt(options[:system_prompt_path])
        queue = Sift::Queue.new(options[:queue_path])
        Sift::ReviewLoop.new(
          queue: queue,
          model: options[:model],
          dry: options[:dry],
          concurrency: options[:concurrency],
          system_prompt: system_prompt,
        ).run
        0
      end

      private

      def read_system_prompt(path)
        return nil unless path

        unless File.exist?(path)
          logger.error("system prompt file not found: #{path}")
          exit 1
        end

        File.read(path)
      end
    end
  end
end
