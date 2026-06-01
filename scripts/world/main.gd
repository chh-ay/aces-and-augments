class_name Main
extends Node2D
##
## Drives a single run. Owns:
##   - boot sequence (delegates to BootOverlay)
##   - level-up / hand-augment / pause overlays
##   - boss timer and exit-door spawn
##   - end-of-run GameOverOverlay
##
## Music is owned by AudioManager. Persistence by SaveManager/GameManager.
##

const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"
const GOOD_ENDING_TEXTURE: Texture2D = preload("res://assets/sprites/ui/ending_good.svg")
const BAD_ENDING_TEXTURE: Texture2D = preload("res://assets/sprites/ui/ending_bad.svg")

@export var boss_scene: PackedScene
@export var exit_door_scene: PackedScene
@export var lucky_terminal_scene: PackedScene
@export_range(0, 6, 1) var lucky_terminal_count: int = 2
@export var run_music_id: String = "run"

@onready var player: PlayerController = $Player
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var floor_generator: FloorGenerator = $FloorGenerator
@onready var run_director: RunDirector = $RunDirector
@onready var arena: Arena = $Arena
@onready var enemies: Node2D = $RunContainers/Enemies
@onready var bosses: Node2D = $RunContainers/Bosses
@onready var exits: Node2D = $RunContainers/Exits
@onready var lucky_terminals_root: Node2D = $RunContainers/LuckyTerminals

@onready var hud: Hud = $HUD
@onready var overlay: RunOverlay = $RunOverlay
var _game_over: bool = false
var _pause_open: bool = false
var _boss_spawned: bool = false
var _exit_spawned: bool = false
var _last_boss_defeat_position: Vector2 = Vector2.ZERO
var _run_rewards_committed: bool = false


func _ready() -> void:
	randomize()
	_wire_signals()
	GameManager.begin_run()
	player.apply_meta_upgrades(GameManager.get_player_meta_profile())
	hud.bind_player(player)
	hud.bind_run_director(run_director)
	AudioManager.play_music(run_music_id)
	_spawn_lucky_terminals()
	_set_gameplay_active(false)
	overlay.game_over.dismiss()
	overlay.boot.bind(floor_generator)
	_update_mouse_mode()


func _unhandled_input(event: InputEvent) -> void:
	if _game_over:
		if (event.is_action_pressed("ui_accept")
			or event.is_action_pressed("ui_cancel")
			or event.is_action_pressed("restart")):
			_return_to_main_menu()
		return
	if event.is_action_pressed("ui_cancel"):
		if _is_overlay_open():
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()


# -- Signal wiring ---------------------------------------------------------

func _wire_signals() -> void:
	player.died.connect(_on_player_died)
	player.level_up_requested.connect(_on_player_level_up_requested)
	player.hand_selection_requested.connect(_on_player_hand_selection_requested)
	player.hand_locked.connect(_on_player_hand_locked)
	player.aim_mode_changed.connect(_on_player_aim_mode_changed)
	overlay.level_up.option_selected.connect(_on_level_up_option_selected)
	overlay.hand_augment.option_selected.connect(_on_hand_augment_option_selected)
	overlay.pause.resume_requested.connect(_close_pause_menu)
	overlay.pause.restart_requested.connect(_on_pause_restart_requested)
	overlay.pause.settings_requested.connect(_on_pause_settings_requested)
	overlay.pause.menu_requested.connect(_on_pause_menu_requested)
	overlay.settings.closed.connect(_on_pause_settings_closed)
	run_director.time_expired.connect(_on_run_time_expired)
	overlay.boot.finished.connect(_on_boot_finished)


# -- Boot ------------------------------------------------------------------

func _on_boot_finished() -> void:
	_set_gameplay_active(true)
	_update_mouse_mode()


func _set_gameplay_active(is_active: bool) -> void:
	var mode: Node.ProcessMode = Node.PROCESS_MODE_INHERIT if is_active else Node.PROCESS_MODE_DISABLED
	player.process_mode = mode
	enemy_spawner.process_mode = mode
	run_director.process_mode = mode


# -- Player events ---------------------------------------------------------

func _on_player_died() -> void:
	_end_run("GAME OVER", "Press Enter or Esc to return to menu")


func _on_player_level_up_requested(choices: Array) -> void:
	hud.visible = false
	overlay.level_up.present(choices, player.get_level_up_summary())
	get_tree().paused = true
	_update_mouse_mode()


func _on_level_up_option_selected(stat_id: String) -> void:
	player.apply_level_up_choice(stat_id)
	overlay.level_up.dismiss()
	hud.visible = true
	get_tree().paused = false
	_update_mouse_mode()


func _on_player_hand_selection_requested(choices: Array, summary: Dictionary) -> void:
	hud.visible = false
	overlay.hand_augment.present(choices, summary)
	get_tree().paused = true
	_update_mouse_mode()


func _on_hand_augment_option_selected(choice_id: String) -> void:
	player.apply_hand_choice(choice_id)
	overlay.hand_augment.dismiss()
	hud.visible = true
	get_tree().paused = false
	_update_mouse_mode()


func _on_player_hand_locked(_hand_name: String, _player_profile: Dictionary, enemy_profile: Dictionary) -> void:
	enemy_spawner.set_enemy_mutation_profile(enemy_profile)


func _on_player_aim_mode_changed(_is_manual: bool) -> void:
	_update_mouse_mode()


# -- Pause -----------------------------------------------------------------

func _open_pause_menu() -> void:
	if _game_over:
		return
	_pause_open = true
	get_tree().paused = true
	overlay.pause.present()
	_update_mouse_mode()


