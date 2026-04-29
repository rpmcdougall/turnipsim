class_name Board
extends RefCounted
## Board geometry and movement validation.
##
## Pure RefCounted — no Node, no scene tree, no signals. Imported by both
## the server engine and the client renderer so deployment-zone bounds and
## distance math cannot drift between authoritative and presentation code.
##
## 1 cell = 1 inch. Distance is Euclidean (sqrt(dx² + dy²)) so diagonal
## ranges are geometrically correct; range visualizations are circles.

const BOARD_WIDTH: int = 48
const BOARD_HEIGHT: int = 32

# Deployment zones (4 rows each)
const DEPLOYMENT_ZONE_1_Y_MIN: int = 28  # Bottom (seat 1)
const DEPLOYMENT_ZONE_1_Y_MAX: int = 31
const DEPLOYMENT_ZONE_2_Y_MIN: int = 0   # Top (seat 2)
const DEPLOYMENT_ZONE_2_Y_MAX: int = 3


## Euclidean distance between two grid cells.
static func grid_distance(x1: int, y1: int, x2: int, y2: int) -> float:
	var dx: int = x2 - x1
	var dy: int = y2 - y1
	return sqrt(float(dx * dx + dy * dy))


## True if (x, y) is inside the board.
static func is_in_bounds(x: int, y: int) -> bool:
	return x >= 0 and x < BOARD_WIDTH and y >= 0 and y < BOARD_HEIGHT


## Validate that `unit` may end a non-charge move (march, move-and-shoot)
## on (x, y). Returns "" on success, else a human-readable error string.
## Checks:
##   - in bounds (board edges)
##   - cell not occupied by another live unit
##   - cell not on an objective marker (v17 p.22)
##   - 1" rule (v17 p.9):
##       * a Follower may not end within 1" of another friendly Follower
##       * any unit may not end within 1" of an enemy unit
##       * Snobs are exempt as either mover or near-unit for friendly checks
##         ("Snobs may be moved and end their moves within 1" of any
##         Friendly unit"); enemy proximity always applies regardless
##
## Charge moves are handled in Targeting.find_adjacent_cell (v17 p.17 is
## stricter — only the charge target gets the proximity exemption).
## Retreat is handled in Panic._is_valid_retreat_dest (any-other-unit rule).
static func validate_move(state: Types.GameState, unit: Types.UnitState, x: int, y: int) -> String:
	if not is_in_bounds(x, y):
		return "Coordinates out of bounds"
	for u in state.units:
		if not u.is_dead and u.x == x and u.y == y and u.id != unit.id:
			return "Position occupied"
	for obj in state.objectives:
		if obj.x == x and obj.y == y:
			return "Cannot end move on an objective marker"

	# 1" rule (v17 p.9). Snobs exempt as either mover or as a friendly
	# near-unit. Enemy proximity always counts.
	var mover_is_snob: bool = unit.is_snob()
	for u in state.units:
		if u.is_dead or u.id == unit.id:
			continue
		if u.x < 0 or u.y < 0:
			continue
		if grid_distance(x, y, u.x, u.y) > 1.0:
			continue
		if u.owner_seat != unit.owner_seat:
			return "Cannot end move within 1\" of enemy unit (%s)" % u.unit_type
		# Friendly within 1": only blocks if both mover and near-unit are
		# Followers (Snobs exempt either way).
		if not mover_is_snob and not u.is_snob():
			return "Cannot end move within 1\" of friendly Follower (%s)" % u.unit_type

	return ""
