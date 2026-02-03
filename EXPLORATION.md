# Interactive Agent Review Loop - Exploration Notes

## Concept Evolution

Started with "iterate over items with human-in-the-loop" and evolved into something more specific: **a queue-driven review system where humans make decisions and agents do the work**.

### The Inversion

Current agent CLIs are good for exploration and implementation, but lack support for:
- **Repeatable tasks** where you want consistency
- **Tedious-but-important work** where full autonomy is risky

The key insight: **invert the control**. Instead of:
- Agent drives the loop, human occasionally intervenes

We want:
- **Human drives decisions**, agents provide signal and do work
- Script drives the loop, queue coordinates everything
- When an agent finishes, it becomes a queue item for human review

### Prior Art: Beads

[github.com/steveyegge/beads](https://github.com/steveyegge/beads) - similar queue concept but agent-driven:
- JSONL work items in `.beads/` directory
- Hash IDs for merge safety
- CLI for agents (`bd ready`, `bd create`, `bd show`)
- Agent picks tasks, works on them

**Our inversion**: Human picks what to work on, agents execute. Queue is the shared coordination mechanism.

---

## Refined Problem Statement

Build a tool where:
1. Work items live in a **JSONL queue**
2. **Human reviews** items one at a time
3. Human can **approve, reject, or revise** (with free-form feedback)
4. **Agents run in background**, results come back to queue
5. Agent sessions are **sticky to items** (can continue conversation)
6. Agents can **add new items** to the queue (e.g., "I made this change, review it")

---

## Motivating Example: Git Diff Review

The scenario that sparked this:
- Reviewing git diffs across many files
- Each diff needs context from related files
- Want to see: **the diff + supporting files + Claude's analysis**
- Actions: approve, skip, or "here's what I expected" → agent revises

Flow:
1. Queue has diff hunks as items
2. For each: show diff, related context, agent analysis
3. Human decides: approve / reject / revise
4. "Revise" → agent modifies the diff → new item in queue
5. Agent might discover more issues → adds to queue
6. Human reviews until queue empty

---

## Decisions Made

| Aspect | Decision | Rationale |
|--------|----------|-----------|
| **Queue storage** | JSONL file | Simple, git-friendly, readable, like Beads |
| **Workflow format** | Ruby DSL | Full power, familiar from Roast |
| **Agent model** | One agent per item (sticky sessions) | Enables "no, try this instead" conversation |
| **Parallelism** | Background parallel | Agents work while human reviews |
| **Queue persistence** | Persist queue across sessions | Can pause and resume |
| **Revision input** | Chat prompt + Ctrl+G for $EDITOR | Quick feedback inline, complex in editor |
| **Primary view** | Minimal - current item only | Queue count in corner, drill down on demand |
| **Empty queue** | Wait/block | Show "waiting..." until agents return |
| **Errors** | Item goes to 'failed' state | Human can retry or dismiss |

---

## Queue Item Model

```json
{
  "id": "abc123",
  "type": "review",
  "status": "pending",
  "payload": { ... },
  "session_id": null,
  "created_at": "2026-02-03T10:00:00Z",
  "updated_at": "2026-02-03T10:00:00Z"
}
```

Status values:
- `pending` - waiting for human review
- `in_progress` - agent working on it
- `approved` - human approved
- `rejected` - human rejected
- `failed` - agent errored

Session stickiness: `session_id` stores the agent session for continuity.

---

## Workflow DSL Sketch

```ruby
# workflow.rb

config do
  queue_file "queue.jsonl"

  agent do
    model "claude-sonnet-4-5-20250929"
    sticky_sessions!  # default: sessions persist per item
  end
end

# Define how to generate initial items
source do
  # Could be anything: git diff, file list, API call, etc.
  `git diff --name-only`.lines.map(&:chomp)
end

# Define what context to show for each item
context do |item|
  {
    file: item,
    diff: `git diff #{item}`,
    related: find_related_files(item)  # custom logic
  }
end

# Define the analysis prompt
analyze do |item, ctx|
  template("analyze", item: item, context: ctx)
end

# Define what "approve" does (optional)
on_approve do |item, response|
  # e.g., stage the file, write to log, etc.
  `git add #{item[:file]}`
end

# Define what "revise" does
on_revise do |item, feedback, session|
  # Returns new prompt for agent, continues session
  template("revise", item: item, feedback: feedback)
