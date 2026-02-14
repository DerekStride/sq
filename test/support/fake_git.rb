# frozen_string_literal: true

class FakeGit
  attr_reader :worktrees_added, :configs_set
  attr_accessor :fake_git_common_dir

  def initialize(branch_exists: true, has_commits: false, worktree_dirty: false, diff_output: "")
    @branch_exists = branch_exists
    @has_commits = has_commits
    @worktree_dirty = worktree_dirty
    @diff_output = diff_output
    @worktrees_added = []
    @configs_set = []
    @fake_git_common_dir = ".git"
  end

  def branch_exists?(_name)
    @branch_exists
  end

  def add_worktree(branch:, path:, start_point:)
    @worktrees_added << { branch: branch, path: path, start_point: start_point }
    FileUtils.mkdir_p(path)
  end

  def worktree_valid?(path)
    Dir.exist?(path)
  end

  def enable_worktree_config
    # no-op
  end

  def set_worktree_config(worktree_path, key, value)
    @configs_set << { path: worktree_path, key: key, value: value }
  end

  def info_exclude_path
    File.join(@fake_git_common_dir, "info", "exclude")
  end

  def has_commits_beyond?(_branch, _base)
    @has_commits
  end

  def worktree_dirty?(_path, _base)
    @worktree_dirty
  end

  def worktree_diff(_path, _base)
    @diff_output
  end

  def diff(_base, _branch)
    @diff_output
  end
end
