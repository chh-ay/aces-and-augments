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
@export var run_music_id: String = "run"

@onready var player: PlayerController = $Player
@onready var enemy_spawner: EnemySpawner = $EnemySpawner
@onready var floor_generator: FloorGenerator = $FloorGenerator
@onready var run_director: RunDirector = $RunDirector
@onready var arena: Arena = $Arena
@onready var enemies: Node2D = $RunContainers/Enemies
@onready var bosses: Node2D = $RunContainers/Bosses
@onready var exits: Node2D = $RunContainers/Exits

@onready var hud: Hud = $HUD
@onready var overlay: RunOverlay = $RunOverlay
var _game_over: bool = false
var _pause_open: bool = false
var _boss_spawned: bool = false
var _exit_spawned: bool = false
var _last_boss_defeat_position: Vector2 = Vector2.ZERO
var _run_rewards_committed: bool = false


const CARD_CACHE_SCENE: PackedScene = preload("res://scenes/world/card_cache.tscn")
## Scripted run beats: elapsed seconds -> event id. Skipped when the run is
## shorter (test ground).
const RUN_EVENTS: Array[Dictionary] = [
	{"at": 120.0, "id": "swarm", "banner": "A SWARM APPROACHES"},
	{"at": 300.0, "id": "elite", "banner": "AN ELITE HUNTS YOU"},
	{"at": 450.0, "id": "frenzy", "banner": "FRENZY - THEY POUR IN"},
]

var _fired_events: Dictionary = {}

func _ready() -> void:
	randomize()
	_wire_signals()
	GameManager.begin_run()
	player.apply_meta_upgrades(GameManager.get_player_meta_profile())
	hud.bind_player(player)
	hud.bind_run_director(run_director)
	AudioManager.play_music(run_music_id)
	_set_gameplay_active(false)
	overlay.game_over.dismiss()
	overlay.boot.bind(floor_generator)
	_spawn_card_caches.call_deferred()
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
	run_director.time_updated.connect(_on_run_time_updated)
	overlay.boot.finished.connect(_on_boot_finished)


# -- Run events --------------------------------------------------------------

func _on_run_time_updated(remaining_seconds: float) -> void:
	if _game_over:
		return
	var elapsed: float = run_director.run_duration_seconds - remaining_seconds
	for event in RUN_EVENTS:
		var event_id: String = String(event.get("id", ""))
		if _fired_events.has(event_id) or elapsed < float(event.get("at", 0.0)):
			continue
		_fired_events[event_id] = true
		_fire_run_event(event_id, String(event.get("banner", "")))


func _fire_run_event(event_id: String, banner: String) -> void:
	if not banner.is_empty():
		hud.show_announcement(banner)
	AudioManager.play_sfx("hand_lock", 0.8, -6.0)
	match event_id:
		"swarm":
			enemy_spawner.spawn_surge(12)
		"elite":
			enemy_spawner.spawn_elite()
		"frenzy":
			enemy_spawner.start_frenzy(25.0)


## A few chests scattered on land give the map a reason to be crossed.
func _spawn_card_caches(count: int = 3) -> void:
	for _index in range(count):
		for _attempt in range(10):
			var direction: Vector2 = Vector2.RIGHT.rotated(randf() * TAU)
			var target: Vector2 = player.global_position + direction * randf_range(420.0, 850.0)
			target = _arena_clamped(target, 64.0)
			var cell: Vector2i = Vector2i(int(floor(target.x / 32.0)), int(floor(target.y / 32.0)))
			if floor_generator.is_cell_water(cell.x, cell.y):
				continue
			var cache: CardCache = CARD_CACHE_SCENE.instantiate() as CardCache
			exits.add_child(cache)
			cache.global_position = target
			break

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
	_end_run("GAME OVER", "Press Enter or Esc to return to menu", null, false)


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
	GameManager.record_hand_locked()
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
	_finalize_run_rewards(false)
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
	hud.show_announcement("THE GOLDEN SLICER AWAKENS")
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
	enemy_spawner.apply_scaling_to(boss)
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
		_end_run("GOOD ENDING", "Royal Flush secured. Press Enter or Esc to return to menu.", GOOD_ENDING_TEXTURE, true)
	else:
		AudioManager.play_sfx("ending_bad", 1.0, -2.0)
		_end_run("BAD ENDING", "You escaped, but not with a Royal Flush. Press Enter or Esc to return to menu.", BAD_ENDING_TEXTURE, true)


func _end_run(title: String, hint: String, art: Texture2D = null, completed: bool = false) -> void:
	var summary: Dictionary = _build_run_summary(completed)
	_finalize_run_rewards(completed)
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
	overlay.game_over.show_result(title, hint, art, "RUN RESULT", summary)
	_update_mouse_mode()


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


## Completed runs bank their scrap; failed or abandoned runs forfeit it.
func _finalize_run_rewards(completed: bool) -> void:
	if _run_rewards_committed:
		return
	_run_rewards_committed = true
	if completed:
		GameManager.commit_run_scrap()
	else:
		GameManager.discard_run_scrap()


## Snapshot of run stats taken BEFORE rewards are finalized, so provisional
## scrap is still visible and can be labeled banked or lost.
func _build_run_summary(completed: bool) -> Dictionary:
	var stats: Dictionary = GameManager.get_run_stats()
	return {
		"time_seconds": max(run_director.run_duration_seconds - run_director.remaining_seconds, 0.0),
		"level": player.current_level,
		"kills": int(stats.get("kills", 0)),
		"hands_locked": int(stats.get("hands_locked", 0)),
		"scrap": GameManager.get_current_run_scrap(),
		"banked": completed,
	}

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
