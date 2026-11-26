extends Node
## Event-driven, pooled sound effects.
##
## Files in res://audio/sfx/ are grouped into banks by name:
##   wall_01.wav, wall_02.wav  -> bank "wall" (random variant per play)
##   hum_loop.wav              -> loop "hum" (see loop_player(); none in use)
##
## play() adds a little random pitch to every one-shot, caps how many of each
## event can *start* within a short window (reverb tails don't count), and has a
## short per-event cooldown so rapid repeats don't machine-gun.
##
## Sounds follow picslide's vocabulary and key (G major pentatonic): use
## step_ratio() to pitch a sample up the scale.

const SFX_DIR := "res://audio/sfx/"
const VOICES := 24
const DEFAULT_CAP := 4
const DEFAULT_COOLDOWN_MS := 30
const PAN := 0.3
const CAP_WINDOW_MS := 150   ## voices started within this window count toward an event's cap
const PENTATONIC := [0, 2, 4, 7, 9]

## Per-event overrides: {cap, cooldown_ms, variance, bus}
const EVENTS := {
	&"wall": {cap = 3, cooldown_ms = 45},
	&"boing": {cap = 3, variance = 0.0},
	&"clack": {cap = 2, cooldown_ms = 60},
	&"rattle": {cap = 1, cooldown_ms = 120},
	&"jingle": {cap = 1, cooldown_ms = 1000, variance = 0.0},
	&"ding": {variance = 0.0},
	&"tick": {cap = 3, cooldown_ms = 0, variance = 0.0},
	&"click": {cap = 8, cooldown_ms = 0, variance = 0.0},
	&"button": {bus = &"UI", variance = 0.0},
}

const SETTINGS_PATH := "user://settings.cfg"

## Persisted like picslide's mute toggle.
var muted := false:
	set(v):
		muted = v
		AudioServer.set_bus_mute(0, v)
		var cfg := ConfigFile.new()
		cfg.load(SETTINGS_PATH)
		cfg.set_value("audio", "muted", v)
		cfg.save(SETTINGS_PATH)

var _banks := {}       ## StringName -> Array[AudioStream]
var _loops := {}       ## StringName -> AudioStream
var _pool: Array[AudioStreamPlayer2D] = []
var _playing_event := {}  ## player -> StringName
var _started_ms := {}     ## player -> start time
var _last_ms := {}


func _ready() -> void:
	_setup_buses()
	_load_banks()
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.get_value("audio", "muted", false):
		muted = true
	for i in VOICES:
		var p := _make_player(&"SFX")
		_pool.append(p)


## Pitch multiplier for a pentatonic step (0 = the sample's own note, 5 = an octave up).
## Same scale as picslide's noteHz().
static func step_ratio(step: int) -> float:
	var octave := floori(step / 5.0)
	var semis: int = octave * 12 + PENTATONIC[posmod(step, 5)]
	return pow(2.0, semis / 12.0)


func has_event(name: StringName) -> bool:
	return _banks.has(name)


## volume: linear 0..1+ (scaled from impact speed etc.). pitch: multiplier.
## Returns the player used (or null if capped / missing).
func play(name: StringName, volume := 1.0, pitch := 1.0, pos = null) -> AudioStreamPlayer2D:
	var bank: Array = _banks.get(name, [])
	if bank.is_empty() or volume <= 0.001:
		return null
	var cfg: Dictionary = EVENTS.get(name, {})
	var now := Time.get_ticks_msec()
	if now - int(_last_ms.get(name, -100000)) < int(cfg.get(&"cooldown_ms", DEFAULT_COOLDOWN_MS)):
		return null
	var cap: int = cfg.get(&"cap", DEFAULT_CAP)
	var count := 0
	for p in _pool:
		if p.playing and _playing_event.get(p) == name and now - int(_started_ms.get(p, 0)) < CAP_WINDOW_MS:
			count += 1
	if count >= cap:
		return null
	var player := _free_player()
	_last_ms[name] = now
	var variance: float = cfg.get(&"variance", 0.06)
	player.stream = bank.pick_random()
	player.bus = cfg.get(&"bus", &"SFX")
	player.volume_db = linear_to_db(volume)
	player.pitch_scale = pitch * (1.0 + randf_range(-variance, variance))
	player.global_position = pos if pos != null else _screen_centre()
	_playing_event[player] = name
	_started_ms[player] = now
	player.play()
	return player


## A dedicated looping player for a continuous sound. Caller owns it and
## drives volume_db / pitch_scale every frame. Returns null if the loop is missing.
func loop_player(name: StringName, parent: Node) -> AudioStreamPlayer2D:
	if not _loops.has(name):
		return null
	var p := AudioStreamPlayer2D.new()
	p.stream = _loops[name]
	p.bus = &"Loops"
	p.max_distance = 100000.0
	p.attenuation = 0.0
	p.panning_strength = PAN
	p.volume_db = -80.0
	parent.add_child(p)
	return p


func _free_player() -> AudioStreamPlayer2D:
	for p in _pool:
		if not p.playing:
			return p
	# Steal the voice that has played longest.
	var oldest := _pool[0]
	for p in _pool:
		if p.get_playback_position() > oldest.get_playback_position():
			oldest = p
	return oldest


func _make_player(bus: StringName) -> AudioStreamPlayer2D:
	var p := AudioStreamPlayer2D.new()
	p.bus = bus
	p.max_distance = 100000.0
	p.attenuation = 0.0
	p.panning_strength = PAN
	add_child(p)
	return p


func _screen_centre() -> Vector2:
	var vp := get_viewport()
	return vp.get_canvas_transform().affine_inverse() * (vp.get_visible_rect().size * 0.5)


func _setup_buses() -> void:
	# Master: gentle compression then a hard limiter, so loud moments never
	# clip tablet speakers.
	var comp := AudioEffectCompressor.new()
	comp.threshold = -12.0
	comp.ratio = 3.0
	comp.attack_us = 2000.0
	comp.release_ms = 120.0
	AudioServer.add_bus_effect(0, comp)
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -0.5
	AudioServer.add_bus_effect(0, lim)
	for bus_name in [&"SFX", &"Loops", &"UI"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			var idx := AudioServer.bus_count
			AudioServer.add_bus(idx)
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, &"Master")


func _load_banks() -> void:
	var files := ResourceLoader.list_directory(SFX_DIR)
	files.sort()
	for f in files:
		if not f.ends_with(".wav"):
			continue
		var base := f.get_basename()
		var stream: AudioStream = load(SFX_DIR + f)
		if base.ends_with("_loop"):
			var wav := stream as AudioStreamWAV
			if wav:
				wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
				wav.loop_begin = 0
				wav.loop_end = int(wav.get_length() * wav.mix_rate)
			_loops[StringName(base.trim_suffix("_loop"))] = stream
			continue
		var parts := base.rsplit("_", true, 1)
		var key := StringName(parts[0] if parts.size() == 2 and parts[1].is_valid_int() else base)
		if not _banks.has(key):
			_banks[key] = []
		_banks[key].append(stream)
	print("Sfx: %d banks, %d loops" % [_banks.size(), _loops.size()])
