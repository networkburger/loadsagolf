@tool
class_name Tee
extends Node2D
## Where balls start. 1P starts on the node; 2P starts at ±spread along spread_dir.

@export var spread_2p := 40.0:
	set(v): spread_2p = v; queue_redraw()
@export var spread_dir := Vector2.DOWN:
	set(v): spread_dir = v; queue_redraw()

var two_player := false:
	set(v): two_player = v; queue_redraw()


func _init() -> void:
	z_index = 1


## Spawn points in the Tee's parent's space.
func spawn_points(two: bool) -> Array[Vector2]:
	if not two:
		return [position]
	var d := spread_dir.normalized() * spread_2p
	return [position - d, position + d]


func _draw() -> void:
	if Engine.is_editor_hint():
		# Show both layouts in the editor.
		draw_circle(Vector2.ZERO, 22.0, Color(1, 1, 1, 0.28))
		var d := spread_dir.normalized() * spread_2p
		for p in [-d, d]:
			draw_arc(p, 14.0, 0, TAU, 24, Color(1, 1, 1, 0.6), 2.0, true)
		return
	for p in spawn_points(two_player):
		draw_circle(p - position, 22.0, Color(1, 1, 1, 0.28))
