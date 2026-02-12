# frozen_string_literal: true

require "json"

module Sift
  module CLI
    module Queue
      class List < Base
        include Formatters

        command_name "list"
        summary "List queue items"
        examples "sq list", "sq list --status pending", "sq list --json"

        def define_flags(parser, options)
          parser.on("--status STATUS", Sift::Queue::VALID_STATUSES,
            "Filter by status (#{Sift::Queue::VALID_STATUSES.join("|")})") do |status|
            options[:status] = status
          end

          parser.on("--json", "Output as JSON") do
            options[:json] = true
          end

          super
        end

        def execute
          items = queue.filter(status: options[:status])

          if options[:json]
            puts JSON.pretty_generate(items.map(&:to_h))
          else
            if items.empty?
              logger.info("No items found")
            else
              items.each { |item| print_item_summary(item) }
              logger.info("#{items.length} item(s)")
            end
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
