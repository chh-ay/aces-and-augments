extends Node

signal difficulty_changed(difficulty_id: String, config: Dictionary)

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

var selected_difficulty_id: String = DEFAULT_DIFFICULTY

func _ready() -> void:
	var persisted_difficulty: String = selected_difficulty_id
	if SaveManager != null and SaveManager.has_method("get_selected_difficulty"):
		persisted_difficulty = String(SaveManager.call("get_selected_difficulty", selected_difficulty_id))
	selected_difficulty_id = _sanitize_difficulty_id(persisted_difficulty)

func set_selected_difficulty(difficulty_id: String) -> Dictionary:
	selected_difficulty_id = _sanitize_difficulty_id(difficulty_id)
	if SaveManager != null and SaveManager.has_method("set_selected_difficulty"):
		SaveManager.call("set_selected_difficulty", selected_difficulty_id)
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

func _sanitize_difficulty_id(difficulty_id: String) -> String:
	if DIFFICULTY_CONFIGS.has(difficulty_id):
		return difficulty_id
	return DEFAULT_DIFFICULTY
