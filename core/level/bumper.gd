@tool
class_name Bumper
extends Node2D
## A springy bumper: always kicks the ball away hard. Pink, white ring, wobbles when hit.

@export var radius := 28.0:
	set(v): radius = v; queue_redraw()

var _hit_at := -10.0
var _time := 0.0


func _init() -> void:
	z_index = 3


func hit() -> void:
	_hit_at = _time


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += dt
	if _time - _hit_at < 1.0:
		queue_redraw()


func _draw() -> void:
	var age := _time - _hit_at
	var wob := sin(age * 38.0) * exp(-age * 7.0) * 6.0 if age < 1.0 else 0.0
	var r := radius + wob
	draw_circle(Vector2(0, 6), r + 5.0, Palette.shadow(0.15))
	draw_circle(Vector2.ZERO, r + 5.0, Palette.WHITE)
	draw_circle(Vector2(0, 4), r, Palette.PINK_DEEP)
	draw_circle(Vector2.ZERO, r - 2.0, Palette.PINK)
	draw_circle(Vector2(-r * 0.3, -r * 0.35), r * 0.25, Color(1, 1, 1, 0.5))
