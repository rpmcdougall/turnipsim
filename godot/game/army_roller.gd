class_name ArmyRoller
extends RefCounted
## Generates a random army from a Ruleset using injected dice rolls.
##
## Usage:
##   var roller = ArmyRoller.new()
##   var army = roller.roll_army(ruleset, func(): return randi_range(1, 6))
