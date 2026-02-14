# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"
require "support/fake_git"

class Sift::WorktreeTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @tmp_dir = Dir.mktmpdir("sift_wt_test_")
    Dir.chdir(@tmp_dir)
    @fake_git = FakeGit.new
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmp_dir)
  end

  # --- create ---

  def test_create_returns_worktree_struct
    wt = Sift::Worktree.create("abc", base_branch: "main", git: @fake_git)

    assert_instance_of Sift::Queue::Worktree, wt
    assert_equal ".sift/worktrees/abc", wt.path
    assert_equal "sift/abc", wt.branch
  end

  def test_create_calls_add_worktree_with_correct_args
    Sift::Worktree.create("abc", base_branch: "main", git: @fake_git)

    assert_equal 1, @fake_git.worktrees_added.size
    added = @fake_git.worktrees_added.first
    assert_equal "sift/abc", added[:branch]
    assert_equal ".sift/worktrees/abc", added[:path]
    assert_equal "main", added[:start_point]
  end

  def test_create_is_idempotent
    # First call creates the worktree
    Sift::Worktree.create("abc", base_branch: "main", git: @fake_git)

    # Second call should skip add_worktree since dir already exists
    wt = Sift::Worktree.create("abc", base_branch: "main", git: @fake_git)

    assert_equal 1, @fake_git.worktrees_added.size
    assert_equal ".sift/worktrees/abc", wt.path
    assert_equal "sift/abc", wt.branch
  end

  def test_create_raises_on_missing_base_branch
    fake = FakeGit.new(branch_exists: false)

    error = assert_raises(Sift::Worktree::Error) do
      Sift::Worktree.create("abc", base_branch: "nonexistent", git: fake)
    end

    assert_includes error.message, "Base branch not found"
    assert_empty fake.worktrees_added
  end

  def test_create_installs_hook
    Sift::Worktree.create("abc", base_branch: "main", git: @fake_git)

    hook_path = ".sift/worktrees/abc/.sift-hooks/commit-msg"
    assert File.exist?(hook_path), "hook script should exist"
    assert File.executable?(hook_path), "hook script should be executable"
  end

  def test_create_runs_setup_command_in_worktree_dir
    Sift::Worktree.create("abc", base_branch: "main", setup_command: "touch .setup-done", git: @fake_git)

    assert File.exist?(".sift/worktrees/abc/.setup-done"), "setup command should run in worktree dir"
  end

  def test_create_warns_on_setup_command_failure
    output = capture_io do
      with_log_level("WARN") do
        Sift::Worktree.create("abc", base_branch: "main", setup_command: "false", git: @fake_git)
      end
    end

    assert_match(/setup command failed/i, output[1])
  end

  # --- install_hook ---

  def test_install_hook_creates_executable_script
    wt_path = File.join(@tmp_dir, "worktree")
    FileUtils.mkdir_p(wt_path)

    Sift::Worktree.install_hook(wt_path, "abc", git: @fake_git)

    hook_path = File.join(wt_path, ".sift-hooks", "commit-msg")
    assert File.exist?(hook_path), "hook script should exist"
    assert File.executable?(hook_path), "hook script should be executable"
  end

  def test_install_hook_script_content
    wt_path = File.join(@tmp_dir, "worktree")
    FileUtils.mkdir_p(wt_path)

    Sift::Worktree.install_hook(wt_path, "abc", git: @fake_git)

    content = File.read(File.join(wt_path, ".sift-hooks", "commit-msg"))
    assert_includes content, "#!/bin/sh"
    assert_includes content, "git interpret-trailers"
    assert_includes content, "Sift-Item: abc"
  end

  def test_install_hook_sets_worktree_config
    wt_path = File.join(@tmp_dir, "worktree")
    FileUtils.mkdir_p(wt_path)

    Sift::Worktree.install_hook(wt_path, "abc", git: @fake_git)

    config = @fake_git.configs_set.find { |c| c[:key] == "core.hooksPath" }
    assert config, "should set core.hooksPath config"
    assert_equal wt_path, config[:path]
    assert_equal ".sift-hooks", config[:value]
  end

  # --- exists? ---

  def test_exists_returns_false_when_dir_does_not_exist
    refute Sift::Worktree.exists?("nope", git: @fake_git)
  end

  def test_exists_returns_true_when_dir_exists_and_worktree_valid
    FileUtils.mkdir_p(".sift/worktrees/abc")

    assert Sift::Worktree.exists?("abc", git: @fake_git)
  end

  # --- path_for ---

  def test_path_for_returns_path_when_worktree_exists
    FileUtils.mkdir_p(".sift/worktrees/abc")

    assert_equal ".sift/worktrees/abc", Sift::Worktree.path_for("abc", git: @fake_git)
  end

  def test_path_for_returns_nil_when_worktree_does_not_exist
    assert_nil Sift::Worktree.path_for("nope", git: @fake_git)
  end
end
