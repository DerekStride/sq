# frozen_string_literal: true

require "bubbletea"

module Sift
  module TUI
    # Tick-based agent polling trigger (fired every 500ms)
    class AgentPollMessage < Bubbletea::Message; end

    # Carries result from a completed agent
    class AgentCompletedMessage < Bubbletea::Message
      attr_reader :item_id, :data

      def initialize(item_id:, data:)
        super()
        @item_id = item_id
        @data = data
      end
    end

    # Clears the flash notification after a delay
    class FlashClearMessage < Bubbletea::Message; end

    # Worktree source refresh completed for an item
    class WorktreeRefreshedMessage < Bubbletea::Message
      attr_reader :item_id, :sources

      def initialize(item_id:, sources:)
        super()
        @item_id = item_id
        @sources = sources
      end
    end

    # Editor view completed — return to reviewing
    class ViewDoneMessage < Bubbletea::Message; end

    # Prompt editor completed — process editor text
    class PromptEditorDoneMessage < Bubbletea::Message; end
  end
end
