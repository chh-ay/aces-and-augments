class_name PauseMenu
extends Control

signal resume_requested
signal restart_requested
signal menu_requested

@onready var _resume_button: Button = $Center/Panel/Margin/VBox/ResumeButton
@onready var _restart_button: Button = $Center/Panel/Margin/VBox/RestartButton
@onready var _menu_button: Button = $Center/Panel/Margin/VBox/MenuButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	mouse_filter = Control.MOUSE_FILTER_STOP
	_resume_button.pressed.connect(_on_resume_pressed)
	_restart_button.pressed.connect(_on_restart_pressed)
	_menu_button.pressed.connect(_on_menu_pressed)

func present() -> void:
	visible = true
	_resume_button.grab_focus()

func dismiss() -> void:
	visible = false

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		resume_requested.emit()

func _on_resume_pressed() -> void:
	resume_requested.emit()

func _on_restart_pressed() -> void:
	restart_requested.emit()

func _on_menu_pressed() -> void:
	menu_requested.emit()
