# frozen_string_literal: true

require "open3"
require "timeout"

module Sift
  # Loads `sq prime` output for agent context.
  class Prime
    DEFAULT = "Use `sq --help` to learn more about using `sq`."

    class << self
      def run!
        output, success = fetch_context
        new(output: output, success: success)
      rescue StandardError => e
        Log.warn "sq prime preload failed: #{e.class}: #{e.message}"
        new(output: nil, success: false)
      end

      private

      def fetch_context
        argv = ["sq", "prime"]

        stdout = ""
        stderr = ""
        status = nil

        Timeout.timeout(2) do
          Open3.popen3(*argv) do |stdin, out_io, err_io, wait_thread|
            stdin.close

            out_reader = Thread.new { out_io.read }
            err_reader = Thread.new { err_io.read }

            stdout = out_reader.value
            stderr = err_reader.value
            status = wait_thread.value
          end
        end

        unless status&.success?
          first_line = stderr.to_s.lines.first&.chomp || "unknown error"
          Log.warn "sq prime failed (#{argv.join(" ")}): #{first_line}"
          return [nil, false]
        end

        output = stdout.to_s.strip
        [output.empty? ? nil : output, true]
      rescue Errno::ENOENT
        Log.warn "sq not found; continuing without prime context"
        [nil, false]
      rescue Timeout::Error
        Log.warn "sq prime timed out; continuing without prime context"
        [nil, false]
      end
    end

    def initialize(output:, success:)
      @output = output
      @success = success
    end

    def valid?
      @success
    end

    def default
      DEFAULT
    end

    def to_s
      valid? ? @output.to_s : default
    end
  end
end
