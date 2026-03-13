class_name Main
extends Node2D

const MAIN_MENU_SCENE_PATH: String = "res://scenes/ui/main_menu.tscn"
const GOOD_ENDING_TEXTURE: Texture2D = preload("res://assets/sprites/ui/ending_good.svg")
const BAD_ENDING_TEXTURE: Texture2D = preload("res://assets/sprites/ui/ending_bad.svg")
const GOOD_ENDING_PANEL_SCENE: PackedScene = preload("res://scenes/ui/good_ending_panel.tscn")
const BAD_ENDING_PANEL_SCENE: PackedScene = preload("res://scenes/ui/bad_ending_panel.tscn")

@export var boss_scene: PackedScene
@export var exit_door_scene: PackedScene
@export_range(1, 6, 1) var lucky_terminal_count: int = 2

@onready var music_player: AudioStreamPlayer = $RunMusicPlayer
@onready var player: PlayerController = $Player
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var floor_generator: FloorGenerator = $FloorGenerator
@onready var game_over_ui: Control = $CanvasLayer/GameOver
@onready var ending_panel_host: Control = $CanvasLayer/GameOver/Panel/EndingPanelHost
@onready var game_over_default_vbox: VBoxContainer = $CanvasLayer/GameOver/Panel/VBox
@onready var game_over_title: Label = $CanvasLayer/GameOver/Panel/VBox/Title
@onready var game_over_art: TextureRect = $CanvasLayer/GameOver/Panel/VBox/ArtCenter/EndingArt
@onready var game_over_hint: Label = $CanvasLayer/GameOver/Panel/VBox/HintCard/Margin/Hint
@onready var boot_overlay: Control = $CanvasLayer/BootOverlay
@onready var pause_menu: PauseMenu = $CanvasLayer/PauseMenu
@onready var settings_menu: SettingsMenu = $CanvasLayer/SettingsMenu
@onready var hud: Hud = $HUD
@onready var level_up_panel: LevelUpPanel = $CanvasLayer/LevelUpPanel
@onready var hand_augment_panel: Control = $CanvasLayer/HandAugmentPanel
@onready var run_director: RunDirector = $RunDirector
@onready var arena: Arena = $Arena
@onready var enemies: Node2D = $Enemies
@onready var bosses: Node2D = $Bosses
@onready var exits: Node2D = $Exits
@onready var lucky_terminal: Node2D = $LuckyTerminal
@onready var pool_manager: Node = get_node_or_null("PoolManager")

var _game_over: bool = false
var _pause_open: bool = false
var _boss_spawned: bool = false
var _exit_spawned: bool = false
var _last_boss_defeat_position: Vector2 = Vector2.ZERO
var _run_rewards_committed: bool = false
var _boot_completed: bool = false
var _lucky_terminals: Array[LuckyTerminal] = []
var _active_ending_panel: Control

func _ready() -> void:
	_set_boot_state(true)
	call_deferred("_start_run_music")
	if floor_generator != null and floor_generator.has_signal("initial_chunks_ready") and not floor_generator.initial_chunks_ready.is_connected(_on_initial_chunks_ready):
		floor_generator.initial_chunks_ready.connect(_on_initial_chunks_ready, CONNECT_ONE_SHOT)
	if GameManager != null and GameManager.has_method("begin_run"):
		GameManager.call("begin_run")
	if player != null and GameManager != null and GameManager.has_method("get_player_meta_profile"):
		player.apply_meta_upgrades(GameManager.call("get_player_meta_profile"))
	_update_game_over_ui(false, "GAME OVER", "Press Enter or Esc to return to menu")
	_setup_lucky_terminals()
	_position_lucky_terminals()
	if player != null:
		player.died.connect(_on_player_died)
		player.level_up_requested.connect(_on_player_level_up_requested)
		player.hand_selection_requested.connect(_on_player_hand_selection_requested)
		player.hand_locked.connect(_on_player_hand_locked)
		if player.has_signal("aim_mode_changed"):
			player.aim_mode_changed.connect(_on_player_aim_mode_changed)
	if hud != null and player != null:
		hud.bind_player(player)
	if hud != null and run_director != null:
		hud.bind_run_director(run_director)
	if level_up_panel != null:
		level_up_panel.option_selected.connect(_on_level_up_option_selected)
	if hand_augment_panel != null and hand_augment_panel.has_signal("option_selected"):
		hand_augment_panel.connect("option_selected", Callable(self, "_on_hand_augment_option_selected"))
	if pause_menu != null:
		pause_menu.resume_requested.connect(_on_pause_resume_requested)
		pause_menu.restart_requested.connect(_on_pause_restart_requested)
		pause_menu.settings_requested.connect(_on_pause_settings_requested)
		pause_menu.menu_requested.connect(_on_pause_menu_requested)
	if settings_menu != null:
		settings_menu.closed.connect(_on_pause_settings_closed)
	if run_director != null:
		run_director.time_expired.connect(_on_run_time_expired)
	if floor_generator != null and floor_generator.has_initial_chunks_ready():
		call_deferred("_complete_boot_sequence")
	_update_mouse_mode()

