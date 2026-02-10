# frozen_string_literal: true

module Sift
  module Source
    class Transcript < Base
      SPEAKER_PATTERN = /\A(H|A|Human|Assistant|User|System):\s*/i

      def render(width: 80, height: nil)
        content = load_content
        return ["(empty transcript)"] if content.nil? || content.empty?

        lines = format_transcript(content)
        lines = lines.first(height) if height
        lines
      end

      def label
        source.path || "transcript"
      end

      private

      def load_content
        if source.content
          source.content
        elsif source.path && ::File.exist?(source.path)
          ::File.read(source.path)
        end
      end

      def format_transcript(content)
        result = []
        current_speaker = nil

        content.each_line do |line|
          line = line.chomp
          if (match = line.match(SPEAKER_PATTERN))
            speaker = normalize_speaker(match[1])
            text = line[match[0].length..]

            if speaker != current_speaker
              result << "" unless result.empty?
              result << speaker_label(speaker)
              current_speaker = speaker
            end
            result << "  #{text}" unless text.empty?
          elsif line.strip.empty?
            result << ""
          else
            result << "  #{line}"
          end
        end

        result
      end

      def normalize_speaker(raw)
        case raw.downcase
        when "h", "human", "user" then "Human"
        when "a", "assistant"     then "Assistant"
        when "system"             then "System"
        else raw
        end
      end

      def speaker_label(speaker)
        color = case speaker
                when "Human"    then "\e[34m"
                when "Assistant" then "\e[35m"
                when "System"   then "\e[33m"
                else "\e[37m"
                end
        "#{color}#{speaker}:\e[0m"
      end
    end
  end
end
