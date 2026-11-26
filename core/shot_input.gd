class_name ShotInput
extends RefCounted
## Slingshot gestures -> shots. Pure logic: the scene feeds it touch events in
## level coordinates and it mutates the BallSim (grab brake, held flag, shot).
##
## Gestures are tracked per touch index, so 2P multi-touch is just a different
## grab policy, not different code.

class Gesture:
	var ball := -1
	var start := Vector2.ZERO
	var current := Vector2.ZERO
	var speed_removed := 0.0   ## for the brake "skrrt" sound

var tuning: Tuning
var two_player := false
var gestures := {}  ## touch index -> Gesture


func _init(t: Tuning) -> void:
	tuning = t


func is_ball_held(i: int) -> bool:
	for g: Gesture in gestures.values():
		if g.ball == i:
			return true
	return false


## Returns the Gesture if this touch grabbed a ball, else null.
func press(index: int, pos: Vector2, sim: BallSim) -> Gesture:
	if gestures.has(index):
		return null
	if not two_player and not gestures.is_empty():
		return null  # 1P: only the first touch counts (palm rejection)
	var target := _pick_ball(pos, sim)
	if target < 0:
		return null
	var b := sim.balls[target]
	var g := Gesture.new()
	g.ball = target
	g.start = pos
	g.current = pos
	var before := b.vel.length()
	match tuning.grab_mode:
		Tuning.GrabMode.BRAKE:
			b.vel *= 1.0 - tuning.brake_fraction
		Tuning.GrabMode.FULL_STOP:
			b.vel = Vector2.ZERO
	g.speed_removed = before - b.vel.length()
	b.held = true
	b.resting = false
	gestures[index] = g
	return g


func drag(index: int, pos: Vector2) -> void:
	if gestures.has(index):
		gestures[index].current = pos


## Returns {ball, shot: Vector2, power: float, cancelled: bool}, or {} if this
## touch wasn't holding a ball.
func release(index: int, sim: BallSim) -> Dictionary:
	if not gestures.has(index):
		return {}
	var g: Gesture = gestures[index]
	gestures.erase(index)
	var b := sim.balls[g.ball]
	b.held = false
	var p := power(g)
	if p <= 0.0 or b.sunk:
		return {ball = g.ball, shot = Vector2.ZERO, power = 0.0, cancelled = true}
	var shot := shot_velocity(g)
	var base := b.vel if tuning.add_leftover_speed else Vector2.ZERO
	sim.shoot(g.ball, base + shot)
	return {ball = g.ball, shot = shot, power = p, cancelled = false}


## Drop any gesture holding ball i (e.g. it rolled into water while held).
func drop_ball(i: int) -> void:
	for k in gestures.keys():
		if gestures[k].ball == i:
			gestures.erase(k)


func cancel_all(sim: BallSim) -> void:
	for g: Gesture in gestures.values():
		sim.balls[g.ball].held = false
	gestures.clear()


## 0 inside the dead zone, then 0..1 along a gentle curve.
func power(g: Gesture) -> float:
	var length := (g.current - g.start).length()
	if length < tuning.dead_zone:
		return 0.0
	var t := clampf((length - tuning.dead_zone) / (tuning.max_drag - tuning.dead_zone), 0.0, 1.0)
	return maxf(pow(t, tuning.power_curve), 0.02)


## Shot goes opposite to the drag.
func shot_velocity(g: Gesture) -> Vector2:
	var drag_v := g.current - g.start
	if drag_v.length() < tuning.dead_zone:
		return Vector2.ZERO
	return -drag_v.normalized() * power(g) * tuning.max_shot_speed


## Velocity the ball would leave with if released now (leftover + shot).
func launch_velocity(g: Gesture, sim: BallSim) -> Vector2:
	var base := sim.balls[g.ball].vel if tuning.add_leftover_speed else Vector2.ZERO
	return base + shot_velocity(g)


func _can_grab(b: BallSim.Ball) -> bool:
	if b.sunk:
		return false
	if tuning.grab_mode == Tuning.GrabMode.RESTING_ONLY and b.vel != Vector2.ZERO:
		return false
	return true


func _pick_ball(pos: Vector2, sim: BallSim) -> int:
	if not two_player:
		# 1P: touch anywhere grabs the (first un-sunk) ball.
		for i in sim.balls.size():
			if _can_grab(sim.balls[i]) and not is_ball_held(i):
				return i
		return -1
	var best := -1
	var best_d := tuning.grab_radius_2p
	for i in sim.balls.size():
		var b := sim.balls[i]
		if not _can_grab(b) or is_ball_held(i):
			continue
		var d := b.pos.distance_to(pos)
		if d <= best_d:
			best = i
			best_d = d
	return best
