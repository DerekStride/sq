# frozen_string_literal: true

module Sift
  module CLI
    module Queue
      class Rm < Base
        command_name "rm"
        summary "Remove an item from the queue"
        examples "sq rm <id>"

        def execute
          id = argv.shift
          unless id
            logger.error("Item ID is required")
            return 1
          end

          removed = queue.remove(id)
          if removed
            puts removed.id
            logger.info("Removed item #{removed.id}")
            0
          else
            logger.error("Item not found: #{id}")
            1
          end
        end

        private

        def queue
          @queue ||= Sift::Queue.new(options[:queue_path])
        end
      end
    end
  end
end
