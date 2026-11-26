class_name BallView
extends Node2D
## Draws one ball: offset "sticker" shadow, squash & stretch, optional stripe (2P ball B).

var radius := 12.0
var color := Color.WHITE
var striped := false
var sunk := false

var _squash := 0.0        ## 0 = round; >0 squashed along _squash_dir
var _squash_dir := Vector2.RIGHT
var _stretch := 0.0       ## aiming pull-back stretch, 0..1
var _stretch_dir := Vector2.RIGHT
var _tween: Tween


func squash(dir: Vector2, amount: float) -> void:
	_squash_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_squash = clampf(amount, 0.0, 0.45)
	if _tween:
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(self, "_squash", 0.0, 0.28).set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)


func set_stretch(dir: Vector2, amount: float) -> void:
	_stretch_dir = dir.normalized() if dir != Vector2.ZERO else Vector2.RIGHT
	_stretch = amount


func pop() -> void:
	## Little hop when the ball reappears after a splash.
	scale = Vector2.ZERO
	var t := create_tween()
	t.tween_property(self, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(_dt: float) -> void:
	queue_redraw()


func _draw() -> void:
	if sunk:
		return
	# Solid offset shadow (picslide "sticker" shadow), unsquashed.
	draw_circle(Vector2(0, 5), radius, Palette.shadow(0.22))
	# Squash along the hit normal; stretch along the aim (pull-back) direction.
	var dir := _squash_dir
	var sx := 1.0 - _squash
	var sy := 1.0 + _squash * 0.6
	if _stretch > 0.0 and _squash < 0.01:
		dir = _stretch_dir
		sx = 1.0 + _stretch * 0.25
		sy = 1.0 - _stretch * 0.15
	draw_set_transform(Vector2.ZERO, dir.angle(), Vector2(sx, sy))
	draw_circle(Vector2.ZERO, radius + 1.5, Palette.shadow(0.28))  # soft ink rim for definition
	draw_circle(Vector2.ZERO, radius, color)
	if striped:
		draw_rect(Rect2(-radius * 0.8, -radius * 0.26, radius * 1.6, radius * 0.52), Palette.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2(-radius * 0.32, -radius * 0.38), radius * 0.3, Color(1, 1, 1, 0.75))  # shine
