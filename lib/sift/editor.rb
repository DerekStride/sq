# frozen_string_literal: true

require "shellwords"
require "tmpdir"

module Sift
  class Editor
    # GUI editors that need --wait to block the process
    WAIT_EDITORS = %w[code subl atom fleet zed].freeze

    # Terminal editors that support -p for tab-per-file
    TAB_EDITORS = %w[vi vim nvim].freeze

    def initialize(sources:, item_id:)
      @sources = sources
      @item_id = item_id
    end

    def open
      paths = collect_paths
      return if paths.empty?

      cmd = editor_command
      system(*cmd, *paths)
    end

    def resolve_editor
      ENV["EDITOR"] || ENV["VISUAL"] || "vi"
    end

    def editor_command
      editor = resolve_editor
      parts = Shellwords.split(editor)
      binary = ::File.basename(parts.first)
      if WAIT_EDITORS.include?(binary)
        parts << "--wait" unless parts.include?("--wait")
      elsif TAB_EDITORS.include?(binary)
        parts << "-p" unless parts.include?("-p")
      end
      parts
    end

    def collect_paths
      @sources.flat_map { |source| paths_for_source(source) }
    end

    private

    def paths_for_source(source)
      paths = []

      case source.type
      when "diff"
        paths << source.path if source.path && ::File.exist?(source.path)
        basename = source.path ? ::File.basename(source.path) : "changes"
        paths << write_temp(source.content || "", basename, ".diff")
      when "file"
        paths << source.path if source.path && ::File.exist?(source.path)
      when "text"
        paths << write_temp(source.content || "", @item_id, ".txt")
      when "transcript"
        basename = source.path ? ::File.basename(source.path) : @item_id
        paths << write_temp(source.content || "", basename, ".md")
      end

      paths
    end

    def write_temp(content, basename, ext)
      path = ::File.join(Dir.tmpdir, "sift-#{@item_id}-#{basename}#{ext}")
      ::File.write(path, content)
      path
    end
  end
end
