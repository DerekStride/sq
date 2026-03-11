# sq

`sq` is the queue CLI for Sift.

It manages queue items in a JSONL file used by the Sift review loop.

## Build / Run

From repository root:

```bash
cargo run --manifest-path sq/Cargo.toml -- --help
```

Or from `sq/`:

```bash
cargo run -- --help
```

## Queue path

By default, `sq` resolves the queue path from Sift defaults.

You can override it with:

- `-q, --queue <PATH>`
- `SIFT_QUEUE_PATH=<PATH>`

## Commands

- `sq add` — create an item
- `sq collect` — collect many items from stdin
- `sq list` — list items
- `sq show <id>` — show item details
- `sq edit <id>` — edit item fields/sources
- `sq close <id>` — mark item as closed
- `sq rm <id>` — remove item
- `sq prime` — output workflow context for AI agents

Use `sq <command> --help` for full options.

## Common examples

```bash
# Add item with source text
sq add --text "Review this"

# Add source-less task item
sq add --title "Refactor parser" --description "Split command logic"

# Add item with metadata
sq add --metadata '{"pi_tasks":{"priority":"high"}}'

# Collect one item per file from ripgrep JSON
rg --json PATTERN | sq collect --by-file

# Add shared description to every created item
rg --json -n -C2 PATTERN | sq collect --by-file --description "Migrate PATTERN to Y"

# Template titles using filepath / filename / match_count
rg --json PATTERN | sq collect --by-file --title-template 'migrate: {{filepath}}'

# List open items (default excludes closed)
sq list

# Include closed too
sq list --all

# Machine-readable output
sq add --text "X" --json
sq edit abc --set-status closed --json
sq rm abc --json
rg --json PATTERN | sq collect --by-file --json

# Merge metadata patch
sq edit abc --merge-metadata '{"pi_tasks":{"priority":"low"}}'

# Close item quickly
sq close abc
```

## `sq collect --by-file`

`sq collect --by-file` reads piped stdin and creates one queue item per file.

### Supported input

Currently supported in v1:

- `rg --json`

Plain-text `rg` output is not supported yet.

### Item shape

Each created item gets:

1. a `file` source for the filepath
2. a `text` source with collected match/context lines

If no title is provided, the default title template is `{{match_count}}:{{filepath}}`.

### Supported flags

- `--title`
- `--description`
- `--title-template`
- `--metadata`
- `--blocked-by`
- `--json`

### Title template variables

- `{{filepath}}`
- `{{filename}}`
- `{{match_count}}`

## Status values

Current statuses:

- `pending`
- `in_progress`
- `closed`

Set explicit status via:

```bash
sq edit <id> --set-status <pending|in_progress|closed>
```

Or use convenience close command:

```bash
sq close <id>
```

## Development

```bash
cargo test
```
