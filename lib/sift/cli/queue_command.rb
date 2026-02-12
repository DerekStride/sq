# frozen_string_literal: true

require_relative "queue/formatters"
require_relative "queue/add"
require_relative "queue/edit"
require_relative "queue/list"
require_relative "queue/show"
require_relative "queue/rm"

module Sift
  module CLI
    class QueueCommand < Base
      command_name "sq"
      summary "Manage Sift's review queue"
      description "Manage Sift's review queue"
      examples(
        "sq add --text 'Review this change'",
        "sq add --diff changes.patch --file main.rb",
        "sq list --status pending",
        "sq show abc"
      )

      register_subcommand Queue::Add, category: :core
      register_subcommand Queue::List, category: :core
      register_subcommand Queue::Show, category: :core
      register_subcommand Queue::Edit, category: :additional
      register_subcommand Queue::Rm, category: :additional

      def initialize(argv, parent: nil, queue_path: nil)
        super(argv, parent: parent)
        @default_queue_path = queue_path
      end

      def define_flags(parser, options)
        options[:queue_path] ||= @default_queue_path || DEFAULT_QUEUE_PATH
        parser.on("--queue-path PATH", "Path to queue file") { |v| options[:queue_path] = v }
        super
      end
    end
  end
end
