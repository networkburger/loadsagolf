class_name BallSim
extends RefCounted
## Deterministic top-down ball simulation. No scene dependencies: the game, the
## aim guide (via copy()) and the tests all drive this same code.
##
## step() returns a list of event dictionaries; the view layer turns those into
## sounds and animation. Events:
##   {type=&"wall",   ball, speed, pos, normal}
##   {type=&"bumper", ball, bumper, speed, pos}
##   {type=&"ball",   a, b, speed, pos}
##   {type=&"surface",ball, surface, speed}     # crossed into a new surface
##   {type=&"rattle", ball, pos}                # too fast over the hole
##   {type=&"sunk",   ball, pos}
##   {type=&"hazard", ball, pos, return_pos}    # splash; ball already moved back
##   {type=&"rest",   ball, pos}

const SURFACES := {
	&"grass": {decel = 1.0, drag = 1.0},
	&"sand":  {decel = 3.2, drag = 3.0},
	&"water": {decel = 1.0, drag = 1.0, hazard = true},
}

class Ball:
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var held := false
	var sunk := false
	var resting := true
	var rest_pos := Vector2.ZERO   ## where a hazard sends the ball back to
	var surface: StringName = &"grass"
	var on_rim := false

	func copy() -> Ball:
		var b := Ball.new()
		b.pos = pos; b.vel = vel; b.held = held; b.sunk = sunk
		b.resting = resting; b.rest_pos = rest_pos; b.surface = surface
		b.on_rim = on_rim
		return b

var tuning: Tuning
var balls: Array[Ball] = []
## Static geometry (shared, never mutated by step):
var segments := PackedVector2Array()  ## wall segments as consecutive pairs a,b
var bumpers: Array[Dictionary] = []   ## {pos: Vector2, radius: float}
var zones: Array[Dictionary] = []     ## {rect: Rect2, surface: StringName, radius?: float}; later zones win
var hole_pos := Vector2.ZERO
var wall_half_width := 8.0          ## walls are thick lines; collide with their edge


func _init(t: Tuning) -> void:
	tuning = t


func add_ball(pos: Vector2) -> int:
	var b := Ball.new()
	b.pos = pos
	b.rest_pos = pos
	balls.append(b)
	return balls.size() - 1


func add_wall_polyline(points: PackedVector2Array, closed := false) -> void:
	for i in points.size() - 1:
		segments.append(points[i]); segments.append(points[i + 1])
	if closed and points.size() > 2:
		segments.append(points[-1]); segments.append(points[0])


## A copy that shares static geometry but owns its ball state.
func copy() -> BallSim:
	var s := BallSim.new(tuning)
	s.segments = segments
	s.bumpers = bumpers
	s.zones = zones
	s.hole_pos = hole_pos
	s.wall_half_width = wall_half_width
	for b in balls:
		s.balls.append(b.copy())
	return s


func surface_at(p: Vector2) -> StringName:
	var result: StringName = &"grass"
	for z in zones:
		if _in_rounded_rect(p, z.rect, z.get(&"radius", 0.0)):
			result = z.surface
	return result


static func _in_rounded_rect(p: Vector2, r: Rect2, radius: float) -> bool:
	if not r.has_point(p):
		return false
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	if radius <= 0.0:
		return true
	# Inside unless in a corner square and outside that corner's circle.
	var cx := clampf(p.x, r.position.x + radius, r.end.x - radius)
	var cy := clampf(p.y, r.position.y + radius, r.end.y - radius)
	return p.distance_to(Vector2(cx, cy)) <= radius


func all_still() -> bool:
	for b in balls:
		if not b.sunk and (b.vel != Vector2.ZERO or b.held):
			return false
	return true


## Called by input when a shot is released.
func shoot(i: int, new_vel: Vector2) -> void:
	var b := balls[i]
	if not SURFACES[surface_at(b.pos)].get(&"hazard", false):
		b.rest_pos = b.pos
	b.vel = new_vel
	b.resting = false


func step(dt: float) -> Array[Dictionary]:
	var events: Array[Dictionary] = []
	var r := tuning.ball_radius
	var max_speed := 0.0
	for b in balls:
		if not b.sunk:
			max_speed = maxf(max_speed, b.vel.length())
	# Substep so no ball moves more than ~40% of its radius per substep.
	var n := clampi(ceili(max_speed * dt / (r * 0.4)), 1, 24)
	var h := dt / n
	for _s in n:
		_substep(h, events)

	for i in balls.size():
		var b := balls[i]
		if b.sunk:
			continue
		if b.held and tuning.grab_mode == Tuning.GrabMode.RAMP:
			b.vel *= exp(-tuning.ramp_brake_per_sec * dt)
		var near_hole := b.pos.distance_to(hole_pos) < tuning.hole_radius * tuning.hole_pull_range
		if not b.held and not near_hole and b.vel != Vector2.ZERO and b.vel.length() < tuning.stop_speed:
			b.vel = Vector2.ZERO
		var was_resting := b.resting
		b.resting = b.vel == Vector2.ZERO and not b.held
		if b.resting and not was_resting:
			b.rest_pos = b.pos
			events.append({type = &"rest", ball = i, pos = b.pos})
	return events


