extends Node
##
## Run-scoped progression authority: difficulty, run scrap, meta upgrades.
## Settings persistence delegates straight to SaveManager.
##

signal difficulty_changed(difficulty_id: String, config: Dictionary)
signal scrap_changed(total_scrap: int, run_scrap: int)
signal upgrades_changed

const DEFAULT_DIFFICULTY: String = "hard"
const DIFFICULTY_ORDER: Array[String] = ["easy", "hard", "hell"]
const DIFFICULTY_CONFIGS: Dictionary = {
	"easy": {"name": "Easy", "enemy_speed": 0.80, "enemy_health": 0.80, "enemy_damage": 0.85, "spawn_rate": 0.80, "card_drop": 1.00},
	"hard": {"name": "Hard", "enemy_speed": 1.00, "enemy_health": 1.00, "enemy_damage": 1.00, "spawn_rate": 1.00, "card_drop": 0.80},
	"hell": {"name": "Hell", "enemy_speed": 1.20, "enemy_health": 1.20, "enemy_damage": 1.15, "spawn_rate": 1.30, "card_drop": 0.50},
}
const META_UPGRADES: Dictionary = {
	"hull_plating":   {"name": "Hull Plating",   "description": "+12 max HP each rank", "base_cost": 10, "cost_step": 10, "max_level": 5, "stat": "max_health",        "per_level": 12},
	"servo_motors":   {"name": "Servo Motors",   "description": "+10 move speed each rank", "base_cost": 12, "cost_step": 12, "max_level": 4, "stat": "move_speed",        "per_level": 10},
	"hot_loader":     {"name": "Hot Loader",     "description": "+1 projectile damage each rank", "base_cost": 18, "cost_step": 16, "max_level": 3, "stat": "projectile_damage", "per_level": 1},
	"lucky_draw":     {"name": "Lucky Draw",     "description": "+5% card drop rate each rank (relative)", "base_cost": 14, "cost_step": 12, "max_level": 3, "stat": "card_drop",         "per_level": 0.05},
	"field_medic":    {"name": "Field Medic",    "description": "+0.2 HP/s regen each rank", "base_cost": 12, "cost_step": 10, "max_level": 3, "stat": "regen",             "per_level": 0.2},
}

var selected_difficulty_id: String = DEFAULT_DIFFICULTY
var selected_character_id: String = CharacterLibrary.DEFAULT_CHARACTER_ID
var _current_run_scrap: int = 0


func _ready() -> void:
	selected_difficulty_id = _sanitize_difficulty_id(SaveManager.get_selected_difficulty(selected_difficulty_id))
	selected_character_id = _sanitize_character_id(SaveManager.get_selected_character(selected_character_id))
	_emit_scrap_changed()


# -- Difficulty -----------------------------------------------------------

func set_selected_difficulty(difficulty_id: String) -> Dictionary:
	selected_difficulty_id = _sanitize_difficulty_id(difficulty_id)
	SaveManager.set_selected_difficulty(selected_difficulty_id)
	var config: Dictionary = get_selected_difficulty()
	difficulty_changed.emit(selected_difficulty_id, config)
	return config


func cycle_difficulty() -> Dictionary:
	var current_index: int = DIFFICULTY_ORDER.find(selected_difficulty_id)
	if current_index == -1:
		current_index = DIFFICULTY_ORDER.find(DEFAULT_DIFFICULTY)
	var next_index: int = wrapi(current_index + 1, 0, DIFFICULTY_ORDER.size())
	return set_selected_difficulty(DIFFICULTY_ORDER[next_index])


func get_selected_difficulty() -> Dictionary:
	return DIFFICULTY_CONFIGS.get(selected_difficulty_id, DIFFICULTY_CONFIGS[DEFAULT_DIFFICULTY]).duplicate(true)


func get_selected_difficulty_name() -> String:
	return String(get_selected_difficulty().get("name", "Hard"))


func get_difficulty_button_text() -> String:
	return "Difficulty: %s" % get_selected_difficulty_name()


# -- Character ------------------------------------------------------------

func set_selected_character(character_id: String) -> Dictionary:
	selected_character_id = _sanitize_character_id(character_id)
	SaveManager.set_selected_character(selected_character_id)
	return get_selected_character()


func cycle_character(step: int = 1) -> Dictionary:
	var current_index: int = CharacterLibrary.get_character_index(selected_character_id)
	var next_index: int = wrapi(current_index + step, 0, CharacterLibrary.CHARACTERS.size())
	return set_selected_character(String(CharacterLibrary.CHARACTERS[next_index].get("id", "")))


func get_selected_character() -> Dictionary:
	return CharacterLibrary.get_character(selected_character_id)


func get_selected_character_id() -> String:
	return selected_character_id


# -- Run scrap and stats ---------------------------------------------------

