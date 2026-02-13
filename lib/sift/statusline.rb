# frozen_string_literal: true

require "cli/ui"
require "io/console"

module Sift
  # Persistent status bar pinned to the bottom of the terminal.
  #
  # Uses ANSI scroll regions to reserve the last terminal line for status
  # content. All normal output (puts, print) scrolls within the region
  # above, leaving the status bar untouched.
  #
  # Writes directly to IO.console to bypass CLI::UI::StdoutRouter,
  # which doesn't pass raw ANSI escape sequences cleanly.
  #
  # Call #tick periodically (~100ms) to advance the spinner glyph.
  # Read the current glyph with #spinner to embed it in your text.
  #
  class Statusline
    SPINNER_GLYPHS = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏].freeze
    TICK_INTERVAL = 0.1 # seconds between spinner frames

    def self.with(&block)
      sl = new
      sl.enable
      block.call(sl)
    ensure
      sl&.disable
    end

    def initialize
      @tty = IO.console
      @enabled = false
      @content = ""
      @spinner_index = 0
      @last_tick = Time.now
      @prev_winch = nil
    end

    def enable
      return if @enabled
      return unless @tty
      return unless $stdout.respond_to?(:tty?) && $stdout.tty?

      @enabled = true
      apply_scroll_region
      trap_resize
      render
    end

    def disable
      return unless @enabled

      @enabled = false
      restore_resize
      reset_scroll_region
    end

    # Update the status bar text and re-render.
    def update(text)
      @content = text.to_s
      render if @enabled
    end

    # Current spinner glyph. Embed this in your text where you want it.
    def spinner
      SPINNER_GLYPHS[@spinner_index]
    end

    # Advance the spinner frame. Returns true if the frame actually
    # advanced (enough time elapsed), false otherwise.
    def tick
      return false unless @enabled

      now = Time.now
      return false if (now - @last_tick) < TICK_INTERVAL

      @last_tick = now
      @spinner_index = (@spinner_index + 1) % SPINNER_GLYPHS.size
      true
    end

    private

    def height
      ::CLI::UI::Terminal.height
    end

    def width
      ::CLI::UI::Terminal.width
    end

    # Set scroll region to rows 1..(height-1), reserving the last line.
    def apply_scroll_region
      h = height
      @tty.print("\e[1;#{h - 1}r\e[#{h - 1};1H")
      @tty.flush
    end

    # Reset scroll region to full terminal.
    def reset_scroll_region
      h = height
      @tty.print("\e[r\e[#{h};1H\e[2K\e[#{h - 1};1H")
      @tty.flush
    end

    def render
      return unless @enabled

      formatted = @content.empty? ? "" : ::CLI::UI.fmt(@content)

      visible_len = ::CLI::UI::ANSI.printing_width(formatted)
      padding = [width - visible_len, 0].max
      padded = formatted + (" " * padding)

      # Single write to avoid interleaving with other terminal output.
      h = height
      @tty.print("\e[s\e[#{h};1H\e[7m#{padded}\e[27m\e[u")
      @tty.flush
    end

    def trap_resize
      @prev_winch = Signal.trap("WINCH") do
        # CLI::UI::Terminal already clears its cache on WINCH.
        # We just need to reapply the scroll region for the new size.
        apply_scroll_region if @enabled
        render if @enabled

        # Chain to previous handler if it was a Proc
        @prev_winch.call if @prev_winch.is_a?(Proc)
      end
    end

    def restore_resize
      if @prev_winch
        Signal.trap("WINCH", @prev_winch)
      else
        Signal.trap("WINCH", "DEFAULT")
      end
    end
  end
end
