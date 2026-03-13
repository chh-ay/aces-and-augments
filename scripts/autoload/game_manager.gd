extends Node

signal difficulty_changed(difficulty_id: String, config: Dictionary)
signal scrap_changed(total_scrap: int, run_scrap: int)
signal upgrades_changed

const DEFAULT_DIFFICULTY: String = "hard"
const DIFFICULTY_ORDER: Array[String] = ["easy", "hard", "hell"]
const DIFFICULTY_CONFIGS: Dictionary = {
	"easy": {
		"name": "Easy",
		"enemy_speed": 0.80,
		"enemy_health": 0.80,
		"enemy_damage": 0.85,
		"spawn_rate": 0.80,
		"card_drop": 0.80
	},
	"hard": {
		"name": "Hard",
		"enemy_speed": 1.00,
		"enemy_health": 1.00,
		"enemy_damage": 1.00,
		"spawn_rate": 1.00,
		"card_drop": 0.50
	},
	"hell": {
		"name": "Hell",
		"enemy_speed": 1.20,
		"enemy_health": 1.20,
		"enemy_damage": 1.15,
		"spawn_rate": 1.30,
		"card_drop": 0.25
	}
}
const META_UPGRADES: Dictionary = {
	"hull_plating": {
		"name": "Hull Plating",
		"description": "+12 max HP each rank",
		"base_cost": 10,
		"cost_step": 10,
		"max_level": 5,
		"stat": "max_health",
		"per_level": 12
	},
	"servo_motors": {
		"name": "Servo Motors",
		"description": "+10 move speed each rank",
		"base_cost": 12,
		"cost_step": 12,
		"max_level": 4,
		"stat": "move_speed",
		"per_level": 10
	},
	"hot_loader": {
		"name": "Hot Loader",
		"description": "+1 projectile damage each rank",
		"base_cost": 18,
		"cost_step": 16,
		"max_level": 3,
		"stat": "projectile_damage",
		"per_level": 1
	}
}

var selected_difficulty_id: String = DEFAULT_DIFFICULTY
var _current_run_scrap: int = 0

func _ready() -> void:
	var persisted_difficulty: String = selected_difficulty_id
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("get_selected_difficulty"):
		persisted_difficulty = String(save_manager.call("get_selected_difficulty", selected_difficulty_id))
	selected_difficulty_id = _sanitize_difficulty_id(persisted_difficulty)
	_emit_scrap_changed()

func set_selected_difficulty(difficulty_id: String) -> Dictionary:
	selected_difficulty_id = _sanitize_difficulty_id(difficulty_id)
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("set_selected_difficulty"):
		save_manager.call("set_selected_difficulty", selected_difficulty_id)
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

func begin_run() -> void:
	_current_run_scrap = 0
	_emit_scrap_changed()

func add_run_scrap(amount: int) -> void:
	if amount <= 0:
		return
	_current_run_scrap += amount
	_emit_scrap_changed()

func commit_run_scrap() -> int:
	if _current_run_scrap <= 0:
		return get_total_scrap()
	var save_manager: Node = _get_save_manager()
	var total_scrap: int = get_total_scrap()
	if save_manager != null and save_manager.has_method("add_total_scrap"):
		total_scrap = int(save_manager.call("add_total_scrap", _current_run_scrap))
	_current_run_scrap = 0
	_emit_scrap_changed()
	return total_scrap

func get_current_run_scrap() -> int:
	return _current_run_scrap

func get_total_scrap() -> int:
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("get_total_scrap"):
		return int(save_manager.call("get_total_scrap", 0))
	return 0

func get_upgrade_definitions() -> Array[Dictionary]:
	var definitions: Array[Dictionary] = []
	for upgrade_id in META_UPGRADES.keys():
		var definition: Dictionary = META_UPGRADES[upgrade_id].duplicate(true)
		definition["id"] = upgrade_id
		definitions.append(definition)
	definitions.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return String(a.get("id", "")) < String(b.get("id", "")))
	return definitions

func get_upgrade_level(upgrade_id: String) -> int:
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("get_upgrade_level"):
		return int(save_manager.call("get_upgrade_level", upgrade_id, 0))
	return 0

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
	var level: int = get_upgrade_level(upgrade_id)
	if level >= int(definition.get("max_level", 0)):
		return false
	return get_total_scrap() >= get_upgrade_cost(upgrade_id)

func purchase_upgrade(upgrade_id: String) -> bool:
	if not can_purchase_upgrade(upgrade_id):
		return false
	var save_manager: Node = _get_save_manager()
	if save_manager == null:
		return false
	var next_total: int = get_total_scrap() - get_upgrade_cost(upgrade_id)
	var next_level: int = get_upgrade_level(upgrade_id) + 1
	if save_manager.has_method("set_total_scrap"):
		save_manager.call("set_total_scrap", next_total)
	if save_manager.has_method("set_upgrade_level"):
		save_manager.call("set_upgrade_level", upgrade_id, next_level)
	_emit_scrap_changed()
	upgrades_changed.emit()
	return true

func wipe_progression() -> void:
	var save_manager: Node = _get_save_manager()
	if save_manager != null and save_manager.has_method("clear_progression"):
		save_manager.call("clear_progression")
	_current_run_scrap = 0
	_emit_scrap_changed()
	upgrades_changed.emit()

func get_player_meta_profile() -> Dictionary:
	var profile: Dictionary = {
		"max_health": 0,
		"move_speed": 0.0,
		"projectile_damage": 0
	}
	for upgrade_id in META_UPGRADES.keys():
		var definition: Dictionary = META_UPGRADES[upgrade_id]
		var stat_id: String = String(definition.get("stat", ""))
		var per_level = definition.get("per_level", 0)
		var level: int = get_upgrade_level(upgrade_id)
		profile[stat_id] = profile.get(stat_id, 0) + per_level * level
	return profile

func get_upgrade_summary(upgrade_id: String) -> Dictionary:
	var definition: Dictionary = META_UPGRADES.get(upgrade_id, {}).duplicate(true)
	if definition.is_empty():
		return {}
	var level: int = get_upgrade_level(upgrade_id)
	var max_level: int = int(definition.get("max_level", 0))
	definition["id"] = upgrade_id
	definition["level"] = level
	definition["cost"] = get_upgrade_cost(upgrade_id)
	definition["purchased"] = level >= max_level
	definition["can_purchase"] = can_purchase_upgrade(upgrade_id)
	return definition

func _sanitize_difficulty_id(difficulty_id: String) -> String:
	if DIFFICULTY_CONFIGS.has(difficulty_id):
		return difficulty_id
	return DEFAULT_DIFFICULTY

func _get_save_manager() -> Node:
	var main_loop: MainLoop = Engine.get_main_loop()
	if main_loop == null:
		return null
	var scene_tree: SceneTree = main_loop as SceneTree
	if scene_tree == null:
		return null
	return scene_tree.root.get_node_or_null("SaveManager")

func _emit_scrap_changed() -> void:
	scrap_changed.emit(get_total_scrap(), _current_run_scrap)
