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


## Validate that `unit` may end its move on (x, y). Returns "" on success,
## else a human-readable error string. Checks bounds, occupancy by other
## live units, and the v17 rule that a unit may move across an objective
## but not finish a move on top of one (v17 core p.22).
static func validate_move(state: Types.GameState, unit: Types.UnitState, x: int, y: int) -> String:
	if not is_in_bounds(x, y):
		return "Coordinates out of bounds"
	for u in state.units:
		if not u.is_dead and u.x == x and u.y == y and u.id != unit.id:
			return "Position occupied"
	for obj in state.objectives:
		if obj.x == x and obj.y == y:
			return "Cannot end move on an objective marker"
	return ""
