extends Node

const SETTINGS_PATH: String = "user://settings.cfg"
const SECTION_META: String = "meta"
const SECTION_GAMEPLAY: String = "gameplay"
const SECTION_VIDEO: String = "video"
const SECTION_AUDIO: String = "audio"
const SECTION_PROGRESS: String = "progress"
const SECTION_UPGRADES: String = "upgrades"
const KEY_VERSION: String = "version"
const KEY_SELECTED_DIFFICULTY: String = "selected_difficulty"
const KEY_SELECTED_CHARACTER: String = "selected_character"
const KEY_FULLSCREEN: String = "fullscreen"
const KEY_MASTER_VOLUME_PERCENT: String = "master_volume_percent"
const KEY_TOTAL_SCRAP: String = "total_scrap"
const CURRENT_VERSION: int = 1

var _settings: ConfigFile = ConfigFile.new()
var _loaded: bool = false

func _ready() -> void:
	load_settings()

func load_settings() -> void:
	_settings = ConfigFile.new()
	var error: Error = _settings.load(SETTINGS_PATH)
	if error != OK and error != ERR_FILE_NOT_FOUND:
		push_error("[SaveManager] Failed to load settings: %s" % error_string(error))
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

func get_selected_character(default_value: String = "") -> String:
	_ensure_loaded()
	return String(_settings.get_value(SECTION_GAMEPLAY, KEY_SELECTED_CHARACTER, default_value))

func set_selected_character(character_id: String) -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_GAMEPLAY, KEY_SELECTED_CHARACTER, character_id)
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

func get_total_scrap(default_value: int = 0) -> int:
	_ensure_loaded()
	return int(_settings.get_value(SECTION_PROGRESS, KEY_TOTAL_SCRAP, default_value))

func set_total_scrap(amount: int) -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_PROGRESS, KEY_TOTAL_SCRAP, max(amount, 0))
	save_settings()

func add_total_scrap(amount: int) -> int:
	var next_total: int = get_total_scrap() + max(amount, 0)
	set_total_scrap(next_total)
	return next_total

func get_upgrade_level(upgrade_id: String, default_value: int = 0) -> int:
	_ensure_loaded()
	return int(_settings.get_value(SECTION_UPGRADES, upgrade_id, default_value))

func set_upgrade_level(upgrade_id: String, level: int) -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_UPGRADES, upgrade_id, max(level, 0))
	save_settings()

func clear_progression() -> void:
	_ensure_loaded()
	if _settings.has_section(SECTION_PROGRESS):
		_settings.erase_section(SECTION_PROGRESS)
	if _settings.has_section(SECTION_UPGRADES):
		_settings.erase_section(SECTION_UPGRADES)
	save_settings()

func save_settings() -> void:
	_ensure_loaded()
	_settings.set_value(SECTION_META, KEY_VERSION, CURRENT_VERSION)
	var error: Error = _settings.save(SETTINGS_PATH)
	if error != OK:
		push_error("[SaveManager] Failed to save settings: %s" % error_string(error))

func _ensure_loaded() -> void:
	if _loaded:
		return
	load_settings()
