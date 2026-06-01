extends Node
## Owns window display state: fullscreen toggle and an embedded-editor hint.
## Persists choice to SaveManager. Audio settings live in AudioManager.

signal fullscreen_changed(is_enabled: bool)


func _ready() -> void:
	apply_saved_state()


## Apply persisted preferences. Safe to call from any scene's _ready.
func apply_saved_state() -> void:
	set_fullscreen_enabled(SaveManager.get_fullscreen_enabled(false), false)


func get_fullscreen_enabled() -> bool:
	var window: Window = _get_window()
	if window == null:
		return false
	return window.mode == Window.MODE_FULLSCREEN or window.mode == Window.MODE_EXCLUSIVE_FULLSCREEN


func can_change_display_mode() -> bool:
	return not OS.has_feature("editor")


func get_display_mode_hint() -> String:
	if can_change_display_mode():
		return "Windowed or fullscreen"
	return "Disabled while running embedded in the editor"


func set_fullscreen_enabled(is_enabled: bool, persist: bool = true) -> void:
	if not can_change_display_mode():
		return
	var window: Window = _get_window()
	if window == null:
		return
	window.mode = Window.MODE_EXCLUSIVE_FULLSCREEN if is_enabled else Window.MODE_WINDOWED
	if not is_enabled:
		window.move_to_center()
	if persist:
		SaveManager.set_fullscreen_enabled(is_enabled)
	fullscreen_changed.emit(is_enabled)


func _get_window() -> Window:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	return tree.root if tree != null else null