func _substep(h: float, events: Array[Dictionary]) -> void:
	var t := tuning
	var r := t.ball_radius
	for i in balls.size():
		var b := balls[i]
		if b.sunk:
			continue
		# Friction: constant rolling deceleration + speed-proportional drag.
		var surf: Dictionary = SURFACES[b.surface]
		var speed := b.vel.length()
		if speed > 0.0:
			var dec: float = (t.rolling_decel * surf.decel + t.drag_coeff * surf.drag * speed) * h
			b.vel = b.vel * (maxf(speed - dec, 0.0) / speed)

		# Gentle suction toward the hole when slow and close.
		var to_hole := hole_pos - b.pos
		var hd := to_hole.length()
		if hd < t.hole_radius * t.hole_pull_range and hd > 0.01 and b.vel.length() < t.capture_speed:
			b.vel += to_hole / hd * t.hole_pull * h

		b.pos += b.vel * h

		# Walls (segments; endpoints give rounded corners for free).
		for k in range(0, segments.size(), 2):
			var q := Geometry2D.get_closest_point_to_segment(b.pos, segments[k], segments[k + 1])
			var d := b.pos - q
			var dist := d.length()
			var rw := r + wall_half_width
			if dist < rw and dist > 0.0001:
				var nrm := d / dist
				b.pos = q + nrm * rw
				var vn := b.vel.dot(nrm)
				if vn < 0.0:
					b.vel -= (1.0 + t.wall_restitution) * vn * nrm
					events.append({type = &"wall", ball = i, speed = -vn, pos = q, normal = nrm})

		# Bumpers: springy circles that always kick back hard.
		for j in bumpers.size():
			var bp: Dictionary = bumpers[j]
			var d: Vector2 = b.pos - bp.pos
			var dist := d.length()
			var min_d: float = r + bp.radius
			if dist < min_d and dist > 0.0001:
				var nrm := d / dist
				b.pos = bp.pos + nrm * min_d
				var vn := b.vel.dot(nrm)
				if vn < 0.0:
					b.vel -= (1.0 + t.bumper_restitution) * vn * nrm
					var out := b.vel.dot(nrm)
					if out < t.bumper_min_speed:
						b.vel += nrm * (t.bumper_min_speed - out)
					events.append({type = &"bumper", ball = i, bumper = j, speed = -vn, pos = bp.pos + nrm * bp.radius})

		# Surface changes.
		var s := surface_at(b.pos)
		if s != b.surface:
			b.surface = s
			if SURFACES[s].get(&"hazard", false):
				var from := b.pos
				b.pos = b.rest_pos
				b.vel = Vector2.ZERO
				b.held = false
				b.surface = surface_at(b.pos)
				events.append({type = &"hazard", ball = i, pos = from, return_pos = b.pos})
				continue
			events.append({type = &"surface", ball = i, surface = s, speed = b.vel.length()})

		# Hole: slow enough = in; too fast = rattle over the rim.
		hd = b.pos.distance_to(hole_pos)
		if hd < t.hole_radius:
			if b.vel.length() < t.capture_speed and not b.held:
				b.sunk = true
				b.pos = hole_pos
				b.vel = Vector2.ZERO
				events.append({type = &"sunk", ball = i, pos = hole_pos})
				continue
			if not b.on_rim:
				b.on_rim = true
				# Deflect away from the hole centre (deterministic, so the aim guide matches).
				var side := signf(b.vel.cross(hole_pos - b.pos))
				b.vel = b.vel.rotated(-side * 0.22) * 0.85
				events.append({type = &"rattle", ball = i, pos = b.pos})
		else:
			b.on_rim = false

	# Ball–ball: equal mass, near-elastic.
	for i in balls.size():
		for j in range(i + 1, balls.size()):
			var a := balls[i]
			var c := balls[j]
			if a.sunk or c.sunk:
				continue
			var d := c.pos - a.pos
			var dist := d.length()
			if dist < 2.0 * r and dist > 0.0001:
				var nrm := d / dist
				var overlap := 2.0 * r - dist
				a.pos -= nrm * overlap * 0.5
				c.pos += nrm * overlap * 0.5
				var rv := (c.vel - a.vel).dot(nrm)
				if rv < 0.0:
					var imp := -(1.0 + t.ball_restitution) * rv * 0.5
					a.vel -= nrm * imp
					c.vel += nrm * imp
					a.resting = false
					c.resting = false
					events.append({type = &"ball", a = i, b = j, speed = -rv, pos = a.pos + nrm * r})


## Path ball i would take if given `vel` now. Stops at rest, sinking, a hazard,
## touching another ball, or after `max_bounces` wall/bumper hits (-1 = no limit).
func predict(i: int, vel: Vector2, max_bounces := -1, max_time := 3.0) -> PackedVector2Array:
	var sim := copy()
	sim.balls[i].vel = vel
	sim.balls[i].held = false
	sim.balls[i].resting = false
	var pts := PackedVector2Array([sim.balls[i].pos])
	var dt := 1.0 / 60.0
	var bounces := 0
	var tt := 0.0
	while tt < max_time:
		tt += dt
		var ev := sim.step(dt)
		var stop := false
		for e in ev:
			if e.type == &"wall" or e.type == &"bumper":
				if e.ball == i:
					bounces += 1
					if max_bounces >= 0 and bounces > max_bounces:
						pts.append(sim.balls[i].pos); stop = true
			elif e.type == &"ball" and (e.a == i or e.b == i):
				pts.append(sim.balls[i].pos); stop = true
			elif e.type == &"hazard" and e.ball == i:
				pts.append(e.pos); stop = true
			elif (e.type == &"sunk" or e.type == &"rest") and e.ball == i:
				stop = true
		if stop:
			break
		pts.append(sim.balls[i].pos)
	return pts
