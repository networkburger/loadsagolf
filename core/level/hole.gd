@tool
class_name Hole
extends Node2D
## The cup and its flag. The flag is drawn on a high layer so balls pass under it.

const TUNING := preload("res://core/tuning.tres")

var winner_color: Variant = null   ## 2P: crown + flag in the winning ball's colour
var _flag: Node2D
var _flash_at := -10.0
var _time := 0.0


func _init() -> void:
	z_index = 2


func _ready() -> void:
	_flag = Node2D.new()
	_flag.z_index = 7
	_flag.z_as_relative = false
	_flag.draw.connect(_draw_flag)
	add_child(_flag, false, Node.INTERNAL_MODE_FRONT)


func flash() -> void:
	_flash_at = _time


func _process(dt: float) -> void:
	_time += dt
	queue_redraw()
	if _flag:
		_flag.queue_redraw()


func _draw() -> void:
	var r: float = TUNING.hole_radius
	draw_circle(Vector2(0, -2), r + 3.0, Palette.shadow(0.18))
	draw_circle(Vector2.ZERO, r, Palette.INK)
	draw_circle(Vector2(0, 4), r - 4.0, Palette.INK.darkened(0.25))
	var age := _time - _flash_at
	if age < 0.7:
		var f := age / 0.7
		draw_circle(Vector2.ZERO, r + f * 40.0, Color(1, 1, 1, 0.85 * (1.0 - f)))


func _draw_flag() -> void:
	var c := _flag
	# picslide "nudge": every few seconds the flag gives a little wiggle.
	var cycle := fmod(_time, 2.4) / 2.4
	var nudge := 0.0
	if cycle > 0.7:
		nudge = sin((cycle - 0.7) / 0.3 * TAU) * 0.12 * (1.0 - (cycle - 0.7) / 0.3)
	var base := Vector2(5, -6)
	var top := base + Vector2(0, -68).rotated(nudge)
	c.draw_line(base + Vector2(0, 4), top + Vector2(0, 4), Palette.shadow(0.15), 5.0, true)
	c.draw_line(base, top, Palette.WHITE, 5.0, true)
	var wave := sin(_time * 4.0) * 4.0
	var col: Color = winner_color if winner_color != null else Palette.CORAL
	var dir := Vector2(1, 0).rotated(nudge)
	var down := Vector2(0, 1).rotated(nudge)
	c.draw_colored_polygon(PackedVector2Array([top, top + dir * 40 + down * (11 + wave), top + down * 24]), col)
	c.draw_circle(top, 5.0, Palette.YELLOW)
	if winner_color != null:
		var at := top + Vector2(0, -18)
		var pts := PackedVector2Array([at + Vector2(-15, 9), at + Vector2(-15, -7), at + Vector2(-7, 2),
			at + Vector2(0, -11), at + Vector2(7, 2), at + Vector2(15, -7), at + Vector2(15, 9)])
		var sh := PackedVector2Array()
		for p in pts:
			sh.append(p + Vector2(0, 3))
		c.draw_colored_polygon(sh, Palette.shadow(0.2))
		c.draw_colored_polygon(pts, Palette.YELLOW)
