extends Node2D
## The game: plays level scenes in the order set by levels/worlds.tres (via the
## Game autoload). Handles input, sound, haptics, fx and the HUD; the level
## scene supplies the course (see core/level/).
## Look and sound follow picslide (see docs/DESIGN.md §7–8).

const PENTATONIC_NOTCHES := 8          ## power ring notches; each one climbs the scale
const NEXT_DELAY := 3.4                ## after the first ball in: let the celebration play

## Grab variants to compare on the tablet: [label, mode, brake_fraction]
const GRAB_VARIANTS := [
	["brake 80%", Tuning.GrabMode.BRAKE, 0.8],
	["brake 50%", Tuning.GrabMode.BRAKE, 0.5],
	["full stop", Tuning.GrabMode.FULL_STOP, 1.0],
	["ramp", Tuning.GrabMode.RAMP, 0.0],
	["resting only", Tuning.GrabMode.RESTING_ONLY, 0.0],
]

var tuning: Tuning = preload("res://core/tuning.tres")
var sim: BallSim
var input: ShotInput
var two_player := false
var latency_mode := false
var grab_variant := 0

var views: Array[BallView] = []
var bumper_streak := {}   ## ball -> bumper hits this shot (climbs the scale)
var notch := {}           ## ball -> current power notch while aiming
var winner := -1
var _resetting := false
var _flash := 0.0
var level: Level

var _board: Node2D      ## pivot at the board centre: pop-in / joy wobble
var _content: Node2D    ## level coordinates live here; the level scene is its first child
var _aim: Node2D
var _fx: Fx
var _info: Label
var _pills := {}
var _btn_players: IconButton
var _btn_mute: IconButton
var _hud_right: BoxContainer
var _hud_left: BoxContainer


func _ready() -> void:
	var back := CanvasLayer.new()
	back.layer = -1
	back.add_child(Backdrop.new())
	add_child(back)

	var cam := Camera2D.new()
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	cam.position = Level.SAFE_AREA.get_center()
	add_child(cam)
	cam.make_current()

	_board = Node2D.new()
	add_child(_board)
	_content = Node2D.new()
	_board.add_child(_content)
	_aim = Node2D.new()
	_aim.z_index = 8
	_aim.draw.connect(_draw_aim)
	_content.add_child(_aim)

	var fx_layer := CanvasLayer.new()
	fx_layer.layer = 5
	_fx = Fx.new()
	fx_layer.add_child(_fx)
	add_child(fx_layer)

	for a in OS.get_cmdline_user_args():
		if a.begins_with("--level="):
			Game.solo_level = a.trim_prefix("--level=")
	_build_hud()
	_apply_grab_variant()
	_load_level()
	if "--demo-aim" in OS.get_cmdline_user_args():
		_demo_aim.call_deferred()
	if "--demo-win" in OS.get_cmdline_user_args():
		get_tree().create_timer(0.6).timeout.connect(func():
			sim.balls[0].sunk = true
			_on_sunk(0))


## Screenshot helper: `-- --demo-aim` holds a mid-power aim on ball 0, toward the hole.
func _demo_aim() -> void:
	await get_tree().create_timer(0.7).timeout
	var b := sim.balls[0].pos
	var away := (b - sim.hole_pos).normalized()
	input.press(0, b + Vector2(0, 80), sim)
	input.drag(0, b + Vector2(0, 80) + away * 140)


# --- Levels ------------------------------------------------------------------

func _load_level() -> void:
	_resetting = false
	winner = -1
	_fx.clear()
	if input:
		input.cancel_all(sim)
	if level:
		level.queue_free()
	for v in views:
		v.queue_free()
	views.clear(); notch.clear(); bumper_streak.clear()

	level = Game.current_level_scene().instantiate()
	print("level: %s" % level.id)
	_content.add_child(level)
	_content.move_child(level, 0)
	var centre := level.board_rect.get_center()
	_board.position = centre
	_content.position = -centre
	level.tee().two_player = two_player
	sim = level.build_sim(tuning)
	input = ShotInput.new(tuning)
	input.two_player = two_player
	var spawns := level.spawn_points(two_player)
	var colors := [Palette.CORAL, Palette.BLUE] if two_player else [Palette.WHITE]
	for i in spawns.size():
		sim.add_ball(spawns[i])
		var v := BallView.new()
		v.radius = tuning.ball_radius
		v.color = colors[i]
		v.striped = i == 1
		v.position = spawns[i]
		v.z_index = 6
		_content.add_child(v)
		v.reset_physics_interpolation()
		views.append(v)
	_layout_hud()
	_pop_in()


