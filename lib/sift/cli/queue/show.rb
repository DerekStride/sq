# frozen_string_literal: true

require "json"

module Sift
  module CLI
    module Queue
      class Show < Base
        include Formatters

        command_name "show"
        summary "Show details of a queue item"
        examples "sq show <id>", "sq show <id> --json"

        def define_flags(parser, options)
          parser.on("--json", "Output as JSON") do
            options[:json] = true
          end

          super
        end

        def execute
          id = argv.shift
          unless id
            logger.error("Item ID is required")
            return 1
          end

          item = queue.find(id)
          unless item
            logger.error("Item not found: #{id}")
            return 1
          end

          if item.worktree
            item = refresh_worktree_sources(item)
          end

          if options[:json]
            puts JSON.pretty_generate(item.to_h)
          else
            print_item_detail(item)
          end

          0
        end

        private

        def refresh_worktree_sources(item)
          git = Sift::Git.new
          return item unless git.worktree_valid?(item.worktree.path)

          config = Sift::Config.new
          base = config.worktree_base_branch
          sources = item.sources.map(&:to_h)

          has_commits = git.has_commits_beyond?(item.worktree.branch, base)
          has_local = git.worktree_dirty?(item.worktree.path, base)

          if has_commits || has_local
            diff_content = git.worktree_diff(item.worktree.path, base)
            entry = { type: "diff", path: "worktree", content: diff_content }
            idx = sources.index { |s| s[:type] == "diff" && s[:path] == "worktree" }
            idx ? sources[idx] = entry : sources << entry
          end

          unless sources.any? { |s| s[:type] == "directory" && s[:path] == item.worktree.path }
            sources << { type: "directory", path: item.worktree.path }
          end

          updated_sources = sources.map { |s| Sift::Queue::Source.from_h(s) }
          queue.update(item.id, sources: updated_sources)
          queue.find(item.id)
        end

        def queue
          @queue ||= Sift::Queue.new(options[:queue_path])
        end
      end
    end
  end
end
