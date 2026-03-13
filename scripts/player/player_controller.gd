class_name PlayerController
extends CharacterBody2D

signal health_changed(hp: int)
signal died
signal experience_changed(current_xp: int, required_xp: int, level: int)
signal level_up_requested(choices: Array)
signal hand_updated(state: Dictionary)
signal hand_locked(hand_name: String, player_multiplier: float, enemy_multiplier: float)

const UPGRADE_RARITIES: Array[Dictionary] = [
	{"name": "Common", "weight": 60.0, "band_min": 0.00, "band_max": 0.24, "color": Color("c7d0d9")},
	{"name": "Uncommon", "weight": 25.0, "band_min": 0.25, "band_max": 0.49, "color": Color("73d98c")},
	{"name": "Rare", "weight": 10.0, "band_min": 0.50, "band_max": 0.72, "color": Color("56b7ff")},
	{"name": "Epic", "weight": 4.5, "band_min": 0.73, "band_max": 0.90, "color": Color("d182ff")},
	{"name": "Legendary", "weight": 0.5, "band_min": 0.91, "band_max": 1.00, "color": Color("ffcc55")}
]

@export var move_speed: float = 200.0
@export var max_health: int = 100
@export var arena_path: NodePath
@export var arena_padding: float = 8.0
@export var projectile_damage: int = 1
@export var attack_interval: float = 0.65
@export var attack_range: float = 260.0
@export var health_regen_interval: float = 10.0
@export var health_regen_rate: float = 0.0
@export_range(0.0, 0.5, 0.01) var lifesteal_ratio: float = 0.0

var current_health: int = 0
var current_experience: int = 0
var current_level: int = 1
var required_experience: int = 5
var collected_cards: int = 0
var active_hand_name: String = "No Hand"
var active_augment_bonus: float = 1.0
var pending_hand_name: String = "No Hand"
var _hand_cards: Array = []
var _pending_hand_result: PokerHandEvaluator.HandResult
var _applied_hand_history: Array[Dictionary] = []
var _player_augment_multiplier: float = 1.0
var _enemy_mutation_multiplier: float = 1.0
var _royal_flush_achieved: bool = false
var _is_dead: bool = false
var _facing: Vector2 = Vector2.DOWN
var _arena: Arena
var _pending_level_ups: int = 0
var _active_level_up_choices: Array = []
var _regen_timer: float = 0.0

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D

func _ready() -> void:
	add_to_group("player")
	_arena = get_node_or_null(arena_path) as Arena
	if _arena == null:
		_arena = get_tree().get_first_node_in_group("arena") as Arena
	current_health = max_health
	health_changed.emit(current_health)
	experience_changed.emit(current_experience, required_experience, current_level)
	_emit_hand_updated()
	_regen_timer = health_regen_interval
	_update_animation()
	_clamp_to_arena()


func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * move_speed
	move_and_slide()
	_clamp_to_arena()
	_update_animation()
	_tick_regen(delta)


func take_damage(amount: int) -> void:
	if _is_dead:
		return
	var next_health: int = max(current_health - amount, 0)
	current_health = next_health
	health_changed.emit(current_health)
	if current_health <= 0:
		_die()


func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	current_experience += amount
	while current_experience >= required_experience:
		current_experience -= required_experience
		current_level += 1
		required_experience = int(round(float(required_experience) * 1.35)) + 2
		_pending_level_ups += 1
	experience_changed.emit(current_experience, required_experience, current_level)
	_emit_level_up_if_ready()


func apply_level_up_choice(stat_id: String) -> void:
	var choice: Dictionary = {}
	for entry in _active_level_up_choices:
		if String(entry.get("id", "")) == stat_id:
			choice = entry
			break
	if choice.is_empty():
		return
	match stat_id:
		"max_health":
			var gain: int = int(round(float(choice.get("value", 0.0))))
			max_health += gain
			current_health = min(current_health + gain, max_health)
			health_changed.emit(current_health)
		"move_speed":
			move_speed += float(choice.get("value", 0.0))
		"projectile_damage":
			projectile_damage += int(round(float(choice.get("value", 0.0))))
		"attack_speed":
			attack_interval = max(attack_interval * (1.0 - float(choice.get("value", 0.0))), 0.18)
		"range":
			attack_range += float(choice.get("value", 0.0))
		"regen":
			health_regen_rate += float(choice.get("value", 0.0))
		"lifesteal":
			lifesteal_ratio = min(lifesteal_ratio + float(choice.get("value", 0.0)), 0.5)
		_:
			return
	_active_level_up_choices.clear()
	_emit_level_up_if_ready()


