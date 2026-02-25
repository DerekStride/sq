# frozen_string_literal: true

# Extend Bubbletea with ExecCommand — like SuspendCommand but runs a callable
# instead of sending SIGTSTP. Properly releases the terminal (exits raw mode,
# stops input reader) so terminal editors can take over stdin.
module Bubbletea
  class ExecCommand < Command
    attr_reader :callable, :message

    def initialize(callable, message: nil)
      super()
      @callable = callable
      @message = message
    end
  end

  class << self
    def exec(callable, message: nil)
      ExecCommand.new(callable, message: message)
    end
  end

  class Runner
    private

    alias_method :original_process_command, :process_command
    alias_method :original_execute_command_sync, :execute_command_sync

    def process_command(command)
      case command
      when ExecCommand
        exec_process(command)
      else
        original_process_command(command)
      end
    end

    def execute_command_sync(command)
      case command
      when ExecCommand
        exec_process(command)
      else
        original_execute_command_sync(command)
      end
    end

    def exec_process(command)
      @program.show_cursor
      @program.stop_input_reader
      @program.exit_raw_mode

      command.callable.call

      @program.enter_raw_mode
      @program.hide_cursor
      @program.start_input_reader

      handle_message(command.message) if command.message
    end
  end
end
