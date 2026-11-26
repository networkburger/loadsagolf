extends SceneTree
## Minimal headless test runner (no plugin dependency):
##   godot --headless -s tests/run_tests.gd
## Every method starting with test_ runs; check() records failures.

var _failures: Array[String] = []
var _current := ""


func _init() -> void:
	var count := 0
	for m in get_method_list():
		var name: String = m.name
		if name.begins_with("test_"):
			_current = name
			count += 1
			call(name)
	if _failures.is_empty():
		print("OK: %d tests passed" % count)
		quit(0)
	else:
		for f in _failures:
			printerr("FAIL " + f)
		printerr("%d failure(s) in %d tests" % [_failures.size(), count])
		quit(1)


func check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append("%s: %s" % [_current, msg])


func _tuning() -> Tuning:
	return Tuning.new()


func _box_sim(t: Tuning) -> BallSim:
	var s := BallSim.new(t)
	s.add_wall_polyline(PackedVector2Array([Vector2(0, 0), Vector2(1000, 0), Vector2(1000, 700), Vector2(0, 700)]), true)
	s.hole_pos = Vector2(-500, -500)  # out of the way
	return s


func _run(s: BallSim, seconds: float) -> Array[Dictionary]:
	var all: Array[Dictionary] = []
	for i in int(seconds * 60):
		all.append_array(s.step(1.0 / 60.0))
	return all


# --- BallSim -----------------------------------------------------------------

func test_ball_comes_to_rest() -> void:
	var s := _box_sim(_tuning())
	s.add_ball(Vector2(200, 350))
	s.shoot(0, Vector2(900, 0))
	_run(s, 6.0)
	check(s.balls[0].resting, "ball should rest within 6s")
	check(s.balls[0].vel == Vector2.ZERO, "resting ball has zero velocity")


func test_ball_never_leaves_walls() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.add_ball(Vector2(500, 350))
	s.shoot(0, Vector2(t.max_shot_speed * 3.0, t.max_shot_speed * 2.1))  # absurdly fast
	for i in 600:
		s.step(1.0 / 60.0)
		var p := s.balls[0].pos
		check(p.x > 0 and p.x < 1000 and p.y > 0 and p.y < 700, "escaped at %s (step %d)" % [p, i])
		if p.x <= 0 or p.x >= 1000:
			return


func test_wall_bounce_reflects_and_emits_event() -> void:
	var s := _box_sim(_tuning())
	s.add_ball(Vector2(900, 350))
	s.shoot(0, Vector2(800, 0))
	var ev := _run(s, 0.5)
	var walls := ev.filter(func(e): return e.type == &"wall")
	check(walls.size() >= 1, "expected a wall event")
	check(s.balls[0].vel.x < 0.0 or s.balls[0].resting, "ball should be heading back left")


func test_slow_ball_drops_in_hole() -> void:
	var s := _box_sim(_tuning())
	s.hole_pos = Vector2(500, 350)
	s.add_ball(Vector2(300, 350))
	s.shoot(0, Vector2(420, 0))
	var ev := _run(s, 3.0)
	check(s.balls[0].sunk, "slow ball should sink")
	check(ev.any(func(e): return e.type == &"sunk"), "expected sunk event")


func test_fast_ball_rattles_over_hole() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.hole_pos = Vector2(400, 350)
	s.add_ball(Vector2(200, 350))
	s.shoot(0, Vector2(t.max_shot_speed, 0))
	var ev := _run(s, 0.25)
	check(ev.any(func(e): return e.type == &"rattle"), "fast ball should rattle")
	check(not s.balls[0].sunk, "fast ball should not sink on first pass")


func test_water_returns_ball_to_rest_pos() -> void:
	var s := _box_sim(_tuning())
	s.zones.append({rect = Rect2(500, 300, 100, 100), surface = &"water"})
	s.add_ball(Vector2(200, 350))
	s.shoot(0, Vector2(900, 0))
	var ev := _run(s, 1.0)
	var hz := ev.filter(func(e): return e.type == &"hazard")
	check(hz.size() == 1, "expected exactly one hazard event, got %d" % hz.size())
	check(s.balls[0].pos.distance_to(Vector2(200, 350)) < 1.0, "ball should be back at its shot position")


