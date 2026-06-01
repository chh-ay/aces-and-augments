class_name RunContextSingleton
extends Node
##
## Single source of truth for the per-run singleton nodes.
##
## Nodes call `register_*` in their `_ready()` and the matching `unregister_*`
## in `_exit_tree()`. Anything else reads `RunContext.player`, `.arena`, etc.
## directly - no `get_tree().get_first_node_in_group(...)` polling.
##

signal player_changed(player: PlayerController)
signal arena_changed(arena: Arena)
signal floor_generator_changed(floor_generator: FloorGenerator)

var player: PlayerController = null
var arena: Arena = null
var floor_generator: FloorGenerator = null


func register_player(node: PlayerController) -> void:
	player = node
	player_changed.emit(node)


func unregister_player(node: PlayerController) -> void:
	if player == node:
		player = null
		player_changed.emit(null)


func register_arena(node: Arena) -> void:
	arena = node
	arena_changed.emit(node)


func unregister_arena(node: Arena) -> void:
	if arena == node:
		arena = null
		arena_changed.emit(null)


func register_floor_generator(node: FloorGenerator) -> void:
	floor_generator = node
	floor_generator_changed.emit(node)


func unregister_floor_generator(node: FloorGenerator) -> void:
	if floor_generator == node:
		floor_generator = null
		floor_generator_changed.emit(null)


func clear() -> void:
	player = null
	arena = null
	floor_generator = null
