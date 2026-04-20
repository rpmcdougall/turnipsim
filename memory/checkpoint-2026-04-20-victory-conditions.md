# Checkpoint — 2026-04-20 — Victory conditions

PR: [#35](https://github.com/rpmcdougall/turnipsim/pull/35) on branch `feature/victory-conditions`. **Awaiting merge.**

## What shipped

- **#22 victory conditions**
  - `game_engine.gd:check_victory` extended with a max-rounds tiebreak (alive units → model count → draw) so games no longer hang after round 4.
  - `network_server.request_action` now emits `_send_game_ended` whenever `phase == "finished"`, including the winner-0 draw case that the old code skipped.
  - Client game-over overlay in `battle.gd:_show_game_over_overlay` — outcome title (green/red/yellow), reason, rounds played (clamped to `max_rounds`), surviving-unit counts per side, single **Return to Main Menu** button that disconnects and scene-changes.

- **#33 stale lobby state** — surfaced during manual testing. `_disconnect_from_server` / `_on_server_disconnected` now call `_reset_army_state()` (clears `has_submitted_army`, `my_roster`, hides submit button, wipes army display). Without this, reconnecting to a different room left clients stuck ready-without-army.

- **#34 order lock with no valid target** — also surfaced during testing.
  - Engine: `_execute_volley_fire` and `_execute_charge` accept `params.fizzle == true`, guarded by new helpers `_has_valid_volley_target` / `_has_valid_charge_target` so fizzle is only legal when there genuinely are no targets.
  - Log entries: `volley_fire_fizzled` / `charge_fizzled`.
  - Client: `_render_order_execute_panel` detects the zero-target state and swaps instruction + shows "Continue (no effect)" button.
  - `move_and_shoot` got a parallel fix — the Skip button is now always visible (labelled "Skip (no move, no shot)" before any destination is staged), since a blundered max_move=1 could otherwise trap the player with no clickable cell.

- **CI lingering chore** — `.github/workflows/tests.yml` now runs `tests/test_game_engine.gd`. Previously only `test_runner.gd`, `test_ui_instantiate.gd`, and `test_phase3_scenes.gd` ran, so the 51-test engine suite was silently not gating on PRs.

- **Wiki** — `docs/wiki/Manual-Testing-Guide.md` Victory section rewritten: end-condition table, per-path recipes (including the `max_rounds = 1` temp-edit trick for forcing max-rounds expiry), and overlay checklist.

- **#36 filed** — the max-rounds tiebreak is a placeholder. v17 actually uses objective-based scoring (see change list: "p42. BUFF Snobs can capture Objectives"). The code branch is annotated with `TODO(objectives)` linking to #36.

## Latent bugs found while testing

1. **Zombie server on port 9999** — `test-stack.sh` didn't notice when an old server was still bound. The "new" stack's server silently failed with `Couldn't create an ENet host` while the clients connected to the old server, giving ghost-code behavior. Workaround: `taskkill //F //IM Godot_v4.6.2-stable_win64.exe` before relaunching. Worth teaching the script to detect/fail loudly — filed mentally, not yet in a ticket.

2. **Grid visibility** — players can't tell which cells are valid movement destinations or which enemies are reachable without click-and-see. Added as a comment on #21 (Phase 5 polish); already in scope for that issue.

## Test counts

- `test_runner.gd`: 19 (unchanged)
- `test_game_engine.gd`: 48 → **55** (3 tiebreak + 4 fizzle)

## Commits on branch

1. `bfcd857` engine: max-rounds tiebreak
2. `9d7ebfe` client: game-over overlay + MEMORY.md fix
3. `0df0eae` ci: run test_game_engine.gd
4. `af97726` docs: wiki victory-testing procedures
5. `11557aa` fix(lobby): clear roster state on disconnect (#33)
6. `b82cc8f` fix(engine,ui): volley/charge fizzle (#34)
7. `4646e88` fix(ui): move_and_shoot skip
8. `ad82053` chore: TODO(objectives) marker for #36

## What I'd do differently

- The zombie-server class of bug cost ~20 min of confused debugging where server-log errors didn't match client behavior. The `test-stack.sh` script should refuse to start if port 9999 is already bound, or should `taskkill` stale Godot processes itself. Fast to add; worth doing before the next multi-iteration test session.

## Next pickup

Per user direction this session: **#28 roster builder** is up next (player-value high; current lobby picks a random preset on Select Army). After that, Phase 5 polish (#21) or Phase 6 deploy. #36 objectives is its own mini-phase before any serious rules-faithful play.
