# Development Process

This document describes the complete workflow for contributing to Turnip28 Simulator.

## Overview

We use a **feature branch workflow** with:
- Modular commits (one logical unit per commit)
- Conventional commit messages
- GitHub PR reviews
- Automated CI testing

## Workflow Steps

### 1. Pick a Task

Check the [GitHub Project Board](https://github.com/users/rpmcdougall/projects/1) for available tasks.

Tasks are organized by phase:
- **Todo** - Ready to be worked on
- **In Progress** - Currently being developed
- **Done** - Completed and merged

### 2. Create a Feature Branch

```bash
# Start from latest main
git checkout main
git pull origin main

# Create feature branch
git checkout -b feature/phase-4-battle-ui

# Or for bug fixes
git checkout -b fix/army-roller-mutation-bug
```

**Branch naming convention:**
- Features: `feature/<phase-name>` or `feature/<feature-name>`
- Fixes: `fix/<issue-description>`
- Docs: `docs/<topic>`

### 3. Implement Incrementally

**Make modular commits** - each commit should be a complete, logical unit:

✅ **Good:**
```bash
# Commit 1: Add data structures
git add godot/game/types.gd
git commit -m "feat(types): add GameState and UnitState classes"

# Commit 2: Add game engine logic
git add godot/server/game_engine.gd
git commit -m "feat(engine): implement placement phase functions"

# Commit 3: Add tests
git add godot/tests/test_game_engine.gd
git commit -m "test(engine): add placement phase tests"
```

❌ **Bad:**
```bash
# Single massive commit
git add .
git commit -m "Add battle gameplay"
```

### 4. Follow Commit Conventions

See [Commit Conventions](Commit-Conventions.md) for detailed format.

**Template:**
```
<type>(<scope>): <description>

[Optional body explaining the change]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

### 5. Run Tests Locally

Before pushing, verify tests pass:

```bash
cd godot/

# Run all test suites
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_runner.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_game_engine.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless -s tests/test_ui_instantiate.gd
```

See [Testing Guidelines](Testing-Guidelines.md) for writing new tests.

### 6. Update Documentation

Before pushing, ensure documentation is current:

**Required updates:**
- [ ] `MEMORY.md` - Current phase status, what was implemented
- [ ] `CLAUDE.md` - Phase checklist if phase completed
- [ ] Checkpoint file in `memory/` - For significant sessions
- [ ] GitHub project board - Move issues to "Done"

**Optional updates:**
- Update wiki pages if you changed architecture
- Add to troubleshooting guides if you hit issues

### 7. Push Feature Branch

```bash
# First push
git push -u origin feature/phase-4-battle-ui

# Subsequent pushes
git push
```

### 8. Create Pull Request

Using GitHub CLI:
```bash
gh pr create --title "feat(phase4): implement battle UI and client integration" \
  --body "$(cat <<'EOF'
## Summary
Implements Phase 4 client battle UI:
- battle.tscn scene structure
- battle.gd UI logic and rendering
- lobby.tscn army submission buttons

## Testing
- [x] All existing tests pass
- [x] Manual test: two clients through full game
- [x] Server handles placement/combat actions correctly

## Checklist
- [x] Commits are modular
- [x] Tests added/updated
- [x] MEMORY.md updated
- [x] Project board updated

Closes #17, #18, #19
EOF
)"
```

Or via GitHub web UI: https://github.com/rpmcdougall/turnipsim/pulls

### 9. Address Review Feedback

If changes requested:
```bash
# Make fixes on the same branch
git add <files>
git commit -m "fix: address review feedback"
git push
```

The PR will update automatically.

### 10. Merge and Clean Up

After approval:

```bash
# Merge via GitHub UI (squash or merge commit)

# Then locally:
git checkout main
git pull origin main
git branch -d feature/phase-4-battle-ui
```

## Session Discipline

### Before `/clear` or Ending Session

**Always update:**
1. `MEMORY.md` - Current status, what's complete, what's next
2. Create checkpoint in `memory/checkpoint-YYYY-MM-DD-<topic>.md`
3. Commit any uncommitted work
4. Update project board

### Starting a New Session

**Always review:**
1. Read latest `MEMORY.md`
2. Read latest checkpoint file
3. Check `git status` for uncommitted changes
4. Review project board for current tasks

## Working with Claude Code

When working with Claude Code (AI assistant):

**Provide context:**
- Reference MEMORY.md and CLAUDE.md
- Point to relevant checkpoint files
- Mention current phase and branch

**Request modular commits:**
- Ask for incremental implementation
- Request commit per logical unit
- Don't batch entire features

**Verify outputs:**
- Review generated code before committing
- Run tests after each change
- Check for security issues (SQL injection, XSS, etc.)

## Emergency Procedures

### Broken main branch
```bash
# Revert the bad commit
git revert <commit-hash>
git push origin main

# Or reset if not pushed yet
git reset --hard HEAD~1
```

### Lost work
```bash
# Check reflog
git reflog

# Recover lost commit
git checkout <commit-hash>
git checkout -b recovery-branch
```

### Merge conflicts
```bash
# On your feature branch
git fetch origin
git merge origin/main

# Resolve conflicts
# Edit files, then:
git add <resolved-files>
git commit
```

## Tips

### Faster iteration
- Keep tests running in watch mode (manually re-run)
- Use Godot editor's "Play Scene" for quick UI tests
- Test server/client locally before pushing

### Communication
- Comment on issues when starting work
- Update PR descriptions with progress
- Ask questions in issue comments, not DMs

### Code review
- Self-review before creating PR
- Use GitHub's suggestion feature
- Be specific in review comments

## See Also

- [Testing Guidelines](Testing-Guidelines.md) - Writing and running tests
- [Code Style Guide](Code-Style-Guide.md) - GDScript conventions
- [Commit Conventions](Commit-Conventions.md) - Message format
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Official contribution guide
