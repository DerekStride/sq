# frozen_string_literal: true

module Sift
  # Roast workflow integration for Sift
  module Roast
    class Error < Sift::Error; end

    # Environment variable used to pass queue path to cogs
    QUEUE_PATH_ENV = "SIFT_QUEUE_PATH"
  end
end

require_relative "roast/orchestrator"
require_relative "roast/cogs/sift_output"
