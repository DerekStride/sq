---
name: sq
description: Queue management CLI for task tracking and review workflows. Use when managing queue items, adding tasks, listing work, or integrating with sift review loops.
license: MIT
compatibility: Requires sq CLI. Install from https://github.com/shopify-playground/sift
allowed-tools: Bash(sq:*)
---

# sq — Queue CLI

`sq` manages items in a JSONL queue file. Items have typed sources (text, diff, file, directory), statuses, metadata, and dependency tracking.

## Queue Path

By default, `sq` resolves the queue path from Sift defaults. Override with:

- `-q, --queue <PATH>` flag
- `SIFT_QUEUE_PATH` environment variable

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
| `text` | `--text`, `--stdin text` | Free-form text |
| `diff` | `--diff`, `--stdin diff` | Patch/diff content |
| `file` | `--file`, `--stdin file` | File content |
| `directory` | `--directory`, `--stdin directory` | Directory listing |
| `transcript` | `--add-transcript` | Agent conversation transcript |

## Dependencies

Items can declare blockers via `--blocked-by`. Use `sq list --ready` to see only items that are pending and have no open blockers.
