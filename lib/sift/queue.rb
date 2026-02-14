# frozen_string_literal: true

require "json"
require "fileutils"
require "securerandom"
require "sift/log"

module Sift
  # Persistent queue for review items stored as JSONL
  class Queue
    class Error < Sift::Error; end

    DEFAULT_PATH = ".sift/queue.jsonl"

    # Source types for queue items
    VALID_SOURCE_TYPES = %w[diff file text directory].freeze

    # Valid status values
    VALID_STATUSES = %w[pending in_progress closed].freeze

    # Represents a source of content for review
    Source = Struct.new(:type, :path, :content, :session_id, keyword_init: true) do
      def to_h
        {
          type: type,
          path: path,
          content: content,
          session_id: session_id
        }.compact
      end

      def self.from_h(hash)
        new(
          type: hash["type"] || hash[:type],
          path: hash["path"] || hash[:path],
          content: hash["content"] || hash[:content],
          session_id: hash["session_id"] || hash[:session_id]
        )
      end
    end

    # Represents a worktree associated with a queue item
    Worktree = Struct.new(:path, :branch, keyword_init: true) do
      def to_h
        { path: path, branch: branch }.compact
      end

      def self.from_h(hash)
        return nil unless hash
        new(
          path: hash["path"] || hash[:path],
          branch: hash["branch"] || hash[:branch]
        )
      end
    end

    # Represents a queue item
    Item = Struct.new(:id, :title, :status, :sources, :metadata, :session_id, :worktree, :errors, :created_at, :updated_at, keyword_init: true) do
      def to_h
        h = {
          id: id,
          status: status,
          sources: sources.map(&:to_h),
          metadata: metadata,
          session_id: session_id,
          created_at: created_at,
          updated_at: updated_at,
        }
        h[:title] = title if title
        h[:worktree] = worktree.to_h if worktree
        h[:errors] = errors if errors && !errors.empty?
        h
      end

      def to_json(*args)
        to_h.to_json(*args)
      end

      def self.from_h(hash)
        sources = (hash["sources"] || hash[:sources] || []).map do |src|
          Source.from_h(src)
        end

        worktree_data = hash["worktree"] || hash[:worktree]

        new(
          id: hash["id"] || hash[:id],
          title: hash["title"] || hash[:title],
          status: hash["status"] || hash[:status],
          sources: sources,
          metadata: hash["metadata"] || hash[:metadata] || {},
          session_id: hash["session_id"] || hash[:session_id],
          worktree: Worktree.from_h(worktree_data),
          errors: hash["errors"] || hash[:errors] || [],
          created_at: hash["created_at"] || hash[:created_at],
          updated_at: hash["updated_at"] || hash[:updated_at]
        )
      end

      def pending?
        status == "pending"
      end

      def in_progress?
        status == "in_progress"
      end

      def closed?
        status == "closed"
      end
    end

    attr_reader :path

    def initialize(path)
      @path = path
    end

    # Add a new item to the queue
    # Returns the created Item
    def push(sources:, title: nil, metadata: {}, session_id: nil)
      validate_sources!(sources)

      with_exclusive_lock do |f|
        existing_ids = read_items(f).map(&:id).to_set

        now = Time.now.utc.iso8601(3)
        item = Item.new(
          id: generate_id(existing_ids),
          title: title,
          status: "pending",
          sources: normalize_sources(sources),
          metadata: metadata,
          session_id: session_id,
          created_at: now,
          updated_at: now
        )

        f.seek(0, IO::SEEK_END)
        f.puts(item.to_json)
        item
      end
    end

    # Iterate over pending items
    def each_pending(&block)
      filter(status: "pending").each(&block)
    end

    # Update an item by ID
    # Returns the updated Item or nil if not found
    def update(id, **attrs)
      with_exclusive_lock do |f|
        items = read_items(f)
        index = items.index { |item| item.id == id }
        return nil unless index

        item = items[index]

        # Validate status if provided
        if attrs[:status]
          status = attrs[:status].to_s
          unless VALID_STATUSES.include?(status)
            raise Error, "Invalid status: #{status}. Valid: #{VALID_STATUSES.join(", ")}"
          end
          attrs[:status] = status
        end

        # Update fields
        attrs[:updated_at] = Time.now.utc.iso8601(3)
        updated_item = Item.new(**item.to_h.merge(attrs))
        items[index] = updated_item

        rewrite_items(f, items)
        updated_item
      end
    end

    # Find an item by ID
    # Returns Item or nil
    def find(id)
      all.find { |item| item.id == id }
    end

    # Filter items by criteria
    # Returns array of Items
    def filter(status: nil)
      items = all
      items = items.select { |item| item.status == status.to_s } if status
      items
    end

    # Get all items
    # Returns array of Items
    # Skips corrupt/unparseable lines with a warning rather than failing
    def all
      with_shared_lock do |f|
        read_items(f)
      end
    end

    # Count items, optionally by status
    def count(status: nil)
      filter(status: status).size
    end

    # Remove an item by ID
    # Returns the removed Item or nil
    def remove(id)
      with_exclusive_lock do |f|
        items = read_items(f)
        removed = nil
        items.reject! do |item|
          if item.id == id
            removed = item
            true
          else
            false
          end
        end

        rewrite_items(f, items) if removed
        removed
      end
    end

    # Atomically claim a pending item by setting it to in_progress.
    # Returns the claimed Item, or nil if the item is not pending.
    # When a block is given, auto-releases back to pending after the block.
    def claim(id)
      item = with_exclusive_lock do |f|
        items = read_items(f)
        index = items.index { |i| i.id == id && i.pending? }
        return nil unless index

        updated = Item.new(**items[index].to_h.merge(
          status: "in_progress", updated_at: Time.now.utc.iso8601(3)
        ))
        items[index] = updated
        rewrite_items(f, items)
        updated
      end

      return item unless block_given?

      begin
        yield item
      ensure
        release(id)
      end
    end

    # Clear all items from the queue
    def clear
      with_exclusive_lock do |f|
        rewrite_items(f, [])
      end
    end

    private

    # Release an in_progress item back to pending.
    # No-ops if the status was changed externally (e.g. manually closed).
    def release(id)
      with_exclusive_lock do |f|
        items = read_items(f)
        index = items.index { |i| i.id == id && i.in_progress? }
        return nil unless index

        updated = Item.new(**items[index].to_h.merge(
          status: "pending", updated_at: Time.now.utc.iso8601(3)
        ))
        items[index] = updated
        rewrite_items(f, items)
        updated
      end
    end

    # Acquire an exclusive lock (LOCK_EX) on the queue file.
    # Creates the file if it doesn't exist. Blocks until lock is available.
    def with_exclusive_lock
      ensure_directory
      File.open(@path, File::RDWR | File::CREAT) do |f|
        f.flock(File::LOCK_EX)
        yield(f)
      end
    end

    # Acquire a shared lock (LOCK_SH) on the queue file.
    # Returns empty array via yield(nil) if file doesn't exist.
    def with_shared_lock
      unless File.exist?(@path)
        return yield(nil)
      end

      File.open(@path, "r") do |f|
        f.flock(File::LOCK_SH)
        yield(f)
      end
    end

    # Read items from an IO, skipping corrupt lines with warnings.
    def read_items(io)
      return [] if io.nil?

      io.rewind
      items = []
      io.each_line.with_index(1) do |line, line_num|
        next if line.strip.empty?

        begin
          data = JSON.parse(line)
          items << Item.from_h(data)
        rescue JSON::ParserError => e
          Sift::Log.warn("Skipping corrupt line #{line_num} in #{@path}: #{e.message}")
        end
      end
      items
    end

    # Truncate and rewrite all items to the file descriptor.
    def rewrite_items(f, items)
      f.rewind
      f.truncate(0)
      items.each do |item|
        f.puts(item.to_json)
      end
      f.flush
    end

    def generate_id(existing_ids)
      chars = ("a".."z").to_a + ("0".."9").to_a

      loop do
        id = 3.times.map { chars.sample }.join
        return id unless existing_ids.include?(id)
      end
    end

    def validate_sources!(sources)
      raise Error, "Sources cannot be empty" if sources.nil? || sources.empty?

      sources.each do |source|
        type = source[:type] || source["type"]
        unless VALID_SOURCE_TYPES.include?(type)
          raise Error, "Invalid source type: #{type}. Valid: #{VALID_SOURCE_TYPES.join(", ")}"
        end
      end
    end

    def normalize_sources(sources)
      sources.map do |source|
        if source.is_a?(Source)
          source
        else
          Source.from_h(source)
        end
      end
    end

    def ensure_directory
      dir = File.dirname(@path)
      FileUtils.mkdir_p(dir) unless File.directory?(dir)
    end
  end
end
