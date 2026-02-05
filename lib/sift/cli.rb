# frozen_string_literal: true

require_relative "cli/queue"

module Sift
  # CLI module for command-line interface components
  module CLI
    DEFAULT_QUEUE_PATH = ".sift/queue.jsonl"

    class << self
      def logger
        @logger ||= Logger.new($stderr, level: Logger::INFO)
      end

      def logger=(logger)
        @logger = logger
      end
    end
  end
end
