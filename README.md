# sq

`sq` is a queue CLI and queue-native task/review substrate.

It manages review and task items in a JSONL queue file. You can use it directly from the shell, from agents, or as the queue layer for tools like `sift`.

## Install `sq` skills in Pi / Claude

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

### Cargo

```bash
cargo install sift-queue
```

## Build / Run

From repository root:

```bash
cargo run -- --help
```

## Queue path

By default, `sq` uses:

- `.sift/queue.jsonl`

You can override it with:

- `-q, --queue <PATH>`
- `SQ_QUEUE_PATH=<PATH>`
- `SIFT_QUEUE_PATH=<PATH>` (legacy compatibility)

## Commands

- `sq add` — create a single item
- `sq collect` — create many items from piped stdin
- `sq list` — list items
- `sq show <id>` — show item details
- `sq edit <id>` — edit item fields/sources
- `sq close <id>` — mark item as closed
- `sq rm <id>` — remove item
- `sq prime` — output queue workflow context for AI agents

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

# Include line numbers and surrounding context in each collected text source
rg --json -n -C2 PATTERN | sq collect --by-file

# Add shared description to every created item
rg --json -n -C2 PATTERN | sq collect --by-file \
  --description "Migrate PATTERN to Y"

# Template titles using filepath / filename / match_count
rg --json PATTERN | sq collect --by-file \
  --title-template 'migrate: {{filepath}}'

# Attach shared metadata while collecting
rg --json PATTERN | sq collect --by-file \
  --metadata '{"campaign":"pattern-removal","priority":"p2"}'

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

`sq collect --by-file` is the bulk-ingestion workflow for turning search results into queue items.

A common pattern is:

1. search the codebase with `rg --json`
2. group results by file
3. create one queue item per file
4. review or process that queue with your preferred workflow

Example:

```bash
rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --description "Migrate OldApi.call to NewApi.call"
```

### Supported input

Currently supported:

- `rg --json`

Plain-text `rg` output is not supported.

If you want surrounding context in each created `text` source, pass ripgrep context flags such as:

- `-n` for line numbers
- `-C2` for two lines of context
- `-A2` / `-B2` for after / before context

### What each collected item contains

For each file group, `sq collect --by-file` creates:

1. a `file` source for the filepath
2. a `text` source containing the grouped ripgrep match/context lines

This makes the queue item easy to inspect later:

- the `file` source points at the file
- the `text` source preserves the specific matches that caused the item to be created

### Shared flags

These flags apply to every created item:

- `--title`
- `--description`
- `--title-template`
- `--metadata`
- `--blocked-by`
- `--json`

### Title behavior

If you do not provide `--title` or `--title-template`, the default title template is:

```text
{{match_count}}:{{filepath}}
```

That keeps bulk-created queues scannable in `sq list`.

Examples:

```bash
# Static title for every item
rg --json PATTERN | sq collect --by-file --title "Pattern cleanup"

# Templated titles per file
rg --json PATTERN | sq collect --by-file \
  --title-template 'cleanup: {{filename}} ({{match_count}} matches)'
```

### Title template variables

Available in `--title-template`:

- `{{filepath}}` — full grouped file path
- `{{filename}}` — basename of `{{filepath}}`
- `{{match_count}}` — number of ripgrep `match` events collected for that file

### Suggested migration / cleanup workflow

When you want to build a queue from repeated occurrences across a codebase:

```bash
rg --json -n -C2 'OldThing' | sq collect --by-file \
  --description 'Replace OldThing with NewThing' \
  --metadata '{"kind":"migration"}'

sq list
sq show <id>
```

This is especially useful for:

- migrations
- API renames
- deprecations
- TODO / FIXME sweeps
- repeated code smell cleanup

## Optional integration with `sift`

`sq` is useful on its own, but it also works well as the queue layer for `sift`.

A common pairing is:

```bash
sq add --text "Investigate flaky spec"
sift
```

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
