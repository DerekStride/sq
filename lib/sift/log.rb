# frozen_string_literal: true

require "logger"

module Sift
  # Central logging interface for Sift.
  #
  # Outputs to $stderr by default so logs can be redirected separately from
  # workflow output. Testable via Minitest's `capture_io`.
  #
  # @example Basic usage
  #   Sift::Log.info("Processing item...")
  #   Sift::Log.debug("Detailed info here")
  #   Sift::Log.warn("Something unexpected")
  #   Sift::Log.error("Something failed")
  #
  # @example Custom logger
  #   Sift::Log.logger = Rails.logger
  #
  module Log
    LOG_LEVELS = {
      "DEBUG" => ::Logger::DEBUG,
      "INFO" => ::Logger::INFO,
      "WARN" => ::Logger::WARN,
      "ERROR" => ::Logger::ERROR,
      "FATAL" => ::Logger::FATAL,
    }.freeze

    class << self
      attr_writer :logger

      # Buffer debug/info logs temporarily, flushing them when the
      # block exits. Warnings and above still log immediately.
      # Useful when the TUI is waiting for input and stderr output
      # would corrupt the display.
      def quiet
        @buffer = []
        yield
      ensure
        buf = @buffer
        @buffer = nil
        buf&.each { |level, msg| logger.send(level, msg) }
      end

      def debug(message)
        if @buffer
          @buffer << [:debug, message]
          return
        end

        logger.debug(message)
      end

      def info(message)
        if @buffer
          @buffer << [:info, message]
          return
        end

        logger.info(message)
      end

      def warn(message)
        logger.warn(message)
      end

      def error(message)
        logger.error(message)
      end

      def fatal(message)
        logger.fatal(message)
      end

      def logger
        @logger ||= create_logger
      end

      def reset!
        @logger = nil
        @buffer = nil
      end

      private

      def create_logger
        ::Logger.new($stderr, progname: "sift").tap do |l|
          l.level = LOG_LEVELS.fetch(log_level)
          l.formatter = proc { |severity, _time, _progname, msg|
            case severity
            when "ERROR", "FATAL" then "Error: #{msg}\n"
            when "WARN" then "Warning: #{msg}\n"
            else "#{msg}\n"
            end
          }
        end
      end

      def log_level
        level_str = (ENV["SIFT_LOG_LEVEL"] || "INFO").upcase
        unless LOG_LEVELS.key?(level_str)
          raise ArgumentError, "Invalid log level: #{level_str}. Valid levels are: #{LOG_LEVELS.keys.join(", ")}"
        end

        level_str
      end
    end
  end
end
