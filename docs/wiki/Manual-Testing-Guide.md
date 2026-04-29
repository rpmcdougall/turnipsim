# Manual Testing Guide

Local end-to-end smoke-test procedure for the full client/server stack. Run this before merging significant feature branches or whenever you suspect cross-layer regressions the unit tests won't catch.

For setup (Godot install, `$GODOT`, etc.) see [Project Setup](Project-Setup.md).

---

## Automated suites (run first)

If these fail, stop — fix them before bothering with a live stack.

```bash
cd godot/
$GODOT --headless -s tests/test_runner.gd         # Phase 1 — 19 tests
$GODOT --headless -s tests/test_game_engine.gd    # Engine — 51 tests
```

Both should report `Failed: 0`.

---

## Launch the local stack

```bash
scripts/test-stack.sh          # headless server + 2 windowed clients
scripts/test-stack.sh --solo   # headless server + 1 client (for solo-test mode)
```

The script detects Windows (Git Bash) vs macOS, writes per-process logs to `test-logs/{server,client1,client2}.log`, and tears everything down on Ctrl+C. Closing a single client window is safe — the rest stays up so you can iterate.

---

## Smoke-test flow

### 1. Lobby → army submission

**Client 1**
1. Main menu → Multiplayer Lobby → Create Room
2. Note the 6-char room code
3. Select Army → pick a preset (e.g. Balanced Regiment, Gunline) → Submit Army

**Client 2**
1. Main menu → Multiplayer Lobby → Join Room → enter the code from client 1
2. Select Army → pick a preset → Submit Army

Both clients should transition to `battle.tscn` once both rosters are submitted. Server log should show `Starting game for room <CODE>`.

### 2. Placement phase

- Seat 1's deployment zone is rows **28–31** (bottom); seat 2's is rows **0–3** (top).
- Active player clicks grid cells in their zone to place each unit in order.
- Clicking outside the zone or on an occupied cell is rejected server-side (look for `Sending error to peer ...: Not in your deployment zone`).
- Click **Confirm Placement** when all units are placed. Turn passes to the other seat.

### 3. Orders phase — v17 state machine

Each round, players alternate picking Snobs to "Make Ready." The sidebar is phase-aware; only one of the four sub-panels is visible at a time, based on `state.order_phase`.

**snob_select** — pick a Snob
- Sidebar lists alive unordered Snobs as buttons.
- Clicking a Snob (button or directly on the board) advances to `order_declare`.

**order_declare** — choose target + order
- Sidebar shows the Made-Ready Snob's type and command range.
- A translucent Euclidean circle overlays the board around the Snob — any cell inside is within command range.
- Target list shows the Snob itself (self-order) plus alive unordered Followers inside the circle.
- Four order buttons (Volley Fire / Move & Shoot / March / Charge) enable or disable based on the selected target's capabilities (weapon range, powder smoke, immobile special rule).
- Pick a target, pick an order → server rolls the blunder die + 2D6 move dice, transitions to `order_execute`. A blundered die (1) adds a panic token and reduces march bonus to the first die only. Snob self-orders never blunder.

