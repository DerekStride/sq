# sq v0.7.0

`sq` v0.7.0 is a feature release focused on worktree-aware queue discovery, more flexible filtering, and a tighter priming flow.

## Highlights

- make implicit queue resolution work better across git worktrees
  - queue lookup now resolves relative to the active worktree instead of assuming a single repository root
  - this makes `sq` safer to use from linked worktrees without accidentally reading or writing the wrong queue
- improve filtering and priming ergonomics
  - `sq list` now supports repeatable `--status` filters for combining multiple states in one view
  - `sq prime` adds a `--prelude-only` flag for agent-facing setup without the full CLI wrapper output
- polish agent-facing guidance and release quality
  - prime output uses more direct wording around priority ordering
  - tests cover the new queue-path and filtering behavior more thoroughly

## Commits since v0.6.0

### feat

- `feat(prime): add prelude-only output flag`
- `feat(cli): allow repeating list status filter`

### fix

- `fix(prime): clarify priority ordering guidance`
- `fix(prime): use a more direct agent-facing tone`
- `fix(queue-path): resolve implicit queues via git worktrees`
