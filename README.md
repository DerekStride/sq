# Sift

Queue-driven review system where humans make decisions and agents do the work.

## The Inversion

Traditional agent CLIs: agent drives, human occasionally intervenes.

**Sift inverts this**: human drives decisions, agents provide signal and execute.

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Human     │────▶│   Queue      │◀────│   Agents    │
│   (TUI)     │     │   (JSONL)    │     │   (bg)      │
└─────────────┘     └──────────────┘     └─────────────┘
```

The queue is the coordination mechanism. Humans review items, spawn agents for analysis, and close items when done. Agents run in the background and their results flow back as new sources on queue items — or as entirely new items.

## Quick Start

```bash
bundle install

# Add items to the queue
sq add --text "Review this change"
sq add --diff changes.patch --file main.rb
sq add --stdin text < notes.txt

# Launch the interactive review TUI
sift

# Or in dry mode (no API calls)
sift --dry
```

## TUI Actions

The core workflow in the review TUI:

- **View** (`v`) — open item sources in `$EDITOR` to read the full context
- **Agent** (`a`) — spawn a background agent for this item. You provide an instruction and the agent runs with the item's sources as context. When it finishes, the conversation transcript is appended to the item.
- **Close** (`c`) — mark the item as closed and move to the next one
- **General** (`g`) — spawn a free-form agent not tied to any item

When you press `a` or `g`, type your instruction inline or press `Ctrl+G` to compose in `$EDITOR`.

Run `sift --help` for all available options.

## How Agents Work

Agents run in the background. While an agent works on one item, you can continue reviewing others.

When an agent finishes, its conversation transcript is appended as a new source on the item. The agent's session ID is stored on the item, so subsequent agent invocations continue the same conversation — enabling multi-turn refinement.

**General agents** are useful for multiple use-cases including:

1. **Actioning insights during review** — when you notice something while reviewing, spawn a general agent to investigate. General agents are given the context to use `sq` themselves, so they can add new items to the queue for you to review.
2. **Exploring and explaining** — ask a general agent to research or explain something. When it finishes, the result shows up as a new queue item, and you can continue reviewing it like any other item.

## `sq` — Queue Management CLI

Manage the JSONL review queue from the command line.

```bash
sq add --text "Review this"                    # Add item with text
sq add --diff changes.patch --file main.rb     # Add with diff + file source
sq add --stdin text < file.txt                 # Add from stdin
sq add --system-prompt prompts/review.md       # Add with per-item system prompt
sq add --metadata '{"priority":"high"}'        # Add with metadata

sq list                                        # List all items
sq list --status pending                       # Filter by status
sq list --json                                 # JSON output

sq show <id>                                   # Show item details

sq edit <id> --set-status closed               # Modify item fields

sq rm <id>                                     # Remove item
```

Run `sq --help` or `sq <command> --help` for full flag details.

## Development

```bash
bundle exec rake test
```

Set `SIFT_LOG_LEVEL=DEBUG` for verbose logging.
