class_name GameEngine
extends RefCounted
## Authoritative game engine. Takes a Ruleset + roll_d6 Callable.
##
## Usage:
##   var engine = GameEngine.new()
##   engine.init(ruleset, func(): return randi_range(1, 6))
