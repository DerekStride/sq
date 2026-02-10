# frozen_string_literal: true

require_relative "sift/version"
require_relative "sift/client"
require_relative "sift/diff_parser"
require_relative "sift/git_actions"
require_relative "sift/cli"
require_relative "sift/queue"
require_relative "sift/review_loop"
require_relative "sift/roast"

module Sift
  class Error < StandardError; end
end
