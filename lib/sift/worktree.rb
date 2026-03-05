# frozen_string_literal: true

require "open3"
require "fileutils"

module Sift
  module Worktree
    class Error < Sift::Error; end

    WORKTREE_DIR = ".sift/worktrees"
    BRANCH_PREFIX = "sift"
    HOOKS_DIR_NAME = ".sift-hooks"

    class << self
      # Create a worktree for the given item, forked from base_branch.
      # Idempotent — returns existing struct if valid worktree already exists.
      def create(item_id, base_branch:, setup_command: nil, git: Git.new)
        wt_path = File.join(WORKTREE_DIR, item_id)
        branch = "#{BRANCH_PREFIX}/#{item_id}"

        if exists?(item_id, git: git)
          return Queue::Worktree.new(path: wt_path, branch: branch)
        end

        raise Error, "Base branch not found: #{base_branch}" unless git.branch_exists?(base_branch)

        git.add_worktree(branch: branch, path: wt_path, start_point: base_branch)

        install_hook(wt_path, item_id, git: git)

        run_setup_command(setup_command, wt_path) if setup_command

        Queue::Worktree.new(path: wt_path, branch: branch)
      end

      # Check if a valid worktree exists for the given item.
      def exists?(item_id, git: Git.new)
        wt_path = File.join(WORKTREE_DIR, item_id)
        return false unless Dir.exist?(wt_path)

        git.worktree_valid?(wt_path)
      end

      # Return the worktree path if it exists, nil otherwise.
      def path_for(item_id, git: Git.new)
        wt_path = File.join(WORKTREE_DIR, item_id)
        exists?(item_id, git: git) ? wt_path : nil
      end

      # Install a commit-msg hook that adds a Sift-Item trailer.
      # Sets per-worktree core.hooksPath via extensions.worktreeConfig.
      def install_hook(worktree_path, item_id, git: Git.new)
        hooks_dir = File.join(worktree_path, HOOKS_DIR_NAME)
        FileUtils.mkdir_p(hooks_dir)

        hook_path = File.join(hooks_dir, "commit-msg")
        File.write(hook_path, hook_script(item_id))
        File.chmod(0o755, hook_path)

        git.enable_worktree_config
        git.set_worktree_config(worktree_path, "core.hooksPath", HOOKS_DIR_NAME)

        add_to_git_exclude(HOOKS_DIR_NAME, git: git)
      end

      private

      # Ensure pattern is listed in .git/info/exclude (idempotent).
      def add_to_git_exclude(pattern, git: Git.new)
        exclude_path = git.info_exclude_path
        FileUtils.mkdir_p(File.dirname(exclude_path))

        existing = File.exist?(exclude_path) ? File.read(exclude_path) : ""
        return if existing.lines.any? { |line| line.strip == pattern }

        File.open(exclude_path, "a") do |f|
          f.puts unless existing.end_with?("\n") || existing.empty?
          f.puts(pattern)
        end
      end

      def run_setup_command(command, wt_path)
        stderr = ""
        status = nil

        Open3.popen3(command, chdir: wt_path) do |stdin, out_io, err_io, wait_thread|
          stdin.close

          out_reader = Thread.new { out_io.read }
          err_reader = Thread.new { err_io.read }

          out_reader.value
          stderr = err_reader.value
          status = wait_thread.value
        end

        unless status.success?
          Log.warn("Worktree setup command failed: #{stderr.strip}")
        end
      end

      def hook_script(item_id)
        <<~SH
          #!/bin/sh
          git interpret-trailers --in-place --trailer "Sift-Item: #{item_id}" "$1"
        SH
      end
    end
  end
end
