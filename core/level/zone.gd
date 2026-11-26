@tool
class_name Zone
extends Node2D
## A sunken patch of a different surface (sand slows the ball, water splashes it
## back to its last resting spot). Centred on the node; no rotation or scale.

enum Surface { SAND, WATER }

@export var surface := Surface.SAND:
	set(v): surface = v; queue_redraw()
@export var size := Vector2(200, 140):
	set(v): size = v; queue_redraw()
@export var corner_radius := 28.0:
	set(v): corner_radius = v; queue_redraw()

const SAND := Color("#ffe29a")
const SAND_SHADE := Color("#f2b93b")
const WATER_SHADE := Color("#2f8fd9")

var _splashes: Array = []   ## [local pos, start time]
var _time := 0.0


func _init() -> void:
	z_index = 1


func rect() -> Rect2:
	return Rect2(-size / 2, size)


func surface_name() -> StringName:
	return &"sand" if surface == Surface.SAND else &"water"


func splash(level_pos: Vector2) -> void:
	_splashes.append([level_pos - position, _time])


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		return
	_time += dt
	_splashes = _splashes.filter(func(s): return _time - s[1] < 1.2)
	if surface == Surface.WATER or not _splashes.is_empty():
		queue_redraw()


func _draw() -> void:
	var r := rect()
	var shade := _box(SAND_SHADE if surface == Surface.SAND else WATER_SHADE)
	var fill := _box(SAND if surface == Surface.SAND else Palette.SKY)
	draw_style_box(shade, r)
	draw_style_box(fill, Rect2(r.position + Vector2(0, 6), r.size - Vector2(0, 6)))
	if surface == Surface.WATER:
		for k in 2:
			var ph := fmod(_time * 0.5 + k * 0.5, 1.0)
			draw_arc(Vector2(0, 3), 10.0 + ph * minf(42.0, size.y * 0.35), 0, TAU, 40, Color(1, 1, 1, 0.55 * (1.0 - ph)), 3.0, true)
		draw_line(r.position + Vector2(26, 30), r.position + Vector2(50, 30), Color(1, 1, 1, 0.6), 4.0, true)
		draw_line(r.end - Vector2(56, 26), r.end - Vector2(38, 26), Color(1, 1, 1, 0.6), 4.0, true)
	else:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(size)
		for k in int(size.x * size.y / 3500.0):
			var p := r.position + Vector2(rng.randf_range(20, size.x - 20), rng.randf_range(22, size.y - 16))
			draw_circle(p, 2.5, SAND_SHADE)
	for s in _splashes:
		var age: float = _time - s[1]
		for k in 3:
			var a := age - k * 0.12
			if a > 0.0:
				draw_arc(s[0], 8.0 + a * 70.0, 0, TAU, 32, Color(1, 1, 1, maxf(0.0, 0.9 - a)), 3.0, true)


func _box(col: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = col
	s.set_corner_radius_all(int(corner_radius))
	s.anti_aliasing = true
	s.corner_detail = 12
	return s