**order_execute** — run the order
- Sidebar shows the declared order, blundered state, and movement range with dice bonus applied.
- **Volley Fire:** click an enemy unit to fire (`-1 Inaccuracy` unless blundered). Shooting resolves as a simultaneous engagement (v17 p.13): the target returns fire if it has a ranged weapon, no powder smoke, and the shooter is in range. Casualties from the primary shot do not suppress return fire. Winner (more unsaved wounds) forces the loser to retreat `D6 + 2" × panic tokens`; ties produce no retreat.
- **March:** click a destination cell within `M + move_bonus`. The destination must be ≥1" from any enemy and (if the marcher is a Follower) ≥1" from any friendly Follower (v17 p.9, "the 1" rule"). Snobs are exempt for friendlies but not for enemies. Diagonal-adjacent cells (√2 ≈ 1.41") are legal; cardinal-adjacent (1.0") is rejected.
- **Charge:** click an enemy within `M + move_bonus`; attacker auto-pathfinds to an adjacent cell and resolves the charge sequence — target panic test (v17 p.16 step 2), Stand and Shoot if the target passed and is eligible (ranged weapon, no powder smoke, not close-combat-equipped — v17 p.16 step 3), then melee as bouts (v17 p.18). Attacker strikes, defender removes casualties, defender counter-strikes, winner = more unsaved wounds per bout. Tied bouts repeat up to 3×; cap-hit ties draw with no retreat. Post-melee both survivors gain +1 panic; the loser retreats (which can include the charger). Charge end-cell must be >1" from any non-target unit (v17 p.17, stricter than the standard rule — even friendly Snobs near the contact cell block it).
- **Move & Shoot:** click a destination (max `M`, or `1D6` if blundered), then click an enemy to fire from the new position *or* press **Confirm move (no shot)** to skip the shot. The engagement rule is the same as Volley Fire — return-fire range is measured from the shooter's post-move position.

On success the turn either passes to the opposing seat (if they still have unordered Snobs), or — once both sides' Snobs are done — transitions to `follower_self_order`.

**follower_self_order** — unordered followers give themselves orders
- Same target-list + order-button UI as `order_declare`, but limited to the active seat's own unordered non-Snob units.
- Self-ordering always blunder-checks (no command-range requirement).
- When no unordered units remain on either side, the round ends: `has_ordered` flags reset, powder smoke clears, round counter advances.

### 4. Victory

Three end conditions, all surfacing via the same `_send_game_ended` broadcast:

| Condition | Winner | Reason string contains |
|---|---|---|
| One seat has no living units (and the other does) | Opposing seat | `"eliminated"` |
| One seat has no living Snobs | Opposing seat | `"Headless Chicken"` |
| `current_round > max_rounds` | Tiebreak by alive units, then by total alive models, then draw | `"Time expired"` |

On game end, every client:

1. Turn banner rewrites to `VICTORY / DEFEAT / DRAW — <reason>`.
2. A **Game Over overlay** appears: large coloured title, reason, rounds played, and surviving-unit counts for both sides.
3. A **Return to Main Menu** button disconnects the peer and navigates back to `main.tscn`. The other player stays in the battle scene until they click their own button (or you kill the client window).

#### Testing victory paths locally

The fastest way to force each path without an hour-long game:

- **Elimination / Headless Chicken** — during `order_execute`, have the opposing seat volley-fire / charge your weaker units until they're all dead (or all Snobs are dead). Works from a Balanced vs Gunline matchup in 2–3 rounds with lucky rolls.
- **Max-rounds expiry** — avoid combat for 4 rounds. Pick March every time on both seats. After round 4 ends with units still alive, the overlay should say `"Time expired — ..."` with the correct winner based on alive-unit count (or draw if equal).
- **Forcing a max-rounds draw** — use `--solo` mode with symmetric rosters on both seats (not possible without a helper), or temporarily edit `state.max_rounds = 1` in `game_engine.gd:_initialize_game_state` and watch the overlay fire after the first round.

#### What to check on the overlay

| Item | Expected |
|---|---|
| Title colour | Green for VICTORY, red for DEFEAT, yellow for DRAW |
| Rounds played | Clamped to `max_rounds` (4), not `current_round` which advances past it |
| Unit counts | `surviving / total` matches what you see on the board |
| Return button | Single click → main menu, no stuck state. Running a second `scripts/test-stack.sh` session should reconnect cleanly. |
| Double-firing | If the server happens to send two game_ended events, only one overlay should show (guarded by `has_node("GameOverOverlay")`) |

---

## What to check for

| Area | What should happen | Red flag |
|---|---|---|
| Sidebar panel visibility | Exactly one of placement / snob_select / declare / execute / self-order visible at a time, only on active seat's turn | Two panels at once, panel visible on opponent's turn |
| Command-range circle | Appears around Snob on declare, matches the target list exactly | Circle and target list disagree |
| Order button enable state | Disabled for invalid orders (volley_fire with no range, etc.) | Button stays enabled → server rejects the action |
| Blunder panic | `+1 panic` in unit info when order blundered | Panic not applied |
| Charge panic test | Target with panic tokens may fail (D6+tokens ≥ 7). Failed = +1 panic token, target retreats away from charger (D6 + 2" per token), melee skipped. Fearless (Brutes, Fodder 8+) get 3+ override. 0-token targets auto-pass. Board edge retreat = destroyed. | Panic test not logged, target doesn't move on failed test, melee always resolves |
| Melee bouts | Target passes panic → bout loop runs: attacker strikes, defender removes dead, defender counter-strikes (if alive), attacker removes dead. Winner = more unsaved wounds that bout; tied bouts repeat up to 3 before draw. Both survivors +1 panic after the melee; loser retreats (charger can end up retreating instead of holding the cell). | Only one side rolls, no counter-attack, melee always ends after one pass, charger always holds the cell regardless of outcome |
| Shooting engagement | Volley Fire / Move & Shoot resolves both sides simultaneously when target is eligible to return fire (has ranged weapon, no powder smoke, shooter in range — measured from post-move position for Move & Shoot). Casualties don't suppress return fire. Winner's loser retreats `D6 + 2"×tokens`; tie = no retreat. Each side gains +1 panic token per side that took hits. | Only shooter rolls, return fire ignored after heavy casualties, smoked unit still returns fire, tied engagement still retreats someone |
| Move & Shoot two-click | Destination staged → Confirm button appears | Confirm never appears, or first click executes immediately |
| 1" rule on march/move&shoot | Cardinal-adjacent (distance 1.0) cells next to enemies are rejected with `Cannot end move within 1" of enemy unit`. Snobs can end within 1" of friendly Followers; Followers cannot. Diagonal-adjacent (1.41") is legal. | Server accepts cardinal-adjacent landing, or rejects diagonal-adjacent |
| 1" rule on charge | Charge end-cell must be >1" from any non-target unit. If the only legal cells next to the target are within 1" of a third unit, charge fails with `No open cell adjacent to target`. | Charge succeeds with end-cell within 1" of a non-target friendly or enemy |
| Stand and Shoot | If the target passes its panic test and has a ranged weapon, no powder smoke, and isn't close-combat-equipped, it fires at the charger before melee. Charger takes wounds (and gains a panic token if any hit landed) before bouts begin. If the charger is wiped out by S&S, the charge ends with no melee and no movement; defender holds. Range and LoS are not required for S&S. | S&S never fires on a viable charge target, or fires after melee, or charger reaches melee at full strength after a hit-landing S&S |
| Round advance | `has_ordered` clears on all units, powder smoke gone | Units stay marked ordered across rounds |

---

## Inspecting logs

Per-process logs land in `test-logs/` (gitignored):

```bash
tail -f test-logs/server.log
tail -f test-logs/client1.log
```

The server logs all connection events and `Sending error to peer ...` lines — useful for catching client/server desyncs. Successful actions are not logged by default; if you need richer trace data add `print()` calls to `request_action()` in `godot/server/network_server.gd`.

**Logs are wiped** on every `rm -rf test-logs/` (which some of my relaunch commands do). If you're investigating a bug, copy the log out before relaunching.

---

## Error-handling spot checks

These should all surface server-side errors in `test-logs/server.log` and in the client's action log:

- Place outside deployment zone
- Place on an occupied cell
- Declare order on Follower outside command range
- Charge enemy out of `M + move_bonus` range
- March to a cell farther than allowed
- March or Move & Shoot to a cell within 1" of an enemy (server returns `Cannot end move within 1"...`)
- Act on opponent's turn (server returns `Not your turn`)

---

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `Identifier 'NetworkClient' not declared` on client startup | Project class cache stale. Run `$GODOT --headless --editor --quit` once to rebuild it. |
| Server logs `Mode: CLIENT` | `--server` flag not making it through. Check `scripts/test-stack.sh` invocation; `NetworkManager._ready()` checks both `get_cmdline_args()` and `get_cmdline_user_args()`. |
| One client's order button stays disabled when it shouldn't | Client-side `_can_receive_order()` in `battle.gd` disagrees with engine's `declare_order` validation. Either fix the mismatch or let the server reject the attempt. |
| Stuck in `order_execute` with no valid destination | Blundered move order with tight dice. Expected behavior — complete the order (even at distance 0 by clicking own current cell) to advance. |

---

## See Also

- [Testing Guidelines](Testing-Guidelines.md) — writing automated tests
- [Debugging Guide](Debugging-Guide.md) — general troubleshooting patterns
- [Project Setup](Project-Setup.md) — Godot install + `$GODOT` path per platform
