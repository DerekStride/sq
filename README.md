# sq

`sq` is a queue CLI and queue-native task/review substrate.

It manages review and task items in a JSONL queue file. You can use it directly from the shell or instruct agents to manage it for you.

If you're coming from [Beads](https://github.com/steveyegge/beads), see [sq vs. Beads](doc/sq-vs-beads.md) for a comparison of the two tools and the trade-offs `sq` makes in favour of simplicity.

## Installation

```bash
cargo install sift-queue
```

## Install `sq` agent skills

You can install this repo as a plugin source to get the `sq` skills.

### Pi

```bash
pi install https://github.com/DerekStride/sq
```

### Claude

```bash
claude plugin marketplace add https://github.com/DerekStride/sq
claude plugin install sq
```

## Usage

### Queue path

By default, `sq` uses `.sift/queue.jsonl`. You can override it with:

- `-q, --queue <PATH>`
- `SQ_QUEUE_PATH=<PATH>`

### Commands

- `sq add` — create a single item
- `sq collect` — create many items from piped stdin
- `sq list` — list items
- `sq show <id>` — show item details
- `sq edit <id>` — edit item fields/sources
- `sq close <id>` — mark item as closed
- `sq rm <id>` — remove item
- `sq prime` — output queue workflow context for AI agents

Use `sq --help` for a full list of options.

### Examples

```bash
# Add item with source text
sq add --text "Review this"

# Add source-less task item
sq add --title "Refactor parser" --description "Split command logic"

# Add item with metadata
sq add --metadata '{"pi_tasks":{"priority":"high"}}'

# Collect one item per file from ripgrep JSON
rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --description "Migrate OldApi.call to NewApi.call"

# Machine-readable output
sq add --text "X" --json
sq edit abc --set-status closed --json
rg --json PATTERN | sq collect --by-file --json

# Merge metadata patch
sq edit abc --merge-metadata '{"pi_tasks":{"priority":"low"}}'

# Mark item as closed
sq close abc
```

## `sq collect --by-file`

`sq collect --by-file` is the bulk-ingestion command for turning search results into queue items. It reads `rg --json` output from stdin, groups results by file, and creates one queue item per file.

```bash
rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --description "Migrate OldApi.call to NewApi.call"
```

Plain-text `rg` output is not supported. Pass ripgrep context flags like `-n`, `-C2`, `-A2`, `-B2` to include line numbers and surrounding context in each created text source.

### What each collected item contains

For each file group, `sq collect --by-file` creates:

1. a `file` source for the filepath
2. a `text` source containing the grouped ripgrep match/context lines

### Title template variables

The default title template is `{{match_count}}:{{filepath}}`. Available variables in `--title-template`:

- `{{filepath}}` — full grouped file path
- `{{filename}}` — basename of `{{filepath}}`
- `{{match_count}}` — number of ripgrep `match` events collected for that file

## Development

```bash
# Build and run
cargo run -- --help

# Run all tests (unit + integration)
cargo test

# Run only integration tests
cargo test --test cli_integration
cargo test --test queue_parity
```