var _run_stats: Dictionary = {"kills": 0, "hands_locked": 0}


func begin_run() -> void:
	_current_run_scrap = 0
	_run_stats = {"kills": 0, "hands_locked": 0}
	_emit_scrap_changed()


func record_kill() -> void:
	_run_stats["kills"] = int(_run_stats.get("kills", 0)) + 1


func record_hand_locked() -> void:
	_run_stats["hands_locked"] = int(_run_stats.get("hands_locked", 0)) + 1


func get_run_stats() -> Dictionary:
	return _run_stats.duplicate()


func add_run_scrap(amount: int) -> void:
	if amount <= 0:
		return
	_current_run_scrap += amount
	_emit_scrap_changed()


func commit_run_scrap() -> int:
	if _current_run_scrap <= 0:
		return get_total_scrap()
	var total: int = SaveManager.add_total_scrap(_current_run_scrap)
	_current_run_scrap = 0
	_emit_scrap_changed()
	return total


## Failed or abandoned runs forfeit their scrap: nothing reaches the bank.
func discard_run_scrap() -> void:
	if _current_run_scrap <= 0:
		return
	_current_run_scrap = 0
	_emit_scrap_changed()


func get_current_run_scrap() -> int:
	return _current_run_scrap


func get_total_scrap() -> int:
	return SaveManager.get_total_scrap(0)


# -- Meta upgrades --------------------------------------------------------

func get_upgrade_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for upgrade_id in META_UPGRADES.keys():
		var definition: Dictionary = META_UPGRADES[upgrade_id].duplicate(true)
		definition["id"] = upgrade_id
		definitions.append(definition)
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return String(a.get("id", "")) < String(b.get("id", "")))
	return definitions


func get_upgrade_level(upgrade_id: String) -> int:
	return SaveManager.get_upgrade_level(upgrade_id, 0)


func get_upgrade_cost(upgrade_id: String) -> int:
	var definition: Dictionary = META_UPGRADES.get(upgrade_id, {})
	if definition.is_empty():
		return 0
	var level: int = get_upgrade_level(upgrade_id)
	return int(definition.get("base_cost", 0)) + int(definition.get("cost_step", 0)) * level


func can_purchase_upgrade(upgrade_id: String) -> bool:
	var definition: Dictionary = META_UPGRADES.get(upgrade_id, {})
	if definition.is_empty():
		return false
	if get_upgrade_level(upgrade_id) >= int(definition.get("max_level", 0)):
		return false
	return get_total_scrap() >= get_upgrade_cost(upgrade_id)


func purchase_upgrade(upgrade_id: String) -> bool:
	if not can_purchase_upgrade(upgrade_id):
		return false
	SaveManager.set_total_scrap(get_total_scrap() - get_upgrade_cost(upgrade_id))
	SaveManager.set_upgrade_level(upgrade_id, get_upgrade_level(upgrade_id) + 1)
	_emit_scrap_changed()
	upgrades_changed.emit()
	return true


func wipe_progression() -> void:
	SaveManager.clear_progression()
	_current_run_scrap = 0
	_emit_scrap_changed()
	upgrades_changed.emit()


func get_player_meta_profile() -> Dictionary:
	var profile: Dictionary = {"max_health": 0, "move_speed": 0.0, "projectile_damage": 0, "card_drop": 0.0, "regen": 0.0}
	for upgrade_id in META_UPGRADES.keys():
		var definition: Dictionary = META_UPGRADES[upgrade_id]
		var stat_id: String = String(definition.get("stat", ""))
		var per_level: Variant = definition.get("per_level", 0)
		var level: int = get_upgrade_level(upgrade_id)
		profile[stat_id] = profile.get(stat_id, 0) + per_level * level
	return profile


func get_upgrade_summary(upgrade_id: String) -> Dictionary:
	var definition: Dictionary = META_UPGRADES.get(upgrade_id, {}).duplicate(true)
	if definition.is_empty():
		return {}
	var level: int = get_upgrade_level(upgrade_id)
	definition["id"] = upgrade_id
	definition["level"] = level
	definition["cost"] = get_upgrade_cost(upgrade_id)
	definition["purchased"] = level >= int(definition.get("max_level", 0))
	definition["can_purchase"] = can_purchase_upgrade(upgrade_id)
	return definition


# -- Helpers --------------------------------------------------------------

func _sanitize_difficulty_id(difficulty_id: String) -> String:
	return difficulty_id if DIFFICULTY_CONFIGS.has(difficulty_id) else DEFAULT_DIFFICULTY


func _sanitize_character_id(character_id: String) -> String:
	return character_id if CharacterLibrary.is_valid_character_id(character_id) else CharacterLibrary.DEFAULT_CHARACTER_ID


func _emit_scrap_changed() -> void:
	scrap_changed.emit(get_total_scrap(), _current_run_scrap)
