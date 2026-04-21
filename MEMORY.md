# Turnip28 Simulator - Project Memory

**Last Updated:** 2026-04-20
**Current state:** Phase 5 targeting-visibility polish shipped (PR #39, closes #21). PR #37 (roster builder, #28) and PR #35 (victory conditions) merged earlier this day. Issue #38 filed for pre-deploy v17 rules-accuracy audit (discovered StumpGun ammo types / Unstable Icon gaps mid-test).
**Active branch:** `main` (clean — ready for next pickup)

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
| 5 — Polish | 🚧 | #22 ✅ (PR #35), #21 ✅ (PR #39 — range diamonds + target rings during order_execute, immobile order hiding), #36 Todo (objectives, replaces placeholder tiebreak) |
| 5b — Army submission UI | ✅ | PR #37 merged (#28) — preset dropdown + custom slot builder with live validation, preset pre-fill, per-slot stats |
| 6 — Deploy | ⬜ | #23–25 Todo. **Gates:** #38 (rules-accuracy audit) + #40 (simultaneous return fire + retreat) should precede deploy |
| 7 — Cult mechanics | ⬜ | #29 Todo. #38's ammo-type plumbing will generalize into Grand Bombard (p.42) |

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
- `memory/checkpoint-2026-04-20-roster-builder.md` ← this session

## Next pickup

- **#36** — v17 objectives (replaces placeholder max-rounds tiebreak with real scoring). Self-contained, natural rules-accuracy warmup before #38.
- **#38** — full v17 rules-accuracy audit (StumpGun ammo types, Unstable Icon, Preliminary Bombardment, per-unit specials). Gate before deploy. See `memory/rules_accuracy_gaps.md` for seed list.
- **Phase 6** — export presets + deploy (#23–25). Do #38 first.
- Remaining #21 scope (sprites, particles, tooltips, camera pan/zoom, placement-undo) — deferred; PR #39 only shipped the three items flagged in the issue comment.
