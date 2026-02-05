# frozen_string_literal: true

require "optparse"
require "json"
require "logger"

module Sift
  module CLI
    # Queue subcommand handler for managing review queue items
    class QueueCommand
      SUBCOMMANDS = %w[add edit list show rm].freeze

      def initialize(args, queue_path: nil, stdin: $stdin, stdout: $stdout, stderr: $stderr)
        @args = args.dup
        @queue_path = queue_path || DEFAULT_QUEUE_PATH
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr
        @logger = Logger.new(@stderr, level: Logger::INFO)
        @logger.formatter = proc { |_sev, _dt, _prog, msg| "#{msg}\n" }
      end

      def run
        if @args.empty? || %w[-h --help].include?(@args.first)
          @stdout.puts help_text
          return 0
        end

        subcommand = @args.shift
        unless SUBCOMMANDS.include?(subcommand)
          @stderr.puts "Unknown subcommand: #{subcommand}"
          @stderr.puts help_text
          return 1
        end

        send("run_#{subcommand}")
      end

      private

      def queue
        @queue ||= Sift::Queue.new(@queue_path)
      end

      def help_text
        <<~HELP
          Usage: sift queue <subcommand> [options]

          Subcommands:
            add     Add a new item to the queue
            edit    Edit an existing queue item
            list    List queue items
            show    Show details of a queue item
            rm      Remove an item from the queue

          Run 'sift queue <subcommand> --help' for subcommand options.
        HELP
      end

      # --- Add subcommand ---
      def run_add
        options = { sources: [], metadata: {} }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: sift queue add [options]"

          opts.on("--diff PATH", "Add diff source (repeatable)") do |path|
            options[:sources] << { type: "diff", path: path }
          end

          opts.on("--file PATH", "Add file source (repeatable)") do |path|
            options[:sources] << { type: "file", path: path }
          end

          opts.on("--text STRING", "Add text source (repeatable)") do |text|
            options[:sources] << { type: "text", content: text }
          end

          opts.on("--transcript PATH", "Add transcript source (repeatable)") do |path|
            options[:sources] << { type: "transcript", path: path }
          end

          opts.on("--stdin TYPE", Sift::Queue::VALID_SOURCE_TYPES,
                  "Read source content from stdin (#{Sift::Queue::VALID_SOURCE_TYPES.join("|")})") do |type|
            options[:stdin_type] = type
          end

          opts.on("--metadata JSON", "Attach metadata as JSON") do |json|
            options[:metadata] = parse_json(json, "metadata")
          end

          opts.on("-h", "--help", "Show this help") do
            @stdout.puts opts
            return 0
          end
        end

        begin
          parser.parse!(@args)
        rescue OptionParser::InvalidArgument, OptionParser::MissingArgument => e
          @stderr.puts "Error: #{e.message}"
          return 1
        end

        # Handle stdin source
        if options[:stdin_type]
          content = @stdin.read
          options[:sources] << { type: options[:stdin_type], content: content }
        end

        if options[:sources].empty?
          @stderr.puts "Error: At least one source is required"
          @stderr.puts "Use --diff, --file, --text, --transcript, or --stdin"
          return 1
        end

        begin
          item = queue.push(sources: options[:sources], metadata: options[:metadata])
          @stdout.puts item.id
          @logger.info "Added item #{item.id} with #{item.sources.length} source(s)"
          0
        rescue Sift::Queue::Error => e
          @stderr.puts "Error: #{e.message}"
          1
        end
      end

      # --- Edit subcommand ---
      def run_edit
        options = { add_sources: [], rm_sources: [] }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: sift queue edit <id> [options]"

          opts.on("--add-diff PATH", "Add diff source") do |path|
            options[:add_sources] << { type: "diff", path: path }
          end

          opts.on("--add-file PATH", "Add file source") do |path|
            options[:add_sources] << { type: "file", path: path }
          end

          opts.on("--add-text STRING", "Add text source") do |text|
            options[:add_sources] << { type: "text", content: text }
          end

          opts.on("--add-transcript PATH", "Add transcript source") do |path|
            options[:add_sources] << { type: "transcript", path: path }
          end

          opts.on("--rm-source INDEX", Integer, "Remove source by index (0-based)") do |index|
            options[:rm_sources] << index
          end

          opts.on("--set-status STATUS", Sift::Queue::VALID_STATUSES,
                  "Change status (#{Sift::Queue::VALID_STATUSES.join("|")})") do |status|
            options[:status] = status
          end

          opts.on("--set-metadata JSON", "Set metadata as JSON") do |json|
            options[:metadata] = parse_json(json, "metadata")
          end

          opts.on("-h", "--help", "Show this help") do
            @stdout.puts opts
            return 0
          end
        end

        begin
          parser.parse!(@args)
        rescue OptionParser::InvalidArgument, OptionParser::MissingArgument => e
          @stderr.puts "Error: #{e.message}"
          return 1
        end

        id = @args.shift
        unless id
          @stderr.puts "Error: Item ID is required"
          @stderr.puts parser
          return 1
        end

        item = queue.find(id)
        unless item
          @stderr.puts "Error: Item not found: #{id}"
          return 1
        end

        # Build update attributes
        attrs = {}
        attrs[:status] = options[:status] if options[:status]
        attrs[:metadata] = options[:metadata] if options[:metadata]

        # Handle source modifications
        if options[:add_sources].any? || options[:rm_sources].any?
          sources = item.sources.map(&:to_h)

          # Remove sources (in reverse order to preserve indices)
          options[:rm_sources].sort.reverse.each do |index|
            if index >= 0 && index < sources.length
              sources.delete_at(index)
            else
              @stderr.puts "Warning: Source index #{index} out of range"
            end
          end

          # Add new sources
          sources.concat(options[:add_sources])

          if sources.empty?
            @stderr.puts "Error: Cannot remove all sources"
            return 1
          end

          attrs[:sources] = sources.map { |s| Sift::Queue::Source.from_h(s) }
        end

        if attrs.empty?
          @stderr.puts "Error: No changes specified"
          return 1
        end

        begin
          updated = queue.update(id, **attrs)
          @stdout.puts updated.id
          @logger.info "Updated item #{updated.id}"
          0
        rescue Sift::Queue::Error => e
          @stderr.puts "Error: #{e.message}"
          1
        end
      end

      # --- List subcommand ---
      def run_list
        options = { json: false }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: sift queue list [options]"

          opts.on("--status STATUS", Sift::Queue::VALID_STATUSES,
                  "Filter by status (#{Sift::Queue::VALID_STATUSES.join("|")})") do |status|
            options[:status] = status
          end

          opts.on("--json", "Output as JSON") do
            options[:json] = true
          end

          opts.on("-h", "--help", "Show this help") do
            @stdout.puts opts
            return 0
          end
        end

        begin
          parser.parse!(@args)
        rescue OptionParser::InvalidArgument => e
          @stderr.puts "Error: #{e.message}"
          return 1
        end

        items = queue.filter(status: options[:status])

        if options[:json]
          @stdout.puts JSON.pretty_generate(items.map(&:to_h))
        else
          if items.empty?
            @logger.info "No items found"
          else
            items.each do |item|
              print_item_summary(item)
            end
            @logger.info "#{items.length} item(s)"
          end
        end

        0
      end

      # --- Show subcommand ---
      def run_show
        options = { json: false }

        parser = OptionParser.new do |opts|
          opts.banner = "Usage: sift queue show <id> [options]"

          opts.on("--json", "Output as JSON") do
            options[:json] = true
          end

          opts.on("-h", "--help", "Show this help") do
            @stdout.puts opts
            return 0
          end
        end

        begin
          parser.parse!(@args)
        rescue OptionParser::InvalidArgument => e
          @stderr.puts "Error: #{e.message}"
          return 1
        end

        id = @args.shift
        unless id
          @stderr.puts "Error: Item ID is required"
          @stderr.puts parser
          return 1
        end

        item = queue.find(id)
        unless item
          @stderr.puts "Error: Item not found: #{id}"
          return 1
        end

        if options[:json]
          @stdout.puts JSON.pretty_generate(item.to_h)
        else
          print_item_detail(item)
        end

        0
      end

      # --- Rm subcommand ---
      def run_rm
        parser = OptionParser.new do |opts|
          opts.banner = "Usage: sift queue rm <id>"

          opts.on("-h", "--help", "Show this help") do
            @stdout.puts opts
            return 0
          end
        end

        begin
          parser.parse!(@args)
        rescue OptionParser::InvalidArgument => e
          @stderr.puts "Error: #{e.message}"
          return 1
        end

        id = @args.shift
        unless id
          @stderr.puts "Error: Item ID is required"
          @stderr.puts parser
          return 1
        end

        removed = queue.remove(id)
        if removed
          @stdout.puts removed.id
          @logger.info "Removed item #{removed.id}"
          0
        else
          @stderr.puts "Error: Item not found: #{id}"
          1
        end
      end

      # --- Output helpers ---
      def print_item_summary(item)
        status_color = status_color_code(item.status)
        source_types = item.sources.map(&:type).tally.map { |t, c| c > 1 ? "#{t}:#{c}" : t }.join(",")

        if cli_ui_available?
          @stdout.puts ::CLI::UI.fmt(
            "{{bold:#{item.id}}}  #{status_color}  {{gray:#{source_types}}}  {{gray:#{item.created_at}}}"
          )
        else
          @stdout.puts "#{item.id}  [#{item.status}]  #{source_types}  #{item.created_at}"
        end
      end

      def print_item_detail(item)
        if cli_ui_available?
          ::CLI::UI::Frame.open("{{bold:Item #{item.id}}}", color: :blue) do
            @stdout.puts ::CLI::UI.fmt("{{bold:Status:}} #{status_color_code(item.status)}")
            @stdout.puts ::CLI::UI.fmt("{{bold:Created:}} {{gray:#{item.created_at}}}")
            @stdout.puts ::CLI::UI.fmt("{{bold:Updated:}} {{gray:#{item.updated_at}}}")
            @stdout.puts ::CLI::UI.fmt("{{bold:Session:}} {{gray:#{item.session_id || "none"}}}")

            if item.metadata && !item.metadata.empty?
              @stdout.puts ::CLI::UI.fmt("{{bold:Metadata:}}")
              item.metadata.each do |k, v|
                @stdout.puts ::CLI::UI.fmt("  {{cyan:#{k}:}} #{v}")
              end
            end

            @stdout.puts ::CLI::UI.fmt("{{bold:Sources:}} (#{item.sources.length})")
            item.sources.each_with_index do |source, i|
              print_source(source, i)
            end
          end
        else
          @stdout.puts "Item: #{item.id}"
          @stdout.puts "Status: #{item.status}"
          @stdout.puts "Created: #{item.created_at}"
          @stdout.puts "Updated: #{item.updated_at}"
          @stdout.puts "Session: #{item.session_id || "none"}"

          if item.metadata && !item.metadata.empty?
            @stdout.puts "Metadata:"
            item.metadata.each do |k, v|
              @stdout.puts "  #{k}: #{v}"
            end
          end

          @stdout.puts "Sources: (#{item.sources.length})"
          item.sources.each_with_index do |source, i|
            print_source(source, i)
          end
        end
      end

      def print_source(source, index)
        type_str = source.type
        location = source.path || (source.content ? "[inline]" : "[empty]")

        if cli_ui_available?
          @stdout.puts ::CLI::UI.fmt("  {{yellow:[#{index}]}} {{bold:#{type_str}}} {{gray:#{location}}}")
          if source.content && !source.path
            preview = source.content.lines.first(3).map(&:chomp).join("\n")
            preview += "\n..." if source.content.lines.length > 3
            @stdout.puts ::CLI::UI.fmt("      {{gray:#{preview}}}")
          end
        else
          @stdout.puts "  [#{index}] #{type_str}: #{location}"
          if source.content && !source.path
            preview = source.content.lines.first(3).map(&:chomp).join("\n      ")
            preview += "\n      ..." if source.content.lines.length > 3
            @stdout.puts "      #{preview}"
          end
        end
      end

      def status_color_code(status)
        if cli_ui_available?
          case status
          when "pending" then "{{yellow:#{status}}}"
          when "in_progress" then "{{blue:#{status}}}"
          when "approved" then "{{green:#{status}}}"
          when "rejected" then "{{red:#{status}}}"
          when "failed" then "{{red:#{status}}}"
          else "{{gray:#{status}}}"
          end
        else
          "[#{status}]"
        end
      end

      def cli_ui_available?
        return @cli_ui_available if defined?(@cli_ui_available)

        @cli_ui_available = begin
          require "cli/ui"
          ::CLI::UI::StdoutRouter.enable unless ::CLI::UI::StdoutRouter.current_id
          true
        rescue LoadError
          false
        end
      end

      def parse_json(str, field_name)
        JSON.parse(str)
      rescue JSON::ParserError => e
        raise OptionParser::InvalidArgument, "Invalid JSON for #{field_name}: #{e.message}"
      end
    end
  end
end
