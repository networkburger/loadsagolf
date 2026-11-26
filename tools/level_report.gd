extends SceneTree
## Brute-force check that levels can be finished, and roughly how many shots it takes.
##   godot --headless -s tools/level_report.gd                 # every level in worlds.tres
##   godot --headless -s tools/level_report.gd -- res://levels/w1_meadow/03.tscn
##
## Tries a fan of shots (angles x powers) from the tee; if none sink, tries again
## from every distinct place the first shots came to rest. Reports the fewest
## shots found (1, 2, or "3+") and how forgiving the first shot is.

const ANGLES := 72
const POWERS := [0.2, 0.35, 0.5, 0.7, 0.85, 1.0]
const CELL := 56.0   ## rest spots closer than this count as the same place
const TUNING := preload("res://core/tuning.tres")


func _init() -> void:
	var paths: Array[String] = []
	for a in OS.get_cmdline_user_args():
		paths.append(a)
	if paths.is_empty():
		var worlds: WorldList = load("res://levels/worlds.tres")
		for w in worlds.worlds:
			for l in w.levels:
				paths.append(l.resource_path)
	for p in paths:
		_report(p)
	quit()


func _report(path: String) -> void:
	var level: Level = load(path).instantiate()
	var t0 := Time.get_ticks_msec()
	var base := level.build_sim(TUNING)
	var start := level.spawn_points(false)[0]
	var first := _fan(base, start)
	var in_one: float = first.sunk * 100.0 / (ANGLES * POWERS.size())
	var shots := "1"
	if first.sunk == 0:
		shots = "3+"
		for spot in first.spots:
			if _fan(base, spot).sunk > 0:
				shots = "2"
				break
	var issues := level.validate()
	print("%-34s %-10s fewest shots: %-3s  hole-in-one: %5.1f%% of shots  splash: %4.1f%%  (%d rest spots, %.1fs)%s" % [
		path.get_file() if path.contains("/w") == false else path.trim_prefix("res://levels/"),
		level.id, shots, in_one, first.splash * 100.0 / (ANGLES * POWERS.size()), first.spots.size(),
		(Time.get_ticks_msec() - t0) / 1000.0, "" if issues.is_empty() else "  ⚠ " + "; ".join(issues)])
	level.free()


## Every shot in the fan from `from`: how many sink, splash, and where the rest stop.
func _fan(base: BallSim, from: Vector2) -> Dictionary:
	var sunk := 0
	var splash := 0
	var cells := {}
	for ai in ANGLES:
		var dir := Vector2.from_angle(TAU * ai / ANGLES)
		for p in POWERS:
			var s := base.copy()
			s.balls.clear()
			s.add_ball(from)
			s.shoot(0, dir * pow(p, 1.0) * TUNING.max_shot_speed)
			var t := 0.0
			var splashed := false
			while t < 12.0:
				for e in s.step(1.0 / 60.0):
					if e.type == &"hazard":
						splashed = true
				t += 1.0 / 60.0
				if s.balls[0].sunk or s.balls[0].resting:
					break
			if s.balls[0].sunk:
				sunk += 1
			elif splashed:
				splash += 1
			else:
				var b := s.balls[0].pos
				cells[Vector2i((b / CELL).floor())] = b
	return {sunk = sunk, splash = splash, spots = cells.values()}
