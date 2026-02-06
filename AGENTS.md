# Agent Instructions

## Project Overview

**Sift** is a queue-driven review system where humans make decisions and agents do the work. It inverts the typical agent CLI pattern: instead of agents driving with human oversight, humans drive decisions while agents provide analysis and execute tasks.

## Key Concepts

- **Queue**: JSONL-based work items (review, analysis, revision)
- **Review Loop**: TUI for human decisions (approve/reject/revise)
- **Sticky Sessions**: Agent conversations persist per item for revisions
- **Roast Integration**: Can orchestrate Roast workflows or use custom cogs

## Project Structure

```
lib/sift/
├── cli.rb           # Thor CLI entry point
├── review_loop.rb   # Main TUI flow
├── queue.rb         # JSONL queue management
├── client.rb        # Claude API wrapper
├── diff_parser.rb   # Git diff parsing
├── git_actions.rb   # Stage/revert operations
└── roast/           # Roast integration layer
```

## Design Documents

- `doc/specs/EXPLORATION.md` - Original design exploration and decisions

## Running Tests

```bash
bundle exec rake test
```

## Key Patterns

### Review Loop Flow

1. Load diff hunks
2. Display hunk (no Claude call yet)
3. Human decides: `a`ccept / `r`eject / `?` ask Claude
4. If `?`: Claude analyzes, show result, prompt again
5. Accept → stage hunk, Reject → revert hunk

### Roast Integration

1. **Wrapper**: Sift calls `Roast::Workflow.from_file` externally
2. **Custom Cog**: Roast workflows use `sift_output` cog to push results

## Issue Tracking

This project uses **bd** (beads) for issue tracking.

```bash
bd ready              # Find available work
bd show <id>          # View issue details
bd update <id> -s in_progress  # Claim work
bd close <id> -r "reason"      # Complete work
bd dep add <id> <blocker>      # Add dependency
```

