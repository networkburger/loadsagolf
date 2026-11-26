extends Node
## Where we are in the game: which world and hole, and solo-play (F6 on a level).

const WORLDS_PATH := "res://levels/worlds.tres"
const GAME_SCENE := "res://scenes/game.tscn"

var worlds: WorldList
var world_index := 0
var level_index := 0
var solo_level := ""   ## set when a level was launched directly (F6): replay just that one


func _ready() -> void:
	worlds = load(WORLDS_PATH)


func current_world() -> World:
	return worlds.worlds[world_index]


func current_level_scene() -> PackedScene:
	if solo_level != "":
		return load(solo_level)
	return current_world().levels[level_index]


## Move to the next hole. Returns true if that started a new world.
func advance() -> bool:
	if solo_level != "":
		return false
	level_index += 1
	if level_index < current_world().levels.size():
		return false
	level_index = 0
	world_index = (world_index + 1) % worlds.worlds.size()
	return true


func play_solo(path: String) -> void:
	solo_level = path
	get_tree().change_scene_to_file(GAME_SCENE)
