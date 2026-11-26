class_name IconButton
extends BaseButton
## picslide's .icon-btn: a round white button with an ink icon, a solid offset
## shadow plus a soft one, and a bouncy press. Icons are drawn, not textures.

enum Icon { RESTART, SOUND_ON, SOUND_OFF, TWO_PLAYER, ONE_PLAYER }

@export var icon := Icon.RESTART:
	set(v):
		icon = v
		queue_redraw()
@export var diameter := 60.0
@export var fill := Palette.WHITE
@export var ink := Palette.INK

var _tween: Tween


func _init() -> void:
	focus_mode = Control.FOCUS_NONE
	action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS


func _ready() -> void:
	custom_minimum_size = Vector2(diameter, diameter + 10)
	size = custom_minimum_size
	pivot_offset = Vector2(diameter, diameter) / 2
	button_down.connect(func():
		Sfx.play(&"button")
		Haptics.tap()
		_scale_to(0.9, 0.08, Tween.TRANS_QUAD))
	button_up.connect(func(): _scale_to(1.0, 0.22, Tween.TRANS_BACK))


func _scale_to(s: float, t: float, trans: Tween.TransitionType) -> void:
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2(s, s), t).set_trans(trans).set_ease(Tween.EASE_OUT)


func _draw() -> void:
	var r := diameter / 2
	var c := Vector2(r, r)
	draw_circle(c + Vector2(0, 10), r * 1.02, Palette.shadow(0.07))   # soft shadow (approx.)
	draw_circle(c + Vector2(0, 5), r, Palette.shadow(0.12))          # solid offset shadow
	draw_circle(c, r, fill)
	var s := r * 0.53   # icon box half-size (picslide: 14px padding on 60px)
	var w := maxf(3.0, r * 0.13)
	match icon:
		Icon.RESTART:
			draw_arc(c, s * 0.72, deg_to_rad(-60), deg_to_rad(230), 24, ink, w, true)
			var tip := c + Vector2.from_angle(deg_to_rad(-60)) * s * 0.72
			draw_colored_polygon(PackedVector2Array([tip + Vector2(-s * 0.42, -s * 0.12),
				tip + Vector2(s * 0.12, -s * 0.55), tip + Vector2(s * 0.22, s * 0.12)]), ink)
		Icon.SOUND_ON, Icon.SOUND_OFF:
			var o := c + Vector2(-s * 0.35, 0)
			draw_colored_polygon(PackedVector2Array([o + Vector2(-s * 0.55, -s * 0.28), o + Vector2(-s * 0.15, -s * 0.28),
				o + Vector2(s * 0.3, -s * 0.7), o + Vector2(s * 0.3, s * 0.7), o + Vector2(-s * 0.15, s * 0.28),
				o + Vector2(-s * 0.55, s * 0.28)]), ink)
			if icon == Icon.SOUND_ON:
				for k in 2:
					draw_arc(o + Vector2(s * 0.3, 0), s * (0.45 + 0.38 * k), -0.8, 0.8, 12, ink, w * 0.8, true)
			else:
				var x := c + Vector2(s * 0.55, 0)
				draw_line(x + Vector2(-s * 0.3, -s * 0.3), x + Vector2(s * 0.3, s * 0.3), ink, w * 0.9, true)
				draw_line(x + Vector2(-s * 0.3, s * 0.3), x + Vector2(s * 0.3, -s * 0.3), ink, w * 0.9, true)
		Icon.ONE_PLAYER:
			_draw_ball(c, s * 0.5, Palette.WHITE)
		Icon.TWO_PLAYER:
			_draw_ball(c + Vector2(-s * 0.38, 0), s * 0.42, Palette.CORAL)
			_draw_ball(c + Vector2(s * 0.38, 0), s * 0.42, Palette.BLUE)


func _draw_ball(at: Vector2, r: float, col: Color) -> void:
	draw_circle(at, r + 2.5, ink)
	draw_circle(at, r, col)
