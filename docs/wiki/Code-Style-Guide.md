# Code Style Guide

GDScript conventions and patterns for Turnip28 Simulator.

## General Principles

1. **Clarity over cleverness** - Code should be obvious, not clever
2. **Consistency** - Follow existing patterns in the codebase
3. **Type safety** - Use static typing wherever possible
4. **Pure functions** - Avoid side effects in game logic

## Formatting

### Indentation
- **Tabs, not spaces**
- Tab size: **4**

```gdscript
func my_function() -> void:
→   if condition:
→   →   do_something()
→   →   do_another_thing()
```

### Line Length
- **Soft limit: 100 characters**
- **Hard limit: 120 characters**
- Break long lines at logical points

```gdscript
# Good
var result = GameEngine.resolve_shoot(
	state,
	attacker_id,
	target_id,
	dice_results
)

# Avoid
var result = GameEngine.resolve_shoot(state, attacker_id, target_id, dice_results)
```

### Blank Lines
- **2 blank lines** between top-level functions
- **1 blank line** between class functions
- **1 blank line** to separate logical sections within functions

```gdscript
func function_one() -> void:
	var local_var = 1
	process(local_var)


func function_two() -> void:
	var another_var = 2
	process(another_var)
```

## Naming Conventions

### Variables and Functions
- **snake_case** for variables, functions, properties

```gdscript
var my_variable: int = 42
var player_count: int = 2

func calculate_damage(attacker: Unit, target: Unit) -> int:
	pass
```

### Constants
- **SCREAMING_SNAKE_CASE** for constants

```gdscript
const BOARD_WIDTH: int = 48
const BOARD_HEIGHT: int = 32
const MAX_PLAYERS: int = 32
```

### Classes
- **PascalCase** for class names

```gdscript
class Stats extends RefCounted:
	pass

class GameState extends RefCounted:
	pass
```

### Private/Internal
- **Leading underscore** for internal functions and variables

```gdscript
var _internal_state: Dictionary = {}

func _helper_function() -> void:
	pass

func public_function() -> void:
	_helper_function()
```

### Booleans
- Use **is_**, **has_**, **can_** prefixes

```gdscript
var is_dead: bool = false
var has_activated: bool = false
var can_move: bool = true
```

## Type Annotations

### Always Use Types

```gdscript
# Good
var health: int = 100
var player_name: String = "Player1"
var units: Array[Unit] = []

func calculate(a: int, b: int) -> int:
	return a + b

# Bad
var health = 100
var player_name = "Player1"
var units = []

func calculate(a, b):
	return a + b
```

### Typed Arrays

```gdscript
# Good - Typed array
var units: Array[UnitState] = []
var mutations: Array[Mutation] = []

# Use append with typed arrays
units.append(unit)

# Bad - Untyped or wrong assignment
var units = []
units = [unit1, unit2]  # Fails with typed arrays
```

### Null Safety

```gdscript
# Make nullability explicit
var nullable_value: Variant = null
var required_value: String = ""  # Never null

# Check before use
if nullable_value != null:
	use(nullable_value)
```

## Class Structure

### Order of Members

1. Class documentation
2. Constants
3. Exports
4. Public variables
5. Private variables
6. Lifecycle methods (_ready, _process, etc.)
7. Public methods
8. Private methods
9. Inner classes

```gdscript
extends RefCounted
## Brief description of class purpose
##
## Longer explanation if needed


const MAX_VALUE: int = 100

@export var public_property: int = 0

var public_variable: int = 0
var _private_variable: int = 0


func _init() -> void:
	pass


func public_method() -> void:
	_private_method()


func _private_method() -> void:
	pass


class InnerClass extends RefCounted:
	pass
```

## Comments and Documentation

### File Headers

```gdscript
extends Node
## Brief one-line description
##
## Longer multi-line description explaining the purpose,
## architecture, and key concepts.
##
## Usage example:
## [codeblock]
## var instance = MyClass.new()
## instance.do_something()
## [/codeblock]
```

### Function Documentation

```gdscript
## Brief one-line description
##
## Detailed explanation of what the function does, how it works,
## and any important caveats.
##
## Parameters:
## - state: The current game state (immutable, will be cloned)
## - unit_id: ID of the unit to move
## - x: Target X coordinate
## - y: Target Y coordinate
##
## Returns:
## EngineResult with success status, new state, or error message
func move_unit(
	state: GameState,
	unit_id: String,
	x: int,
	y: int
) -> EngineResult:
	pass
```

### Inline Comments

```gdscript
# Use comments to explain WHY, not WHAT
# Good
# Calculate hit threshold: 7 - (shooter skill + weapon bonus)
var to_hit = 7 - (shooter_stat + weapon_modifier)

# Bad
# Set to_hit to 7 minus shooter_stat plus weapon_modifier
var to_hit = 7 - (shooter_stat + weapon_modifier)
```

## Control Flow

### If Statements

```gdscript
# Single-line: OK for simple cases
if condition: return early_value

# Multi-line: Always use braces and proper indentation
if complex_condition:
	do_something()
	do_another_thing()
elif other_condition:
	do_alternative()
else:
	do_default()
```

### Match Statements

```gdscript
# Prefer match over long if-elif chains
match action_type:
	"place_unit":
		result = GameEngine.place_unit(state, unit_id, x, y)

	"move":
		result = GameEngine.move_unit(state, unit_id, x, y)

	"shoot":
		var dice = [_roll_d6(), _roll_d6(), _roll_d6()]
		result = GameEngine.resolve_shoot(state, attacker_id, target_id, dice)

	_:
		push_error("Unknown action type: " + action_type)
		return
```

### Early Returns