func is_dead() -> bool:
	return _is_dead

func add_card_to_hand(suit: String, value: int) -> void:
	if _hand_cards.size() >= 5:
		return
	var card: PokerHandEvaluator.Card = PokerHandEvaluator.Card.new(suit, value)
	_hand_cards.append(card)
	collected_cards = _hand_cards.size()
	if collected_cards == 5:
		_pending_hand_result = PokerHandEvaluator.evaluate_hand(_hand_cards)
		pending_hand_name = _pending_hand_result.name
	else:
		_pending_hand_result = null
		pending_hand_name = "Drawing..."
	_emit_hand_updated()

func lock_current_hand() -> void:
	if _pending_hand_result == null or _hand_cards.size() < 5:
		return
	active_hand_name = _pending_hand_result.name
	_player_augment_multiplier *= _pending_hand_result.augment_multiplier
	_enemy_mutation_multiplier *= _pending_hand_result.mutation_multiplier
	active_augment_bonus = _player_augment_multiplier
	var history_entry: Dictionary = {
		"name": _pending_hand_result.name,
		"player_multiplier": _pending_hand_result.augment_multiplier,
		"enemy_multiplier": _pending_hand_result.mutation_multiplier
	}
	_applied_hand_history.append(history_entry)
	if _pending_hand_result.is_royal_flush:
		_royal_flush_achieved = true
	CustomLogger.card("Locked %s x%.2f / enemy x%.2f" % [
		_pending_hand_result.name,
		_pending_hand_result.augment_multiplier,
		_pending_hand_result.mutation_multiplier
	])
	_hand_cards.clear()
	collected_cards = 0
	pending_hand_name = "No Hand"
	_pending_hand_result = null
	_emit_hand_updated()
	hand_locked.emit(active_hand_name, _player_augment_multiplier, _enemy_mutation_multiplier)

func get_effective_projectile_damage() -> int:
	return max(int(round(float(projectile_damage) * _player_augment_multiplier)), 1)

func apply_lifesteal(damage_dealt: int) -> void:
	if lifesteal_ratio <= 0.0 or damage_dealt <= 0 or current_health >= max_health:
		return
	var heal_amount: int = max(int(ceil(float(damage_dealt) * lifesteal_ratio)), 1)
	heal(heal_amount)

func heal(amount: int) -> void:
	if amount <= 0 or _is_dead:
		return
	current_health = min(current_health + amount, max_health)
	health_changed.emit(current_health)


func get_level_up_summary() -> Dictionary:
	var regen_per_tick: float = health_regen_rate * health_regen_interval
	return {
		"stats_text": "HP %d / %d\nMove %.0f\nDamage %d\nAtk %.2fs\nRange %.0f\nRegen %.1f / s (%.1f / 10s)\nLifesteal %.0f%%" % [
			current_health,
			max_health,
			move_speed,
			projectile_damage,
			attack_interval,
			attack_range,
			health_regen_rate,
			regen_per_tick,
			lifesteal_ratio * 100.0
		],
		"hand_text": "Cards %d / 5\nPending %s\nPlayer x%.2f\nEnemy x%.2f" % [
			collected_cards,
			pending_hand_name,
			_player_augment_multiplier,
			_enemy_mutation_multiplier
		]
	}

func get_enemy_mutation_multiplier() -> float:
	return _enemy_mutation_multiplier

func has_royal_flush_run() -> bool:
	return _royal_flush_achieved

func debug_force_royal_flush() -> void:
	active_hand_name = "Royal Flush"
	_player_augment_multiplier = max(_player_augment_multiplier, 2.0)
	_enemy_mutation_multiplier = max(_enemy_mutation_multiplier, 1.25)
	active_augment_bonus = _player_augment_multiplier
	_royal_flush_achieved = true
	_applied_hand_history.append({
		"name": "Royal Flush",
		"player_multiplier": 2.0,
		"enemy_multiplier": 1.25
	})
	_emit_hand_updated()
	hand_locked.emit(active_hand_name, _player_augment_multiplier, _enemy_mutation_multiplier)


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	died.emit()
	velocity = Vector2.ZERO
	_update_animation()


