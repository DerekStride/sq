# frozen_string_literal: true

require "yaml"

module Sift
  # Configuration loaded from user (~/.config/sift/config.yml)
  # and project (.sift/config.yml) tiers with deep merge.
  #
  # Precedence (highest to lowest):
  #   CLI flags > env vars > project config > user config > hardcoded defaults
  #
  # Config is optional — sift works without it using defaults.
  # CLI commands load config once, apply env var overrides, then
  # apply CLI flag overrides via setters. The resulting Config
  # object is passed to components as the single source of truth.
  #
  # File-backed values (like system_prompt) are read eagerly and
  # validated at set-time. Raises Sift::Config::FileNotFound if
  # a referenced file doesn't exist.
  class Config
    DEFAULT_PROJECT_PATH = ".sift/config.yml"
    DEFAULT_PATH = DEFAULT_PROJECT_PATH

    class FileNotFound < Sift::Error; end

    DEFAULTS = {
      "agent" => {
        "command" => "claude",
        "flags" => [],
        "allowed_tools" => [],
        "model" => "sonnet",
        "system_prompt" => nil,
      },
      "worktree" => {
        "setup_command" => nil,
        "base_branch" => "main",
      },
      "queue_path" => ".sift/queue.jsonl",
      "concurrency" => 5,
      "dry" => false,
    }.freeze

    def self.default_user_path
      File.join(ENV.fetch("XDG_CONFIG_HOME", File.join(Dir.home, ".config")), "sift", "config.yml")
    end

    def self.load(project_path: DEFAULT_PROJECT_PATH, user_path: default_user_path)
      user_data = load_yaml(user_path)
      project_data = load_yaml(project_path)
      config = new(user_data, project_data)
      config.send(:apply_env_vars)
      config.send(:resolve_file_values)
      config
    end

    private_class_method def self.load_yaml(path)
      if File.exist?(path)
        parsed = YAML.safe_load_file(path) || {}
        Log.debug "config loaded from #{path}"
        parsed
      else
        Log.debug "no config file at #{path}, using defaults"
        {}
      end
    end

    def initialize(user_data = {}, project_data = {})
      @data = deep_merge(deep_merge(DEFAULTS, user_data), project_data)
    end

    # -- Agent settings (readers) --

    def agent_command = @data.dig("agent", "command")
    def agent_flags = @data.dig("agent", "flags")
    def agent_allowed_tools = @data.dig("agent", "allowed_tools")
    def agent_model = @data.dig("agent", "model")
    def agent_system_prompt = @agent_system_prompt

    # -- Agent settings (writers for CLI overrides) --

    def agent_model=(value)
      @data["agent"]["model"] = value
    end

    def agent_system_prompt=(path)
      @agent_system_prompt = read_file!(path)
    end

    # -- Worktree settings --

    def worktree_setup_command = @data.dig("worktree", "setup_command")
    def worktree_base_branch = @data.dig("worktree", "base_branch")

    # -- Top-level settings --

    def queue_path = @data["queue_path"]

    def queue_path=(value)
      @data["queue_path"] = value
    end

    def concurrency = @data["concurrency"]

    def concurrency=(value)
      @data["concurrency"] = value
    end

    def dry? = @data["dry"]

    def dry=(value)
      @data["dry"] = value
    end

    private

    def apply_env_vars
      @data["queue_path"] = ENV["SIFT_QUEUE_PATH"] if ENV.key?("SIFT_QUEUE_PATH")
    end

    # Eagerly read file-backed config values after loading.
    def resolve_file_values
      path = @data.dig("agent", "system_prompt")
      @agent_system_prompt = read_file!(path) if path
    end

    # Read a file, raising FileNotFound if it doesn't exist.
    def read_file!(path)
      return nil if path.nil?

      raise FileNotFound, "file not found: #{path}" unless File.exist?(path)

      File.read(path)
    end

    def deep_merge(base, override)
      result = {}
      (base.keys | override.keys).each do |key|
        base_val = base[key]
        over_val = override[key]

        result[key] = if base.key?(key) && override.key?(key)
          base_val.is_a?(Hash) && over_val.is_a?(Hash) ? deep_merge(base_val, over_val) : over_val
        elsif base.key?(key)
          base_val.is_a?(Hash) ? base_val.dup : base_val
        else
          over_val
        end
      end
      result
    end
  end
end
