class_name MainMenu
extends Control

@export var run_scene: PackedScene
@export var test_scene: PackedScene
@export var menu_music_id: String = "menu"

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
@onready var _upgrade_shop: UpgradeShop = $UpgradeShop
@onready var _settings_menu: SettingsMenu = $SettingsMenu
@onready var _how_to_menu: HowToPlayMenu = $HowToPlayMenu
@onready var _credits_menu: CreditsMenu = $CreditsMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_wire_buttons()
	_wire_overlays()
	GameManager.scrap_changed.connect(_refresh_meta_ui)
	GameManager.upgrades_changed.connect(_refresh_meta_ui)
	AudioManager.play_music(menu_music_id, -16.0)
	_refresh_difficulty_ui()
	_refresh_meta_ui()
	_start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if (_upgrade_shop.visible or _settings_menu.visible
		or _how_to_menu.visible or _credits_menu.visible):
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


# -- Wiring ----------------------------------------------------------------

func _wire_buttons() -> void:
	_start_button.pressed.connect(_on_start_pressed)
	_difficulty_button.pressed.connect(_on_difficulty_pressed)
	_test_button.pressed.connect(_on_test_ground_pressed)
	_shop_button.pressed.connect(_upgrade_shop.present)
	_settings_button.pressed.connect(_settings_menu.present)
	_how_to_button.pressed.connect(_how_to_menu.present)
	_credits_button.pressed.connect(_credits_menu.present)
	_wipe_button.pressed.connect(_on_wipe_pressed)
	_quit_button.pressed.connect(get_tree().quit)


func _wire_overlays() -> void:
	_upgrade_shop.closed.connect(_focus_start)
	_settings_menu.closed.connect(_focus_start)
	_how_to_menu.closed.connect(_focus_start)
	_credits_menu.closed.connect(_focus_start)


# -- Actions ---------------------------------------------------------------

func _on_start_pressed() -> void:
	_change_scene(run_scene)


func _on_difficulty_pressed() -> void:
	GameManager.cycle_difficulty()
	_refresh_difficulty_ui()


func _on_test_ground_pressed() -> void:
	_change_scene(test_scene)


func _on_wipe_pressed() -> void:
	GameManager.wipe_progression()
	_focus_start()


func _change_scene(target_scene: PackedScene) -> void:
	if target_scene == null:
		push_warning("[MainMenu] target scene is not assigned.")
		return
	get_tree().change_scene_to_packed(target_scene)


# -- Refresh ---------------------------------------------------------------

func _focus_start() -> void:
	_start_button.grab_focus()


func _refresh_difficulty_ui() -> void:
	_difficulty_button.text = GameManager.get_difficulty_button_text()
	var config: Dictionary = GameManager.get_selected_difficulty()
	_difficulty_hint.text = "Enemy speed %.0f%%  |  HP %.0f%%  |  spawn %.0f%%  |  cards %.0f%%" % [
		float(config.get("enemy_speed", 1.0)) * 100.0,
		float(config.get("enemy_health", 1.0)) * 100.0,
		float(config.get("spawn_rate", 1.0)) * 100.0,
		float(config.get("card_drop", 1.0)) * 100.0,
	]


func _refresh_meta_ui(_total: int = 0, _run: int = 0) -> void:
	_scrap_label.text = "Scrap %d" % GameManager.get_total_scrap()
