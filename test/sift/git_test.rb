# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Sift::GitTest < Minitest::Test
  def setup
    @original_dir = Dir.pwd
    @tmp_dir = Dir.mktmpdir("sift_git_test_")
    Dir.chdir(@tmp_dir)

    system("git init -q", exception: true)
    system("git config user.email 'test@test.com'", exception: true)
    system("git config user.name 'Test'", exception: true)
    File.write("README.md", "# Test\n")
    system("git add README.md && git commit -q -m 'init'", exception: true)

    @git = Sift::Git.new
  end

  def teardown
    Dir.chdir(@original_dir)
    FileUtils.rm_rf(@tmp_dir)
  end

  # --- has_commits_beyond? ---

  def test_has_commits_beyond_false_same_ref
    refute @git.has_commits_beyond?("main", "main")
  end

  def test_has_commits_beyond_true_with_commits
    system("git checkout -q -b feature", exception: true)
    File.write("a.txt", "a\n")
    system("git add a.txt && git commit -q -m 'add a'", exception: true)

    assert @git.has_commits_beyond?("feature", "main")
  end

  def test_has_commits_beyond_false_no_commits
    system("git checkout -q -b feature", exception: true)

    refute @git.has_commits_beyond?("feature", "main")
  end

  def test_has_commits_beyond_false_nonexistent_branch
    refute @git.has_commits_beyond?("nonexistent", "main")
  end

  # --- diff ---

  def test_diff_returns_content
    system("git checkout -q -b feature", exception: true)
    File.write("a.txt", "hello\n")
    system("git add a.txt && git commit -q -m 'add a'", exception: true)

    diff = @git.diff("main", "feature")

    assert_includes diff, "a.txt"
    assert_includes diff, "+hello"
  end

  def test_diff_empty_when_no_changes
    system("git checkout -q -b feature", exception: true)

    assert_equal "", @git.diff("main", "feature").strip
  end

  def test_diff_raises_on_invalid_branch
    assert_raises(Sift::Git::Error) { @git.diff("main", "nonexistent") }
  end
end
