class_name WorldList
extends Resource
## The game's running order: worlds in order, each with its holes in order.
## Edit levels/worlds.tres in the inspector to reorder or add holes.

@export var worlds: Array[World] = []


func level_count() -> int:
	var n := 0
	for w in worlds:
		n += w.levels.size()
	return n
