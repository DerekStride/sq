---
name: sq-task-tracking
description: Generic guide for using the `sq` (Sift Queue) CLI as a task tracker across projects. Covers queue conventions, safe command patterns, collect-based queue seeding, and common add/list/show/edit/close workflows.
license: MIT
allowed-tools: Bash(sq:*)
---

# SQ Task Tracking

Use this skill when you are asked to manage tasks with the `sq` CLI.

## Default Convention

- Prefer an explicit queue path instead of relying on implicit defaults.
- Project convention: use `.sift/issues.jsonl` unless the user specifies otherwise.

## Preflight Checklist

Before writing (`add`, `collect`, `edit`, `close`, `rm`):

1. Confirm queue file path.
2. Use `--queue <path>` explicitly.
3. If needed, create parent dir (`.sift/`).
4. Avoid writing to unintended files like `.sift/queue.jsonl` by accident.

## Canonical Command Patterns

```bash
# Add one item
sq --queue .sift/issues.jsonl add --title "..." --description "..." --text "..."

# Collect many items from ripgrep results
rg --json PATTERN | sq --queue .sift/issues.jsonl collect --by-file

# List
sq --queue .sift/issues.jsonl list --status pending --json

# Show
sq --queue .sift/issues.jsonl show <id> --json

# Edit
sq --queue .sift/issues.jsonl edit <id> --set-status in_progress

# Close
sq --queue .sift/issues.jsonl close <id>
```

## Seeding a Queue from Search Results

A strong `sq` pattern is:

1. search for a repeated pattern in a repo
2. group matches by file
3. create one task per file
4. review and work the queue

Use:

```bash
rg --json -n -C2 'OldThing' | sq --queue .sift/issues.jsonl collect --by-file \
  --description 'Replace OldThing with NewThing'
```

Why this is useful:

- each file becomes its own task
- the task keeps a `file` source for the path
- the task keeps a `text` source with the exact matching snippets
- the resulting queue is easy to inspect with `sq list`, `sq show`, or `sift`

Recommended options:

```bash
# Add context around matches
rg --json -n -C2 'PATTERN' | sq --queue .sift/issues.jsonl collect --by-file

# Attach metadata to all created tasks
rg --json PATTERN | sq --queue .sift/issues.jsonl collect --by-file \
  --metadata '{"priority":"p2","taskType":"chore"}'

# Customize titles per file
rg --json PATTERN | sq --queue .sift/issues.jsonl collect --by-file \
  --title-template 'cleanup: {{filepath}}'
```

Important constraints:

- use `rg --json`
- plain-text `rg` output is not supported
- prefer `-n` and `-C` when you want richer context preserved in the created tasks

Default title template:

```text
{{match_count}}:{{filepath}}
```

Template variables:

- `{{filepath}}`
- `{{filename}}`
- `{{match_count}}`

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

Collect example:

```bash
rg --json -n -C2 'legacy_method' | sq --queue .sift/issues.jsonl collect --by-file \
  --description 'Migrate legacy_method to new_method' \
  --metadata '{"priority":"p1","taskType":"chore"}'
```

## Safety Rule

If a task operation was run without `--queue`, verify where it wrote and reconcile files immediately.