```gdscript
# Good - Early validation returns
func validate_action(state: GameState) -> EngineResult:
	if state.phase != "combat":
		return EngineResult.error("Not in combat phase")

	if not is_valid_target():
		return EngineResult.error("Invalid target")

	# Main logic here
	return EngineResult.success(new_state)

# Bad - Deep nesting
func validate_action(state: GameState) -> EngineResult:
	if state.phase == "combat":
		if is_valid_target():
			# Main logic deeply nested
			return EngineResult.success(new_state)
		else:
			return EngineResult.error("Invalid target")
	else:
		return EngineResult.error("Not in combat phase")
```

## Functions

### Keep Functions Small

**Target: < 30 lines per function**

```gdscript
# Good - Extracted helpers
func process_combat(state: GameState) -> GameState:
	var attacker = _find_active_unit(state)
	var target = _find_target(state, attacker)
	var result = _roll_combat(attacker, target)
	return _apply_damage(state, target, result)

# Bad - One huge function
func process_combat(state: GameState) -> GameState:
	# 100 lines of inline logic...
	pass
```

### Single Responsibility

```gdscript
# Good - Each function does one thing
func calculate_to_hit(stat: int, modifier: int) -> int:
	return 7 - stat - modifier

func roll_to_hit(threshold: int, dice: int) -> bool:
	return dice >= threshold

# Bad - Function does too much
func resolve_attack(attacker, target, dice):
	var to_hit = 7 - attacker.stat - attacker.weapon.modifier
	if dice >= to_hit:
		var to_wound = 7 - attacker.combat
		# ... mixing calculations and logic
```

### Pure Functions (game/ folder)

```gdscript
# Good - Pure, testable
static func place_unit(
	state: GameState,
	unit_id: String,
	x: int,
	y: int
) -> EngineResult:
	var new_state = _clone_state(state)
	# Modify new_state, return result
	return EngineResult.success(new_state)

# Bad - Mutates input, side effects
func place_unit(unit_id: String, x: int, y: int) -> void:
	self.state.units[0].x = x  # Mutates class state
	_broadcast_to_clients()     # Network side effect
```

## Error Handling

### Result Pattern

```gdscript
# Use EngineResult for operations that can fail
class EngineResult extends RefCounted:
	var success: bool
	var error: String
	var new_state: GameState

	static func success(state: GameState) -> EngineResult:
		var result = EngineResult.new()
		result.success = true
		result.new_state = state
		return result

	static func error(message: String) -> EngineResult:
		var result = EngineResult.new()
		result.success = false
		result.error = message
		return result

# Usage
var result = GameEngine.move_unit(state, unit_id, x, y)
if not result.success:
	print("Error: " + result.error)
	return
```

### Assertions

```gdscript
# Use asserts for impossible states (debug builds only)
assert(units.size() > 0, "Units array should never be empty")
assert(active_seat == 1 or active_seat == 2, "Invalid seat number")

# Use explicit errors for runtime validation
if active_seat != 1 and active_seat != 2:
	return EngineResult.error("Invalid seat: " + str(active_seat))
```

## Godot-Specific

### Signals

```gdscript
# Use past tense for signal names
signal unit_moved(unit_id: String, x: int, y: int)
signal combat_resolved(attacker_id: String, target_id: String, damage: int)

# Connect signals
unit_moved.connect(_on_unit_moved)
```

### Node References

```gdscript
# Cache node references in _ready
@onready var label: Label = $UI/TurnBanner
@onready var units_container: Node2D = $UnitsContainer

func _ready() -> void:
	label.text = "Game Start"
```

### RPC Calls

```gdscript
# Client → Server: Use .rpc_id(1, ...)
request_action.rpc_id(1, action_data)

# Server → All: Use .rpc_id(peer_id, ...) in loop
for player in room.players:
	_send_state_update.rpc_id(player["peer_id"], state_data)
```

## Security

### Validate All Inputs

```gdscript
# Server-side RPC handlers MUST validate
@rpc("any_peer", "call_remote", "reliable")
func request_action(action_data: Dictionary) -> void:
	var peer_id = multiplayer.get_remote_sender_id()

	# Validate peer is in game
	if not _is_valid_peer(peer_id):
		return

	# Validate it's their turn
	if not _is_peer_turn(peer_id):
		_send_error.rpc_id(peer_id, "Not your turn")
		return

	# Validate action data
	if not action_data.has("type"):
		_send_error.rpc_id(peer_id, "Missing action type")
		return

	# Process action...
```

### Avoid Command Injection

```gdscript
# Bad - User input in file paths
var path = "res://saves/" + player_name + ".save"  # Could be "../../../etc/passwd"

# Good - Sanitize input
var safe_name = player_name.validate_filename()
var path = "res://saves/" + safe_name + ".save"
```

## Performance

### Avoid Unnecessary Allocations

```gdscript
# Good - Reuse container
var results: Array[int] = []
for unit in units:
	results.append(process(unit))

# Bad - Creates array every loop
for unit in units:
	var results = []  # Allocates every iteration
	results.append(process(unit))
```

### Cache Expensive Calculations

```gdscript
# Good - Calculate once
var effective_stats = unit.get_effective_stats()
var to_hit = 7 - effective_stats.shooting
var to_wound = 7 - effective_stats.combat

# Bad - Recalculates 3 times
var to_hit = 7 - unit.get_effective_stats().shooting
var to_wound = 7 - unit.get_effective_stats().combat
var save = unit.get_effective_stats().save
```

## See Also

- [Testing Guidelines](Testing-Guidelines.md) - Writing testable code
- [Development Process](Development-Process.md) - Workflow and commits
- [Architecture Overview](Architecture-Overview.md) - System design
- [GDScript Style Guide (Official)](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/gdscript_styleguide.html)