end
```

---

## TUI Sketch

```
┌─ Review Queue ──────────────────────────── 3 pending ─┐
│                                                       │
│  file: src/auth/login.rb                              │
│                                                       │
│  ─────────────────────────────────────────────────    │
│  Claude's Analysis:                                   │
│                                                       │
│  This change removes null checking on the user        │
│  object. This could cause a NullPointerException      │
│  if the user lookup fails. Consider adding...         │
│                                                       │
│  ─────────────────────────────────────────────────    │
│                                                       │
│  [a]pprove  [r]eject  [c]ustom  [d]iff  [t]ranscript │
│                                                       │
│  > _                                                  │
└───────────────────────────────────────────────────────┘
```

Hotkeys:
- `a` - approve, move to next
- `r` - reject, move to next
- `c` or just start typing - enter revision feedback
- `Ctrl+G` - open $EDITOR for complex feedback
- `d` - drill down to see full diff
- `t` - view full agent transcript
- `q` - quit (queue persists)

---

## Agent Capabilities

Agents need skills/tools to:
1. **Read the queue** - understand what they're working on
2. **Add to queue** - "I found another issue, adding it"
3. **Report completion** - "I'm done, here's the result"

Could be implemented as:
- Custom tools in the workflow
- Default skills loaded into all agents
- CLI commands the agent can run (`queue add ...`)

---

## Claude CLI Session Mechanics

Verified through testing:

### Key Flags
```bash
--resume <session-id>   # Resume by UUID
--fork-session          # Branch off (new ID, keeps context)
--session-id <uuid>     # Use specific UUID
-c, --continue          # Continue most recent
```

### Getting Session ID
```bash
result=$(echo "prompt" | claude -p --output-format json)
session=$(echo "$result" | jq -r '.session_id')
```

### Session Continuity
```bash
# Create
result=$(echo "Remember: 42" | claude -p --output-format json)
session=$(echo "$result" | jq -r '.session_id')

# Resume
echo "What number?" | claude -p --resume "$session" --output-format json
# → Returns 42
```

### Forking (Branching)
```bash
# Fork creates new ID but preserves context
echo "New prompt" | claude -p --resume "$base" --fork-session --output-format json
```

### Decision for Prototype
**Linear continuation** (no forking) - simpler, each revision builds on previous.

---

## Architecture Diagram

```
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│   Human     │────▶│   Queue      │◀────│   Agents    │
│   (TUI)     │     │   (JSONL)    │     │   (bg)      │
└─────────────┘     └──────────────┘     └─────────────┘
      │                    │                    │
      │  approve/reject    │  read/write        │  read/write
      │  revise            │                    │  add items
      ▼                    ▼                    ▼
┌─────────────┐     ┌──────────────┐     ┌─────────────┐
│  Workflow   │     │   State      │     │   Claude    │
│  DSL        │     │   Sessions   │     │   CLI       │
└─────────────┘     └──────────────┘     └─────────────┘
```

---

## Relationship to Roast

This feels related to Roast but different enough that it might be:

**Option 1: Extension to Roast**
- Add `queue` cog type
- Add `input` cog for human prompts
- Upstream these features

**Option 2: Built on Roast**
- Use Roast for agent invocation + templates
- Build queue/TUI layer on top

**Option 3: Standalone**
- Fresh implementation
- Cherry-pick ideas from Roast (templates, sessions)
- More freedom, more work

The queue-driven model is fundamentally different from Roast's "execute steps in order" model. Might be cleaner to build fresh and borrow concepts.

---

## Open Questions

1. **Queue file location**: `./.review-queue.jsonl`? Configurable?

2. **Multiple workflows**: Can you have different workflows for different kinds of review?

3. **Filtering**: Should you be able to filter queue by status/type?

4. **Batch operations**: "Approve all remaining" or "Reject all failed"?

5. **Notifications**: When agents finish, how to alert? (Terminal bell? Desktop notification?)

6. **Multi-user**: Could two people review the same queue? (Locking?)

---

## Prototype Scope (v0)

### Goal
Prove the UX feels right. After 10 minutes, you're in flow - not fighting the tool.

### Success Criteria
- Fast feedback loop (item → decide → next feels snappy)
- Right information density (enough context, not overwhelming)
- Revision flow feels natural (conversational)
- Want to keep using it

### In Scope
- Real git diff hunks (from ~/.dotfiles HEAD~3..HEAD)
- Real Claude agent (sequential, no parallelism)
- Basic TUI: show item + response, hotkeys
- Actions: approve, reject, revise
- Session continuity for revise
- In-memory only

### Explicitly Cut
- JSONL queue file
- Workflow DSL
- Parallel/background agents
- Persistence across runs
- Drill-down views
- Custom context hooks

### Tech Stack
- Ruby script
- CLI::UI or TTY for prompts
- Claude CLI with `--resume` for sessions

### Test Data
5 diff hunks from ~/.dotfiles (HEAD~3..HEAD):
1. ghostty config (new file)
2. raycast package.json (removed commands)
3. raycast types (removed type defs)
4. configure script (alacritty → ghostty)
5. zshrc (simplified conditional)

---

## Next Steps

---

## Name Ideas

- `review-loop`
- `human-loop`
- `hl` (human loop)
- `queue-review`
- `agent-queue`
- `signal` (agents filter noise, surface signal)
- `sift`
