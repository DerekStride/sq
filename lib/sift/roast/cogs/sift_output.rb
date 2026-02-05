# frozen_string_literal: true

require "json"

module Sift
  module Roast
    # Define constants and error here for standalone loading by Roast
    QUEUE_PATH_ENV = "SIFT_QUEUE_PATH" unless const_defined?(:QUEUE_PATH_ENV)

    class Error < StandardError; end unless const_defined?(:Error)

    module Cogs
      # Custom Roast cog for pushing results to Sift queue
      #
      # Usage in workflow.rb:
      #   use [:sift_output], from: 'sift/roast/cogs'
      #
      #   execute do
      #     agent!(:analyze) { "Review this code" }
      #
      #     sift_output do |my|
      #       my.sources = [
      #         { type: 'text', content: agent!(:analyze).response }
      #       ]
      #       my.metadata = { workflow: 'analyze', target: target! }
      #     end
      #   end
      #
      class SiftOutput
        # Configuration object yielded to the block
        class Config
          attr_accessor :sources, :metadata, :session_id

          def initialize
            @sources = []
            @metadata = {}
            @session_id = nil
          end
        end

        # Called when cog is registered with workflow
        def self.included(base)
          base.extend(ClassMethods)
        end

        module ClassMethods
          def sift_output_cog
            @sift_output_cog ||= SiftOutput.new
          end
        end

        def initialize
          @queue_path = ENV.fetch(Sift::Roast::QUEUE_PATH_ENV, nil)
        end

        # Push output to the Sift queue
        #
        # @yield [Config] configuration object to set sources and metadata
        # @return [String] created item ID
        # @raise [Error] if SIFT_QUEUE_PATH not set or sources empty
        def call
          config = Config.new
          yield config if block_given?

          validate_config!(config)

          queue = load_queue
          item = queue.push(
            sources: config.sources,
            metadata: config.metadata,
            session_id: config.session_id
          )

          item.id
        end

        private

        def validate_config!(config)
          unless @queue_path
            raise Sift::Roast::Error,
                  "#{Sift::Roast::QUEUE_PATH_ENV} environment variable not set. " \
                  "Run workflow via Sift::Roast::Orchestrator."
          end

          if config.sources.nil? || config.sources.empty?
            raise Sift::Roast::Error, "sift_output requires at least one source"
          end
        end

        def load_queue
          require "sift/queue"
          Sift::Queue.new(@queue_path)
        end
      end

      # Module method to make cog available as a workflow method
      # This follows Roast's cog loading pattern
      def sift_output(&block)
        @_sift_output_cog ||= SiftOutput.new
        @_sift_output_cog.call(&block)
      end
    end
  end
end
