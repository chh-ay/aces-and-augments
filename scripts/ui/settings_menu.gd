class_name SettingsMenu
extends Control

signal closed

const VOLUME_STEP: int = 10

@onready var _volume_value: Label = $Center/Panel/Margin/VBox/Rows/VolumeCard/Margin/Row/ValuePill/Margin/Value
@onready var _fullscreen_value: Label = $Center/Panel/Margin/VBox/Rows/FullscreenCard/Margin/Row/ValuePill/Margin/Value
@onready var _close_button: Button = $Center/Panel/Margin/VBox/Buttons/CloseButton
@onready var _volume_down_button: Button = $Center/Panel/Margin/VBox/Rows/VolumeCard/Margin/Row/VolumeDownButton
@onready var _volume_up_button: Button = $Center/Panel/Margin/VBox/Rows/VolumeCard/Margin/Row/VolumeUpButton
@onready var _fullscreen_button: Button = $Center/Panel/Margin/VBox/Rows/FullscreenCard/Margin/Row/FullscreenButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_volume_down_button.pressed.connect(_on_volume_down_pressed)
	_volume_up_button.pressed.connect(_on_volume_up_pressed)
	_fullscreen_button.pressed.connect(_on_fullscreen_pressed)
	_close_button.pressed.connect(dismiss)
	_refresh_values()

func present() -> void:
	visible = true
	_refresh_values()
	_volume_down_button.grab_focus()

func dismiss() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismiss()

func _on_volume_down_pressed() -> void:
	var next_value: int = max(AudioManager.get_master_volume_percent() - VOLUME_STEP, 0)
	AudioManager.set_master_volume_percent(next_value)
	_refresh_values()

func _on_volume_up_pressed() -> void:
	var next_value: int = min(AudioManager.get_master_volume_percent() + VOLUME_STEP, 100)
	AudioManager.set_master_volume_percent(next_value)
	_refresh_values()

func _on_fullscreen_pressed() -> void:
	AudioManager.set_fullscreen_enabled(not AudioManager.get_fullscreen_enabled())
	_refresh_values()

func _refresh_values() -> void:
	if _volume_value != null:
		_volume_value.text = "%d%%" % AudioManager.get_master_volume_percent()
	if _fullscreen_value != null:
		_fullscreen_value.text = "On" if AudioManager.get_fullscreen_enabled() else "Off"
