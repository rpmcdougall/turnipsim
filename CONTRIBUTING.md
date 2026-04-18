# Contributing to Turnip28 Simulator

## Branching Strategy

We use a feature branch workflow for all development:

### For New Features (Phases 3+)

1. **Create a feature branch from main:**
   ```bash
   git checkout main
   git pull origin main
   git checkout -b feature/phase-3-networking
   ```

2. **Make modular commits on the branch:**
   - Follow conventional commit format
   - One logical unit per commit
   - Use `Co-Authored-By` trailer

3. **Push the branch to GitHub:**
   ```bash
   git push -u origin feature/phase-3-networking
   ```

4. **Create a Pull Request:**
   - Use `gh pr create` or GitHub web UI
   - Reference the phase/milestone in the description
   - Wait for CI tests to pass (GitHub Actions)

5. **Merge after approval:**
   - Use "Squash and merge" or "Create a merge commit" (your choice)
   - Delete the feature branch after merge

### Branch Naming Convention

- Feature work: `feature/<phase-name>` (e.g., `feature/phase-3-networking`)
- Bug fixes: `fix/<issue-description>` (e.g., `fix/army-roller-infinite-loop`)
- Documentation: `docs/<topic>` (e.g., `docs/deployment-guide`)

## CI/CD

### GitHub Actions

`.github/workflows/tests.yml` runs automatically on:
- Pull requests to `main`
- Pushes to `main`

**Tests run:**
1. Phase 1 game logic (19 tests)
2. UI scene instantiation validation

**Runtime:** ~10 seconds on Ubuntu runner

### Local Testing

Before pushing, run tests locally:

```bash
cd godot/
godot --headless --script tests/test_runner.gd
godot --headless --script tests/test_ui_instantiate.gd
```

## Commit Message Format

```
<type>(<scope>): <description>

[Optional body]

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
```

**Types:** `feat`, `fix`, `docs`, `test`, `refactor`, `ci`, `chore`

**Scopes:** `game`, `client`, `server`, `test`, `plan`, etc.

## Development Phases

- [x] **Phase 0** — Project scaffold
- [x] **Phase 1** — Game data layer
- [x] **Phase 2** — Army rolling UI
- [ ] **Phase 3** — ENet networking, lobby, room management
- [ ] **Phase 4** — Battle gameplay (server-authoritative)
- [ ] **Phase 5** — Polish, multiple rulesets
- [ ] **Phase 6** — Export presets, deployment

Each phase should be developed on a feature branch and merged via PR.
