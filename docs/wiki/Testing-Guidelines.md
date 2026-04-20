# Testing Guidelines

This guide covers how to write, run, and maintain tests for Turnip28 Simulator.

## Testing Philosophy

**Core principles:**
1. **Pure functions are deterministic** - Inject dependencies (dice, RNG) for reproducibility
2. **Test behavior, not implementation** - Focus on what code does, not how
3. **Fast feedback loops** - Tests should run quickly (headless mode)
4. **No flaky tests** - Avoid timing, race conditions, random failures

## Test Structure

### Test File Organization

```
godot/tests/
├── test_runner.gd              # Phase 1: types, ruleset, roster validation (19 tests)
├── test_game_engine.gd         # Engine: order state machine, combat (48 tests)
├── test_ui_instantiate.gd      # UI scene loading tests
├── test_phase3_scenes.gd       # Phase 3 networking tests
└── demo_army_roll.gd           # Manual demo (not automated)
```

Set `GODOT` in your shell (see [Project Setup](Project-Setup.md)) so the snippets below resolve.

### Test File Template

```gdscript
extends Node
## Test suite for <component name>
## Run with: godot --headless -s tests/test_<name>.gd

var passed: int = 0
var failed: int = 0

func _ready() -> void:
	print("\n=== Running <Component> Tests ===\n")

	# Run test methods
	_test_feature_one()
	_test_feature_two()
	_test_edge_case()

	# Print results
	print("\n=== Test Results ===")
	print("Passed: %d" % passed)
	print("Failed: %d" % failed)

	# Exit with appropriate code
	if failed > 0:
		OS.exit_code = 1
	get_tree().quit()

func _test_feature_one() -> void:
	var result = MyClass.my_function(input)
	_assert_equal(result, expected, "Feature one should return expected value")

func _assert_equal(actual, expected, message: String) -> void:
	if actual == expected:
		print("✓ PASS: %s" % message)
		passed += 1
	else:
		print("✗ FAIL: %s" % message)
		print("  Expected: %s" % str(expected))
		print("  Actual:   %s" % str(actual))
		failed += 1

func _assert_true(condition: bool, message: String) -> void:
	if condition:
		print("✓ PASS: %s" % message)
		passed += 1
	else:
		print("✗ FAIL: %s" % message)
		failed += 1
```

## Running Tests

### Single Test Suite
```bash
cd godot/
$GODOT --headless -s tests/test_runner.gd
```

### All Tests
```bash
cd godot/

# Phase 1 tests
$GODOT --headless -s tests/test_runner.gd

# Phase 4 engine tests
$GODOT --headless -s tests/test_game_engine.gd

# UI tests
$GODOT --headless -s tests/test_ui_instantiate.gd

# Phase 3 scene tests
$GODOT --headless -s tests/test_phase3_scenes.gd
```

### CI Testing
Tests run automatically on GitHub Actions for:
- Pull requests to `main`
- Pushes to `main`

See `.github/workflows/tests.yml` for configuration.

## Writing Tests

### Testing Pure Functions

**Example: Game engine function**

```gdscript
func _test_place_unit_valid_position() -> void:
	# Arrange: Create test state
	var state = _mock_game_state()
	state.phase = "placement"
	state.active_seat = 1

	var unit = state.units[0]
	unit.owner_seat = 1
	unit.x = -1  # Not placed yet
	unit.y = -1

	# Act: Place unit in valid deployment zone
	var result = GameEngine.place_unit(state, unit.id, 10, 30)

	# Assert: Success and position updated
	_assert_true(result.success, "Should place unit in valid zone")
	_assert_equal(result.new_state.units[0].x, 10, "Unit x should be updated")
	_assert_equal(result.new_state.units[0].y, 30, "Unit y should be updated")
```

### Testing with Injected Dependencies

**Example: Army roller with deterministic dice**

```gdscript
func _test_declare_order_deterministic() -> void:
	var state = _mock_orders_state()
	state = GameEngine.select_snob(state, state.units[0].id).new_state

	# blunder_die=3 (no blunder), move_dice=[4, 2] → move_bonus = 6
	var result = GameEngine.declare_order(
		state, state.units[2].id, "march", 3, [4, 2]
	)

	_assert_true(result.success, "March order should be declared")
	_assert_equal(result.new_state.current_order_move_bonus, 6,
		"Unblundered march bonus is sum of both dice")
```

Engine functions take dice as explicit arguments — the server rolls them and injects. This makes every test fully reproducible without mocking RNG.

### Testing Error Cases

```gdscript
func _test_place_unit_invalid_zone() -> void:
	var state = _mock_game_state()
	state.phase = "placement"
	state.active_seat = 1

	var unit = state.units[0]
	unit.owner_seat = 1

	# Try to place in opponent's zone
	var result = GameEngine.place_unit(state, unit.id, 10, 2)

	# Should fail
	_assert_true(not result.success, "Should reject invalid zone")
	_assert_true(result.error.contains("deployment zone"), "Error should mention zone")
```

### Testing with Mock Data

**Create mock state generators.** See `godot/tests/test_game_engine.gd` for a full set — the v17 stat names are M/A/I/W/V (movement, attacks, inaccuracy, wounds, vulnerability):

