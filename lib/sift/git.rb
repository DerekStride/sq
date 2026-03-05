# frozen_string_literal: true

require "open3"

module Sift
  class Git
    class Error < Sift::Error; end

    # Does this branch/ref exist?
    def branch_exists?(name)
      _, _, status = run_capture("git", "rev-parse", "--verify", name)
      status.success?
    end

    # Create a worktree at path, on a new branch forked from start_point.
    def add_worktree(branch:, path:, start_point:)
      run("worktree", "add", "-b", branch, path, start_point)
    end

    # Is this path a valid git worktree?
    def worktree_valid?(path)
      _, _, status = run_capture("git", "-C", path, "rev-parse", "--git-dir")
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

    # Return the path to .git/info/exclude (from the common git dir).
    def info_exclude_path
      out, _, status = run_capture("git", "rev-parse", "--git-common-dir")
      raise Error, "git rev-parse --git-common-dir failed" unless status.success?
      File.join(out.strip, "info", "exclude")
    end

    # Does branch have commits not present in base?
    def has_commits_beyond?(branch, base)
      out, _, status = run_capture("git", "rev-list", "--count", "#{base}..#{branch}")
      status.success? && out.strip.to_i > 0
    end

    # Return diff between base and branch.
    def diff(base, branch)
      run("diff", "#{base}..#{branch}")
    end

    # Does the worktree working tree differ from base? (includes uncommitted changes)
    def worktree_dirty?(worktree_path, base)
      _, _, status = run_capture("git", "-C", worktree_path, "diff", "--quiet", base)
      !status.success?
    end

    # Return diff of worktree working tree against base (committed + uncommitted changes).
    def worktree_diff(worktree_path, base)
      out, err, status = run_capture("git", "-C", worktree_path, "diff", base)
      raise Error, "git diff failed: #{err.strip}" unless status.success?
      out
    end

    private

    def run(*args)
      out, err, status = run_capture("git", *args)
      raise Error, "git #{args.first} failed: #{err.strip}" unless status.success?
      out
    end

    # Use popen3 directly instead of Open3.capture3 to avoid known
    # Ruby 3.4 capture3 crashes under concurrent/signal-heavy workloads.
    def run_capture(*argv)
      stdout_data = ""
      stderr_data = ""
      status = nil

      Open3.popen3(*argv) do |stdin, stdout, stderr, wait_thread|
        stdin.close

        out_reader = Thread.new { stdout.read }
        err_reader = Thread.new { stderr.read }

        stdout_data = out_reader.value
        stderr_data = err_reader.value
        status = wait_thread.value
      end

      [stdout_data, stderr_data, status]
    end
  end
end
