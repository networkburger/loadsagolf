extends Node
## Vibration patterns, matching picslide's haptics.ts. Android vibrates; iPads
## have no motor, and devices without one ignore this silently.
## Patterns are [on, off, on, ...] in ms, like navigator.vibrate().

var enabled := true


func tap() -> void: _pattern([8])
func lift() -> void: _pattern([12])
func drop() -> void: _pattern([18])
func bump(strength: float) -> void: _pattern([int(lerpf(6.0, 22.0, clampf(strength, 0.0, 1.0)))])
func correct() -> void: _pattern([20, 40, 30])
func win() -> void: _pattern([30, 60, 30, 60, 80])


func _pattern(p: Array) -> void:
	if not enabled or not OS.has_feature("mobile"):
		return
	var t := 0.0
	for i in p.size():
		if i % 2 == 0:
			if t == 0.0:
				Input.vibrate_handheld(p[i])
			else:
				var ms: int = p[i]
				get_tree().create_timer(t / 1000.0).timeout.connect(func(): Input.vibrate_handheld(ms))
		t += p[i]
