@tool
class_name Level
extends Node2D
## Root of every level scene. Draws the board (a white-bordered sticker on the
## table), validates the layout (warnings show in the scene tree), and builds
## the BallSim from its children: Wall, Zone, Bumper, Tee, Hole.
##
## Press F6 on a level to play just that level.

const SAFE_AREA := Rect2(0, 0, 1024, 768)    ## the 4:3 area every screen shows
const BORDER := 16.0                          ## white board border = outer wall
## On 4:3 screens the game buttons sit in this corner, over the board.
const HUD_CORNER := Rect2(1024 - 230, 0, 230, 96)
const TUNING := preload("res://core/tuning.tres")

@export var id := "":
	set(v): id = v; update_configuration_warnings()
@export var board_rect := Rect2(24, 24, 976, 720):
	set(v): board_rect = v; queue_redraw(); update_configuration_warnings()
## Aim guide: how many bounces the dotted line shows (-1 = whole path).
@export_range(-1, 5) var aim_guide_bounces := 1

var _styles := {}
var _warn_timer := 0.0


func _ready() -> void:
	if Engine.is_editor_hint():
		child_order_changed.connect(update_configuration_warnings)
		return
	# Opened directly (F6): hand over to the game scene, playing just this level.
	if get_parent() == get_tree().root and get_tree().current_scene == self:
		var game := get_node_or_null("/root/Game")
		if game:
			game.play_solo.call_deferred(scene_file_path)


func _process(dt: float) -> void:
	if Engine.is_editor_hint():
		_warn_timer += dt
		if _warn_timer > 1.0:   # children move without telling us; re-check now and then
			_warn_timer = 0.0
			update_configuration_warnings()
			queue_redraw()


func fairway_rect() -> Rect2:
	return board_rect.grow(-BORDER)


# --- Gathering children ------------------------------------------------------------

func walls() -> Array[Wall]:
	var out: Array[Wall] = []
	for n in _all_children(self):
		if n is Wall:
			out.append(n)
	return out


func zones() -> Array[Zone]:
	var out: Array[Zone] = []
	for n in _all_children(self):
		if n is Zone:
			out.append(n)
	return out


func bumpers() -> Array[Bumper]:
	var out: Array[Bumper] = []
	for n in _all_children(self):
		if n is Bumper:
			out.append(n)
	return out


func tees() -> Array[Tee]:
	var out: Array[Tee] = []
	for n in _all_children(self):
		if n is Tee:
			out.append(n)
	return out


func holes() -> Array[Hole]:
	var out: Array[Hole] = []
	for n in _all_children(self):
		if n is Hole:
			out.append(n)
	return out


func tee() -> Tee:
	var t := tees()
	return t[0] if t.size() > 0 else null


func hole() -> Hole:
	var h := holes()
	return h[0] if h.size() > 0 else null


static func _all_children(n: Node) -> Array[Node]:
	var out: Array[Node] = []
	for c in n.get_children():
		out.append(c)
		out.append_array(_all_children(c))
	return out


func _local(n: Node2D, p: Vector2) -> Vector2:
	## n's local point -> level space (independent of any transform above the level).
	return n.get_relative_transform_to_parent(self) * p


# --- Simulation ------------------------------------------------------------------

func build_sim(tuning: Tuning) -> BallSim:
	var s := BallSim.new(tuning)
	s.wall_half_width = Wall.WIDTH / 2.0
	var r := board_rect.grow(-BORDER / 2.0)   # outer wall runs down the middle of the border
	s.add_wall_polyline(PackedVector2Array([r.position, Vector2(r.end.x, r.position.y), r.end,
		Vector2(r.position.x, r.end.y)]), true)
	for w in walls():
		var pts := PackedVector2Array()
		for p in w.points:
			pts.append(_local(w, p))
		s.add_wall_polyline(pts, w.closed)
	for z in zones():
		var zr := z.rect()
		s.zones.append({rect = Rect2(_local(z, zr.position), zr.size), surface = z.surface_name(),
			radius = z.corner_radius})
	for b in bumpers():
		s.bumpers.append({pos = _local(b, Vector2.ZERO), radius = b.radius})
	var h := hole()
	if h:
		s.hole_pos = _local(h, Vector2.ZERO)
	return s


func spawn_points(two_player: bool) -> Array[Vector2]:
	var t := tee()
	if not t:
		return [fairway_rect().get_center()]
	var out: Array[Vector2] = []
	for p in t.spawn_points(two_player):
		out.append(_local(t.get_parent() as Node2D, p) if t.get_parent() != self else p)
	return out


# --- Validation ------------------------------------------------------------------

func _get_configuration_warnings() -> PackedStringArray:
	return validate()


