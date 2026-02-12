# frozen_string_literal: true

require "json"

module Sift
  module CLI
    module Queue
      class Edit < Base
        command_name "edit"
        summary "Edit an existing queue item"
        examples "sq edit <id> --set-status closed"

        def define_flags(parser, options)
          options[:add_sources] ||= []
          options[:rm_sources] ||= []

          parser.on("--add-diff PATH", "Add diff source") do |path|
            options[:add_sources] << { type: "diff", path: path }
          end

          parser.on("--add-file PATH", "Add file source") do |path|
            options[:add_sources] << { type: "file", path: path }
          end

          parser.on("--add-text STRING", "Add text source") do |text|
            options[:add_sources] << { type: "text", content: text }
          end

          parser.on("--add-transcript PATH", "Add transcript source") do |path|
            options[:add_sources] << { type: "transcript", path: path }
          end

          parser.on("--rm-source INDEX", Integer, "Remove source by index (0-based)") do |index|
            options[:rm_sources] << index
          end

          parser.on("--set-status STATUS", Sift::Queue::VALID_STATUSES,
            "Change status (#{Sift::Queue::VALID_STATUSES.join("|")})") do |status|
            options[:status] = status
          end

          parser.on("--set-system-prompt PATH", "Set system prompt file path") do |path|
            options[:system_prompt] = path
          end

          parser.on("--set-metadata JSON", "Set metadata as JSON") do |json|
            options[:metadata] = parse_json(json, "metadata")
          end

          super
        end

        def execute
          id = argv.shift
          unless id
            stderr.puts "Error: Item ID is required"
            return 1
          end

          item = queue.find(id)
          unless item
            stderr.puts "Error: Item not found: #{id}"
            return 1
          end

          attrs = {}
          attrs[:status] = options[:status] if options[:status]
          attrs[:metadata] = options[:metadata] if options[:metadata]

          if options[:system_prompt]
            metadata = attrs[:metadata] || item.metadata.dup
            metadata["system_prompt"] = options[:system_prompt]
            attrs[:metadata] = metadata
          end

          if options[:add_sources].any? || options[:rm_sources].any?
            sources = item.sources.map(&:to_h)

            options[:rm_sources].sort.reverse.each do |index|
              if index >= 0 && index < sources.length
                sources.delete_at(index)
              else
                stderr.puts "Warning: Source index #{index} out of range"
              end
            end

            sources.concat(options[:add_sources])

            if sources.empty?
              stderr.puts "Error: Cannot remove all sources"
              return 1
            end

            attrs[:sources] = sources.map { |s| Sift::Queue::Source.from_h(s) }
          end

          if attrs.empty?
            stderr.puts "Error: No changes specified"
            return 1
          end

          updated = queue.update(id, **attrs)
          stdout.puts updated.id
          Sift::Log.info "Updated item #{updated.id}"
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