func _unhandled_input(event: InputEvent) -> void:
	if _game_over:
		if event.is_action_pressed("ui_accept"):
			_return_to_main_menu()
		elif event.is_action_pressed("restart"):
			_return_to_main_menu()
		elif event.is_action_pressed("ui_cancel"):
			_return_to_main_menu()
		return
	if event.is_action_pressed("ui_cancel"):
		if level_up_panel != null and level_up_panel.visible:
			return
		if hand_augment_panel != null and hand_augment_panel.visible:
			return
		if _pause_open:
			return
		_open_pause_menu()
		get_viewport().set_input_as_handled()

func _on_player_died() -> void:
	_finalize_run_rewards()
	_game_over = true
	_pause_open = false
	get_tree().paused = false
	if run_director != null:
		run_director.stop()
	if pause_menu != null:
		pause_menu.dismiss()
	if hand_augment_panel != null and hand_augment_panel.has_method("dismiss"):
		hand_augment_panel.call("dismiss")
	if level_up_panel != null:
		level_up_panel.dismiss()
	_update_game_over_ui(true, "GAME OVER", "Press Enter or Esc to return to menu")
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
		enemy_spawner.stop_enemies()
	_update_mouse_mode()

func _update_game_over_ui(should_show: bool, title_text: String, hint_text: String, art_texture: Texture2D = null) -> void:
	if game_over_ui != null:
		game_over_ui.visible = should_show
	_clear_result_panel()
	if game_over_default_vbox != null:
		game_over_default_vbox.visible = should_show
	if game_over_title != null:
		game_over_title.text = title_text
	if game_over_art != null:
		game_over_art.texture = art_texture
		game_over_art.visible = art_texture != null
	if game_over_hint != null:
		game_over_hint.text = hint_text

func _show_result_panel(panel_scene: PackedScene) -> void:
	if not should_instance_result_panel(panel_scene):
		return
	_clear_result_panel()
	if game_over_default_vbox != null:
		game_over_default_vbox.visible = false
	var panel_instance: Control = panel_scene.instantiate() as Control
	_active_ending_panel = panel_instance
	ending_panel_host.add_child(panel_instance)

func _clear_result_panel() -> void:
	if is_instance_valid(_active_ending_panel):
		_active_ending_panel.queue_free()
	_active_ending_panel = null

func should_instance_result_panel(panel_scene: PackedScene) -> bool:
	return ending_panel_host != null and panel_scene != null

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
	_update_mouse_mode()

func _on_level_up_option_selected(stat_id: String) -> void:
	if player != null:
		player.apply_level_up_choice(stat_id)
	if level_up_panel != null:
		level_up_panel.dismiss()
	if hud != null:
		hud.visible = true
	get_tree().paused = false
	_update_mouse_mode()

func _on_player_hand_selection_requested(choices: Array, summary: Dictionary) -> void:
	if hand_augment_panel == null:
		return
	if hud != null:
		hud.visible = false
	hand_augment_panel.call("present", choices, summary)
	get_tree().paused = true
	_update_mouse_mode()

func _on_hand_augment_option_selected(choice_id: String) -> void:
	if player != null:
		player.apply_hand_choice(choice_id)
	if hand_augment_panel != null and hand_augment_panel.has_method("dismiss"):
		hand_augment_panel.call("dismiss")
	if hud != null:
		hud.visible = true
	get_tree().paused = false
	_update_mouse_mode()

func _open_pause_menu() -> void:
	if pause_menu == null or _game_over:
		return
	_pause_open = true
	get_tree().paused = true
	pause_menu.present()
	_update_mouse_mode()

func _close_pause_menu() -> void:
	if pause_menu == null:
		return
	_pause_open = false
	pause_menu.dismiss()
	get_tree().paused = false
	_update_mouse_mode()

func _on_pause_resume_requested() -> void:
	_close_pause_menu()

func _on_pause_restart_requested() -> void:
	_pause_open = false
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.dismiss()
	if settings_menu != null:
		settings_menu.dismiss()
	get_tree().reload_current_scene()