func _next_level() -> void:
	Game.advance()
	# Pop the finished board away, then pop the next one in.
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	t.tween_property(_board, "scale", Vector2(0.6, 0.6), 0.3)
	t.tween_property(_board, "rotation", deg_to_rad(6), 0.3)
	t.tween_property(_board, "modulate:a", 0.0, 0.3)
	t.chain().tween_callback(_load_level)


## picslide pop-in: from scale 0.4, rotated -8°, with an overshoot.
func _pop_in() -> void:
	_board.scale = Vector2(0.4, 0.4)
	_board.rotation = deg_to_rad(-8)
	_board.modulate.a = 0.0
	var t := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(_board, "scale", Vector2.ONE, 0.5)
	t.tween_property(_board, "rotation", 0.0, 0.5)
	t.tween_property(_board, "modulate:a", 1.0, 0.2).set_trans(Tween.TRANS_LINEAR)
	for v in views:
		v.scale = Vector2.ZERO
		var bt := create_tween()
		bt.tween_interval(0.35)
		bt.tween_property(v, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	get_tree().create_timer(0.35).timeout.connect(func(): Sfx.play(&"pop", 0.6))


## picslide joy: a happy wobble of the whole board.
func _joy() -> void:
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_property(_board, "scale", Vector2(1.04, 1.04), 0.25)
	t.parallel().tween_property(_board, "rotation", deg_to_rad(-1.5), 0.25)
	t.tween_property(_board, "scale", Vector2(0.99, 0.99), 0.25)
	t.parallel().tween_property(_board, "rotation", deg_to_rad(1.0), 0.25)
	t.tween_property(_board, "scale", Vector2.ONE, 0.4).set_trans(Tween.TRANS_BACK)
	t.parallel().tween_property(_board, "rotation", 0.0, 0.4)


func _ball_pitch(i: int) -> float:
	## Non-musical sounds: ball B sits a little lower so kids can hear whose ball it was.
	return Sfx.step_ratio(-1) if i == 1 else 1.0


func _to_screen(level_pos: Vector2) -> Vector2:
	return _content.get_global_transform_with_canvas() * level_pos


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventScreenTouch or event is InputEventScreenDrag):
		return
	var local := _content.make_input_local(event)
	if latency_mode:
		if event is InputEventScreenTouch and event.pressed:
			Sfx.play(&"click")   # straight from the input event: no frame delay
			_flash = 1.0
		return
	if _resetting:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var g := input.press(event.index, local.position, sim)
			if g:
				var at := sim.balls[g.ball].pos
				Sfx.play(&"pip", 1.0, _ball_pitch(g.ball), at)
				Haptics.lift()
				notch[g.ball] = 0
				if g.speed_removed > 40.0:
					Sfx.play(&"skrrt", clampf(g.speed_removed / 700.0, 0.3, 1.0), _ball_pitch(g.ball), at)
		else:
			var res := input.release(event.index, sim)
			if res.is_empty():
				return
			var i: int = res.ball
			views[i].set_stretch(Vector2.ZERO, 0.0)
			notch.erase(i)
			var at := sim.balls[i].pos
			if res.cancelled:
				Sfx.play(&"fwoop", 1.0, _ball_pitch(i), at)
			else:
				var p: float = res.power
				var layer := &"hit_soft" if p < 0.33 else (&"hit_mid" if p < 0.7 else &"hit_hard")
				Sfx.play(layer, 0.6 + 0.4 * p, _ball_pitch(i), at)
				Haptics.drop()
				views[i].squash(res.shot, 0.15 + 0.25 * p)
				bumper_streak[i] = 0
	elif event is InputEventScreenDrag:
		input.drag(event.index, local.position)


