# frozen_string_literal: true

module Sift
  module Source
    class File < Base
      def render(width: 80, height: nil)
        content = load_content
        return ["(empty)"] if content.nil? || content.empty?

        lines = content.lines.map(&:chomp)
        lines = lines.first(height) if height

        gutter_width = lines.length.to_s.length
        lines.each_with_index.map do |line, i|
          lineno = (i + 1).to_s.rjust(gutter_width)
          "\e[90m#{lineno}\e[0m  #{line}"
        end
      end

      def label
        source.path || "file"
      end

      private

      def load_content
        if source.content
          source.content
        elsif source.path && ::File.exist?(source.path)
          ::File.read(source.path)
        end
      end
    end
  end
end
