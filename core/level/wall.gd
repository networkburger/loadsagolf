@tool
class_name Wall
extends Line2D
## A wall: a raised white rail. Edit its points with Godot's Line2D handles.
## Collides along its centre line; the ball stops at its edge (width/2).

const WIDTH := 16.0

var _shadow: Line2D


func _init() -> void:
	width = WIDTH
	default_color = Palette.WHITE
	joint_mode = Line2D.LINE_JOINT_ROUND
	begin_cap_mode = Line2D.LINE_CAP_ROUND
	end_cap_mode = Line2D.LINE_CAP_ROUND
	antialiased = true
	z_index = 4


func _ready() -> void:
	# Solid offset shadow (an internal child, so it is never saved into the scene).
	_shadow = Line2D.new()
	_shadow.width = WIDTH
	_shadow.default_color = Palette.shadow(0.15)
	_shadow.joint_mode = joint_mode
	_shadow.begin_cap_mode = begin_cap_mode
	_shadow.end_cap_mode = end_cap_mode
	_shadow.antialiased = true
	_shadow.position = Vector2(0, 5)
	_shadow.show_behind_parent = true
	add_child(_shadow, false, Node.INTERNAL_MODE_FRONT)
	_sync()
	set_process(Engine.is_editor_hint())


func _process(_dt: float) -> void:
	_sync()   # editor only: follow point edits
	width = WIDTH


func _sync() -> void:
	if _shadow and _shadow.points != points:
		_shadow.points = points
		_shadow.closed = closed
