# Git Hooks Strategy

## Overview

Sift uses **per-worktree git hooks** to automatically tag commits with the queue item they belong to. Each worktree gets its own `commit-msg` hook that injects a `Sift-Item: <item_id>` trailer.

## How It Works

### Hook Installation

When a worktree is created for a queue item (`Worktree.create`):

1. A `.sift-hooks/` directory is created inside the worktree
2. A `commit-msg` hook is written that runs:
   ```sh
   git interpret-trailers --in-place --trailer "Sift-Item: <item_id>" "$1"
   ```
3. `extensions.worktreeConfig` is enabled on the repo
4. `core.hooksPath` is set **per-worktree** to `.sift-hooks`
5. `.sift-hooks` is added to `.git/info/exclude` (idempotent)

### Per-Worktree Config

Git's `extensions.worktreeConfig` (Git 2.20+) allows each worktree to have its own config overrides. Sift uses this to set `core.hooksPath` independently per worktree, so different worktrees can inject different item IDs without interfering with each other.

### Exclude Management

The `.sift-hooks` directory is excluded via `.git/info/exclude` rather than `.gitignore`. This avoids polluting the repo's tracked files. The exclude file lives at the git common directory level (`git rev-parse --git-common-dir`), so it covers all worktrees in a repo with a single entry.

## Why Per-Worktree, Not Global

We evaluated using a global hooks path (`~/.config/sift/githooks/`) but decided against it:

- **`core.hooksPath` is exclusive** — Git looks in exactly one hooks directory. Setting it globally would override `.git/hooks/` in every repo on the machine.
- **Breaks other tools** — The `pre-commit` Python framework refuses to install when a global `core.hooksPath` is set. Lefthook may install into the wrong directory.
- **Item-specific context** — Each hook needs the item ID baked in. A global hook would need to derive this dynamically from the worktree path, adding fragility.
- **Per-worktree config solves the multi-repo problem** — Each worktree independently sets its own `core.hooksPath`, scoped to that worktree only. Other repos and other worktrees are unaffected.

## Key Files

- `lib/sift/worktree.rb` — `install_hook`, `add_to_git_exclude`, `hook_script`
- `lib/sift/git.rb` — `enable_worktree_config`, `set_worktree_config`, `info_exclude_path`
- `test/sift/worktree_test.rb` — Tests for hook installation and exclude management