# --- Simulation + sound --------------------------------------------------------

func _physics_process(dt: float) -> void:
	if latency_mode:
		return
	for e in sim.step(dt):
		_on_event(e)
	for i in sim.balls.size():
		var b := sim.balls[i]
		views[i].position = b.pos
		views[i].sunk = b.sunk


func _on_event(e: Dictionary) -> void:
	match e.type:
		&"wall":
			var v := clampf(e.speed / 900.0, 0.0, 1.0)
			if v > 0.04:
				Sfx.play(&"wall", 0.2 + 0.8 * v, (0.94 + 0.12 * v) * _ball_pitch(e.ball), e.pos)
				views[e.ball].squash(e.normal, v * 0.4)
				if v > 0.3:
					Haptics.bump(v)
		&"bumper":
			var n: int = bumper_streak.get(e.ball, 0)
			bumper_streak[e.ball] = n + 1
			var step := mini(n, 9) + (2 if e.ball == 1 else 0)
			Sfx.play(&"boing", 1.0, Sfx.step_ratio(step), e.pos)
			Haptics.tap()
			level.bumpers()[e.bumper].hit()
			views[e.ball].squash(sim.balls[e.ball].vel, 0.35)
			_fx.sparkle(_to_screen(e.pos), 8, 0.6)
		&"ball":
			var v := clampf(e.speed / 800.0, 0.0, 1.0)
			if v > 0.03:
				Sfx.play(&"clack", 0.25 + 0.75 * v, 0.95 + 0.1 * v, e.pos)
				Haptics.bump(v)
				views[e.a].squash(sim.balls[e.a].pos - sim.balls[e.b].pos, v * 0.4)
				views[e.b].squash(sim.balls[e.b].pos - sim.balls[e.a].pos, v * 0.4)
		&"surface":
			if e.surface == &"sand":
				Sfx.play(&"pff", clampf(e.speed / 600.0, 0.35, 1.0), 1.0, sim.balls[e.ball].pos)
		&"rattle":
			Sfx.play(&"rattle", 1.0, 1.0, e.pos)
		&"hazard":
			_on_splash(e)
		&"sunk":
			_on_sunk(e.ball)


func _on_splash(e: Dictionary) -> void:
	var i: int = e.ball
	input.drop_ball(i)
	notch.erase(i)
	views[i].set_stretch(Vector2.ZERO, 0.0)
	Sfx.play(&"plop", 1.0, _ball_pitch(i), e.pos)
	Haptics.drop()
	for z in level.zones():
		if z.surface == Zone.Surface.WATER and Rect2(z.position + z.rect().position, z.size).grow(4).has_point(e.pos):
			z.splash(e.pos)
	views[i].reset_physics_interpolation()
	views[i].position = e.return_pos
	views[i].visible = false
	get_tree().create_timer(0.55).timeout.connect(func():
		if i < views.size():
			views[i].visible = true
			views[i].pop()
			Sfx.play(&"pop", 0.9, 1.0, views[i].position)
			_fx.sparkle(_to_screen(views[i].position), 10, 0.5))


func _on_sunk(i: int) -> void:
	var hole_pos := sim.hole_pos
	Sfx.play(&"plunk", 1.0, _ball_pitch(i), hole_pos)
	Haptics.correct()
	level.hole().flash()
	_fx.sparkle(_to_screen(hole_pos), 16, 1.0)
	var all_in := true
	for b in sim.balls:
		all_in = all_in and b.sunk
	var first := winner == -1
	if first:
		winner = i
		if two_player:
			level.hole().winner_color = views[i].color
		get_tree().create_timer(0.15).timeout.connect(func():
			Sfx.play(&"jingle")
			Haptics.win()
			_joy())
		get_tree().create_timer(0.75).timeout.connect(_fx.celebrate)
	else:
		get_tree().create_timer(0.15).timeout.connect(func(): Sfx.play(&"ding"))
	if all_in:
		_resetting = true
		get_tree().create_timer(NEXT_DELAY if first else 1.6).timeout.connect(_next_level)


