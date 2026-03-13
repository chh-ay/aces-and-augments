extends Node

const MASTER_BUS_NAME: String = "Master"
const MIN_AUDIBLE_LINEAR: float = 0.0001

var _master_bus_index: int = -1

func _ready() -> void:
	_master_bus_index = AudioServer.get_bus_index(MASTER_BUS_NAME)
	apply_saved_settings()

func apply_saved_settings() -> void:
	var save_manager: Node = _get_save_manager()
	if save_manager == null:
		return
	if save_manager.has_method("get_master_volume_percent"):
		set_master_volume_percent(int(save_manager.call("get_master_volume_percent", 100)))
	if save_manager.has_method("get_fullscreen_enabled"):
		set_fullscreen_enabled(bool(save_manager.call("get_fullscreen_enabled", false)))

func get_master_volume_percent() -> int:
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("get_master_volume_percent"):
		return int(save_manager.call("get_master_volume_percent", 100))
	return 100

func set_master_volume_percent(percent: int) -> void:
	var safe_percent: int = clampi(percent, 0, 100)
	if _master_bus_index == -1:
		_master_bus_index = AudioServer.get_bus_index(MASTER_BUS_NAME)
	if _master_bus_index != -1:
		if safe_percent <= 0:
			AudioServer.set_bus_mute(_master_bus_index, true)
			AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(MIN_AUDIBLE_LINEAR))
		else:
			AudioServer.set_bus_mute(_master_bus_index, false)
			AudioServer.set_bus_volume_db(_master_bus_index, linear_to_db(max(float(safe_percent) / 100.0, MIN_AUDIBLE_LINEAR)))
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("set_master_volume_percent"):
		save_manager.call("set_master_volume_percent", safe_percent)

func get_fullscreen_enabled() -> bool:
	return DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN

func set_fullscreen_enabled(is_enabled: bool) -> void:
	var window_mode: DisplayServer.WindowMode = DisplayServer.WINDOW_MODE_FULLSCREEN if is_enabled else DisplayServer.WINDOW_MODE_WINDOWED
	DisplayServer.window_set_mode(window_mode)
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("set_fullscreen_enabled"):
		save_manager.call("set_fullscreen_enabled", is_enabled)

func _get_save_manager() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return null
	var scene_tree: SceneTree = main_loop as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root.get_node_or_null("SaveManager")
