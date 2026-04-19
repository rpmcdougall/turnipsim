# V17 Order Sequence Implementation Plan

## Context

Replacing free-form move/shoot/charge with the full Turnip28 v17 order sequence. The orders phase becomes multi-step: select snob → declare order (with blunder check) → execute order → advance to next player.

**Branch**: `feature/order-mechanics`

## Status

- [x] Step 1: GameState + UnitState field additions (commit 314c7b4)
- [x] Step 2: Engine state machine (commit 55278f9)
- [ ] Step 3: Network server action routing
- [ ] Step 4: Client UI rewrite
- [ ] Step 5: Engine tests rewrite

## Acceptable Simplifications (for now)
- No retreat movement (panic test adds panic but no physical retreat)
- No Stand and Shoot on charge
- No return fire on shooting (one-way)
- No melee bouts (single resolution)
- March/charge movement is Manhattan distance with dice bonus cells

## Step 1: GameState + UnitState Changes (`godot/game/types.gd`) ✅

**GameState new fields:**
- `order_phase: String` — `"snob_select"`, `"order_declare"`, `"order_execute"`, `"follower_self_order"`
- `current_snob_id: String` — Snob currently issuing order
- `current_order_unit_id: String` — unit receiving the order
- `current_order_type: String` — `"volley_fire"`, `"move_and_shoot"`, `"march"`, `"charge"`
- `current_order_blundered: bool`
- `current_order_move_bonus: int` — dice-rolled bonus movement (for march/charge)

**UnitState:** Renamed `has_activated` → `has_ordered`

## Step 2: Engine State Machine (`godot/server/game_engine.gd`) ✅

### New functions:

**`select_snob(state, snob_id)`** — Pick a Snob to Make Ready. Validates ownership, alive, not yet ordered. Transitions to `"order_declare"`.

**`declare_order(state, unit_id, order_type, blunder_die, move_dice)`** — Pick unit + order type. Validates command range (Manhattan distance ≤ snob's range). Blunder check: if ordering a follower (not self), `blunder_die == 1` → blundered + panic token. For march/charge: computes `move_bonus` from dice (2D6 normal, 1D6 if blundered). Transitions to `"order_execute"`.

**`execute_order(state, params, dice_results)`** — Dispatches by `current_order_type`:
- **volley_fire**: `{target_id}` — Shoot with -1 Inaccuracy (no bonus if blundered)
- **move_and_shoot**: `{x, y, target_id}` — Move up to M" (D6" if blundered), then shoot
- **march**: `{x, y}` — Move M + move_bonus cells
- **charge**: `{target_id}` — Move to cell adjacent to target within M + move_bonus, resolve melee

**`declare_self_order(state, unit_id, order_type, blunder_die, move_dice)`** — For follower_self_order phase. No snob, always blunder-checks.

**`_advance_after_order(state)`** — Marks units ordered, switches players:
1. Other player has unordered snobs → switch seat, `"snob_select"`
2. No snobs left → check for unordered followers → `"follower_self_order"`
3. No unordered followers → `_end_round(state)`

**`_end_round(state)`** — Clear has_ordered, clear powder smoke, advance round, check max_rounds.

### Removed functions:
`move_unit`, `resolve_shoot`, `resolve_charge`, `end_activation`, `end_turn`

### Combat helpers (shared by all order types):
- `_resolve_shooting(attacker, target, dice, inaccuracy_mod)` — 1 attack/model, I roll, V save, powder smoke, panic
- `_resolve_melee(attacker, target, dice)` — A attacks/model, I roll, V save, CC equipment bonus

## Step 3: Network Server (`godot/server/network_server.gd`)

Replace action routing `match` block in `request_action()`:

```
"select_snob"      → GameEngine.select_snob(state, snob_id)
"declare_order"    → roll blunder_die + move_dice, pass to GameEngine.declare_order()
"execute_order"    → roll combat dice, pass to GameEngine.execute_order()
"declare_self_order" → roll blunder_die + move_dice, pass to GameEngine.declare_self_order()
```

Keep: `"place_unit"`, `"confirm_placement"`
Remove: `"move"`, `"shoot"`, `"charge"`, `"end_activation"`, `"end_turn"`

Dice rolling: server rolls blunder_die (1 D6), move_dice (2 D6), combat dice (varies by unit) and injects into engine.

## Step 4: Client UI (`godot/client/scenes/battle.gd`)

Rewrite orders panel to be phase-aware:

**`order_phase == "snob_select"`:** Show alive un-ordered Snobs as buttons. Click → send `{type: "select_snob", snob_id}`.

**`order_phase == "order_declare"`:** Show followers in command range. Show 4 order buttons (Volley Fire, Move & Shoot, March, Charge) — disabled if invalid. Click unit + order → send `{type: "declare_order", unit_id, order_type}`.

**`order_phase == "order_execute"`:** Per order type:
- Volley Fire: click enemy → `{type: "execute_order", target_id}`
- Move & Shoot: click cell + enemy → `{type: "execute_order", x, y, target_id}`
- March: click cell → `{type: "execute_order", x, y}`
- Charge: click enemy → `{type: "execute_order", target_id}`

**`order_phase == "follower_self_order"`:** Auto-highlight next unordered follower. Show order buttons. → `{type: "declare_self_order", unit_id, order_type}`.

**`grid_draw.gd`:** Add command range diamond overlay when snob selected.

## Step 5: Tests (`godot/tests/test_game_engine.gd`)

Rewrite all orders-phase tests:
- Snob selection (valid, invalid, already ordered)
- Declare order (command range, blunder, invalid order type)
- Execute each order type (volley fire ±bonus, march distance, charge + melee)
- Advance logic (switch players, follower self-order, round end)
- Full round flow

## Key Design Decisions

- **Blunder check embedded in declare_order** — fewer round-trips, result stored in state
- **Move bonus dice rolled during declare** — stored in `current_order_move_bonus` so client can show range overlay before player picks destination
- **Single execute_order function** dispatches by order type — simpler server routing
- **_advance_after_order handles all turn flow** — alternating snobs, then followers, then round end
