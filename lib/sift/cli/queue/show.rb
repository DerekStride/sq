# frozen_string_literal: true

require "json"

module Sift
  module CLI
    module Queue
      class Show < Base
        include Formatters

        command_name "show"
        summary "Show details of a queue item"
        examples "sq show <id>", "sq show <id> --json"

        def define_flags(parser, options)
          parser.on("--json", "Output as JSON") do
            options[:json] = true
          end

          super
        end

        def execute
          id = argv.shift
          unless id
            logger.error("Item ID is required")
            return 1
          end

          item = queue.find(id)
          unless item
            logger.error("Item not found: #{id}")
            return 1
          end

          if options[:json]
            puts JSON.pretty_generate(item.to_h)
          else
            print_item_detail(item)
          end

          0
        end

        private

        def queue
          @queue ||= Sift::Queue.new(options[:queue_path])
        end
      end
    end
  end
end
