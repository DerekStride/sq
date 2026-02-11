# frozen_string_literal: true

require_relative "cli/base"
require_relative "cli/help_renderer"
require_relative "cli/queue_command"
require_relative "cli/sift_command"

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
