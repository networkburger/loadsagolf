class_name Palette
## Colours shared with picslide (src/style.css :root). One family of apps, one palette.

const CREAM := Color("#fff4e6")
const INK := Color("#4a2c3a")           ## text, outlines; shadows are INK at low alpha
const CORAL := Color("#ff7a59")
const PINK := Color("#ff5f8f")
const PINK_DEEP := Color("#d63f6e")     ## pink's solid "pressed" shadow
const TEAL := Color("#2ec4b6")
const YELLOW := Color("#ffc93c")
const PURPLE := Color("#8b5cf6")
const BLUE := Color("#4f8bff")
const SKY := Color("#4fb8ff")
const GREEN := Color("#7bd96a")
const GREEN_DEEP := Color("#4fbf55")
const WHITE := Color.WHITE

## Backdrop blobs (body background radial gradients).
const BLOB_PEACH := Color("#ffd9c7")
const BLOB_MINT := Color("#d8f3ef")
const BLOB_PINK := Color("#ffe3ef")
const BLOB_LAVENDER := Color("#e6e0ff")

## Confetti / sparkle colours (fx.ts).
const CONFETTI: Array[Color] = [Color("#ff5f8f"), Color("#ffc93c"), Color("#2ec4b6"), Color("#8b5cf6"),
	Color("#ff7a59"), Color("#4fb8ff"), Color("#7bd96a")]
const SPARKLE: Array[Color] = [Color("#fff7b0"), Color("#ffc93c"), Color("#ffffff"), Color("#ff9ec0")]


static func shadow(alpha: float) -> Color:
	return Color(INK, alpha)
