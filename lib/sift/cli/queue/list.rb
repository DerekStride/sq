# frozen_string_literal: true

require "json"
require "open3"

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

          parser.on("--filter EXPR", "jq select expression (e.g. 'select(.status == \"pending\")')") do |expr|
            options[:filter] = expr
          end

          parser.on("--sort PATH", "jq path expression to sort by (e.g. '.metadata.track.priority')") do |path|
            options[:sort] = path
          end

          parser.on("--reverse", "Reverse sort order") do
            options[:reverse] = true
          end

          parser.on("--ready", "Show only ready items (pending and unblocked)") do
            options[:ready] = true
          end

          super
        end

        def execute
          items = if options[:ready]
            queue.ready
          else
            queue.filter(status: options[:status])
          end

          if options[:filter]
            items = jq_filter(items, "[.[] | #{options[:filter]}]")
            return 1 if items.nil?
          end

          if options[:sort]
            path = options[:sort]
            items = jq_filter(items, "sort_by(#{path} // infinite)")
            return 1 if items.nil?
          end

          items = items.reverse if options[:reverse]

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

        def jq_filter(items, expr)
          json = JSON.generate(items.map(&:to_h))
          out, err, status = Open3.capture3("jq", "-e", expr, stdin_data: json)
          unless status.success?
            logger.error("Filter failed: #{err.strip}")
            return nil
          end
          JSON.parse(out).map { |h| Sift::Queue::Item.from_h(h) }
        end

        def queue
          @queue ||= Sift::Queue.new(options[:queue_path])
        end
      end
    end
  end
end
