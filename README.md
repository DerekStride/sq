# sq

`sq` is a lightweight task-list CLI with structured sources.

It manages tasks in a JSONL file. You can use it directly from the shell or instruct agents to manage them for you.

If you're coming from [Beads](https://github.com/steveyegge/beads), see [sq vs. Beads](doc/sq-vs-beads.md) for a comparison of the two tools and the trade-offs `sq` makes in favour of simplicity.

## Installation

### Homebrew

```bash
brew install derekstride/tap/sift-queue
```

### Cargo

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

> [!NOTE]
> There's no queue! See the [FAQ](#faq) section to see the origin of the name.

By default, `sq` uses `.sift/issues.jsonl`. You can override it with:

- `-q, --queue <PATH>`
- `SQ_QUEUE_PATH=<PATH>`

### Commands

- `sq add` — create a single task
- `sq collect` — create many tasks from piped stdin
- `sq list` — list tasks
- `sq show <id>` — show task details
- `sq edit <id>` — edit task fields/sources
- `sq close <id>` — mark task as closed
- `sq rm <id>` — remove task
- `sq prime` — output `sq` workflow context for AI agents

Use `sq --help` for a full list of options.

### Examples

```bash
# Add task with title, description, priority, and pasted source text
sq add --title "Investigate checkout exception" \
  --description "Review the pasted error report and identify the failing code path" \
  --priority 1 \
  --text "Sentry alert: NoMethodError in Checkout::ApplyDiscount at app/services/checkout/apply_discount.rb:42"

# Add source-less task
sq add --title "Refactor parser" --description "Split command logic"

# Add task with metadata
sq add --title "Triage follow-up" --description "Review support escalation" \
  --metadata '{"pi_tasks":{"escalation":"support"}}'

# Collect one task per file from ripgrep JSON
rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --title-template "migrate: {{filepath}}" \
  --description "Migrate OldApi.call to NewApi.call"

# Machine-readable output
sq add --title "Summarize support escalation" \
  --description "Emit the created item as JSON for downstream tooling" \
  --text "Customer reports checkout fails when applying a discount code on mobile Safari" --json
sq edit abc --set-status closed --json
rg --json PATTERN | sq collect --by-file --title-template "review: {{filepath}}" \
  --description "Review ripgrep matches" --json

# Merge metadata patch
sq edit abc --merge-metadata '{"pi_tasks":{"type":"bug"},"owner":"derek"}'

# Mark task as closed
sq close abc
```

## `sq collect --by-file`

`sq collect --by-file` is the bulk-ingestion command for turning search results into tasks. It reads `rg --json` output from stdin, groups results by file, and creates one task per file.

```bash
rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --title-template "migrate: {{filepath}}" \
  --description "Migrate OldApi.call to NewApi.call"
```

Plain-text `rg` output is not supported. Pass ripgrep context flags like `-n`, `-C2`, `-A2`, `-B2` to include line numbers and surrounding context in each created text source.

### What each collected task contains

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

## FAQ

### Where's the queue?

The initial design was meant to manage a queue for [`sift`](https://github.com/derekstride/sift) a Human-in-the-loop review tool I was building. That model stopped making sense pretty quickly as the tool evolved. The current tool is better understood as a lightweight task list with structured sources, filtering, and dependency state.

The name stuck because it was short, memorable, and already embedded in the CLI (`sq`, `-q`, `--queue`). Keeping the name does not mean `sq` is trying to be a literal FIFO queue.
