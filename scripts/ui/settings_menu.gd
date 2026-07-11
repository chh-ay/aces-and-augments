class_name SettingsMenu
extends Control
##
## Volume and fullscreen toggle. Audio settings go through AudioManager.
## Display settings go through DisplayManager. Neither autoload needs a guard.
##

signal closed

const VOLUME_STEP: int = 10

@onready var _volume_value: Label = $Center/Panel/Margin/VBox/Rows/VolumeCard/Margin/Row/ValuePill/Margin/Value
@onready var _fullscreen_value: Label = $Center/Panel/Margin/VBox/Rows/FullscreenCard/Margin/Row/ValuePill/Margin/Value
@onready var _fullscreen_hint: Label = $Center/Panel/Margin/VBox/Rows/FullscreenCard/Margin/Row/LabelBlock/Hint
@onready var _close_button: Button = %CloseButton
@onready var _volume_down_button: Button = %VolumeDownButton
@onready var _volume_up_button: Button = %VolumeUpButton
@onready var _fullscreen_button: Button = %FullscreenButton


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
	AudioManager.set_master_volume_percent(max(AudioManager.get_master_volume_percent() - VOLUME_STEP, 0))
	_refresh_values()


func _on_volume_up_pressed() -> void:
	AudioManager.set_master_volume_percent(min(AudioManager.get_master_volume_percent() + VOLUME_STEP, 100))
	_refresh_values()


func _on_fullscreen_pressed() -> void:
	DisplayManager.set_fullscreen_enabled(not DisplayManager.get_fullscreen_enabled())
	_refresh_values()


func _refresh_values() -> void:
	_volume_value.text = "%d%%" % AudioManager.get_master_volume_percent()
	_fullscreen_hint.text = DisplayManager.get_display_mode_hint()
	var can_change: bool = DisplayManager.can_change_display_mode()
	_fullscreen_button.disabled = not can_change
	_fullscreen_button.text = "Toggle" if can_change else "Editor Only"
	if not can_change:
		_fullscreen_value.text = "Embed"
	else:
		_fullscreen_value.text = "On" if DisplayManager.get_fullscreen_enabled() else "Off"
