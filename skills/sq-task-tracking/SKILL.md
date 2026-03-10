---
name: sq-task-tracking
description: Generic guide for using the `sq` (Sift Queue) CLI as a task tracker across projects. Covers queue conventions, safe command patterns, and common add/list/show/edit/close workflows.
license: MIT
allowed-tools: Bash(sq:*)
---

# SQ Task Tracking

Use this skill when you are asked to manage tasks with the `sq` CLI.

## Default Convention

- Prefer an explicit queue path instead of relying on implicit defaults.
- Project convention: use `.sift/issues.jsonl` unless the user specifies otherwise.

## Preflight Checklist

Before writing (`add`, `edit`, `close`, `rm`):

1. Confirm queue file path.
2. Use `--queue <path>` explicitly.
3. If needed, create parent dir (`.sift/`).
4. Avoid writing to unintended files like `.sift/queue.jsonl` by accident.

## Canonical Command Patterns

```bash
# Add
sq --queue .sift/issues.jsonl add --title "..." --description "..." --text "..."

# List
sq --queue .sift/issues.jsonl list --status pending --json

# Show
sq --queue .sift/issues.jsonl show <id> --json

# Edit
sq --queue .sift/issues.jsonl edit <id> --set-status in_progress

# Close
sq --queue .sift/issues.jsonl close <id>
```

## Status Conventions

- `pending`: ready or blocked depending on `blocked_by`
- `in_progress`: actively being worked
- `closed`: done / no longer needed

## Recommended Metadata

Use metadata for machine-readable prioritization:

- `priority`: `p0..p4`
- `taskType`: `task | feature | bug | chore | epic`
- `dueAt`: ISO datetime string

Example:

```bash
sq --queue .sift/issues.jsonl add \
  --title "Migrate query helper" \
  --text "Refactor ..." \
  --metadata '{"priority":"p1","taskType":"feature"}' \
  --json
```

## Safety Rule

If a task operation was run without `--queue`, verify where it wrote and reconcile files immediately.
