# Agent Instructions

## Project Overview

**Sift** is a queue-driven review system where humans make decisions and agents do the work. It inverts the typical agent CLI pattern: instead of agents driving with human oversight, humans drive decisions while agents provide analysis and execute tasks.

## Key Concepts

- **Queue**: JSONL-based work items with typed sources (diff, file, transcript, text)
- **Review Loop**: TUI where humans view items, spawn agents, close items, or ask general questions
- **Background Agents**: Run as Async fibers with semaphore-limited concurrency
- **Sticky Sessions**: Agent conversations persist per item via Claude session IDs
- **General Agents**: Free-form agents not tied to items — results become new queue items
- **System Prompts**: Customizable per-session or per-item agent behavior

## Project Structure

```
lib/sift/
├── cli.rb                  # CLI module
├── cli/
│   ├── base.rb             # Base command class (OptionParser, subcommand routing)
│   ├── help_renderer.rb    # gh-style help output
│   ├── sift_command.rb     # `sift` TUI entry point
│   ├── queue_command.rb    # `sq` root command dispatcher
│   └── queue/              # One class per sq subcommand (add, edit, list, show, rm)
├── review_loop.rb          # Main TUI flow with Async concurrency
├── queue.rb                # JSONL queue with file locking
├── client.rb               # Claude CLI wrapper with session support
├── agent_runner.rb         # Background agent management (Async + Semaphore)
└── log.rb                  # Logging with TUI-safe buffering
```

Other supporting modules (statusline, editor, session transcript parsing, etc.) live alongside these in `lib/sift/`. Explore the directory for the full picture.

## Running Tests

```bash
bundle exec rake test
```

## CLI Entry Points

Two executables in `exe/`:

- **`sift`** — Interactive review loop TUI. Run `sift --help` to see all options.
- **`sq`** — Queue management CLI. Add, list, show, edit, and remove queue items.

### `sq` Subcommands

```bash
sq add --text "Review this"             # Add item with text source
sq add --diff changes.patch             # Add item with diff source
sq add --stdin text < file.txt          # Add from stdin
sq add --system-prompt prompts/sec.md   # Per-item system prompt
sq list --status pending                # List/filter items
sq list --json                          # JSON output
sq show <id> --json                     # Show item details
sq edit <id> --set-status closed        # Modify item
sq rm <id>                              # Remove item
```

Run `sq --help` or `sq <command> --help` for full flag details.

### Adding a New Subcommand

Each subcommand is a `Sift::CLI::Base` subclass. The pattern:

```ruby
class Sift::CLI::Queue::MyCommand < Sift::CLI::Base
  command_name "mycommand"
  summary "One-line description"

  def define_flags(parser, options)
    parser.on("--flag VALUE", "Description") { |v| options[:flag] = v }
    super  # chains inherited flags from parent
  end

  def execute
    # Do work, return exit code (0 = success, 1 = error)
    0
  end
end
```

Register it in `lib/sift/cli/queue_command.rb`:
```ruby
register_subcommand Queue::MyCommand, category: :core
```

## Key Patterns

### Review Loop Flow

1. Load pending items from queue
2. Display item card (sources grouped by type)
3. Human chooses action: `v`iew / `a`gent / `c`lose / `g`eneral / `n`ext / `p`rev / `q`uit
4. If `a`gent: prompt for instruction → spawn background agent → continue reviewing
5. If `g`eneral: prompt for instruction → spawn free-form agent → result becomes new queue item
6. If `c`lose: mark item closed, advance to next
7. When agents finish: transcript appended as source, session_id stored for continuity
8. Loop exits when no pending items remain and no agents are running

### Agent Session Continuity

- First agent turn: all item sources are included in the prompt
- Subsequent turns: only the user prompt is sent (Claude `--resume` handles context)
- Session ID is stored on the queue item for future turns

### Async Concurrency

- `AgentRunner` manages background fibers gated by `Async::Semaphore`
- `ReviewLoop` polls for completed agents between user actions
- Non-blocking input loop ticks the statusline spinner while waiting for keystrokes
- `Log.quiet { ... }` buffers debug/info logs during input to prevent stderr corruption

### File Locking

- Queue uses `flock(LOCK_EX)` for writes, `flock(LOCK_SH)` for reads
- `claim(id)` atomically transitions pending → in_progress (with auto-release block form)
- Corrupt JSONL lines are skipped with a warning, not fatal

## Issue Tracking

This project uses **bd** (beads) for issue tracking.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> -s in_progress  # Claim work
bd close <id> -r "reason"      # Complete work
bd dep add <id> <blocker>      # Add dependency
```
