class_name Main
extends Node2D

@onready var player: PlayerController = $Player
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var game_over_ui: Control = $CanvasLayer/GameOver

var _game_over: bool = false

func _ready() -> void:
	_update_game_over_ui(false)
	if player != null:
		player.died.connect(_on_player_died)

func _unhandled_input(event: InputEvent) -> void:
	if not _game_over:
		return
	if event.is_action_pressed("ui_accept"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("restart"):
		get_tree().reload_current_scene()
	elif event.is_action_pressed("ui_cancel"):
		get_tree().quit()

func _on_player_died() -> void:
	_game_over = true
	_update_game_over_ui(true)
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
		enemy_spawner.stop_enemies()

func _update_game_over_ui(should_show: bool) -> void:
	if game_over_ui != null:
		game_over_ui.visible = should_show