func test_sand_slows_more_than_grass() -> void:
	var t := _tuning()
	var grass := _box_sim(t)
	grass.add_ball(Vector2(100, 350))
	grass.shoot(0, Vector2(500, 0))
	var sand := _box_sim(t)
	sand.zones.append({rect = Rect2(0, 0, 1000, 700), surface = &"sand"})
	sand.add_ball(Vector2(100, 350))
	sand.balls[0].surface = &"sand"
	sand.shoot(0, Vector2(500, 0))
	_run(grass, 4.0); _run(sand, 4.0)
	check(sand.balls[0].pos.x < grass.balls[0].pos.x - 50.0, "sand should stop the ball sooner")


func test_ball_ball_collision_transfers_momentum() -> void:
	var s := _box_sim(_tuning())
	s.add_ball(Vector2(200, 350))
	s.add_ball(Vector2(400, 350))
	s.shoot(0, Vector2(700, 0))
	var ev := _run(s, 0.6)
	check(ev.any(func(e): return e.type == &"ball"), "expected a ball-ball event")
	check(s.balls[1].pos.x > 400.0, "struck ball should move right")
	check(s.balls[0].pos.x < s.balls[1].pos.x, "balls should not pass through each other")


func test_predict_matches_real_shot() -> void:
	var s := _box_sim(_tuning())
	s.bumpers.append({pos = Vector2(600, 330), radius = 28.0})
	s.add_ball(Vector2(200, 350))
	var v := Vector2(1100, -200)
	var path := s.predict(0, v, -1, 6.0)
	s.shoot(0, v)
	_run(s, 6.0)
	check(path[-1].distance_to(s.balls[0].pos) < 2.0, "prediction end %s != real end %s" % [path[-1], s.balls[0].pos])


func test_bumper_kicks_ball_away() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.bumpers.append({pos = Vector2(500, 350), radius = 28.0})
	s.add_ball(Vector2(300, 350))
	s.shoot(0, Vector2(600, 0))
	var ev := _run(s, 1.0)
	check(ev.any(func(e): return e.type == &"bumper"), "expected bumper event")
	check(s.balls[0].pos.x < 300.0, "ball should be kicked back past its start (kick >= bumper_min_speed)")


# --- ShotInput ---------------------------------------------------------------

func test_dead_zone_cancels() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.add_ball(Vector2(500, 350))
	var inp := ShotInput.new(t)
	inp.press(0, Vector2(100, 100), s)
	inp.drag(0, Vector2(100 + t.dead_zone * 0.5, 100))
	var r := inp.release(0, s)
	check(r.cancelled, "short drag should cancel")
	check(s.balls[0].vel == Vector2.ZERO, "cancelled shot leaves ball still")


func test_shot_goes_opposite_to_drag() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.add_ball(Vector2(500, 350))
	var inp := ShotInput.new(t)
	inp.press(0, Vector2(100, 100), s)
	inp.drag(0, Vector2(100 - t.max_drag * 2.0, 100))  # pull left, past max
	var r := inp.release(0, s)
	check(not r.cancelled, "should shoot")
	check(is_equal_approx(s.balls[0].vel.x, t.max_shot_speed), "full pull = max speed rightwards, got %s" % s.balls[0].vel)


func test_brake_on_grab() -> void:
	var t := _tuning()
	t.grab_mode = Tuning.GrabMode.BRAKE
	t.brake_fraction = 0.8
	var s := _box_sim(t)
	s.add_ball(Vector2(500, 350))
	s.balls[0].vel = Vector2(1000, 0)
	var inp := ShotInput.new(t)
	var g := inp.press(0, Vector2(10, 10), s)
	check(g != null, "1P grabs from anywhere")
	check(is_equal_approx(s.balls[0].vel.x, 200.0), "80%% brake: expected 200, got %s" % s.balls[0].vel.x)
	check(is_equal_approx(g.speed_removed, 800.0), "speed_removed should be 800")


func test_resting_only_refuses_moving_ball() -> void:
	var t := _tuning()
	t.grab_mode = Tuning.GrabMode.RESTING_ONLY
	var s := _box_sim(t)
	s.add_ball(Vector2(500, 350))
	s.balls[0].vel = Vector2(300, 0)
	var inp := ShotInput.new(t)
	check(inp.press(0, Vector2(500, 350), s) == null, "moving ball can't be grabbed")