func _update_animation() -> void:
	if _anim == null:
		return
	var is_moving: bool = velocity.length_squared() > 0.0
	if is_moving:
		_facing = velocity.normalized()
	var use_north: bool = _facing.y < 0.0 and abs(_facing.y) >= abs(_facing.x)
	if is_moving:
		if use_north:
			_play_animation("walk_north")
		else:
			_play_animation("walk_south")
	else:
		if use_north:
			_play_animation("idle_north")
		else:
			_play_animation("idle_south")
	_anim.flip_h = _facing.x < 0.0


func _play_animation(animation_name: String) -> void:
	if _anim == null:
		return
	var frames: SpriteFrames = _anim.sprite_frames
	if frames == null:
		return
	if frames.has_animation(animation_name):
		if _anim.animation != animation_name:
			_anim.animation = animation_name
		if not _anim.is_playing():
			_anim.play()
	else:
		if frames.has_animation("walk_south"):
			if _anim.animation != "walk_south":
				_anim.animation = "walk_south"
			if not _anim.is_playing():
				_anim.play()


func _clamp_to_arena() -> void:
	if _arena == null or not is_instance_valid(_arena):
		_arena = get_tree().get_first_node_in_group("arena") as Arena
		if _arena == null:
			return
	var margin: float = _get_collision_radius() + arena_padding
	var clamped_position: Vector2 = _arena.clamp_world_position(global_position, margin)
	if clamped_position.distance_squared_to(global_position) <= 0.01:
		return
	var normal: Vector2 = (clamped_position - _arena.global_position).normalized()
	global_position = clamped_position
	if normal != Vector2.ZERO and velocity.dot(normal) > 0.0:
		velocity = velocity.slide(normal)


func _get_collision_radius() -> float:
	if _collision_shape == null:
		return 12.0
	var circle: CircleShape2D = _collision_shape.shape as CircleShape2D
	if circle != null:
		return circle.radius
	return 12.0


func _emit_level_up_if_ready() -> void:
	if _pending_level_ups <= 0 or not _active_level_up_choices.is_empty():
		return
	_pending_level_ups -= 1
	_active_level_up_choices = _build_level_up_choices()
	level_up_requested.emit(_active_level_up_choices)

func _emit_hand_updated() -> void:
	hand_updated.emit(_build_hand_state())

func _build_hand_state() -> Dictionary:
	var history_lines: Array[String] = []
	for entry in _applied_hand_history.slice(max(_applied_hand_history.size() - 3, 0), _applied_hand_history.size()):
		history_lines.append("%s  P x%.2f / E x%.2f" % [
			String(entry.get("name", "")),
			float(entry.get("player_multiplier", 1.0)),
			float(entry.get("enemy_multiplier", 1.0))
		])
	var pending_multiplier: float = 1.0
	var pending_enemy_multiplier: float = 1.0
	if _pending_hand_result != null:
		pending_multiplier = _pending_hand_result.augment_multiplier
		pending_enemy_multiplier = _pending_hand_result.mutation_multiplier
	return {
		"card_count": collected_cards,
		"cards": _build_card_slot_labels(),
		"pending_hand_name": pending_hand_name,
		"pending_player_multiplier": pending_multiplier,
		"pending_enemy_multiplier": pending_enemy_multiplier,
		"active_hand_name": active_hand_name,
		"active_augment_bonus": _player_augment_multiplier,
		"enemy_mutation_multiplier": _enemy_mutation_multiplier,
		"can_lock": _pending_hand_result != null and _hand_cards.size() == 5,
		"history_text": "\n".join(history_lines),
		"royal_flush_achieved": _royal_flush_achieved
	}

func _build_card_slot_labels() -> Array[String]:
	var labels: Array[String] = []
	for card in _hand_cards:
		if card is PokerHandEvaluator.Card:
			labels.append(_card_to_short_text(card as PokerHandEvaluator.Card))
	while labels.size() < 5:
		labels.append("--")
	return labels