func _on_pause_settings_requested() -> void:
	if settings_menu == null:
		return
	settings_menu.present()
	_update_mouse_mode()

func _on_pause_settings_closed() -> void:
	if pause_menu != null and pause_menu.visible:
		pause_menu.grab_focus()
	_update_mouse_mode()

func _on_pause_menu_requested() -> void:
	_finalize_run_rewards()
	_pause_open = false
	get_tree().paused = false
	if pause_menu != null:
		pause_menu.dismiss()
	if settings_menu != null:
		settings_menu.dismiss()
	_return_to_main_menu()

func _on_run_time_expired() -> void:
	if _boss_spawned or boss_scene == null or bosses == null or player == null:
		return
	_boss_spawned = true
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
	_clear_enemies()
	call_deferred("_spawn_boss")

func _spawn_boss() -> void:
	if boss_scene == null or bosses == null or player == null:
		return
	var boss_node: Node = boss_scene.instantiate()
	if boss_node is Node2D:
		var boss: Node2D = boss_node as Node2D
		bosses.add_child(boss)
		boss.global_position = _get_boss_spawn_position()
		if boss.has_method("apply_mutation_profile") and player != null:
			boss.call("apply_mutation_profile", player.get_enemy_mutation_profile())
		if boss.has_signal("defeated"):
			boss.connect("defeated", Callable(self, "_on_boss_defeated"))

func _on_boss_defeated(defeat_position: Vector2 = Vector2.ZERO) -> void:
	CustomLogger.info("Boss defeated", "Boss")
	_last_boss_defeat_position = defeat_position
	if player != null:
		player.add_screen_shake(9.0, 0.22)
	call_deferred("_spawn_exit_door")

func _clear_enemies() -> void:
	if enemies == null:
		return
	for child in enemies.get_children():
		if pool_manager != null and pool_manager.has_method("release"):
			pool_manager.release(child)
		else:
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
	_finalize_run_rewards()
	_game_over = true
	_pause_open = false
	get_tree().paused = false
	if run_director != null:
		run_director.stop()
	if pause_menu != null:
		pause_menu.dismiss()
	if enemy_spawner != null:
		enemy_spawner.set_active(false)
		enemy_spawner.stop_enemies()
	_clear_enemies()
	var has_royal_flush: bool = player != null and player.has_royal_flush_run()
	if has_royal_flush:
		if player != null:
			player.add_screen_shake(6.0, 0.18)
		if AudioManager != null and AudioManager.has_method("play_sfx"):
			AudioManager.play_sfx("ending_good", 1.0, -2.0)
		_update_game_over_ui(true, "GOOD ENDING", "Royal Flush secured. Press Enter or Esc to return to menu.", GOOD_ENDING_TEXTURE)
		_show_result_panel(GOOD_ENDING_PANEL_SCENE)
	else:
		if player != null:
			player.add_screen_shake(6.0, 0.18)
		if AudioManager != null and AudioManager.has_method("play_sfx"):
			AudioManager.play_sfx("ending_bad", 1.0, -2.0)
		_update_game_over_ui(true, "BAD ENDING", "You escaped, but not with a Royal Flush. Press Enter or Esc to return to menu.", BAD_ENDING_TEXTURE)
		_show_result_panel(BAD_ENDING_PANEL_SCENE)
	_update_mouse_mode()

func _return_to_main_menu() -> void:
	get_tree().paused = false
	var main_menu_scene: PackedScene = load(MAIN_MENU_SCENE_PATH) as PackedScene
	if main_menu_scene == null:
		get_tree().quit()
		return
	get_tree().change_scene_to_packed(main_menu_scene)

func _on_player_hand_locked(_hand_name: String, _player_profile: Dictionary, enemy_profile: Dictionary) -> void:
	if enemy_spawner != null:
		enemy_spawner.set_enemy_mutation_profile(enemy_profile)

func _setup_lucky_terminals() -> void:
	_lucky_terminals.clear()
	var base_terminal: LuckyTerminal = lucky_terminal as LuckyTerminal
	if base_terminal == null:
		return
	_lucky_terminals.append(base_terminal)
	var target_count: int = max(lucky_terminal_count, 1)
	while _lucky_terminals.size() < target_count:
		var duplicate_terminal: LuckyTerminal = base_terminal.duplicate() as LuckyTerminal
		if duplicate_terminal == null:
			break
		duplicate_terminal.name = "LuckyTerminal%d" % (_lucky_terminals.size() + 1)
		add_child(duplicate_terminal)
		_lucky_terminals.append(duplicate_terminal)

