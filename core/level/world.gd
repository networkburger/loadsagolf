class_name World
extends Resource
## One world: a theme and an ordered list of holes.

@export var id: StringName
@export var color := Palette.GREEN    ## theme accent (map, UI)
@export var levels: Array[PackedScene] = []
