# Session Discipline

Guidelines for maintaining project memory and documentation across development sessions.

## The Problem

Long-running projects accumulate context:
- What was implemented
- What decisions were made
- What's left to do
- Why things are the way they are

Without discipline, this context is lost between sessions, leading to:
- Duplicate work
- Contradictory changes
- Forgotten decisions
- Stalled progress

## The Solution: Memory Files

We maintain **two levels of memory:**

1. **MEMORY.md** - Current session state (< 200 lines)
2. **Checkpoints** - Deep archives of significant sessions

### MEMORY.md

**Location:** `/MEMORY.md` (repo root)

**Purpose:** Quick-start reference for current phase

**Update frequency:** Every session, before `/clear` or ending work

**Contents:**
```markdown
# Project Memory

**Last Updated:** YYYY-MM-DD
**Current Phase:** Phase X
**Feature Branch:** feature/phase-x-name

## Project Status
- Completed Phases ✅
- Current Phase 🎯
- Remaining Phases

## Architecture Quick Reference
- Project structure
- Key design decisions

## Phase X Flow
- How current phase works
- Critical files

## Testing
- How to run tests
- How to run server/client

## GitHub Project Board
- Issue tracking
- Phase completion

## Commands Quick Reference
- Common commands with full paths

## Current Implementation Status
- Checklist of what's done/pending

## Session Discipline Reminders
- Checklist of meta-tasks
```

**Example:**
See `/MEMORY.md` in repo for current format.

### Checkpoint Files

**Location:** `/memory/checkpoint-YYYY-MM-DD-<topic>.md`

**Purpose:** Deep archive of what happened in a significant session

**Create when:**
- Completing a phase
- Major architectural decision
- Large refactoring
- Before long break

**Contents:**
```markdown
# Checkpoint: <Phase> Implementation

**Date:** YYYY-MM-DD
**Branch:** feature/phase-name
**Commits:** X commits (abc123 → def456)
**Status:** Phase complete / In progress

## Session Summary
Brief overview of what was accomplished

## What Was Implemented
Detailed breakdown:
- Feature 1 (commit abc123)
- Feature 2 (commit def456)

## Architecture Decisions Made
- Decision 1: Rationale
- Decision 2: Rationale

## Testing Strategy
How was it tested?

## Files Modified
- New files created
- Modified files
- Total line count

## What Remains
- [ ] Task 1
- [ ] Task 2

## Known Issues / Notes
Gotchas, TODOs, limitations

## Next Session Tasks
Immediate next steps

## Commit History
```
abc123 feat: first commit
def456 feat: second commit
```

## References
Links to relevant docs
```

**Example:**
See `/memory/checkpoint-2026-04-17-phase-3b-4.md` for recent example.

## Session Workflow

### Starting a Session

**1. Review Current State**
```bash
# Read MEMORY.md (always up-to-date)
cat MEMORY.md

# Read latest checkpoint (for deep context)
ls -lt memory/
cat memory/checkpoint-<latest>.md

# Check git status
git status
git log --oneline -10

# Check current branch
git branch --show-current
```

**2. Check Project Board**
```bash
gh project item-list 1 --owner rpmcdougall --format json | \
  jq -r '.items[] | select(.status=="Todo") | "\(.content.number) \(.content.title)"'
```

**3. Identify Next Task**
- Pick from "Todo" column on project board
- Or continue current in-progress work
- Update task to "In Progress"

### During Session

**Track Progress:**
- Make modular commits as you go
- Update MEMORY.md incrementally
- Move project board tasks to "Done" when complete
- Create checkpoint for significant milestones

**Document Decisions:**
- Why did you choose approach A over B?
- What trade-offs were considered?
- Add to checkpoint or MEMORY.md

### Ending a Session

**Required Before `/clear` or Stopping Work:**

**1. Update MEMORY.md**
```markdown
**Last Updated:** 2026-04-17
**Current Phase:** Phase 4 In Progress
**Feature Branch:** feature/phase-3b-4-battle

### Current Phase 🎯
**Phase 4: Battle Gameplay** - In Progress

**Completed:**
- ✅ Game engine (644 lines)
- ✅ Engine tests (38 tests, 28/34 passing)
- ✅ Server integration

**Remaining:**
- battle.tscn scene (requires Godot editor)
- battle.gd client UI (~300-400 lines)
- lobby.tscn updates
```

**2. Create Checkpoint (if significant work done)**
```bash
# Create checkpoint file
vim memory/checkpoint-2026-04-17-phase-4-client.md

# Include:
# - What was implemented (detailed)
# - Commits made (list with messages)
# - Decisions made (why, not just what)
# - What's next (specific tasks)
```

