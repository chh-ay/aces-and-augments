class_name MainMenu
extends Control

@export var run_scene: PackedScene
## Debug playground (extra hotkeys, short run) for showcasing the endings.
@export var test_scene: PackedScene
@export var menu_music_id: String = "menu"

@onready var _start_button: Button = %StartButton
@onready var _shop_button: Button = %ShopButton
@onready var _settings_button: Button = %SettingsButton
@onready var _how_to_button: Button = %HowToButton
@onready var _credits_button: Button = %CreditsButton
@onready var _wipe_button: Button = %WipeButton
@onready var _test_button: Button = %TestGroundButton
@onready var _quit_button: Button = %QuitButton
@onready var _scrap_label: Label = %ScrapLabel
@onready var _upgrade_shop: UpgradeShop = $UpgradeShop
@onready var _settings_menu: SettingsMenu = $SettingsMenu
@onready var _how_to_menu: HowToPlayMenu = $HowToPlayMenu
@onready var _credits_menu: CreditsMenu = $CreditsMenu
@onready var _play_setup: PlaySetupMenu = $PlaySetupMenu


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_wire_buttons()
	_wire_overlays()
	GameManager.scrap_changed.connect(_refresh_meta_ui)
	GameManager.upgrades_changed.connect(_refresh_meta_ui)
	AudioManager.play_music(menu_music_id, -16.0)
	_refresh_meta_ui()
	_start_button.grab_focus()


func _unhandled_input(event: InputEvent) -> void:
	if (_upgrade_shop.visible or _settings_menu.visible
		or _how_to_menu.visible or _credits_menu.visible
		or _play_setup.visible):
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		get_tree().quit()


# -- Wiring ----------------------------------------------------------------

func _wire_buttons() -> void:
	_start_button.pressed.connect(_play_setup.present)
	_shop_button.pressed.connect(_upgrade_shop.present)
	_settings_button.pressed.connect(_settings_menu.present)
	_how_to_button.pressed.connect(_how_to_menu.present)
	_credits_button.pressed.connect(_credits_menu.present)
	_wipe_button.pressed.connect(_on_wipe_pressed)
	_test_button.pressed.connect(_on_test_ground_pressed)
	_quit_button.pressed.connect(get_tree().quit)


func _wire_overlays() -> void:
	_upgrade_shop.closed.connect(_focus_start)
	_settings_menu.closed.connect(_focus_start)
	_how_to_menu.closed.connect(_focus_start)
	_credits_menu.closed.connect(_focus_start)
	_play_setup.closed.connect(_focus_start)
	_play_setup.start_requested.connect(_on_start_run_requested)


# -- Actions ---------------------------------------------------------------

func _on_start_run_requested() -> void:
	if run_scene == null:
		push_warning("[MainMenu] run scene is not assigned.")
		return
	get_tree().change_scene_to_packed(run_scene)


func _on_wipe_pressed() -> void:
	GameManager.wipe_progression()
	_focus_start()


func _on_test_ground_pressed() -> void:
	if test_scene == null:
		push_warning("[MainMenu] test scene is not assigned.")
		return
	get_tree().change_scene_to_packed(test_scene)


# -- Refresh ---------------------------------------------------------------

func _focus_start() -> void:
	_start_button.grab_focus()


func _refresh_meta_ui(_total: int = 0, _run: int = 0) -> void:
	_scrap_label.text = "Scrap %d" % GameManager.get_total_scrap()
