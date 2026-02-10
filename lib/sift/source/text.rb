# frozen_string_literal: true

module Sift
  module Source
    class Text < Base
      def render(width: 80, height: nil)
        content = source.content || ""
        lines = wrap(content, width)
        lines = lines.first(height) if height
        lines
      end

      def label
        source.path || "text"
      end

      private

      def wrap(text, width)
        text.lines.flat_map do |line|
          line = line.chomp
          if line.length <= width
            [line]
          else
            wrap_line(line, width)
          end
        end
      end

      def wrap_line(line, width)
        result = []
        while line.length > width
          # Find last space within width
          break_at = line.rindex(" ", width) || width
          result << line[0...break_at]
          line = line[break_at..].lstrip
        end
        result << line unless line.empty?
        result
      end
    end
  end
end