func _process(dt: float) -> void:
	_flash = maxf(_flash - dt * 6.0, 0.0)
	# Aiming: stretch the ball, and tick up/down the scale as power crosses notches.
	for g: ShotInput.Gesture in input.gestures.values():
		var p := input.power(g)
		views[g.ball].set_stretch(g.current - g.start, p)
		var n := floori(p * PENTATONIC_NOTCHES + 0.001) if p > 0.0 else 0
		var prev: int = notch.get(g.ball, 0)
		if n != prev:
			notch[g.ball] = n
			if n > 0:
				Sfx.play(&"tick", 1.0 if n > prev else 0.5, Sfx.step_ratio(n - 1 + (2 if g.ball == 1 else 0)), sim.balls[g.ball].pos)
				if n > prev:
					Haptics.tap()
	_info.text = "fps %d · audio out latency %.0f ms" % [Engine.get_frames_per_second(), AudioServer.get_output_latency() * 1000.0]
	_info.text += " · LATENCY TEST: tap anywhere" if latency_mode else ""
	_aim.queue_redraw()
	if _flash > 0.0 or latency_mode:
		queue_redraw()


func _draw() -> void:
	if _flash > 0.0:
		draw_rect(Rect2(-2000, -2000, 5000, 5000), Color(1, 1, 1, _flash * 0.6))


# --- Aim ---------------------------------------------------------------------------

func _draw_aim() -> void:
	for g: ShotInput.Gesture in input.gestures.values():
		var b := sim.balls[g.ball]
		var p := input.power(g)
		var pull := g.current - g.start
		# Rubber band from the ball back along the pull.
		var band_end := b.pos + pull.limit_length(tuning.max_drag) * 0.45
		var bw := 4.0 + 4.0 * p
		_aim.draw_line(b.pos + Vector2(0, 3), band_end + Vector2(0, 3), Palette.shadow(0.15), bw, true)
		_aim.draw_line(b.pos, band_end, Color(1, 1, 1, 0.85), bw, true)
		_aim.draw_circle(band_end, bw * 0.9, Palette.WHITE)
		# Power ring (picslide's hold ring): fills clockwise, coral -> pink, with notch pips.
		var rr := tuning.ball_radius + 11.0
		_aim.draw_arc(b.pos, rr, 0, TAU, 48, Color(1, 1, 1, 0.55), 6.0, true)
		if p > 0.0:
			_aim.draw_arc(b.pos, rr, -PI / 2, -PI / 2 + TAU * p, 48, Palette.CORAL.lerp(Palette.PINK, p), 6.0, true)
		for k in PENTATONIC_NOTCHES:
			var a := -PI / 2 + TAU * k / PENTATONIC_NOTCHES
			_aim.draw_circle(b.pos + Vector2.from_angle(a) * rr, 1.6, Palette.shadow(0.25))
		if p <= 0.0:
			continue
		var path := sim.predict(g.ball, input.launch_velocity(g, sim), level.aim_guide_bounces)
		_draw_dots(path)


func _draw_dots(path: PackedVector2Array) -> void:
	var total := 0.0
	for k in path.size() - 1:
		total += path[k].distance_to(path[k + 1])
	var spacing := 18.0
	var carry := 0.0
	var travelled := 0.0
	for k in path.size() - 1:
		var a := path[k]
		var seg := path[k + 1] - a
		var length := seg.length()
		var d := spacing - carry
		while d <= length:
			# Full strength for most of the path, fading over the final 30%.
			var t := (travelled + d) / maxf(total, 1.0)
			var fade := clampf((1.0 - t) / 0.3, 0.15, 1.0)
			var at := a + seg * (d / length)
			_aim.draw_circle(at + Vector2(0, 2), 4.0, Palette.shadow(0.12 * fade))
			_aim.draw_circle(at, 4.0, Color(1, 1, 1, fade))
			d += spacing
		carry = length - (d - spacing)
		travelled += length