func _card_to_short_text(card: PokerHandEvaluator.Card) -> String:
	var suit_icon: String = "?"
	match card.suit:
		"spades":
			suit_icon = "S"
		"clubs":
			suit_icon = "C"
		"hearts":
			suit_icon = "H"
		"diamonds":
			suit_icon = "D"
	return "%s%s" % [card.get_display_value(), suit_icon]


func _build_level_up_choices() -> Array:
	var pool: Array[Dictionary] = [
		{"id": "max_health", "title": "Bulk Up", "weight": 1.0},
		{"id": "move_speed", "title": "Overclock", "weight": 1.0},
		{"id": "projectile_damage", "title": "Hot Hands", "weight": 0.85},
		{"id": "attack_speed", "title": "Loaded Deck", "weight": 0.9},
		{"id": "range", "title": "Long Reach", "weight": 0.8},
		{"id": "regen", "title": "Nanoforge", "weight": 0.28},
		{"id": "lifesteal", "title": "Blood Circuit", "weight": 0.22}
	]
	var choices: Array = []
	while choices.size() < 3 and not pool.is_empty():
		var total_weight: float = 0.0
		for entry in pool:
			total_weight += float(entry.get("weight", 1.0))
		var roll: float = randf() * total_weight
		var accumulated: float = 0.0
		for index in range(pool.size()):
			var entry: Dictionary = pool[index]
			accumulated += float(entry.get("weight", 1.0))
			if roll <= accumulated:
				choices.append(_materialize_upgrade(entry))
				pool.remove_at(index)
				break
	return choices


func _tick_regen(delta: float) -> void:
	if health_regen_rate <= 0.0 or health_regen_interval <= 0.0:
		return
	_regen_timer -= delta
	if _regen_timer > 0.0:
		return
	_regen_timer = health_regen_interval
	if current_health < max_health:
		var heal_amount: int = max(int(round(health_regen_rate * health_regen_interval)), 1)
		heal(heal_amount)


func _materialize_upgrade(base_entry: Dictionary) -> Dictionary:
	var rarity: Dictionary = _roll_rarity()
	var entry: Dictionary = base_entry.duplicate(true)
	entry["rarity"] = rarity["name"]
	entry["rarity_color"] = rarity["color"]
	match String(entry.get("id", "")):
		"max_health":
			var value: int = int(round(_roll_value(rarity, 12.0, 80.0)))
			entry["value"] = value
			entry["description"] = "+%d max health and heal %d" % [value, value]
		"move_speed":
			var value: float = _roll_value(rarity, 10.0, 52.0)
			entry["value"] = value
			entry["description"] = "+%.0f move speed" % value
		"projectile_damage":
			var value: int = max(int(round(_roll_value(rarity, 1.0, 3.4))), 1)
			entry["value"] = value
			entry["description"] = "+%d projectile damage" % value
		"attack_speed":
			var value: float = _roll_value(rarity, 0.04, 0.22)
			entry["value"] = value
			entry["description"] = "+%.0f%% attack speed" % (value * 100.0)
		"range":
			var value: float = _roll_value(rarity, 12.0, 72.0)
			entry["value"] = value
			entry["description"] = "+%.0f attack range" % value
		"regen":
			var value: float = _roll_value(rarity, 0.1, 1.0)
			entry["value"] = snappedf(value, 0.1)
			entry["description"] = "+%.1f HP/s regen" % entry["value"]
		"lifesteal":
			var value: float = _roll_value(rarity, 0.01, 0.08)
			entry["value"] = snappedf(value, 0.01)
			entry["description"] = "+%.0f%% lifesteal" % (entry["value"] * 100.0)
	return entry


func _roll_rarity() -> Dictionary:
	var total_weight: float = 0.0
	for rarity in UPGRADE_RARITIES:
		total_weight += float(rarity.get("weight", 1.0))
	var roll: float = randf() * total_weight
	var accumulated: float = 0.0
	for rarity in UPGRADE_RARITIES:
		accumulated += float(rarity.get("weight", 1.0))
		if roll <= accumulated:
			return rarity
	return UPGRADE_RARITIES[0]


func _roll_value(rarity: Dictionary, min_value: float, max_value: float) -> float:
	var t: float = randf_range(float(rarity["band_min"]), float(rarity["band_max"]))
	return lerpf(min_value, max_value, t)