func _position_lucky_terminals() -> void:
	if _lucky_terminals.is_empty():
		return
	if player == null:
		return
	var offset_distance: float = 224.0
	if run_director == null or run_director.run_duration_seconds > 30.0:
		offset_distance = 640.0
	if arena != null:
		offset_distance = min(offset_distance, arena.get_inner_radius(160.0))
		offset_distance = max(offset_distance, arena.get_inner_radius(240.0) * 0.72)
	var terminal_count: int = _lucky_terminals.size()
	var base_angle: float = randf() * TAU
	for index in range(terminal_count):
		var terminal: LuckyTerminal = _lucky_terminals[index]
		if terminal == null:
			continue
		var angle: float = base_angle + (TAU / float(terminal_count)) * float(index) + randf_range(-0.08, 0.08)
		var distance_scale: float = randf_range(0.92, 1.0)
		var offset: Vector2 = Vector2.RIGHT.rotated(angle) * offset_distance * distance_scale
		var target_position: Vector2 = player.global_position + offset
		if arena != null:
			target_position = arena.clamp_world_position(target_position, 48.0)
		terminal.global_position = target_position

func _finalize_run_rewards() -> void:
	if _run_rewards_committed:
		return
	_run_rewards_committed = true
	if GameManager != null and GameManager.has_method("commit_run_scrap"):
		GameManager.call("commit_run_scrap")

func _on_initial_chunks_ready() -> void:
	call_deferred("_complete_boot_sequence")

func _complete_boot_sequence() -> void:
	if _boot_completed:
		return
	_boot_completed = true
	_set_boot_state(false)

func _set_boot_state(is_booting: bool) -> void:
	if boot_overlay != null:
		boot_overlay.visible = is_booting
	if hud != null:
		hud.visible = not is_booting
	if player != null:
		player.process_mode = Node.PROCESS_MODE_DISABLED if is_booting else Node.PROCESS_MODE_INHERIT
	if enemy_spawner != null:
		enemy_spawner.process_mode = Node.PROCESS_MODE_DISABLED if is_booting else Node.PROCESS_MODE_INHERIT
	if run_director != null:
		run_director.process_mode = Node.PROCESS_MODE_DISABLED if is_booting else Node.PROCESS_MODE_INHERIT
	_update_mouse_mode()

func _on_player_aim_mode_changed(_is_manual: bool) -> void:
	_update_mouse_mode()

func _update_mouse_mode() -> void:
	if boot_overlay != null and boot_overlay.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if _game_over or _pause_open:
		if settings_menu != null and settings_menu.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			return
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if level_up_panel != null and level_up_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if hand_augment_panel != null and hand_augment_panel.visible:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		return
	if player != null and player.has_method("is_manual_aim_enabled") and player.is_manual_aim_enabled():
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
		return
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _start_run_music() -> void:
	if music_player == null:
		return
	if AudioManager != null:
		if AudioManager.has_method("get_music_volume_db"):
			music_player.volume_db = AudioManager.get_music_volume_db("run", -14.0)
		if AudioManager.has_method("apply_saved_settings"):
			AudioManager.apply_saved_settings()
	music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	music_player.stream_paused = false
	if music_player.stream != null and not music_player.playing:
		music_player.play()
	call_deferred("_verify_run_music_playback")

func _verify_run_music_playback() -> void:
	await get_tree().create_timer(0.35, false, false, true).timeout
	if not is_instance_valid(music_player):
		return
	if music_player.stream != null and (music_player.stream_paused or not music_player.playing or music_player.get_playback_position() < 0.05):
		music_player.stop()
		music_player.stream_paused = false
		music_player.play()
	await get_tree().create_timer(0.35, false, false, true).timeout
	_report_run_music_state()

func _report_run_music_state() -> void:
	if music_player == null:
		return
	var bus_index: int = AudioServer.get_bus_index(music_player.bus)
	var bus_db: float = AudioServer.get_bus_volume_db(bus_index) if bus_index != -1 else 0.0
	var bus_muted: bool = AudioServer.is_bus_mute(bus_index) if bus_index != -1 else false
	if CustomLogger != null and CustomLogger.has_method("info"):
		CustomLogger.info(
			"Run player stream=%s playing=%s paused=%s pos=%.2f bus=%s muted=%s bus_db=%.1f vol_db=%.1f" % [
				"true" if music_player.stream != null else "false",
				"true" if music_player.playing else "false",
				"true" if music_player.stream_paused else "false",
				music_player.get_playback_position(),
				String(music_player.bus),
				"true" if bus_muted else "false",
				bus_db,
				music_player.volume_db
			],
			"Audio"
		)
