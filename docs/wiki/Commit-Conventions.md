# Commit Conventions

We follow **Conventional Commits** with project-specific conventions.

## Format

```
<type>(<scope>): <description>

[Optional body with detailed explanation]

[Optional footer with references]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

## Commit Types

| Type | Description | Example |
|------|-------------|---------|
| `feat` | New feature | `feat(engine): add placement phase validation` |
| `fix` | Bug fix | `fix(army-roller): prevent infinite mutation loop` |
| `docs` | Documentation only | `docs(wiki): add testing guidelines` |
| `test` | Adding or updating tests | `test(engine): add victory condition tests` |
| `refactor` | Code change that neither fixes nor adds | `refactor(types): simplify to_dict serialization` |
| `perf` | Performance improvement | `perf(engine): optimize pathfinding algorithm` |
| `ci` | CI/CD changes | `ci: add Phase 4 tests to workflow` |
| `chore` | Other changes (deps, config) | `chore: update Godot to 4.6.2` |

## Scopes

Common scopes by area:

### Core Game Logic (`game/`)
- `types` - Data classes (Stats, Unit, GameState, etc.)
- `ruleset` - JSON loading and validation
- `army-roller` - Army generation logic
- `engine` - Game engine functions

### Server (`server/`)
- `server` - Server-side RPC handlers, game state
- `room-manager` - Room creation and management
- `netcode` - Network protocol

### Client (`client/`)
- `client` - Client-side UI and logic
- `lobby` - Lobby scene and UI
- `battle` - Battle scene and UI
- `ui` - Generic UI components

### Infrastructure
- `test` - Testing infrastructure
- `ci` - GitHub Actions and automation
- `docs` - Documentation
- `plan` - Planning and architecture

## Examples

### Adding a Feature

```bash
git commit -m "feat(engine): implement combat resolution functions

Added resolve_shoot() and resolve_charge() to handle ranged and melee
combat. Uses hit/wound/save cascade with injected dice for determinism.

Relates to #14

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Fixing a Bug

```bash
git commit -m "fix(army-roller): prevent duplicate mutation application

Mutation effects were being applied twice when rolling units with
multiple mutations from the same table. Now tracks applied mutations
and skips duplicates.

Fixes #42

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Refactoring

```bash
git commit -m "refactor(types): use typed arrays for units and mutations

Changed Unit.mutations from Array to Array[Mutation] and
GameState.units from Array to Array[UnitState] for better type safety.

Breaking change: Requires using .append() instead of direct assignment.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Documentation

```bash
git commit -m "docs(wiki): add commit conventions guide

Created comprehensive guide covering commit types, scopes, and examples
for contributors.

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

### Tests

```bash
git commit -m "test(engine): add comprehensive placement phase tests

Added 9 tests covering:
- Valid/invalid deployment zones
- Bounds checking
- Occupation detection
- Player switching
- Combat phase transition

All tests passing (38/38)

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

## Guidelines

### Description Line

**Do:**
- ✅ Use imperative mood ("add feature", not "added feature")
- ✅ Don't capitalize first letter after colon
- ✅ No period at the end
- ✅ Keep under 72 characters

**Don't:**
- ❌ "Added new feature" (past tense)
- ❌ "Adding feature" (present continuous)
- ❌ "feat: Add Feature" (capitalized)
- ❌ "feat: add feature." (period at end)

### Body (Optional)

Use the body to explain:
- **Why** the change was made
- **Context** that's not obvious from code
- **Trade-offs** considered
- **Breaking changes**

```
feat(engine): switch to alternating activations

Changed from "all units activate simultaneously" to "each player
activates all their units before passing turn". This better matches
Turnip28 tabletop rules and provides more tactical depth.

Breaking change: Clients must update end_turn logic to check all
friendly units have activated before allowing turn end.
```

### Footer (Optional)

Link to issues and PRs:

```
Fixes #42
Relates to #14
Closes #17, #18, #19
```

### Co-Authored-By

When working with AI assistants (Claude Code, GitHub Copilot, etc.):

```
🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

## Modular Commits

**Each commit should be a complete, logical unit.**

### Good Example

```bash
# Commit 1: Data structures
git add godot/game/types.gd
git commit -m "feat(types): add GameState and UnitState classes"

# Commit 2: Engine logic
git add godot/server/game_engine.gd
git commit -m "feat(engine): implement placement phase functions"

# Commit 3: Tests
git add godot/tests/test_game_engine.gd
git commit -m "test(engine): add placement phase tests"

# Commit 4: Integration
git add godot/server/network_server.gd
git commit -m "feat(server): add placement action RPC routing"
```

### Bad Example

```bash
# Single massive commit
git add .
git commit -m "feat: add battle gameplay

Added GameState, UnitState, game engine, tests, server integration,
and client UI. Everything works now."
```

### Why Modular?

1. **Reviewable** - Each commit can be reviewed independently
2. **Revertable** - Can revert specific changes without losing everything
3. **Bisectable** - Can use `git bisect` to find bugs
4. **Understandable** - Clear history of what changed when

## Commit Amend

**Only amend commits that haven't been pushed:**

```bash
# Fix typo in last commit (before push)
git add <file>
git commit --amend --no-edit

# Change commit message (before push)
git commit --amend -m "new message"
```

**Never amend after pushing to shared branch** - creates conflicts.

## Rewriting History

**Only on your feature branch, never on `main`:**

```bash
# Interactive rebase to clean up commits
git rebase -i HEAD~3

# Squash multiple WIP commits into one
# In editor: change 'pick' to 'squash' for commits to merge
```

## CI Integration

GitHub Actions checks commit messages on PRs:
- Validates conventional commit format
- Checks for required trailers
- Warns on large commits (>500 lines)

## See Also

- [Development Process](Development-Process.md) - Full workflow
- [CONTRIBUTING.md](../../CONTRIBUTING.md) - Contribution guidelines
- [Conventional Commits](https://www.conventionalcommits.org/) - Official spec
