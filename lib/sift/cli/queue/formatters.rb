# frozen_string_literal: true

module Sift
  module CLI
    module Queue
      module Formatters
        private

        def print_item_summary(item)
          status_color = status_color_code(item.status)
          source_types = item.sources.map(&:type).tally.map { |t, c| c > 1 ? "#{t}:#{c}" : t }.join(",")

          title_part = item.title ? "  #{item.title}" : ""

          if cli_ui_available?
            puts ::CLI::UI.fmt(
              "{{bold:#{item.id}}}  #{status_color}#{title_part}  {{gray:#{source_types}}}  {{gray:#{item.created_at}}}"
            )
          else
            puts "#{item.id}  [#{item.status}]#{title_part}  #{source_types}  #{item.created_at}"
          end
        end

        def print_item_detail(item)
          if cli_ui_available?
            ::CLI::UI::Frame.open("{{bold:Item #{item.id}}}", color: :blue) do
              puts ::CLI::UI.fmt("{{bold:Title:}} #{item.title}") if item.title
              puts ::CLI::UI.fmt("{{bold:Status:}} #{status_color_code(item.status)}")
              puts ::CLI::UI.fmt("{{bold:Created:}} {{gray:#{item.created_at}}}")
              puts ::CLI::UI.fmt("{{bold:Updated:}} {{gray:#{item.updated_at}}}")
              puts ::CLI::UI.fmt("{{bold:Session:}} {{gray:#{item.session_id || "none"}}}")

              if item.worktree
                wt = item.worktree
                puts ::CLI::UI.fmt("{{bold:Worktree:}} {{cyan:#{wt.branch}}} {{gray:#{wt.path}}}")
              end

              if item.metadata && !item.metadata.empty?
                puts ::CLI::UI.fmt("{{bold:Metadata:}}")
                item.metadata.each do |k, v|
                  puts ::CLI::UI.fmt("  {{cyan:#{k}:}} #{v}")
                end
              end

              puts ::CLI::UI.fmt("{{bold:Sources:}} (#{item.sources.length})")
              item.sources.each_with_index do |source, i|
                print_source(source, i)
              end

              print_transcript(item.session_id) if item.session_id
            end
          else
            puts "Item: #{item.id}"
            puts "Title: #{item.title}" if item.title
            puts "Status: #{item.status}"
            puts "Created: #{item.created_at}"
            puts "Updated: #{item.updated_at}"
            puts "Session: #{item.session_id || "none"}"

            if item.worktree
              wt = item.worktree
              puts "Worktree: #{wt.branch} #{wt.path}"
            end

            if item.metadata && !item.metadata.empty?
              puts "Metadata:"
              item.metadata.each do |k, v|
                puts "  #{k}: #{v}"
              end
            end

            puts "Sources: (#{item.sources.length})"
            item.sources.each_with_index do |source, i|
              print_source(source, i)
            end

            print_transcript(item.session_id) if item.session_id
          end
        end

        def print_source(source, index)
          type_str = source.type
          location = source.path || (source.content ? "[inline]" : "[empty]")

          if cli_ui_available?
            puts ::CLI::UI.fmt("  {{yellow:[#{index}]}} {{bold:#{type_str}}} {{gray:#{location}}}")
            if source.content && !source.path
              preview = source.content.lines.first(3).map(&:chomp).join("\n")
              preview += "\n..." if source.content.lines.length > 3
              puts ::CLI::UI.fmt("      {{gray:#{preview}}}")
            end
          else
            puts "  [#{index}] #{type_str}: #{location}"
            if source.content && !source.path
              preview = source.content.lines.first(3).map(&:chomp).join("\n      ")
              preview += "\n      ..." if source.content.lines.length > 3
              puts "      #{preview}"
            end
          end
        end

        def print_transcript(session_id)
          path = Sift::SessionTranscript.find_session(session_id)
          return unless path

          first_prompt = first_user_prompt(path)
          preview = first_prompt ? first_prompt.lines.first.chomp : ""

          if cli_ui_available?
            puts ::CLI::UI.fmt("  {{yellow:[transcript]}} {{bold:session}} {{gray:#{session_id[0, 8]}...}}")
            puts ::CLI::UI.fmt("      {{gray:#{preview}}}") unless preview.empty?
          else
            puts "  [transcript] session #{session_id[0, 8]}..."
            puts "      #{preview}" unless preview.empty?
          end
        end

        def first_user_prompt(path)
          File.foreach(path) do |line|
            next if line.strip.empty?
            data = JSON.parse(line)
            msg = data["message"]
            next unless data["type"] == "user" && msg
            content = msg["content"]
            return content if content.is_a?(String) && !content.strip.empty?
          rescue JSON::ParserError
            next
          end
          nil
        end

        def status_color_code(status)
          if cli_ui_available?
            case status
            when "pending" then "{{yellow:#{status}}}"
            when "in_progress" then "{{blue:#{status}}}"
            when "closed" then "{{green:#{status}}}"
            else "{{gray:#{status}}}"
            end
          else
            "[#{status}]"
          end
        end
      end
    end
  end
end
