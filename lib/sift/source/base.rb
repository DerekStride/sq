# frozen_string_literal: true

module Sift
  module Source
    class Base
      attr_reader :source

      def initialize(source)
        @source = source
      end

      def render(width: 80, height: nil)
        raise NotImplementedError, "#{self.class}#render not implemented"
      end

      def label
        source.path || source.type
      end

      # Factory: dispatch to correct renderer based on source type
      def self.for(source)
        case source.type
        when "diff"       then Diff.new(source)
        when "file"       then File.new(source)
        when "text"       then Text.new(source)
        when "transcript" then Transcript.new(source)
        else raise ArgumentError, "Unknown source type: #{source.type}"
        end
      end
    end
  end
end

require_relative "diff"
require_relative "file"
require_relative "text"
require_relative "transcript"