func test_1p_ignores_second_touch() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.add_ball(Vector2(500, 350))
	var inp := ShotInput.new(t)
	inp.press(0, Vector2(10, 10), s)
	check(inp.press(1, Vector2(20, 20), s) == null, "second touch ignored in 1P")


func test_2p_grab_radius_and_exclusive_hold() -> void:
	var t := _tuning()
	var s := _box_sim(t)
	s.add_ball(Vector2(200, 350))
	s.add_ball(Vector2(600, 350))
	var inp := ShotInput.new(t)
	inp.two_player = true
	check(inp.press(0, Vector2(400, 350), s) == null, "touch far from both balls grabs nothing")
	var g := inp.press(1, Vector2(610, 360), s)
	check(g != null and g.ball == 1, "touch near ball 1 grabs it")
	check(inp.press(2, Vector2(600, 340), s) == null, "held ball can't be grabbed twice")
	var g2 := inp.press(3, Vector2(205, 350), s)
	check(g2 != null and g2.ball == 0, "other kid grabs ball 0 at the same time")


func test_leftover_speed_added_or_replaced() -> void:
	for add in [true, false]:
		var t := _tuning()
		t.grab_mode = Tuning.GrabMode.BRAKE
		t.brake_fraction = 0.5
		t.add_leftover_speed = add
		var s := _box_sim(t)
		s.add_ball(Vector2(500, 350))
		s.balls[0].vel = Vector2(0, 400)
		var inp := ShotInput.new(t)
		inp.press(0, Vector2(100, 100), s)
		inp.drag(0, Vector2(100 - t.max_drag, 100))
		inp.release(0, s)
		var expect_y := 200.0 if add else 0.0
		check(is_equal_approx(s.balls[0].vel.y, expect_y), "add=%s: vel.y expected %s got %s" % [add, expect_y, s.balls[0].vel.y])


# --- Levels ------------------------------------------------------------------

func _level_paths() -> Array[String]:
	var out: Array[String] = []
	var dirs := ["res://levels"]
	while not dirs.is_empty():
		var d: String = dirs.pop_back()
		for sub in DirAccess.get_directories_at(d):
			dirs.append(d + "/" + sub)
		for f in DirAccess.get_files_at(d):
			if f.ends_with(".tscn"):
				out.append(d + "/" + f)
	return out


func test_every_level_validates() -> void:
	var paths := _level_paths()
	check(paths.size() >= 5, "expected template, sandbox and meadow levels, found %d" % paths.size())
	for p in paths:
		var level: Level = load(p).instantiate()
		var issues := level.validate()
		check(issues.is_empty(), "%s: %s" % [p, "; ".join(issues)])
		var sim := level.build_sim(Tuning.new())
		check(sim.segments.size() >= 8, "%s: no outer walls" % p)
		level.free()


func test_worlds_list_meadow_in_order() -> void:
	var worlds: WorldList = load("res://levels/worlds.tres")
	check(worlds.worlds.size() >= 1, "no worlds")
	var meadow := worlds.worlds[0]
	check(meadow.id == &"meadow", "first world should be meadow")
	check(meadow.levels.size() == 4, "meadow should have 4 holes, has %d" % meadow.levels.size())
	var ids := {}
	for w in worlds.worlds:
		for l in w.levels:
			var level: Level = l.instantiate()
			check(not ids.has(level.id), "duplicate level id %s" % level.id)
			ids[level.id] = true
			level.free()


func test_validator_catches_problems() -> void:
	var level: Level = load("res://levels/_template.tscn").instantiate()
	check(level.validate().is_empty(), "template should be valid")
	level.get_node("Hole").position = Vector2(900, 40)   # under the 4:3 button corner, off the fairway
	var issues := level.validate()
	check(issues.size() >= 1, "moved hole should produce warnings")
	level.get_node("Hole").queue_free()
	level.remove_child(level.get_node("Hole"))
	check(" ".join(level.validate()).contains("exactly one Hole"), "missing hole should be reported")
	level.free()


func test_rounded_zone_corners() -> void:
	var s := _box_sim(_tuning())
	s.zones.append({rect = Rect2(100, 100, 200, 100), surface = &"water", radius = 30.0})
	check(s.surface_at(Vector2(150, 150)) == &"water", "middle is water")
	check(s.surface_at(Vector2(102, 102)) == &"grass", "cut-off corner is grass")
	check(s.surface_at(Vector2(102, 150)) == &"water", "edge middle is water")
