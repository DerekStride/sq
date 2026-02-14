# frozen_string_literal: true

module Sift
  module CLI
    class SiftCommand < Base
      command_name "sift"
      summary "Interactive review loop for queue items"
      description "Launch the interactive review loop TUI. Reads pending queue items and presents them for human review."
      examples(
        "sift",
        "sift init",
        "sift --queue .sift/queue.jsonl",
        "sift --model opus",
        "sift --dry"
      )

      register_subcommand Init, category: :additional

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

      private

      # Hybrid routing: dispatch to subcommand if matched, otherwise
      # fall through to leaf behavior (launch TUI). This lets `sift`
      # remain the TUI entry point while also supporting `sift init`.
      def route_subcommand
        klass = find_subcommand
        if klass
          klass.new(@argv, parent: self).run
        else
          run_leaf
        end
      end
    end
  end
end
