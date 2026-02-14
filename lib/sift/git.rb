# frozen_string_literal: true

require "open3"

module Sift
  class Git
    class Error < Sift::Error; end

    # Does this branch/ref exist?
    def branch_exists?(name)
      _, _, status = Open3.capture3("git", "rev-parse", "--verify", name)
      status.success?
    end

    # Create a worktree at path, on a new branch forked from start_point.
    def add_worktree(branch:, path:, start_point:)
      run("worktree", "add", "-b", branch, path, start_point)
    end

    # Is this path a valid git worktree?
    def worktree_valid?(path)
      _, _, status = Open3.capture3("git", "-C", path, "rev-parse", "--git-dir")
      status.success?
    end

    # Enable per-worktree config files (repo-wide, idempotent).
    def enable_worktree_config
      run("config", "extensions.worktreeConfig", "true")
    end

    # Set a config value scoped to a specific worktree.
    def set_worktree_config(worktree_path, key, value)
      run("-C", worktree_path, "config", "--worktree", key, value)
    end

    # Does branch have commits not present in base?
    def has_commits_beyond?(branch, base)
      out, _, status = Open3.capture3("git", "rev-list", "--count", "#{base}..#{branch}")
      status.success? && out.strip.to_i > 0
    end

    # Return diff between base and branch.
    def diff(base, branch)
      run("diff", "#{base}..#{branch}")
    end

    private

    def run(*args)
      out, err, status = Open3.capture3("git", *args)
      raise Error, "git #{args.first} failed: #{err.strip}" unless status.success?
      out
    end
  end
end