## Problems with this level's layout; empty when it's good to play.
func validate() -> PackedStringArray:
	var w := PackedStringArray()
	if id.strip_edges().is_empty():
		w.append("Level has no id.")
	if not SAFE_AREA.encloses(board_rect):
		w.append("Board %s goes outside the 1024x768 safe area." % board_rect)
	var t := tees()
	var h := holes()
	if t.size() != 1:
		w.append("Needs exactly one Tee (has %d)." % t.size())
	if h.size() != 1:
		w.append("Needs exactly one Hole (has %d)." % h.size())
	if t.size() != 1 or h.size() != 1:
		return w

	var fair := fairway_rect()
	var r: float = TUNING.ball_radius
	var clearance := r + Wall.WIDTH / 2.0
	var sim := build_sim(TUNING)
	var inner := fair.grow(-r)

	var check_point := func(what: String, p: Vector2, need_clear: bool) -> void:
		if not inner.has_point(p):
			w.append("%s at %s is off the fairway." % [what, p.round()])
		if HUD_CORNER.has_point(p):
			w.append("%s at %s is under the 4:3 button corner (top-right); keep that corner clear." % [what, p.round()])
		if need_clear:
			for k in range(8, sim.segments.size(), 2):
				var q := Geometry2D.get_closest_point_to_segment(p, sim.segments[k], sim.segments[k + 1])
				if p.distance_to(q) < clearance:
					w.append("%s at %s is inside or touching a wall." % [what, p.round()])
					break
			for b in sim.bumpers:
				if p.distance_to(b.pos) < b.radius + r + 4:
					w.append("%s at %s overlaps a bumper." % [what, p.round()])
			var surf := sim.surface_at(p)
			if surf != &"grass":
				w.append("%s at %s is on %s." % [what, p.round(), surf])

	for sp in spawn_points(false):
		check_point.call("Tee", sp, true)
	var two := spawn_points(true)
	for i in two.size():
		check_point.call("2P tee spot %s" % ["A", "B"][i], two[i], true)
	check_point.call("Hole", sim.hole_pos, true)
	for b in sim.bumpers:
		check_point.call("Bumper", b.pos, false)
	for z in zones():
		if z.rotation != 0.0 or z.scale != Vector2.ONE:
			w.append("Zone %s is rotated or scaled; use its size instead." % z.name)
	for wall in walls():
		if wall.rotation != 0.0 or wall.scale != Vector2.ONE:
			w.append("Wall %s is rotated or scaled; move its points instead." % wall.name)
		for p in wall.points:
			var lp := _local(wall, p)
			if not fair.grow(Wall.WIDTH).has_point(lp):
				w.append("Wall %s has a point off the board at %s." % [wall.name, lp.round()])
				break
	if sim.hole_pos.distance_to(spawn_points(false)[0]) < 120:
		w.append("Tee and hole are very close together.")
	return w


# --- Drawing ---------------------------------------------------------------------

func _draw() -> void:
	if _styles.is_empty():
		_make_styles()
	draw_style_box(_styles.soft, board_rect)
	draw_style_box(_styles.board_shadow, Rect2(board_rect.position + Vector2(0, 8), board_rect.size))
	draw_style_box(_styles.board, board_rect)
	var fair := fairway_rect()
	draw_style_box(_styles.fairway_shade, fair)
	draw_style_box(_styles.fairway, Rect2(fair.position + Vector2(0, 5), fair.size - Vector2(0, 5)))
	if Engine.is_editor_hint():
		# Safe area every screen shows, and the corner the buttons cover on 4:3.
		draw_rect(SAFE_AREA, Color(Palette.INK, 0.5), false, 2.0)
		draw_rect(HUD_CORNER, Color(1, 0.2, 0.2, 0.12))
		draw_rect(HUD_CORNER, Color(1, 0.2, 0.2, 0.5), false, 2.0)


func _make_styles() -> void:
	var sb := func(col: Color, radius: int) -> StyleBoxFlat:
		var s := StyleBoxFlat.new()
		s.bg_color = col
		s.set_corner_radius_all(radius)
		s.anti_aliasing = true
		s.corner_detail = 12
		return s
	var soft: StyleBoxFlat = sb.call(Color(0, 0, 0, 0), 34)
	soft.shadow_color = Palette.shadow(0.16)
	soft.shadow_size = 28
	soft.shadow_offset = Vector2(0, 14)
	_styles.soft = soft
	_styles.board_shadow = sb.call(Palette.shadow(0.12), 34)
	_styles.board = sb.call(Palette.WHITE, 34)
	_styles.fairway_shade = sb.call(Palette.GREEN_DEEP, 20)
	_styles.fairway = sb.call(Palette.GREEN, 20)
