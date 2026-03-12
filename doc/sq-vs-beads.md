# sq vs. Beads

`sq` and [Beads](https://github.com/steveyegge/beads) (`bd`) provide a persistent, structured way to track tasks and dependencies.

**TL;DR** — Use `sq` when you want a lightweight task list you can spin up instantly. It supports multi-agent workflows locally via file-level locking. Use Beads when you have multiple agents that need to collaborate across multiple machines.

## At a glance

| | **sq** | **Beads** |
|---|---|---|
| Sources | First-class (`--file`, `--diff`, `--text`, `--directory`) | Description blob |
| Storage | Single JSONL file | Dolt (version-controlled SQL database) |
| Bulk ingestion | `rg --json \| sq collect --by-file` | Manual or scripted |
| Multi-agent | File-level locking | Atomic claiming, cell-level merge, branch sync |
| Runtime deps | None | Dolt server |
| Hooks / side-effects | None | Pre-commit hook, `bd doctor`, `bd sync` |

## Intentional trade-offs

- **No database.** JSONL is less powerful than SQL but is human-readable, git-friendly, requires zero setup and no management of ongoing processes. For lists that fit in memory (most single-repo task lists), this is the right trade-off.

- **Minimal dependency tracking.** `sq` supports `--blocked-by` and `sq list --ready`, which is just enough for a "pick the next unblocked item" workflow. It does not model richer relationships between items.

- **Weaker agent coordination.** `sq` uses file-level locking rather than a database with atomic operations. This means multiple agents on the same machine can safely read and write the list, but `sq` does not try to solve distributed coordination across machines. For most single-agent and local multi-agent workflows, this is sufficient — and it means `sq` has no runtime dependencies, no sync protocol, and no merge conflicts to resolve.

## Where sq is stronger

### Source-driven items

Agents thrive on having the right amount of context. sq builds this in as a first-class primitive — every item can carry typed sources: files, directories, diffs, and inline text.

```bash
sq add --file src/parser.rs --diff /tmp/proposed.patch --text "Consider edge case on line 42"
```

The item itself contains or points to the context needed to act on it, rather than packing everything into a description string. In fact, the earliest version of sift didn't even have title or description fields — sources were the only thing an agent needed. Titles and descriptions were added later to improve the human experience, but for agents, structured sources are what matter.

This also makes integration straightforward. Adding a file source is a single flag; there's no need to inline content into a description or maintain a separate reference system.

### Bulk collection from search results

`sq collect --by-file` turns a ripgrep search directly into a task list — one item per file, with match context preserved as a text source and the filepath as a file source.

```bash
rg --json -n -C2 'OldApi.call' | sq collect --by-file \
  --description "Migrate to NewApi" \
  --metadata '{"kind":"migration"}'
```

### Zero-dependenies

`sq` is a single static binary that reads and writes a JSONL file.

### No side-effects

**`sq` does not install git hooks, modify your git config, modify your AGENTS.md, or run background processes.** It touches exactly one file and only when you ask it to. Beads' `bd sync` and pre-commit hook can interfere with workflows that don't expect them.

## Where Beads is stronger

### Multi-agent coordination

Beads is built for many agents working concurrently on the same repository. Atomic task claiming (`bd update --claim`), cell-level merge via Dolt, and deterministic hash-based IDs make it robust when multiple agents race to pick up work. `sq` uses file-level locking, which is safe for concurrent access on a single machine but does not extend to distributed coordination.

Most of Beads' additional complexity — the relationship graph, hierarchical IDs, role system — exists to support this multi-agent use case.
