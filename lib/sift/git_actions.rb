# frozen_string_literal: true

require "open3"
require "tempfile"

module Sift
  # Git operations for staging/reverting hunks
  module GitActions
    class Error < StandardError; end

    class << self
      # Stage a hunk (accept = add to index)
      def stage_hunk(hunk, path: ".")
        apply_patch(hunk.patch, path: path, cached: true)
      end

      # Revert a hunk (reject = remove from working tree)
      def revert_hunk(hunk, path: ".")
        apply_patch(hunk.patch, path: path, reverse: true)
      end

      private

      def apply_patch(patch, path:, cached: false, reverse: false)
        args = ["git", "-C", path, "apply"]
        args << "--cached" if cached
        args << "--reverse" if reverse

        stdout, stderr, status = Open3.capture3(*args, stdin_data: patch)

        unless status.success?
          raise Error, "git apply failed: #{stderr}"
        end

        true
      end
    end
  end
end