**3. Commit Documentation**
```bash
# Stage MEMORY.md and checkpoint
git add MEMORY.md memory/checkpoint-*.md

# Commit with clear message
git commit -m "docs(memory): update after Phase 4 client UI session

Implemented battle.tscn scene structure and battle.gd rendering.
Created checkpoint documenting scene architecture and UI patterns.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

**4. Update Project Board**
```bash
# Move completed issues to Done
gh project item-edit --id <item-id> --field-id <status-field> --single-select-option-id <done-id>
```

**5. Push Changes**
```bash
git push
```

## Memory File Best Practices

### MEMORY.md Guidelines

**Do:**
- ✅ Keep under 200 lines (archive to checkpoint if longer)
- ✅ Update every session
- ✅ Include full paths for commands
- ✅ Link to external docs (don't duplicate)
- ✅ Use checklists for pending work
- ✅ Include current branch name

**Don't:**
- ❌ Duplicate content from CLAUDE.md or other docs
- ❌ Include outdated information
- ❌ Write novel-length explanations
- ❌ Leave "Last Updated" stale

### Checkpoint Guidelines

**Do:**
- ✅ Write for future you (6 months later)
- ✅ Explain **why** decisions were made
- ✅ Include commit hashes and branches
- ✅ Document known issues and gotchas
- ✅ List specific next steps

**Don't:**
- ❌ Just paste git log output
- ❌ Omit rationale for decisions
- ❌ Assume you'll remember details
- ❌ Skip creating one for major work

## Archive Policy

### When to Archive

**Move to `memory/history.md` when:**
- Phase is complete and merged
- Information is no longer relevant to current work
- MEMORY.md exceeds 200 lines

**Keep in MEMORY.md:**
- Current phase status
- Immediately next phase
- Recently completed phase (for reference)

### Archive Format

```markdown
# Historical Memory

## Phase 1 (Completed 2025-XX-XX)
Brief summary, link to checkpoint

## Phase 2 (Completed 2025-XX-XX)
Brief summary, link to checkpoint
```

## Working with AI Assistants

### Providing Context to Claude Code

**Always include:**
- "See MEMORY.md for current project status"
- "See memory/checkpoint-<latest>.md for detailed context"
- "Current branch: feature/phase-x-name"

**Request updates:**
- "Update MEMORY.md with today's progress"
- "Create checkpoint for Phase X completion"
- "Update project board to reflect completed tasks"

### Verifying AI Outputs

**Before committing AI-generated updates:**
- ✅ Read the diff (`git diff MEMORY.md`)
- ✅ Verify accuracy (did it capture everything?)
- ✅ Check for stale info being left in
- ✅ Ensure "Last Updated" date is current

## Troubleshooting

### "I forgot where I left off"

```bash
# 1. Check MEMORY.md
cat MEMORY.md

# 2. Check latest checkpoint
cat memory/checkpoint-$(ls -t memory/ | head -1)

# 3. Check git log
git log --oneline -10

# 4. Check uncommitted work
git status
git diff
```

### "MEMORY.md is out of date"

**Fix it immediately:**
```bash
vim MEMORY.md
# Update with current status
git add MEMORY.md
git commit -m "docs(memory): update with current session progress"
```

### "MEMORY.md is too long"

**Archive old content:**
```bash
# 1. Create/update history.md
vim memory/history.md
# Add completed phase summaries

# 2. Trim MEMORY.md to current phase only
vim MEMORY.md

# 3. Commit both
git add MEMORY.md memory/history.md
git commit -m "docs(memory): archive Phase X to history"
```

### "Lost a checkpoint"

**Checkpoints are committed to git:**
```bash
# Find in history
git log --all --full-history -- memory/checkpoint-*.md

# Restore deleted checkpoint
git checkout <commit-hash> -- memory/checkpoint-YYYY-MM-DD-topic.md
```

## Examples

### Good Session End

```bash
# Updated MEMORY.md with today's work
vim MEMORY.md

# Created checkpoint for phase completion
vim memory/checkpoint-2026-04-17-phase-4-complete.md

# Committed both
git add MEMORY.md memory/checkpoint-*.md
git commit -m "docs(memory): Phase 4 complete, client UI finished"

# Updated project board
gh project item-edit --id PVTI_xyz --field-id PVTSSF_abc --single-select-option-id 98236657

# Pushed
git push
```

### Bad Session End

```bash
# Just typed /clear without updating anything ❌
# Next session starts with no context
# Hours wasted re-learning what was done
```

## Checklist

**Before ending session:**
- [ ] MEMORY.md updated with current status
- [ ] Checkpoint created (if significant work)
- [ ] Project board reflects completed tasks
- [ ] All changes committed
- [ ] Documentation pushed to GitHub
- [ ] "Last Updated" date is current
- [ ] Next steps are clear

## See Also

- [Development Process](Development-Process.md) - Full workflow
- [Commit Conventions](Commit-Conventions.md) - Commit message format
- [MEMORY.md](../../MEMORY.md) - Current project memory
- [memory/](../../memory/) - Checkpoint archives
