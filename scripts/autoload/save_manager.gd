extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION_META: String = "meta"
const SECTION_GAMEPLAY: String = "gameplay"
const SECTION_VIDEO: String = "video"
const SECTION_AUDIO: String = "audio"
const KEY_VERSION: String = "version"
const KEY_SELECTED_DIFFICULTY: String = "selected_difficulty"
const KEY_FULLSCREEN: String = "fullscreen"
const KEY_MASTER_VOLUME_PERCENT: String = "master_volume_percent"
const CURRENT_VERSION: int = 1

var _settings: ConfigFile = ConfigFile.new()
var _loaded: bool = false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	_settings = ConfigFile.new()
	var error: Error = _settings.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		var logger: Node = _get_logger()
		if logger != null and logger.has_method("error"):
			logger.call("error", "Failed to load settings: %s" % error_string(error), "SaveManager")
	if not _settings.has_section_key(SECTION_META, KEY_VERSION):
		_settings.set_value(SECTION_META, KEY_VERSION, CURRENT_VERSION)
	_loaded = true

func get_selected_difficulty(default_value: String = "hard") -> String:
	_ensure_loaded()
	return String(_settings.get_value(SECTION_GAMEPLAY, KEY_SELECTED_DIFFICULTY, default_value))

func set_selected_difficulty(difficulty_id: String) -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_GAMEPLAY, KEY_SELECTED_DIFFICULTY, difficulty_id)
	save_settings()

func get_fullscreen_enabled(default_value: bool = false) -> bool:
	_ensure_loaded()
	return bool(_settings.get_value(SECTION_VIDEO, KEY_FULLSCREEN, default_value))

func set_fullscreen_enabled(is_enabled: bool) -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_VIDEO, KEY_FULLSCREEN, is_enabled)
	save_settings()

func get_master_volume_percent(default_value: int = 100) -> int:
	_ensure_loaded()
	return int(_settings.get_value(SECTION_AUDIO, KEY_MASTER_VOLUME_PERCENT, default_value))

func set_master_volume_percent(percent: int) -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_AUDIO, KEY_MASTER_VOLUME_PERCENT, clampi(percent, 0, 100))
	save_settings()

func save_settings() -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_META, KEY_VERSION, CURRENT_VERSION)
	var error: Error = _settings.save(SETTINGS_PATH)
	if error != OK:
		var logger: Node = _get_logger()
		if logger != null and logger.has_method("error"):
			logger.call("error", "Failed to save settings: %s" % error_string(error), "SaveManager")

func _ensure_loaded() -> void:
	if _loaded:
		return
	load_settings()

func _get_logger() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return null
	var scene_tree: SceneTree = main_loop as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root.get_node_or_null("CustomLogger")
