class_name MainMenu
extends Control

@export var run_scene: PackedScene
@export var test_scene: PackedScene

@onready var _start_button: Button = $Center/Panel/Margin/VBox/Buttons/StartButton
@onready var _test_button: Button = $Center/Panel/Margin/VBox/Buttons/TestGroundButton
@onready var _quit_button: Button = $Center/Panel/Margin/VBox/Buttons/QuitButton

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_start_button.pressed.connect(_on_start_pressed)
	_test_button.pressed.connect(_on_test_ground_pressed)
	_quit_button.pressed.connect(_on_quit_pressed)
	_start_button.grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_on_quit_pressed()

func _on_start_pressed() -> void:
	_change_scene(run_scene)

func _on_test_ground_pressed() -> void:
	_change_scene(test_scene)

func _on_quit_pressed() -> void:
	get_tree().quit()

func _change_scene(target_scene: PackedScene) -> void:
	if target_scene == null:
		push_warning("MainMenu target scene is not assigned.")
		return
	get_tree().change_scene_to_packed(target_scene)
