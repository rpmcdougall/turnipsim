# Turnip28 Simulator - Project Memory

**Last Updated:** 2026-04-20
**Current state:** v17 rules-accuracy audit (#38) complete; PR [#43](https://github.com/rpmcdougall/turnipsim/pull/43) in flight with the first data-correction slice. 16 sub-issues filed (#44–#59) covering all audit gaps, all on the project board. PR #41 (objectives, closes #36), PR #39 (targeting, closes #21), PR #37 (roster builder, closes #28), PR #35 (victory conditions) all merged.
**Active branch:** `feature/rules-audit-v17` (PR #43 open awaiting merge)

## Phase status

| Phase | Status | Notes |
|---|---|---|
| 0 — Scaffold | ✅ | `d2f127b` |
| 1 — Game data | ✅ | `9b9b2c1`, later rewritten in v17 data-model rework (PR #30) |
| 2 — Army UI | ✅ | Superseded by Phase 5b roster builder |
| 3 — ENet + lobby | ✅ | `91047e5`, PR #30 |
| 3b — Army submission | ✅ | PR #26 |
| 4 — Battle engine (initial) | ✅ | PR #26 — later replaced by v17 order state machine (PR #32) |
| 4.5 — v17 data model | ✅ | PR #30 (issue #27) |
| 4.5 — v17 order mechanics | ✅ | **PR #32 (issue #31)** — this session |
| 5 — Polish | ✅ (scoped) | #22 ✅ (PR #35), #21 ✅ (PR #39 — flagged bullets only; sprites/camera/tooltips deferred), #36 ✅ (PR #41 — v17 objective scoring) |
| 5b — Army submission UI | ✅ | PR #37 merged (#28) — preset dropdown + custom slot builder with live validation, preset pre-fill, per-slot stats |
| 5.5 — Rules-accuracy pass | 🚧 | #38 umbrella; PR #43 in flight. 16 sub-issues (#44–#59) cover all audit gaps. See `memory/checkpoint-2026-04-20-rules-audit.md` for catalog. |
| 6 — Deploy | ⬜ | #23–25 Todo. **Gates:** #38 audit + #40 (return fire + retreat) + #42 (Cult audit) before deploy |
| 7 — Cult mechanics | ⬜ | #29 Todo. #38's ammo-type plumbing will generalize into Grand Bombard (p.42). Validated against rules via #42. |

## Architecture quick-ref

```
godot/
├── game/                          # Pure RefCounted, no Node deps
│   ├── types.gd                   # Stats(M/A/I/W/V), UnitDef, Roster, UnitState, GameState
│   ├── ruleset.gd                 # JSON loader, roster validator
│   └── rulesets/v17.json          # 8 unit types, 4 equipment types, 4 preset rosters
├── server/
│   ├── server_main.gd             # ENet server, port 9999
│   ├── room_manager.gd            # 6-char room codes (excludes I/O/0/1)
│   ├── network_server.gd          # RPC routing for lobby + v17 order actions
│   └── game_engine.gd             # v17 state machine (pure functions)
├── client/
│   ├── main.tscn                  # Main menu
│   └── scenes/
│       ├── lobby.gd               # Programmatic UI — preset picker + mode toggle
│       ├── roster_builder.gd      # Custom roster slots (PR #37) — RosterBuilder class
│       └── battle.gd              # Programmatic battle UI
├── autoloads/
│   ├── network_manager.gd         # Mode detection (--server, both arg arrays)
│   └── network_client.gd          # Signals + RPC interface
└── tests/
    ├── test_runner.gd             # 19 tests — types, ruleset, roster validation
    └── test_game_engine.gd        # 55 tests — order state machine, combat, victory, fizzle paths
```

**Key design decisions:**
1. Single project, runtime mode split via `--server` flag (checked in both `get_cmdline_args()` + `get_cmdline_user_args()`)
2. Pure `game/` folder: RefCounted only, safe for server + client + headless tests
3. Data-driven rulesets (JSON), not hardcoded GDScript
4. Server-authoritative; dice injected into engine functions
5. Programmatic UI throughout — no manual Godot editor work tracked

## v17 Order flow (current battle gameplay)

```
placement → orders (loop) → finished
             └─ order_phase ─┘
                snob_select → order_declare → order_execute → _advance_after_order
                                                                    │
                                                                    ├─ more Snobs → snob_select (other seat)
                                                                    └─ all Snobs done → follower_self_order → order_execute → round end
```

**Actions (client → server):**
- `select_snob` — pick a Snob to Make Ready (no dice)
- `declare_order` — pick target + order type (server rolls 1 blunder + 2 move dice)
- `declare_self_order` — follower_self_order phase variant
- `execute_order` — with params dict per order type (server sizes combat dice pool)

**Order types:** Volley Fire (−1 I), Move & Shoot, March (M+2D6, 1D6 blundered), Charge (M+2D6 adjacent + melee). Snob self-orders bypass blunder check. All blunders add a panic token.

## Local dev

```bash
# Godot path per platform (see memory/godot_executable_path.md)
export GODOT="/c/tools/Godot/Godot_v4.6.2-stable_win64.exe"  # Windows
# or
export GODOT="/Applications/Godot.app/Contents/MacOS/Godot"  # macOS

# Automated tests
cd godot/
$GODOT --headless -s tests/test_runner.gd       # 19 tests
$GODOT --headless -s tests/test_game_engine.gd  # 55 tests

# Full local stack (headless server + 2 windowed clients)
scripts/test-stack.sh

# Solo mode (1 client)
scripts/test-stack.sh --solo
```

Per-process logs land in `test-logs/` (gitignored). Ctrl+C tears everything down. Closing one client doesn't cascade.

## Docs & tracking

- **Wiki** is source of truth for developer docs. Auto-syncs from `docs/wiki/` on push to main via `.github/workflows/sync-wiki.yml`.
- Manual testing procedure: `docs/wiki/Manual-Testing-Guide.md`.
- Plan doc (now complete): `ORDER_MECHANICS_PLAN.md` — keep as historical ref.
- GitHub Project: [TurnipSim v0.1](https://github.com/users/rpmcdougall/projects/1)

## Known deferred items

- `entry.gd:6/8` benign warning — `change_scene_to_file()` in `_ready()` needs to be `call_deferred`'d
- Fresh-clone tests fail until `$GODOT --editor --quit` builds the script class cache once
- `docs/wiki/Phase-4-UI-{Programmatic,Tasks}.md` are historical checkpoint-style docs; candidates for archival
- **Zombie server on port 9999** — `test-stack.sh` doesn't detect a stale previously-launched server; new stack's server silently fails to bind while clients attach to the old one (ghost-code behavior). Workaround: `taskkill //F //IM Godot_v4.6.2-stable_win64.exe` before relaunch. Candidate for a small script hardening pass.
- **Max-rounds tiebreak is a placeholder** — v17 actually scores by objectives captured (#36). Current alive-units → model-count tiebreak is stand-in logic, marked `TODO(objectives)` in `game_engine.gd:check_victory`.
- **GDScript warnings-as-errors + inferred Variant on ternaries** — any conditional expression with a `Dictionary.get(...)` branch can infer `Variant` and fail the whole file to compile. Cost ~15 min on PR #37 when `RosterBuilder.new()` silently failed and Custom mode appeared empty. Split into explicit `if`/assign with typed lvalue. First check the client log for compile errors when a programmatic UI "just doesn't appear."
- **Autoload identifiers in `godot -s <script>` mode** — parse-time globals that runtime node creation can't register. `test_phase3_scenes.gd` prints `Identifier not found: NetworkClient` errors but the test still PASSES because `load()` returns the scene resource. Cosmetic. Real fix (if ever needed) is to rewrite call sites to `get_node("/root/NetworkClient")`.

## Checkpoint history

- `memory/checkpoint-2026-04-17-phases-1-2-3.md`
- `memory/checkpoint-2026-04-17-phase-3b-4.md`
- `memory/checkpoint-2026-04-18-phase-4-ui.md`
- `memory/checkpoint-2026-04-19-order-mechanics.md`
- `memory/checkpoint-2026-04-20-victory-conditions.md`
- `memory/checkpoint-2026-04-20-roster-builder.md`
- `memory/checkpoint-2026-04-20-rules-audit.md` ← this session

## Next pickup

Primary track = rules-accuracy (#38) sub-issues. Suggested order:
1. **#44** — grid-vs-inches decision. Meta, gates LoS / 1" rule / range math. Small discussion + decision-log entry in CLAUDE.md.
2. **#52** — panic test subsystem. Foundational; unlocks charge panic, retreat, Fearless, Safety in Numbers, Bowel-Loosening.
3. **#53** — retreat subsystem. Depends on #52.
4. **#55** — two-sided melee bouts. Depends on #52 / #53.
5. **#56** — LoS + closest-target. Depends on #44.
6. Independent mediums interleaved: #45 (Improbable Hits), #46 (1" rule), #47 (charge fixes), #48 (snob-moves-with-unit), #49 (reroll infra), #50 (Vanguard), #51 (Dash), #54 (Stand and Shoot), #57 (Toff Off).
7. **#58** terrain, **#59** scenarios — systems-sized, coordinate with scenario data memory.
8. **#42** — Cult rules audit. Last pre-deploy gate.
9. Phase 6 (#23–25) — after #38 and #40 and #42.

Deferred #21 bullets (sprites, camera, tooltips, placement-undo) — not blocking anything; revisit post-deploy.
