# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "fileutils"

class Sift::Roast::Cogs::SiftOutputTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dir = create_temp_dir
    @queue_path = File.join(@temp_dir, "queue.jsonl")

    # Save and clear env var
    @original_env = ENV[Sift::Roast::QUEUE_PATH_ENV]
    ENV.delete(Sift::Roast::QUEUE_PATH_ENV)
  end

  def teardown
    # Restore env var
    if @original_env
      ENV[Sift::Roast::QUEUE_PATH_ENV] = @original_env
    else
      ENV.delete(Sift::Roast::QUEUE_PATH_ENV)
    end

    FileUtils.rm_rf(@temp_dir) if @temp_dir && File.exist?(@temp_dir)
  end

  def queue
    Sift::Queue.new(@queue_path)
  end

  # --- Successful push tests ---

  def test_pushes_to_queue_when_env_set
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    cog = Sift::Roast::Cogs::SiftOutput.new
    item_id = cog.call do |my|
      my.sources = [{ type: "text", content: "Hello from workflow" }]
      my.metadata = { workflow: "test", target: "file.rb" }
    end

    assert item_id
    assert_match(/\A[a-z0-9]{3}\z/, item_id)

    # Verify item in queue
    item = queue.find(item_id)
    assert item
    assert_equal "pending", item.status
    assert_equal 1, item.sources.length
    assert_equal "text", item.sources.first.type
    assert_equal "Hello from workflow", item.sources.first.content
    assert_equal "test", item.metadata["workflow"]
    assert_equal "file.rb", item.metadata["target"]
  end

  def test_pushes_with_session_id
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    cog = Sift::Roast::Cogs::SiftOutput.new
    item_id = cog.call do |my|
      my.sources = [{ type: "text", content: "test" }]
      my.session_id = "my-session-123"
    end

    item = queue.find(item_id)
    assert_equal "my-session-123", item.session_id
  end

  def test_pushes_with_multiple_sources
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    cog = Sift::Roast::Cogs::SiftOutput.new
    item_id = cog.call do |my|
      my.sources = [
        { type: "diff", content: "diff content" },
        { type: "text", content: "analysis" },
        { type: "file", path: "/code.rb" }
      ]
    end

    item = queue.find(item_id)
    assert_equal 3, item.sources.length
    assert_equal "diff", item.sources[0].type
    assert_equal "text", item.sources[1].type
    assert_equal "file", item.sources[2].type
  end

  def test_config_defaults
    config = Sift::Roast::Cogs::SiftOutput::Config.new

    assert_equal [], config.sources
    assert_equal({}, config.metadata)
    assert_nil config.session_id
  end

  # --- Error cases ---

  def test_raises_error_when_env_not_set
    # Env var is already deleted in setup

    cog = Sift::Roast::Cogs::SiftOutput.new

    error = assert_raises(Sift::Roast::Error) do
      cog.call do |my|
        my.sources = [{ type: "text", content: "test" }]
      end
    end

    assert_match(/SIFT_QUEUE_PATH/i, error.message)
    assert_match(/environment variable not set/i, error.message)
  end

  def test_raises_error_when_sources_empty
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    cog = Sift::Roast::Cogs::SiftOutput.new

    error = assert_raises(Sift::Roast::Error) do
      cog.call do |my|
        my.sources = []
      end
    end

    assert_match(/at least one source/i, error.message)
  end

  def test_raises_error_when_sources_nil
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    cog = Sift::Roast::Cogs::SiftOutput.new

    error = assert_raises(Sift::Roast::Error) do
      cog.call do |my|
        # Don't set sources, leaving it as nil
        my.metadata = { test: true }
      end
    end

    assert_match(/at least one source/i, error.message)
  end

  def test_raises_error_with_no_block
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    cog = Sift::Roast::Cogs::SiftOutput.new

    error = assert_raises(Sift::Roast::Error) do
      cog.call
    end

    # Without a block, config.sources stays empty, triggering the validation error
    assert_match(/at least one source/i, error.message)
  end

  # --- Module method tests ---

  def test_module_method_creates_and_caches_cog
    ENV[Sift::Roast::QUEUE_PATH_ENV] = @queue_path

    # Create a test object that includes the Cogs module
    test_obj = Object.new
    test_obj.extend(Sift::Roast::Cogs)

    item_id = test_obj.sift_output do |my|
      my.sources = [{ type: "text", content: "module method test" }]
    end

    assert item_id
    item = queue.find(item_id)
    assert_equal "module method test", item.sources.first.content
  end
end
