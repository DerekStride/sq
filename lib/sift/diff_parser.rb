# frozen_string_literal: true

module Sift
  # Parse git diff output into individual hunks
  class DiffParser
    Hunk = Struct.new(:file, :header, :content, :full, keyword_init: true)

    def self.parse(diff_text)
      new.parse(diff_text)
    end

    def self.from_git(path = ".", base: "HEAD")
      diff_text = `git -C #{path} diff #{base}`
      parse(diff_text)
    end

    def parse(diff_text)
      hunks = []
      current_file = nil
      current_hunk_lines = []
      current_header = nil

      diff_text.each_line do |line|
        case line
        when /^diff --git a\/.+ b\/(.+)$/
          # Save previous hunk if exists
          save_hunk(hunks, current_file, current_header, current_hunk_lines)
          current_file = ::Regexp.last_match(1)
          current_hunk_lines = []
          current_header = nil
        when /^@@.+@@/
          # Save previous hunk if exists (same file, new hunk)
          save_hunk(hunks, current_file, current_header, current_hunk_lines)
          current_header = line.chomp
          current_hunk_lines = [line]
        when /^[-+ ]/
          current_hunk_lines << line if current_header
        end
      end

      # Save final hunk
      save_hunk(hunks, current_file, current_header, current_hunk_lines)

      hunks
    end

    private

    def save_hunk(hunks, file, header, lines)
      return if file.nil? || header.nil? || lines.empty?

      content = lines.join
      hunks << Hunk.new(
        file: file,
        header: header,
        content: content,
        full: content
      )
    end
  end
end
