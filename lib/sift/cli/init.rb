# frozen_string_literal: true

require "fileutils"

module Sift
  module CLI
    class Init < Base
      command_name "init"
      summary "Initialize .sift/ directory and config"
      description "Create the .sift/ directory and a config.yml with all keys commented out as a reference.\n" \
        "Use --user to create the user-level config at ~/.config/sift/config.yml instead."
      examples "sift init", "sift init --user"

      CONFIG_TEMPLATE = <<~YAML
        # Sift configuration
        # Uncomment and modify values to override defaults.

        # agent:
        #   command: claude          # CLI command to invoke agents
        #   flags: []                # Additional CLI flags passed to agent
        #   allowed_tools: []        # Restrict agent to these tools
        #   model: sonnet            # Claude model (sonnet, opus, haiku)

        # worktree:
        #   setup_command:           # Command to run when setting up worktree
        #   base_branch: main        # Base branch for git operations

        # queue_path: .sift/queue.jsonl   # Queue file location
        # concurrency: 5                  # Max concurrent agents
        # dry: false                      # Skip Claude API calls
      YAML

      SIFT_DIR = ".sift"
      CONFIG_PATH = File.join(SIFT_DIR, "config.yml")

      def define_flags(parser, options)
        parser.on("--user", "Initialize user-level config (~/.config/sift/config.yml)") do
          options[:user] = true
        end
        super
      end

      def execute
        if options[:user]
          init_user_config
        else
          init_project_config
        end
      end

      private

      def init_project_config
        dir_created = false
        unless Dir.exist?(SIFT_DIR)
          Dir.mkdir(SIFT_DIR)
          dir_created = true
        end

        if File.exist?(CONFIG_PATH)
          puts "#{CONFIG_PATH} already exists"
        else
          File.write(CONFIG_PATH, CONFIG_TEMPLATE)
          puts "created #{CONFIG_PATH}"
        end

        logger.info("created #{SIFT_DIR}/") if dir_created
        0
      end

      def init_user_config
        path = Sift::Config.default_user_path
        dir = File.dirname(path)

        FileUtils.mkdir_p(dir) unless Dir.exist?(dir)

        if File.exist?(path)
          puts "#{path} already exists"
        else
          File.write(path, CONFIG_TEMPLATE)
          puts "created #{path}"
        end

        0
      end
    end
  end
end
