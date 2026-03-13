class_name MainMenu
extends Control

@export var run_scene: PackedScene
@export var test_scene: PackedScene

@onready var _music_player: AudioStreamPlayer = $MenuMusicPlayer
@onready var _difficulty_button: Button = $Center/Panel/Margin/VBox/DifficultyButton
@onready var _difficulty_hint: Label = $Center/Panel/Margin/VBox/DifficultyHint
@onready var _start_button: Button = $Center/Panel/Margin/VBox/Buttons/StartButton
@onready var _test_button: Button = $Center/Panel/Margin/VBox/Buttons/TestGroundButton
@onready var _shop_button: Button = $Center/Panel/Margin/VBox/Buttons/ShopButton
@onready var _settings_button: Button = $Center/Panel/Margin/VBox/Buttons/SettingsButton
@onready var _how_to_button: Button = $Center/Panel/Margin/VBox/Buttons/HowToButton
@onready var _credits_button: Button = $Center/Panel/Margin/VBox/Buttons/CreditsButton
@onready var _wipe_button: Button = $Center/Panel/Margin/VBox/Buttons/WipeButton
@onready var _quit_button: Button = $Center/Panel/Margin/VBox/Buttons/QuitButton
@onready var _scrap_label: Label = $Center/Panel/Margin/VBox/ScrapLabel
@onready var _upgrade_shop = $UpgradeShop
@onready var _settings_menu = $SettingsMenu
@onready var _how_to_menu = $HowToPlayMenu
@onready var _credits_menu = $CreditsMenu

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	call_deferred("_start_menu_music")
	_difficulty_button.pressed.connect(_on_difficulty_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_test_button.pressed.connect(_on_test_ground_pressed)
	_shop_button.pressed.connect(_on_shop_pressed)
	_settings_button.pressed.connect(_on_settings_pressed)
	_how_to_button.pressed.connect(_on_how_to_pressed)
	_credits_button.pressed.connect(_on_credits_pressed)
	_wipe_button.pressed.connect(_on_wipe_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_upgrade_shop.closed.connect(_on_shop_closed)
	_settings_menu.closed.connect(_on_settings_closed)
	_how_to_menu.closed.connect(_on_how_to_closed)
	_credits_menu.closed.connect(_on_credits_closed)
	if GameManager != null:
		GameManager.scrap_changed.connect(_refresh_meta_ui)
		GameManager.upgrades_changed.connect(_refresh_meta_ui)
	_refresh_difficulty_ui()
	_refresh_meta_ui()
	_start_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _upgrade_shop != null and _upgrade_shop.visible:
		return
	if _settings_menu != null and _settings_menu.visible:
		return
	if _how_to_menu != null and _how_to_menu.visible:
		return
	if _credits_menu != null and _credits_menu.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_quit_pressed()

func _on_start_pressed() -> void:
	_change_scene(run_scene)

func _on_difficulty_pressed() -> void:
	GameManager.cycle_difficulty()
	_refresh_difficulty_ui()

func _on_test_ground_pressed() -> void:
	_change_scene(test_scene)

func _on_shop_pressed() -> void:
	if _upgrade_shop == null:
		return
	_upgrade_shop.present()

func _on_shop_closed() -> void:
	_start_button.grab_focus()

func _on_settings_pressed() -> void:
	if _settings_menu == null:
		return
	_settings_menu.present()

func _on_how_to_pressed() -> void:
	if _how_to_menu == null:
		return
	_how_to_menu.present()

func _on_wipe_pressed() -> void:
	if GameManager != null:
		GameManager.wipe_progression()
	_refresh_meta_ui()
	_start_button.grab_focus()

func _on_settings_closed() -> void:
	_start_button.grab_focus()

func _on_how_to_closed() -> void:
	_start_button.grab_focus()

func _on_credits_pressed() -> void:
	if _credits_menu == null:
		return
	_credits_menu.present()

func _on_credits_closed() -> void:
	_start_button.grab_focus()

func _on_quit_pressed() -> void:
	get_tree().quit()

func _change_scene(target_scene: PackedScene) -> void:
	if target_scene == null:
		push_warning("MainMenu target scene is not assigned.")
		return
	get_tree().change_scene_to_packed(target_scene)

func _refresh_difficulty_ui() -> void:
	if _difficulty_button != null:
		_difficulty_button.text = GameManager.get_difficulty_button_text()
	if _difficulty_hint != null:
		var config: Dictionary = GameManager.get_selected_difficulty()
		_difficulty_hint.text = "Enemy speed %.0f%%  |  HP %.0f%%  |  spawn %.0f%%  |  cards %.0f%%" % [
			float(config.get("enemy_speed", 1.0)) * 100.0,
			float(config.get("enemy_health", 1.0)) * 100.0,
			float(config.get("spawn_rate", 1.0)) * 100.0,
			float(config.get("card_drop", 1.0)) * 100.0
		]

func _refresh_meta_ui(_arg1 = null, _arg2 = null) -> void:
	if _scrap_label != null and GameManager != null:
		_scrap_label.text = "Scrap %d" % GameManager.get_total_scrap()

func _start_menu_music() -> void:
	if _music_player == null:
		return
	if AudioManager != null:
		if AudioManager.has_method("get_music_volume_db"):
			_music_player.volume_db = AudioManager.get_music_volume_db("menu", -16.0)
		if AudioManager.has_method("apply_saved_settings"):
			AudioManager.apply_saved_settings()
	_music_player.process_mode = Node.PROCESS_MODE_ALWAYS
	_music_player.stream_paused = false
	if _music_player.stream != null and not _music_player.playing:
		_music_player.play()
	call_deferred("_verify_menu_music_playback")

func _verify_menu_music_playback() -> void:
	await get_tree().create_timer(0.35, false, false, true).timeout
	if not is_instance_valid(_music_player):
		return
	if _music_player.stream != null and (_music_player.stream_paused or not _music_player.playing or _music_player.get_playback_position() < 0.05):
		_music_player.stop()
		_music_player.stream_paused = false
		_music_player.play()
	await get_tree().create_timer(0.35, false, false, true).timeout
	_report_menu_music_state()

func _report_menu_music_state() -> void:
	if _music_player == null:
		return
	var bus_index: int = AudioServer.get_bus_index(_music_player.bus)
	var bus_db: float = AudioServer.get_bus_volume_db(bus_index) if bus_index != -1 else 0.0
	var bus_muted: bool = AudioServer.is_bus_mute(bus_index) if bus_index != -1 else false
	if CustomLogger != null and CustomLogger.has_method("info"):
		CustomLogger.info(
			"Menu player stream=%s playing=%s paused=%s pos=%.2f bus=%s muted=%s bus_db=%.1f vol_db=%.1f" % [
				"true" if _music_player.stream != null else "false",
				"true" if _music_player.playing else "false",
				"true" if _music_player.stream_paused else "false",
				_music_player.get_playback_position(),
				String(_music_player.bus),
				"true" if bus_muted else "false",
				bus_db,
				_music_player.volume_db
			],
			"Audio"
		)
