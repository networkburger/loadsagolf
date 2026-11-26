class_name Fx
extends Node2D
## Sparkles and confetti: a port of picslide's fx.ts. Lives in screen space
## (put it on a CanvasLayer above the game); pass screen positions.

enum Shape { STAR, DOT, RIBBON }

class Particle:
	var pos: Vector2
	var vel: Vector2
	var rot: float
	var vr: float
	var size: float
	var life := 0.0
	var max_life: float
	var color: Color
	var shape: int
	var gravity: float
	var drag: float

var _particles: Array[Particle] = []


## Small radial burst of stars, e.g. when the ball drops in.
func sparkle(at: Vector2, count := 16, spread := 1.0) -> void:
	for i in count:
		var a := float(i) / count * TAU + randf_range(-0.2, 0.2)
		var speed := randf_range(180.0, 420.0) * spread
		_add(at, Vector2.from_angle(a) * speed, randf_range(6, 13), randf_range(0.5, 0.9),
			Palette.SPARKLE.pick_random(), Shape.STAR if randf() < 0.7 else Shape.DOT, 300.0, 3.2)


## Confetti cannons from both bottom corners plus a gentle rain from the top.
func celebrate() -> void:
	var r := get_viewport_rect()
	var w := r.size.x
	var h := r.size.y
	for side: int in [-1, 1]:
		for i in 90:
			var a := -PI / 2 + side * randf_range(0.15, 0.6)
			var speed := randf_range(700.0, 1400.0) * minf(1.0, h / 800.0 + 0.3)
			_add(Vector2(0.0 if side < 0 else w, h), Vector2.from_angle(a) * speed, randf_range(8, 15),
				randf_range(2.4, 3.6), Palette.CONFETTI.pick_random(),
				Shape.RIBBON if randf() < 0.75 else Shape.STAR, 900.0, 1.4)
	for i in 70:
		_add(Vector2(randf_range(0, w), randf_range(-h * 0.6, -10)), Vector2(randf_range(-40, 40), randf_range(60, 200)),
			randf_range(8, 14), randf_range(3.0, 4.5), Palette.CONFETTI.pick_random(), Shape.RIBBON, 120.0, 0.6)


func clear() -> void:
	_particles.clear()
	queue_redraw()


func _add(pos: Vector2, vel: Vector2, size: float, max_life: float, color: Color, shape: int, gravity: float, drag: float) -> void:
	var p := Particle.new()
	p.pos = pos; p.vel = vel; p.size = size; p.max_life = max_life; p.color = color
	p.shape = shape; p.gravity = gravity; p.drag = drag
	p.rot = randf() * TAU
	p.vr = randf_range(-10, 10)
	_particles.append(p)


func _process(dt: float) -> void:
	if _particles.is_empty():
		return
	dt = minf(dt, 0.033)
	var h := get_viewport_rect().size.y
	var alive: Array[Particle] = []
	for p in _particles:
		p.life += dt
		if p.life >= p.max_life or p.pos.y > h + 60:
			continue
		var k := exp(-p.drag * dt)
		p.vel.x *= k
		p.vel.y = p.vel.y * k + p.gravity * dt
		p.pos += p.vel * dt
		p.rot += p.vr * dt
		alive.append(p)
	_particles = alive
	queue_redraw()


func _draw() -> void:
	for p in _particles:
		var t := p.life / p.max_life
		var c := p.color
		c.a = 1.0 if t < 0.7 else 1.0 - (t - 0.7) / 0.3
		match p.shape:
			Shape.RIBBON:
				# Fake 3D flutter by squashing one axis.
				draw_set_transform(p.pos, p.rot, Vector2(1, cos(p.life * 9 + p.size)))
				draw_rect(Rect2(-p.size / 2, -p.size / 4, p.size, p.size / 2), c)
			Shape.STAR:
				draw_set_transform(p.pos, p.rot, Vector2.ONE)
				draw_colored_polygon(_star(p.size * (1.0 - t * 0.5)), c)
			_:
				draw_set_transform(p.pos, 0.0, Vector2.ONE)
				draw_circle(Vector2.ZERO, p.size / 3, c)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _star(r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 8:
		var rr := r * 0.28 if i % 2 else r
		pts.append(Vector2.from_angle(float(i) / 8 * TAU) * rr)
	return pts
