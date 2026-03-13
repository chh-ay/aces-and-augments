class_name Main
extends Node2D

@export var boss_scene: PackedScene
@export var exit_door_scene: PackedScene

@onready var player: PlayerController = $Player
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var game_over_ui: Control = $CanvasLayer/GameOver
@onready var game_over_title: Label = $CanvasLayer/GameOver/Panel/VBox/Title
@onready var game_over_hint: Label = $CanvasLayer/GameOver/Panel/VBox/Hint
@onready var pause_menu: PauseMenu = $CanvasLayer/PauseMenu
@onready var hud: Hud = $HUD
@onready var level_up_panel: LevelUpPanel = $CanvasLayer/LevelUpPanel
@onready var run_director: RunDirector = $RunDirector
@onready var arena: Arena = $Arena
@onready var enemies: Node2D = $Enemies
@onready var bosses: Node2D = $Bosses
@onready var exits: Node2D = $Exits
@onready var lucky_terminal: Node2D = $LuckyTerminal

var _game_over: bool = false
var _pause_open: bool = false
var _boss_spawned: bool = false
var _exit_spawned: bool = false
var _last_boss_defeat_position: Vector2 = Vector2.ZERO

func _ready() -> void:
	_update_game_over_ui(false, "GAME OVER", "Press Enter to restart or Esc to quit")
	_position_lucky_terminal()
	if player != null:
		player.died.connect(_on_player_died)
		player.level_up_requested.connect(_on_player_level_up_requested)
	if hud != null and player != null:
		hud.bind_player(player)
	if hud != null and run_director != null:
		hud.bind_run_director(run_director)
	if level_up_panel != null:
		level_up_panel.option_selected.connect(_on_level_up_option_selected)
	if pause_menu != null:
		pause_menu.resume_requested.connect(_on_pause_resume_requested)
		pause_menu.restart_requested.connect(_on_pause_restart_requested)
		pause_menu.quit_requested.connect(_on_pause_quit_requested)
	if run_director != null:
		run_director.time_expired.connect(_on_run_time_expired)

func _unhandled_input(event: InputEvent) -> void:
	if _game_over:
		if event.is_action_pressed("ui_accept"):
			get_tree().reload_current_scene()
		elif event.is_action_pressed("restart"):
			get_tree().reload_current_scene()
		elif event.is_action_pressed("ui_cancel"):
			get_tree().quit()
		return
	if event.is_action_pressed("ui_cancel"):
		if level_up_panel != null and level_up_panel.visible:
			return
		if _pause_open:
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()

func _on_player_died() -> void:
	_game_over = true
	_pause_open = false
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.dismiss()
	_update_game_over_ui(true, "GAME OVER", "Press Enter to restart or Esc to quit")
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
		enemy_spawner.stop_enemies()

func _update_game_over_ui(should_show: bool, title_text: String, hint_text: String) -> void:
	if game_over_ui != null:
		game_over_ui.visible = should_show
	if game_over_title != null:
		game_over_title.text = title_text
	if game_over_hint != null:
		game_over_hint.text = hint_text

func _on_player_level_up_requested(choices: Array) -> void:
	if level_up_panel == null:
		return
	var summary: Dictionary = {}
	if player != null:
		summary = player.get_level_up_summary()
	if hud != null:
		hud.visible = false
	level_up_panel.present(choices, summary)
	get_tree().paused = true

func _on_level_up_option_selected(stat_id: String) -> void:
	if player != null:
		player.apply_level_up_choice(stat_id)
	if level_up_panel != null:
		level_up_panel.dismiss()
	if hud != null:
		hud.visible = true
	get_tree().paused = false

func _open_pause_menu() -> void:
	if pause_menu == null or _game_over:
		return
	_pause_open = true
	get_tree().paused = true
	pause_menu.present()

func _close_pause_menu() -> void:
	if pause_menu == null:
		return
	_pause_open = false
	pause_menu.dismiss()
	get_tree().paused = false

func _on_pause_resume_requested() -> void:
	_close_pause_menu()

func _on_pause_restart_requested() -> void:
	_pause_open = false
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.dismiss()
	get_tree().reload_current_scene()

func _on_pause_quit_requested() -> void:
	_pause_open = false
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.dismiss()
	get_tree().quit()

func _on_run_time_expired() -> void:
	if _boss_spawned or boss_scene == null or bosses == null or player == null:
		return
	_boss_spawned = true
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
	_clear_enemies()
	var boss_node: Node = boss_scene.instantiate()
	if boss_node is Node2D:
		var boss: Node2D = boss_node as Node2D
		bosses.add_child(boss)
		boss.global_position = _get_boss_spawn_position()
		if boss.has_signal("defeated"):
			boss.connect("defeated", Callable(self, "_on_boss_defeated"))

func _on_boss_defeated(defeat_position: Vector2 = Vector2.ZERO) -> void:
	CustomLogger.info("Boss defeated", "Boss")
	_last_boss_defeat_position = defeat_position
	call_deferred("_spawn_exit_door")

func _clear_enemies() -> void:
	if enemies == null:
		return
	for child in enemies.get_children():
		child.queue_free()

func _get_boss_spawn_position() -> Vector2:
	var spawn_position: Vector2 = player.global_position + Vector2(240.0, -80.0)
	if arena != null:
		return arena.clamp_world_position(spawn_position, 48.0)
	return spawn_position

func _spawn_exit_door() -> void:
	if _exit_spawned or exit_door_scene == null or exits == null:
		return
	_exit_spawned = true
	var exit_node: Node = exit_door_scene.instantiate()
	if exit_node is Node2D:
		var door: Node2D = exit_node as Node2D
		exits.add_child(door)
		door.global_position = _get_exit_spawn_position()
		if door.has_signal("player_exited"):
			door.connect("player_exited", Callable(self, "_on_player_exited_run"))

func _get_exit_spawn_position() -> Vector2:
	var spawn_position: Vector2 = _last_boss_defeat_position
	if spawn_position == Vector2.ZERO and player != null:
		spawn_position = player.global_position
	if arena != null:
		return arena.clamp_world_position(spawn_position, 48.0)
	return spawn_position

func _on_player_exited_run() -> void:
	if _game_over:
		return
	_game_over = true
	_pause_open = false
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.dismiss()
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
		enemy_spawner.stop_enemies()
	_clear_enemies()
	var has_royal_flush: bool = player != null and player.active_hand_name == "Royal Flush"
	if has_royal_flush:
		_update_game_over_ui(true, "GOOD ENDING", "Royal Flush secured. Press Enter to restart.")
	else:
		_update_game_over_ui(true, "BAD ENDING", "You escaped, but not with a Royal Flush. Press Enter to restart.")

func _position_lucky_terminal() -> void:
	if lucky_terminal == null:
		return
	if player == null:
		return
	var offset_distance: float = 224.0
	if run_director == null or run_director.run_duration_seconds > 30.0:
		offset_distance = 960.0
	if arena != null:
		offset_distance = min(offset_distance, arena.get_inner_radius(96.0))
	var angle: float = randf() * TAU
	var offset: Vector2 = Vector2.RIGHT.rotated(angle) * offset_distance
	var target_position: Vector2 = player.global_position + offset
	if arena != null:
		target_position = arena.clamp_world_position(target_position, 48.0)
	lucky_terminal.global_position = target_position
