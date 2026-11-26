class_name Backdrop
extends Node2D
## picslide's body background: cream, four soft corner blobs, and a faint ink
## dot grid. Screen-space: put it on a CanvasLayer below the game. Redraws only
## when the screen size changes.

## [colour, centre as fraction of screen] (CSS: radial-gradient(circle at x% y%, c 0 18%, transparent 40%))
const BLOBS := [
	[Palette.BLOB_PEACH, Vector2(0.12, 0.18), 0.18, 0.40],
	[Palette.BLOB_MINT, Vector2(0.88, 0.12), 0.14, 0.36],
	[Palette.BLOB_PINK, Vector2(0.80, 0.92), 0.18, 0.42],
	[Palette.BLOB_LAVENDER, Vector2(0.08, 0.90), 0.14, 0.36],
]
const DOT_SPACING := 26
const DOT_RADIUS := 1.5

var _dots: ImageTexture
var _blob_tex := {}


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	_dots = _make_dot_texture()
	get_viewport().size_changed.connect(queue_redraw)


func _draw() -> void:
	var size := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), Palette.CREAM)
	for b in BLOBS:
		var centre: Vector2 = b[1] * size
		# CSS default size is farthest-corner.
		var far := 0.0
		for corner in [Vector2.ZERO, Vector2(size.x, 0), Vector2(0, size.y), size]:
			far = maxf(far, centre.distance_to(corner))
		var radius: float = far * b[3]
		draw_texture_rect(_blob(b[0], b[2] / b[3]), Rect2(centre - Vector2(radius, radius), Vector2(radius, radius) * 2), false)
	draw_texture_rect(_dots, Rect2(Vector2.ZERO, size), true)


func _blob(col: Color, solid_until: float) -> GradientTexture2D:
	var key := "%s/%s" % [col.to_html(), solid_until]
	if _blob_tex.has(key):
		return _blob_tex[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, solid_until, 1.0])
	g.colors = PackedColorArray([col, col, Color(col, 0.0)])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 256
	t.height = 256
	_blob_tex[key] = t
	return t


static func _make_dot_texture() -> ImageTexture:
	var img := Image.create(DOT_SPACING, DOT_SPACING, false, Image.FORMAT_RGBA8)
	var c := Vector2(DOT_SPACING, DOT_SPACING) / 2.0
	for y in DOT_SPACING:
		for x in DOT_SPACING:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c)
			var a := clampf(DOT_RADIUS + 0.5 - d, 0.0, 1.0) * 0.06
			img.set_pixel(x, y, Color(Palette.INK, a))
	return ImageTexture.create_from_image(img)
