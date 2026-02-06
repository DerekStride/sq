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

## Quick Start

```bash
bundle install

# Review git diffs interactively
bin/sift review ~/project --base HEAD~3

# Manage queue
bin/sift queue list
bin/sift queue add '{"type":"review","file":"foo.rb"}'
```

## TUI Hotkeys

| Key | Action |
|-----|--------|
| `a` | Accept (stages hunk) |
| `r` | Reject (reverts hunk) |
| `c` | Add comment |
| `?` | Ask Claude for analysis |
| `v` | Revise analysis with feedback |
| `q` | Quit |

## Architecture

```
lib/sift/
├── cli.rb           # Thor CLI
├── cli/queue.rb     # Queue subcommands
├── client.rb        # Claude API wrapper
├── diff_parser.rb   # Git diff → hunks
├── git_actions.rb   # Stage/revert hunks
├── queue.rb         # JSONL queue
├── review_loop.rb   # TUI review flow
└── roast/           # Roast integration
    ├── orchestrator.rb
    └── cogs/
        └── sift_output.rb
```

## Roast Integration

Sift can orchestrate [Roast](https://github.com/Shopify/roast) workflows:

```ruby
# Wrapper approach - Sift calls Roast externally
orchestrator = Sift::Roast::Orchestrator.new
orchestrator.run("analyze.rb", targets: [file])

# Custom cog approach - Roast workflows push to Sift
use [:sift_output], from: "sift/roast/cogs/sift_output"
execute do
  agent(:analyze) { target! }
  sift_output(:result) { agent!(:analyze).response }
end
```

## Development

```bash
bundle exec rake test
```

## Status

Early prototype. See `doc/specs/EXPLORATION.md` for design notes.
