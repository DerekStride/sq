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

      attr_reader :config

      def define_flags(parser, options)
        @config = Sift::Config.load

        parser.on("-q", "--queue PATH", "Queue file path (default: #{Sift::Queue::DEFAULT_PATH})") do |v|
          @config.queue_path = v
        end
        parser.on("-m", "--model MODEL", "Claude model (default: sonnet)") do |v|
          @config.agent_model = v
        end
        parser.on("-c", "--concurrency N", Integer, "Max concurrent agents (default: 5)") do |v|
          @config.concurrency = v
        end
        parser.on("-s", "--system-prompt PATH", "System prompt file for agent invocations") do |v|
          @config.agent_system_prompt = v
        end
        parser.on("--dry", "Dry mode: skip Claude API calls, print prompts instead") do
          @config.dry = true
        end
        parser.on("--version", "Show version") do
          puts "sift #{Sift::VERSION}"
          exit
        end
        super
      end

      def execute
        Sift::ReviewLoop.new(config: @config).run
        0
      end
    end
  end
end
