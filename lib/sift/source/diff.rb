# frozen_string_literal: true

module Sift
  module Source
    class Diff < Base
      def render(width: 80, height: nil)
        content = source.content || ""
        lines = content.lines.map(&:chomp)
        lines = lines.first(height) if height

        lines.map { |line| format_line(line) }
      end

      def label
        source.path || "diff"
      end

      private

      def format_line(line)
        case line[0]
        when "+" then "\e[32m#{line}\e[0m"
        when "-" then "\e[31m#{line}\e[0m"
        when "@" then "\e[36m#{line}\e[0m"
        else line
        end
      end
    end
  end
end