# --- HUD -----------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(root)

	# Game buttons (picslide icon buttons): a column in the right margin on wide
	# screens, a row in the top-right corner when there's no margin (4:3).
	var right := BoxContainer.new()
	right.add_theme_constant_override("separation", 12)
	root.add_child(right)
	_hud_right = right
	_btn_players = _icon(right, IconButton.Icon.ONE_PLAYER, func():
		two_player = not two_player
		_btn_players.icon = IconButton.Icon.TWO_PLAYER if two_player else IconButton.Icon.ONE_PLAYER
		_load_level())
	_btn_mute = _icon(right, IconButton.Icon.SOUND_OFF if Sfx.muted else IconButton.Icon.SOUND_ON, func():
		Sfx.muted = not Sfx.muted
		_btn_mute.icon = IconButton.Icon.SOUND_OFF if Sfx.muted else IconButton.Icon.SOUND_ON)
	_icon(right, IconButton.Icon.RESTART, _load_level)

	# Dev pills (debug builds only): same rule, on the left.
	var left := BoxContainer.new()
	left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	_hud_left = left
	_pills.grab = _pill(left, func():
		grab_variant = (grab_variant + 1) % GRAB_VARIANTS.size()
		_apply_grab_variant())
	_pills.leftover = _pill(left, func():
		tuning.add_leftover_speed = not tuning.add_leftover_speed
		_apply_grab_variant())
	_pills.latency = _pill(left, func():
		latency_mode = not latency_mode
		_pills.latency.text = "latency: ON" if latency_mode else "latency test"
		_load_level())
	_pills.latency.text = "latency test"
	_pills.next = _pill(left, func():
		input.cancel_all(sim)
		_next_level())
	_pills.next.text = "next hole"
	if not OS.is_debug_build():
		left.hide()

	get_viewport().size_changed.connect(_layout_hud)
	_layout_hud.call_deferred()

	_info = Label.new()
	_info.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_info.position = Vector2(14, -26)
	_info.add_theme_font_size_override("font_size", 13)
	_info.add_theme_color_override("font_color", Palette.shadow(0.45))
	root.add_child(_info)


func _layout_hud() -> void:
	var vis := get_viewport_rect().size
	if not level:
		return
	var board := level.board_rect
	var margin := (vis.x - Level.SAFE_AREA.size.x) / 2.0 + board.position.x
	var wide := margin >= 76.0
	_hud_right.vertical = wide
	_hud_left.vertical = wide
	_hud_right.reset_size()
	_hud_left.reset_size()
	if wide:
		_hud_right.position = Vector2(vis.x - margin / 2.0 - 28.0, 18)
		_hud_left.position = Vector2(10, 18)
		for b in _hud_left.get_children():
			(b as Button).add_theme_font_size_override("font_size", 11)
	else:
		_hud_right.position = Vector2(vis.x - _hud_right.size.x - 14, 10)
		_hud_left.position = Vector2(14, 14)


func _icon(parent: Node, icon: IconButton.Icon, cb: Callable) -> IconButton:
	var b := IconButton.new()
	b.icon = icon
	b.diameter = 56.0
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _pill(parent: Node, cb: Callable) -> Button:
	var b := Button.new()
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "focus"]:
		var s := StyleBoxFlat.new()
		s.bg_color = Color(1, 1, 1, 0.92 if state != "pressed" else 0.7)
		s.set_corner_radius_all(16)
		s.content_margin_left = 14; s.content_margin_right = 14
		s.content_margin_top = 6; s.content_margin_bottom = 6
		s.shadow_color = Palette.shadow(0.12)
		s.shadow_offset = Vector2(0, 3)
		s.shadow_size = 1
		s.anti_aliasing = true
		b.add_theme_stylebox_override(state, s)
	for c in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		b.add_theme_color_override(c, Palette.INK)
	b.pressed.connect(func():
		Sfx.play(&"button")
		cb.call())
	parent.add_child(b)
	return b


func _apply_grab_variant() -> void:
	var v: Array = GRAB_VARIANTS[grab_variant]
	tuning.grab_mode = v[1]
	tuning.brake_fraction = v[2]
	_pills.grab.text = "grab: " + v[0]
	_pills.leftover.text = "leftover: " + ("add" if tuning.add_leftover_speed else "replace")
