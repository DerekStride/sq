# frozen_string_literal: true

module Sift
  # Parse git diff output into individual hunks
  class DiffParser
    Hunk = Struct.new(:file, :header, :content, :patch, keyword_init: true)

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
      current_diff_header = []
      current_hunk_lines = []
      current_header = nil

      diff_text.each_line do |line|
        case line
        when /^diff --git/
          # Save previous hunk if exists
          save_hunk(hunks, current_file, current_header, current_hunk_lines, current_diff_header)
          current_file = nil
          current_diff_header = [line]
          current_hunk_lines = []
          current_header = nil
        when /^--- a\/(.+)$/
          current_diff_header << line
        when /^\+\+\+ b\/(.+)$/
          current_file = ::Regexp.last_match(1)
          current_diff_header << line
        when /^@@.+@@/
          # Save previous hunk if exists (same file, new hunk)
          save_hunk(hunks, current_file, current_header, current_hunk_lines, current_diff_header)
          current_header = line.chomp
          current_hunk_lines = [line]
        when /^[-+ ]/
          current_hunk_lines << line if current_header
        when /^(index |old mode |new mode |new file |deleted file |similarity |rename |copy )/
          current_diff_header << line
        end
      end

      # Save final hunk
      save_hunk(hunks, current_file, current_header, current_hunk_lines, current_diff_header)

      hunks
    end

    private

    def save_hunk(hunks, file, header, lines, diff_header)
      return if file.nil? || header.nil? || lines.empty?

      content = lines.join
      # Build a complete patch that can be applied
      patch = diff_header.join + content

      hunks << Hunk.new(
        file: file,
        header: header,
        content: content,
        patch: patch
      )
    end
  end
end
