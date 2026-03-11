---
name: sq
description: Queue management CLI for task tracking and review workflows. Use when managing queue items, collecting work from search results, listing queue state, or integrating with sift review loops.
license: MIT
compatibility: Requires sq CLI. Install from https://github.com/shopify-playground/sift
allowed-tools: Bash(sq:*)
---

# sq — Queue CLI

`sq` manages items in a JSONL queue file. Items have typed sources, statuses, metadata, and dependency tracking.

Use this skill when you need to:

- add or edit queue items directly
- inspect queue state
- build a queue from search results with `sq collect --by-file`
- prepare work for the `sift` review loop

## Queue Path

By default, `sq` resolves the queue path from Sift defaults. Override with:

- `-q, --queue <PATH>` flag
- `SIFT_QUEUE_PATH` environment variable

When operating on a project-specific queue, prefer an explicit queue path.

## Commands

### `sq add` — Add a new item

```bash
sq add --title "Review auth module" --text "Check for injection risks"
sq add --diff changes.patch --file src/auth.rb
sq add --stdin text < notes.txt
sq add --title "Blocked task" --blocked-by a1b,c3d
sq add --metadata '{"priority":"p0","taskType":"bug"}'
```

| Flag | Description |
|------|-------------|
| `--title TITLE` | Title for the item |
| `--description TEXT` | Description for the item |
| `--text STRING` | Add text source (repeatable) |
| `--diff PATH` | Add diff source (repeatable) |
| `--file PATH` | Add file source (repeatable) |
| `--directory PATH` | Add directory source (repeatable) |
| `--stdin TYPE` | Read source from stdin (`diff\|file\|text\|directory`) |
| `--metadata JSON` | Attach metadata as JSON |
| `--blocked-by IDS` | Comma-separated blocker IDs |
| `--json` | Output as JSON |

### `sq collect --by-file` — Build one queue item per file from ripgrep results

Use `collect` when you already have a stream of findings and want to turn them into a queue quickly.

Canonical pattern:

```bash
rg --json PATTERN | sq collect --by-file
```

Recommended variants:

```bash
# Include line numbers and context in each created text source
rg --json -n -C2 PATTERN | sq collect --by-file

# Add a shared description to every created item
rg --json -n -C2 PATTERN | sq collect --by-file \
  --description "Migrate PATTERN to Y"

# Add shared metadata
rg --json PATTERN | sq collect --by-file \
  --metadata '{"kind":"migration","priority":"p2"}'

# Customize titles per file
rg --json PATTERN | sq collect --by-file \
  --title-template 'migrate: {{filepath}}'
```

What `collect --by-file` does:

- reads piped stdin
- expects `rg --json` input
- groups results by file
- creates one queue item per file
- attaches:
  - a `file` source for the grouped file path
  - a `text` source containing the grouped match/context lines

Important constraints:

- plain-text `rg` output is not supported
- use `rg --json`
- use `-n`, `-C`, `-A`, or `-B` on `rg` when you want more useful context in the created `text` source

Supported shared flags:

- `--title`
- `--description`
- `--title-template`
- `--metadata`
- `--blocked-by`
- `--json`

Default title template:

```text
{{match_count}}:{{filepath}}
```

Template variables:

- `{{filepath}}`
- `{{filename}}`
- `{{match_count}}`

Good use cases:

- migration queues
- API rename sweeps
- deprecation cleanup
- TODO / FIXME triage
- turning repeated search matches into reviewable work

### `sq list` — List queue items

```bash
sq list                              # Pending + in_progress (default)
sq list --status pending             # Filter by status
sq list --ready                      # Pending and unblocked only
sq list --all                        # Include closed items
sq list --json                       # Machine-readable output
sq list --filter 'select(.p == 0)'   # jq select expression
sq list --sort .metadata.priority    # Sort by jq path
sq list --sort .created_at --reverse # Sort descending
```

| Flag | Description |
|------|-------------|
| `--status STATUS` | Filter: `pending\|in_progress\|closed` |
| `--all` | Include closed items |
| `--ready` | Pending + unblocked only |
| `--filter EXPR` | jq select expression |
| `--sort PATH` | jq path to sort by |
| `--reverse` | Reverse sort order |
| `--json` | Output as JSON |

### `sq show <id>` — Show item details

```bash
sq show abc123
sq show abc123 --json
```

### `sq edit <id>` — Edit an existing item

```bash
sq edit abc --set-status in_progress
sq edit abc --set-title "Updated title"
sq edit abc --add-text "Additional context"
sq edit abc --set-blocked-by a1b,c3d
sq edit abc --set-blocked-by ""           # Clear blockers
sq edit abc --merge-metadata '{"priority":"low"}'
sq edit abc --rm-source 0                 # Remove source by index
```

| Flag | Description |
|------|-------------|
| `--set-status STATUS` | Change status |
| `--set-title TITLE` | Set title |
| `--set-description TEXT` | Set description |
| `--add-text STRING` | Add text source |
| `--add-diff PATH` | Add diff source |
| `--add-file PATH` | Add file source |
| `--add-directory PATH` | Add directory source |
| `--add-transcript PATH` | Add transcript source |
| `--rm-source INDEX` | Remove source by 0-based index (repeatable) |
| `--set-metadata JSON` | Replace full metadata object |
| `--merge-metadata JSON` | Deep merge metadata |
| `--set-blocked-by IDS` | Set blocker IDs (comma-separated, empty to clear) |
| `--json` | Output as JSON |

### `sq close <id>` — Mark item as closed

```bash
sq close abc
sq close abc --json
```

### `sq rm <id>` — Remove item from queue

```bash
sq rm abc
sq rm abc --json
```

## Status Values

| Status | Meaning |
|--------|---------|
| `pending` | Waiting — may be blocked by other items |
| `in_progress` | Actively being worked |
| `closed` | Done or no longer needed |

## Item Sources

Items carry typed sources that provide context:

| Type | Added via | Description |
|------|-----------|-------------|
| `text` | `--text`, `--stdin text`, `collect --by-file` | Free-form text or collected ripgrep snippets |
| `diff` | `--diff`, `--stdin diff` | Patch/diff content |
| `file` | `--file`, `--stdin file`, `collect --by-file` | File path/context |
| `directory` | `--directory`, `--stdin directory` | Directory listing |
| `transcript` | `--add-transcript` | Agent conversation transcript |

## Dependencies

Items can declare blockers via `--blocked-by`. Use `sq list --ready` to see only items that are pending and have no open blockers.

## Suggested collect workflow

When a user wants to remove or migrate a repeated pattern across a codebase:

```bash
rg --json -n -C2 'OldThing' | sq collect --by-file \
  --description 'Replace OldThing with NewThing' \
  --metadata '{"kind":"migration"}'

sq list
sq show <id>
```

This gives a per-file review queue with both the file path and the specific matching snippets preserved.
