extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION_META: String = "meta"
const SECTION_GAMEPLAY: String = "gameplay"
const KEY_VERSION: String = "version"
const KEY_SELECTED_DIFFICULTY: String = "selected_difficulty"
const CURRENT_VERSION: int = 1

var _settings: ConfigFile = ConfigFile.new()
var _loaded: bool = false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	_settings = ConfigFile.new()
	var error: Error = _settings.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		if CustomLogger != null:
			CustomLogger.error("Failed to load settings: %s" % error_string(error), "SaveManager")
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

func save_settings() -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_META, KEY_VERSION, CURRENT_VERSION)
	var error: Error = _settings.save(SETTINGS_PATH)
	if error != OK and CustomLogger != null:
		CustomLogger.error("Failed to save settings: %s" % error_string(error), "SaveManager")

func _ensure_loaded() -> void:
	if _loaded:
		return
	load_settings()
