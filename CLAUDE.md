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
│   ├── types.gd        # Data classes (RefCounted)
│   ├── ruleset.gd      # Loads JSON rulesets
│   ├── army_roller.gd  # roll_army(ruleset, roll_d6: Callable)
│   └── rulesets/       # One JSON file per ruleset
├── server/             # Server-only (server_main, game_engine, networking)
├── client/             # Client-only (main, scenes/menu, lobby, battle)
└── tests/
```

## Key Decisions

- **Dependency injection for dice**: Game logic takes a `roll_d6: Callable` — deterministic testing, server-authoritative rolls
- **Data-driven rulesets**: JSON files in `game/rulesets/`, not hardcoded GDScript. Engine logic is singular; data varies.
- **gl_compatibility renderer**: Lightest option, no Vulkan requirement
- **`game/` no-node contract**: Everything in `game/` must be pure RefCounted — no Node, no scene tree, no signals. Safe to use from server, client, or headless tests.
- **Runtime mode detection**: `--server` CLI arg or `dedicated_server` feature tag → `NetworkManager.is_server`

## Phase Status

- [x] **Phase 0** — Project scaffold (commit d2f127b)
- [ ] **Phase 1** — Game data: types, simplified ruleset JSON, army roller
- [ ] **Phase 2** — Army rolling UI (client-side, no networking)
- [ ] **Phase 3** — ENet networking, lobby, room management
- [ ] **Phase 4** — Battle gameplay (server-authoritative)
- [ ] **Phase 5** — Polish, multiple rulesets
- [ ] **Phase 6** — Export presets, deployment

## Conventions

- Conventional commits: `<type>(<scope>): <description>` with `Co-Authored-By` trailer
- Modular commits — one logical unit per commit
- Feature branches for significant work
- No export presets in git — created via editor UI (Phase 6)