func _close_pause_menu() -> void:
	_pause_open = false
	overlay.pause.dismiss()
	get_tree().paused = false
	_update_mouse_mode()


func _on_pause_restart_requested() -> void:
	_pause_open = false
	get_tree().paused = false
	overlay.pause.dismiss()
	overlay.settings.dismiss()
	get_tree().reload_current_scene()


func _on_pause_settings_requested() -> void:
	overlay.settings.present()
	_update_mouse_mode()


func _on_pause_settings_closed() -> void:
	if overlay.pause.visible:
		overlay.pause.grab_focus()
	_update_mouse_mode()


func _on_pause_menu_requested() -> void:
	_finalize_run_rewards()
	_pause_open = false
	get_tree().paused = false
	overlay.pause.dismiss()
	overlay.settings.dismiss()
	_return_to_main_menu()


# -- Run progression -------------------------------------------------------

func _on_run_time_expired() -> void:
	if _boss_spawned or boss_scene == null:
		return
	_boss_spawned = true
	enemy_spawner.set_active(false)
	_clear_enemies()
	_spawn_boss.call_deferred()


func _spawn_boss() -> void:
	if boss_scene == null:
		return
	var boss: BossCore = boss_scene.instantiate() as BossCore
	if boss == null:
		return
	bosses.add_child(boss)
	boss.global_position = _arena_clamped(player.global_position + Vector2(240.0, -80.0), 48.0)
	boss.apply_mutation_profile(player.get_enemy_mutation_profile())
	boss.defeated.connect(_on_boss_defeated)


func _on_boss_defeated(defeat_position: Vector2 = Vector2.ZERO) -> void:
	print("[Boss] defeated")
	_last_boss_defeat_position = defeat_position
	player.add_screen_shake(9.0, 0.22)
	_spawn_exit_door.call_deferred()


func _spawn_exit_door() -> void:
	if _exit_spawned or exit_door_scene == null:
		return
	_exit_spawned = true
	var door: ExitDoor = exit_door_scene.instantiate() as ExitDoor
	if door == null:
		return
	exits.add_child(door)
	var fallback: Vector2 = _last_boss_defeat_position if _last_boss_defeat_position != Vector2.ZERO else player.global_position
	door.global_position = _arena_clamped(fallback, 48.0)
	door.player_exited.connect(_on_player_exited_run)


func _on_player_exited_run() -> void:
	if _game_over:
		return
	if player.has_royal_flush_run():
		AudioManager.play_sfx("ending_good", 1.0, -2.0)
		_end_run("GOOD ENDING", "Royal Flush secured. Press Enter or Esc to return to menu.", GOOD_ENDING_TEXTURE)
	else:
		AudioManager.play_sfx("ending_bad", 1.0, -2.0)
		_end_run("BAD ENDING", "You escaped, but not with a Royal Flush. Press Enter or Esc to return to menu.", BAD_ENDING_TEXTURE)


func _end_run(title: String, hint: String, art: Texture2D = null) -> void:
	_finalize_run_rewards()
	_game_over = true
	_pause_open = false
	get_tree().paused = false
	run_director.stop()
	overlay.pause.dismiss()
	overlay.hand_augment.dismiss()
	overlay.level_up.dismiss()
	enemy_spawner.set_active(false)
	enemy_spawner.stop_enemies()
	_clear_enemies()
	player.add_screen_shake(6.0, 0.18)
	overlay.game_over.show_result(title, hint, art)
	_update_mouse_mode()


# -- Lucky terminals -------------------------------------------------------

func _spawn_lucky_terminals() -> void:
	if lucky_terminal_scene == null or lucky_terminal_count <= 0:
		return
	var inner_radius: float = arena.get_inner_radius(160.0)
	var offset_distance: float = clampf(640.0, arena.get_inner_radius(240.0) * 0.72, inner_radius)
	var base_angle: float = randf() * TAU
	for index in range(lucky_terminal_count):
		var terminal: LuckyTerminal = lucky_terminal_scene.instantiate() as LuckyTerminal
		if terminal == null:
			continue
		terminal.name = "LuckyTerminal%d" % (index + 1)
		lucky_terminals_root.add_child(terminal)
		var angle: float = base_angle + (TAU / float(lucky_terminal_count)) * float(index) + randf_range(-0.08, 0.08)
		var radius: float = offset_distance * randf_range(0.92, 1.0)
		var target_pos: Vector2 = player.global_position + Vector2.RIGHT.rotated(angle) * radius
		terminal.global_position = _arena_clamped(target_pos, 48.0)


# -- Helpers ---------------------------------------------------------------

func _clear_enemies() -> void:
	for child in enemies.get_children():
		PoolManager.release(child)


func _arena_clamped(world_position: Vector2, margin: float) -> Vector2:
	return arena.clamp_world_position(world_position, margin)


func _is_overlay_open() -> bool:
	return (overlay.boot.visible
		or overlay.level_up.visible
		or overlay.hand_augment.visible
		or overlay.settings.visible
		or _pause_open)


func _finalize_run_rewards() -> void:
	if _run_rewards_committed:
		return
	_run_rewards_committed = true
	GameManager.commit_run_scrap()


func _return_to_main_menu() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(MAIN_MENU_SCENE_PATH)


func _update_mouse_mode() -> void:
	var force_visible: bool = (
		overlay.boot.visible
		or _game_over
		or _pause_open
		or overlay.settings.visible
		or overlay.level_up.visible
		or overlay.hand_augment.visible
	)
	if force_visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	Input.mouse_mode = Input.MOUSE_MODE_HIDDEN if player.is_manual_aim_enabled() else Input.MOUSE_MODE_VISIBLE
