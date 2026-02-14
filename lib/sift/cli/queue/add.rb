# frozen_string_literal: true

require "json"

module Sift
  module CLI
    module Queue
      class Add < Base
        command_name "add"
        summary "Add a new item to the review queue"
        examples(
          "sq add --text 'Review this function'",
          "sq add --diff changes.patch --metadata '{\"workflow\":\"analyze\"}'",
          "echo 'content' | sq add --stdin text"
        )

        def define_flags(parser, options)
          options[:sources] ||= []
          options[:metadata] ||= {}

          parser.on("--diff PATH", "Add diff source (repeatable)") do |path|
            options[:sources] << { type: "diff", path: path }
          end

          parser.on("--file PATH", "Add file source (repeatable)") do |path|
            options[:sources] << { type: "file", path: path }
          end

          parser.on("--text STRING", "Add text source (repeatable)") do |text|
            options[:sources] << { type: "text", content: text }
          end

          parser.on("--directory PATH", "Add directory source (repeatable)") do |path|
            options[:sources] << { type: "directory", path: path }
          end

          parser.on("--stdin TYPE", Sift::Queue::VALID_SOURCE_TYPES,
            "Read source content from stdin (#{Sift::Queue::VALID_SOURCE_TYPES.join("|")})") do |type|
            options[:stdin_type] = type
          end

          parser.on("--title TITLE", "Title for the item") do |title|
            options[:title] = title
          end

          parser.on("--metadata JSON", "Attach metadata as JSON") do |json|
            options[:metadata] = parse_json(json, "metadata")
          end

          super
        end

        def execute
          if options[:stdin_type]
            content = $stdin.read
            options[:sources] << { type: options[:stdin_type], content: content }
          end

          if options[:sources].empty?
            logger.error("At least one source is required")
            logger.error("Use --diff, --file, --text, --directory, or --stdin")
            return 1
          end

          metadata = options[:metadata]

          item = queue.push(sources: options[:sources], title: options[:title], metadata: metadata)
          puts item.id
          logger.info("Added item #{item.id} with #{item.sources.length} source(s)")
          0
        end

        private

        def queue
          @queue ||= Sift::Queue.new(options[:queue_path])
        end

        def parse_json(str, field_name)
          JSON.parse(str)
        rescue JSON::ParserError => e
          raise OptionParser::InvalidArgument, "Invalid JSON for #{field_name}: #{e.message}"
        end
      end
    end
  end
end
