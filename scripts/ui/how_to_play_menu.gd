class_name HowToPlayMenu
extends Control

signal closed

@onready var _close_button: Button = $Center/Panel/Margin/VBox/CloseButton

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(dismiss)

func present() -> void:
	visible = true
	_close_button.grab_focus()

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
