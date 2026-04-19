# Turnip28 Simulator

## Project Overview

Multiplayer tabletop simulator for Turnip 28 (grimdark root-vegetable wargame).

- **Stack**: Godot 4.6.2 stable, GDScript, authoritative server + thin clients over ENet
- **Layout**: Single Godot project at `godot/`, server/client mode determined at runtime
- **Rules reference**: `rules_export/` — v17 print rules PDF, v18 playtest PDF, changelists
- **Roadmap**: `turnip28-sim-plan-godot.md` — full phase plan (Phases 0–6)

## Architecture

```
godot/
├── entry.tscn          # Main scene — branches on NetworkManager.is_server
├── autoloads/          # NetworkManager (mode detection singleton)
├── game/               # Pure logic — NO node/scene dependencies
│   ├── types.gd        # Stats (M/A/I/W/V), UnitDef, Roster, UnitState, GameState
│   ├── ruleset.gd      # Loads + validates v17 JSON rulesets, validates rosters
│   └── rulesets/       # One JSON file per ruleset (v17.json)
├── server/             # Server-only (server_main, game_engine, networking)
├── client/             # Client-only (main, scenes/menu, lobby, battle)
└── tests/
```

## Key Decisions

- **Dependency injection for dice**: Game logic takes a `roll_d6: Callable` — deterministic testing, server-authoritative rolls
- **Data-driven rulesets**: JSON files in `game/rulesets/` (v17.json), not hardcoded GDScript. Engine logic is singular; data varies.
- **Roster-based army submission**: Players build rosters (Snobs + Followers + equipment) validated against ruleset composition rules. Presets available for quick start. Replaces the old random army roller.
- **gl_compatibility renderer**: Lightest option, no Vulkan requirement
- **`game/` no-node contract**: Everything in `game/` must be pure RefCounted — no Node, no scene tree, no signals. Safe to use from server, client, or headless tests.
- **Runtime mode detection**: `--server` CLI arg or `dedicated_server` feature tag → `NetworkManager.is_server`

## Phase Status

- [x] **Phase 0** — Project scaffold (commit d2f127b)
- [ ] **Phase 1** — Game data: v17 types, ruleset JSON, roster format ← REWORKING (was MVP, now v17)
- [x] ~~Phase 2~~ — Removed (was: Army rolling UI — replaced by Phase 5b)
- [x] **Phase 3** — ENet networking, lobby, room management (commit 91047e5)
- [ ] **Phase 4** — Battle gameplay (server-authoritative)
- [ ] **Phase 5** — Polish
- [ ] **Phase 5b** — Army Submission UI (roster builder + presets)
- [ ] **Phase 6** — Export presets, deployment
- [ ] **Phase 7** — Cult mechanics (cult-specific units, special rules, army mods)

## Conventions

- Conventional commits: `<type>(<scope>): <description>` with `Co-Authored-By` trailer
- Modular commits — one logical unit per commit
- Feature branches for significant work
- No export presets in git — created via editor UI (Phase 6)