```gdscript
func _mock_unit(id: String, seat: int, unit_type: String, category: String,
		m: int, a: int, i: int, w: int, v: int, wr: int, models: int
) -> Types.UnitState:
	var stats = Types.Stats.new(m, a, i, w, v, wr)
	var rules: Array[String] = []
	return Types.UnitState.new(
		id, seat, unit_type, category, models, models, stats, "black_powder", rules
	)

func _mock_orders_state() -> Types.GameState:
	var state = Types.GameState.new()
	state.phase = "orders"
	state.order_phase = "snob_select"
	state.active_seat = 1
	state.initiative_seat = 1
	# 1 Snob + 1 Follower per seat at known positions
	state.units.append(_mock_unit("u0", 1, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1))
	state.units.append(_mock_unit("u1", 2, "Toff", "snob", 6, 2, 5, 2, 5, 6, 1))
	state.units.append(_mock_unit("u2", 1, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12))
	state.units.append(_mock_unit("u3", 2, "Fodder", "infantry", 6, 1, 6, 1, 6, 0, 12))
	state.units[0].x = 10; state.units[0].y = 30
	state.units[1].x = 10; state.units[1].y = 2
	state.units[2].x = 12; state.units[2].y = 30
	state.units[3].x = 12; state.units[3].y = 2
	return state
```

## Test Coverage Goals

### Phase 1: Game Logic
- [x] Ruleset loading (valid and malformed JSON)
- [x] Army roller determinism
- [x] Mutation application
- [x] Unit stat calculations

### Engine (v17 order state machine)
- [x] Placement phase (zones, bounds, occupation)
- [x] Snob selection (ownership, phase gating, already-ordered rejection)
- [x] Declare order (command range, blunder check, equipment constraints, self-order bypass)
- [x] Declare self-order (follower_self_order phase)
- [x] Execute volley fire (±1 Inaccuracy bonus, powder smoke, multi-model)
- [x] Execute move & shoot (blundered 1D6 cap)
- [x] Execute march (unblundered 2D6 / blundered 1D6)
- [x] Execute charge (adjacency pathfinding, close_combat equipment)
- [x] Advance flow (seat switching, follower self-order, round end, max rounds, powder smoke reset)
- [x] Victory conditions (elimination, Headless Chicken, solo mode)

### Phase 3: Networking (Manual)
- [ ] Room creation and joining
- [ ] Ready status synchronization
- [ ] Army submission
- [ ] State broadcasting

### Phase 4: Client UI (Manual)
- [ ] Placement UI flow
- [ ] Combat UI interactions
- [ ] Error message display
- [ ] Victory screen

## Common Patterns

### Testing State Immutability

```gdscript
func _test_engine_does_not_mutate_input() -> void:
	var original_state = _mock_game_state()
	var original_unit_x = original_state.units[0].x

	# Call engine function
	var result = GameEngine.place_unit(original_state, "unit_0", 10, 30)

	# Original state should be unchanged
	_assert_equal(original_state.units[0].x, original_unit_x,
		"Original state should not be mutated")
	_assert_equal(result.new_state.units[0].x, 10,
		"New state should have updated value")
```

### Testing Typed Arrays

```gdscript
func _test_typed_array_handling() -> void:
	var state = Types.GameState.new()

	# Don't assign directly with typed arrays
	# state.units = [unit1, unit2]  # ❌ Will fail

	# Use append instead
	state.units.append(unit1)  # ✅ Correct
	state.units.append(unit2)

	_assert_equal(state.units.size(), 2, "Should have 2 units")
```

### Testing Error Messages

```gdscript
func _test_helpful_error_messages() -> void:
	var result = GameEngine.move_unit(state, "nonexistent_unit", 10, 20)

	_assert_true(not result.success, "Should fail for missing unit")
	_assert_true(result.error.contains("not found"),
		"Error should mention unit not found")
	_assert_true(result.error.contains("nonexistent_unit"),
		"Error should include unit ID")
```

## Debugging Failed Tests

### Enable Verbose Output

```gdscript
func _test_complex_scenario() -> void:
	print("  State before: %s" % state.to_dict())
	var result = GameEngine.some_function(state, params)
	print("  Result: %s" % result.to_dict())
	print("  State after: %s" % result.new_state.to_dict())

	_assert_true(result.success, "Should succeed")
```

### Isolate Failing Test

```gdscript
func _ready() -> void:
	# Comment out all other tests
	# _test_passing_one()
	# _test_passing_two()
	_test_failing_one()  # Focus on this

	# ...
```

### Check Godot Console

```bash
# Run without --headless to see Godot's output window
$GODOT -s tests/test_game_engine.gd
```

## Performance Testing

### Measure Test Runtime

```gdscript
func _ready() -> void:
	var start_time = Time.get_ticks_msec()

	# Run all tests
	_test_suite()

	var elapsed = Time.get_ticks_msec() - start_time
	print("Total test time: %d ms" % elapsed)
```

### Optimize Slow Tests

- Reduce mock data size
- Avoid unnecessary deep copies
- Skip rendering in headless mode
- Use test-specific simplified logic

## Integration Testing

For features requiring full client/server interaction, use `scripts/test-stack.sh` rather than launching Godot instances by hand. See the [Manual Testing Guide](Manual-Testing-Guide.md) for the end-to-end procedure.

## See Also

- [Code Style Guide](Code-Style-Guide.md) - GDScript conventions
- [Debugging Guide](Debugging-Guide.md) - Troubleshooting tests
- [Game Engine API](Game-Engine-API.md) - Engine function reference
