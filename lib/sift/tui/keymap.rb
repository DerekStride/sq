# frozen_string_literal: true

module Sift
  module TUI
    module Keymap
      # Key binding definitions for each mode.
      # Each entry: [key, label, color]
      REVIEWING = [
        ["v", "view", "#56B6C2"],
        ["a", "agent", "#5B8DEF"],
        ["c", "close", "#98C379"],
        ["g", "general", "#C678DD"],
      ].freeze

      REVIEWING_NAV = [
        ["n", "next", "#E5C07B"],
        ["p", "prev", "#E5C07B"],
      ].freeze

      QUIT = [
        ["q", "quit", "#666666"],
      ].freeze

      WAITING = [
        ["g", "general", "#C678DD"],
        ["q", "quit", "#666666"],
      ].freeze

      SHUTTING_DOWN = [
        ["s", "stop agents", "#E06C75"],
        ["q", "force quit", "#666666"],
      ].freeze

      def self.render_action_bar(bindings)
        parts = bindings.map do |key, label, color|
          key_style = Lipgloss::Style.new.foreground(color).bold(true)
          "#{key_style.render(key)} #{label}"
        end
        parts.join("  ")
      end

      def self.reviewing_bar(show_nav: false)
        bindings = REVIEWING.dup
        bindings.concat(REVIEWING_NAV) if show_nav
        bindings.concat(QUIT)
        render_action_bar(bindings)
      end

      def self.waiting_bar
        render_action_bar(WAITING)
      end

      def self.shutting_down_bar
        render_action_bar(SHUTTING_DOWN)
      end
    end
  end
end
