class_name PlayerController
extends CharacterBody2D

const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const HIT_FLASH_DURATION: float = 0.10

signal health_changed(hp: int)
signal died
signal experience_changed(current_xp: int, required_xp: int, level: int)
signal level_up_requested(choices: Array)
signal hand_updated(state: Dictionary)
signal hand_selection_requested(choices: Array, summary: Dictionary)
signal hand_locked(hand_name: String, player_profile: Dictionary, enemy_profile: Dictionary)

const UPGRADE_RARITIES: Array[Dictionary] = [
	{"name": "Common", "weight": 60.0, "band_min": 0.00, "band_max": 0.24, "color": Color("c7d0d9")},
	{"name": "Uncommon", "weight": 25.0, "band_min": 0.25, "band_max": 0.49, "color": Color("73d98c")},
	{"name": "Rare", "weight": 10.0, "band_min": 0.50, "band_max": 0.72, "color": Color("56b7ff")},
	{"name": "Epic", "weight": 4.5, "band_min": 0.73, "band_max": 0.90, "color": Color("d182ff")},
	{"name": "Legendary", "weight": 0.5, "band_min": 0.91, "band_max": 1.00, "color": Color("ffcc55")}
]

const HAND_TIER_DATA: Dictionary = {
	PokerHandEvaluator.HandRank.HIGH_CARD: {"name": "Common", "color": Color("c7d0d9"), "player_scale": 0.55, "enemy_scale": 0.60},
	PokerHandEvaluator.HandRank.PAIR: {"name": "Common", "color": Color("c7d0d9"), "player_scale": 0.72, "enemy_scale": 0.76},
	PokerHandEvaluator.HandRank.TWO_PAIR: {"name": "Uncommon", "color": Color("73d98c"), "player_scale": 0.86, "enemy_scale": 0.88},
	PokerHandEvaluator.HandRank.THREE_OF_A_KIND: {"name": "Rare", "color": Color("56b7ff"), "player_scale": 1.00, "enemy_scale": 1.00},
	PokerHandEvaluator.HandRank.STRAIGHT: {"name": "Rare", "color": Color("56b7ff"), "player_scale": 1.08, "enemy_scale": 1.06},
	PokerHandEvaluator.HandRank.FLUSH: {"name": "Rare", "color": Color("56b7ff"), "player_scale": 1.08, "enemy_scale": 1.06},
	PokerHandEvaluator.HandRank.FULL_HOUSE: {"name": "Epic", "color": Color("d182ff"), "player_scale": 1.20, "enemy_scale": 1.16},
	PokerHandEvaluator.HandRank.FOUR_OF_A_KIND: {"name": "Epic", "color": Color("d182ff"), "player_scale": 1.30, "enemy_scale": 1.22},
	PokerHandEvaluator.HandRank.STRAIGHT_FLUSH: {"name": "Legendary", "color": Color("ffcc55"), "player_scale": 1.45, "enemy_scale": 1.30},
	PokerHandEvaluator.HandRank.ROYAL_FLUSH: {"name": "Mythic", "color": Color("ff8b39"), "player_scale": 1.80, "enemy_scale": 1.40}
}

const HAND_CHOICE_TEMPLATES: Array[Dictionary] = [
	{
		"id": "kill_chain",
		"title": "Kill Chain",
		"curse_name": "Thick Hide",
		"player_stats": {"damage": 0.11, "attack_speed": 0.09},
		"enemy_stats": {"health": 0.07}
	},
	{
		"id": "vector_lens",
		"title": "Vector Lens",
		"curse_name": "Pursuit Grid",
		"player_stats": {"range": 0.14, "move_speed": 0.07},
		"enemy_stats": {"speed": 0.07}
	},
	{
		"id": "fortress_stack",
		"title": "Fortress Stack",
		"curse_name": "War Engine",
		"player_stats": {"max_health": 0.15},
		"enemy_stats": {"health": 0.08, "damage": 0.05}
	},
	{
		"id": "overdrive_loop",
		"title": "Overdrive Loop",
		"curse_name": "Hot Pursuit",
		"player_stats": {"move_speed": 0.08, "attack_speed": 0.08},
		"enemy_stats": {"speed": 0.08, "damage": 0.03}
	},
	{
		"id": "breach_rounds",
		"title": "Breach Rounds",
		"curse_name": "Bulwark Swarm",
		"player_stats": {"damage": 0.08, "range": 0.10},
		"enemy_stats": {"health": 0.08, "speed": 0.04}
	}
]

const PLAYER_STAT_LABELS: Dictionary = {
	"damage": "damage",
	"move_speed": "move speed",
	"attack_speed": "atk speed",
	"range": "range",
	"max_health": "max HP"
}

const ENEMY_STAT_LABELS: Dictionary = {
	"health": "enemy HP",
	"damage": "enemy damage",
	"speed": "enemy speed"
}

@export var move_speed: float = 200.0
@export var max_health: int = 100
@export var arena_path: NodePath
@export var arena_padding: float = 8.0
@export var projectile_damage: int = 1
@export var attack_interval: float = 0.65
@export var attack_range: float = 234.0
@export var health_regen_interval: float = 10.0
@export var health_regen_rate: float = 0.0
@export_range(0.0, 0.5, 0.01) var lifesteal_ratio: float = 0.0

var current_health: int = 0
var current_experience: int = 0
var current_level: int = 1
var required_experience: int = 6
var collected_cards: int = 0
var active_hand_name: String = "No Hand"
var active_hand_tier: String = "None"
var active_blessing_title: String = "No Blessing"
var active_blessing_text: String = "No active blessing"
var active_curse_name: String = "No Curse"
var active_curse_text: String = "No enemy mutation"
var pending_hand_name: String = "No Hand"
var _hand_cards: Array = []
var _pending_hand_result: PokerHandEvaluator.HandResult
var _pending_hand_choices: Array[Dictionary] = []
var _applied_hand_history: Array[Dictionary] = []
var _player_augment_profile: Dictionary = {
	"damage": 1.0,
	"move_speed": 1.0,
	"attack_speed": 1.0,
	"range": 1.0,
	"max_health": 1.0
}
var _enemy_mutation_profile: Dictionary = {
	"health": 1.0,
	"damage": 1.0,
	"speed": 1.0
}
var _royal_flush_achieved: bool = false
var _is_dead: bool = false
var _facing: Vector2 = Vector2.DOWN
var _arena: Arena
var _pending_level_ups: int = 0
var _active_level_up_choices: Array = []
var _regen_timer: float = 0.0
var _meta_upgrade_bonus: Dictionary = {
	"max_health": 0,
	"move_speed": 0.0,
	"projectile_damage": 0
}

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _camera: Camera2D = $Camera2D
@onready var _hit_flash_target: CanvasItem = $AnimatedSprite2D

var _shake_strength: float = 0.0
var _shake_time_remaining: float = 0.0
var _shake_duration: float = 0.0
var _hit_flash_time_remaining: float = 0.0

func _ready() -> void:
	add_to_group("player")
	_arena = get_node_or_null(arena_path) as Arena
	if _arena == null:
		_arena = get_tree().get_first_node_in_group("arena") as Arena
	required_experience = _get_required_experience_for_level(current_level)
	current_health = get_effective_max_health()
	health_changed.emit(current_health)
	experience_changed.emit(current_experience, required_experience, current_level)
	_emit_hand_updated()
	_regen_timer = health_regen_interval
	_ensure_hit_flash_material()
	_update_animation()
	_clamp_to_arena()

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * get_effective_move_speed()
	move_and_slide()
	_clamp_to_arena()
	_update_animation()
	_tick_regen(delta)

func _process(delta: float) -> void:
	_update_screen_shake(delta)
	_update_hit_flash(delta)

func _unhandled_input(event: InputEvent) -> void:
	if _is_dead or get_tree().paused:
		return
	if event.is_action_pressed("lock_hand"):
		get_viewport().set_input_as_handled()
		lock_current_hand()

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	var next_health: int = max(current_health - amount, 0)
	current_health = next_health
	health_changed.emit(current_health)
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("player_hit", randf_range(0.96, 1.02), -4.0)
	_trigger_hit_flash()
	add_screen_shake(5.0, 0.14)
	if current_health <= 0:
		_die()

func add_experience(amount: int) -> void:
	if amount <= 0:
		return
	var leveled_up: bool = false
	current_experience += amount
	while current_experience >= required_experience:
		current_experience -= required_experience
		current_level += 1
		required_experience = _get_required_experience_for_level(current_level)
		_pending_level_ups += 1
		leveled_up = true
	experience_changed.emit(current_experience, required_experience, current_level)
	if leveled_up and AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("level_up", 1.0, -2.0)
	if leveled_up:
		add_screen_shake(2.6, 0.12)
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
			var previous_effective_max: int = get_effective_max_health()
			var gain: int = int(round(float(choice.get("value", 0.0))))
			max_health += gain
			var next_effective_max: int = get_effective_max_health()
			current_health = min(current_health + (next_effective_max - previous_effective_max), next_effective_max)
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
	_emit_hand_updated()

func is_dead() -> bool:
	return _is_dead

func add_card_to_hand(suit: String, value: int) -> void:
	if _hand_cards.size() >= 5 or not _pending_hand_choices.is_empty():
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
	if not can_lock_hand():
		return
	_pending_hand_choices = _build_hand_choices(_pending_hand_result)
	_emit_hand_updated()
	hand_selection_requested.emit(_pending_hand_choices, _build_hand_choice_summary())

func apply_hand_choice(choice_id: String) -> void:
	if _pending_hand_result == null:
		return
	var choice: Dictionary = {}
	for entry in _pending_hand_choices:
		if String(entry.get("id", "")) == choice_id:
			choice = entry
			break
	if choice.is_empty():
		return
	var previous_effective_max: int = get_effective_max_health()
	_apply_profile_modifiers(_player_augment_profile, choice.get("player_profile", {}))
	_apply_profile_modifiers(_enemy_mutation_profile, choice.get("enemy_profile", {}))
	active_hand_name = _pending_hand_result.name
	active_hand_tier = String(choice.get("tier_name", "Common"))
	active_blessing_title = String(choice.get("title", "Blessing"))
	active_blessing_text = String(choice.get("player_text", ""))
	active_curse_name = String(choice.get("curse_name", "Curse"))
	active_curse_text = String(choice.get("enemy_text", ""))
	var next_effective_max: int = get_effective_max_health()
	if next_effective_max >= previous_effective_max:
		current_health = min(current_health + (next_effective_max - previous_effective_max), next_effective_max)
	else:
		current_health = min(current_health, next_effective_max)
	health_changed.emit(current_health)
	_applied_hand_history.append({
		"name": _pending_hand_result.name,
		"tier": active_hand_tier,
		"title": active_blessing_title,
		"curse_name": active_curse_name
	})
	if _pending_hand_result.is_royal_flush:
		_royal_flush_achieved = true
	CustomLogger.card("Locked %s -> %s | %s" % [
		_pending_hand_result.name,
		active_blessing_text,
		active_curse_text
	])
	_hand_cards.clear()
	collected_cards = 0
	pending_hand_name = "No Hand"
	_pending_hand_result = null
	_pending_hand_choices.clear()
	_emit_hand_updated()
	hand_locked.emit(active_hand_name, _enemy_safe_duplicate(_player_augment_profile), _enemy_safe_duplicate(_enemy_mutation_profile))
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("hand_lock", 1.0, -2.0)
	add_screen_shake(3.0, 0.12)

func can_lock_hand() -> bool:
	return _pending_hand_result != null and _hand_cards.size() == 5 and _pending_hand_choices.is_empty()

func get_effective_projectile_damage() -> int:
	var base_damage: int = projectile_damage + int(_meta_upgrade_bonus.get("projectile_damage", 0))
	return max(int(round(float(base_damage) * float(_player_augment_profile.get("damage", 1.0)))), 1)

func get_effective_move_speed() -> float:
	var base_speed: float = move_speed + float(_meta_upgrade_bonus.get("move_speed", 0.0))
	return base_speed * float(_player_augment_profile.get("move_speed", 1.0))

func get_effective_attack_interval() -> float:
	var speed_multiplier: float = float(_player_augment_profile.get("attack_speed", 1.0))
	return max(attack_interval / max(speed_multiplier, 0.01), 0.18)

func get_effective_attack_range() -> float:
	return attack_range * float(_player_augment_profile.get("range", 1.0))

func get_effective_max_health() -> int:
	var base_health: int = max_health + int(_meta_upgrade_bonus.get("max_health", 0))
	return max(int(round(float(base_health) * float(_player_augment_profile.get("max_health", 1.0)))), 1)

func apply_meta_upgrades(profile: Dictionary) -> void:
	var previous_max: int = get_effective_max_health()
	_meta_upgrade_bonus["max_health"] = int(profile.get("max_health", 0))
	_meta_upgrade_bonus["move_speed"] = float(profile.get("move_speed", 0.0))
	_meta_upgrade_bonus["projectile_damage"] = int(profile.get("projectile_damage", 0))
	var next_max: int = get_effective_max_health()
	if current_health > 0:
		current_health = min(current_health + max(next_max - previous_max, 0), next_max)
		health_changed.emit(current_health)
	_emit_hand_updated()

func get_enemy_mutation_profile() -> Dictionary:
	return _enemy_safe_duplicate(_enemy_mutation_profile)

func apply_lifesteal(damage_dealt: int) -> void:
	if lifesteal_ratio <= 0.0 or damage_dealt <= 0 or current_health >= get_effective_max_health():
		return
	var heal_amount: int = max(int(ceil(float(damage_dealt) * lifesteal_ratio)), 1)
	heal(heal_amount)

func heal(amount: int) -> void:
	if amount <= 0 or _is_dead:
		return
	current_health = min(current_health + amount, get_effective_max_health())
	health_changed.emit(current_health)

func get_level_up_summary() -> Dictionary:
	var regen_per_tick: float = health_regen_rate * health_regen_interval
	var hand_label: String = active_hand_name
	if not _pending_hand_choices.is_empty():
		hand_label = "%s locked" % pending_hand_name
	return {
		"stats_text": "HP %d / %d\nMove %.0f\nDamage %d\nAtk %.2fs\nRange %.0f\nRegen %.1f / s (%.1f / 10s)\nLifesteal %.0f%%" % [
			current_health,
			get_effective_max_health(),
			get_effective_move_speed(),
			get_effective_projectile_damage(),
			get_effective_attack_interval(),
			get_effective_attack_range(),
			health_regen_rate,
			regen_per_tick,
			lifesteal_ratio * 100.0
		],
		"hand_text": "Cards %d / 5\nPending %s\nActive %s [%s]\nBlessing %s\nCurse %s" % [
			collected_cards,
			pending_hand_name,
			hand_label,
			active_hand_tier,
			active_blessing_title,
			active_curse_name
		]
	}

func has_royal_flush_run() -> bool:
	return _royal_flush_achieved

func debug_force_royal_flush() -> void:
	_pending_hand_result = PokerHandEvaluator.HandResult.new(PokerHandEvaluator.HandRank.ROYAL_FLUSH, [])
	pending_hand_name = _pending_hand_result.name
	_pending_hand_choices = _build_hand_choices(_pending_hand_result)
	if _pending_hand_choices.is_empty():
		return
	apply_hand_choice(String(_pending_hand_choices[0].get("id", "")))

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("player_defeat", 1.0, -1.0)
	_trigger_hit_flash()
	add_screen_shake(8.0, 0.26)
	died.emit()
	velocity = Vector2.ZERO
	_update_animation()

func add_screen_shake(strength: float, duration: float) -> void:
	if _camera == null:
		return
	_shake_strength = max(_shake_strength, strength)
	_shake_duration = max(duration, 0.01)
	_shake_time_remaining = max(_shake_time_remaining, duration)

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
	elif frames.has_animation("walk_south"):
		if _anim.animation != "walk_south":
			_anim.animation = "walk_south"
		if not _anim.is_playing():
			_anim.play()

func _clamp_to_arena() -> void:
	if _arena == null or not is_instance_valid(_arena):
		_arena = get_tree().get_first_node_in_group("arena") as Arena
		if _arena == null:
			return
	var margin: float = get_collision_radius() + arena_padding
	var clamped_position: Vector2 = _arena.clamp_world_position(global_position, margin)
	if clamped_position.distance_squared_to(global_position) <= 0.01:
		return
	var normal: Vector2 = (clamped_position - _arena.global_position).normalized()
	global_position = clamped_position
	if normal != Vector2.ZERO and velocity.dot(normal) > 0.0:
		velocity = velocity.slide(normal)

func get_collision_radius() -> float:
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
		history_lines.append("%s [%s]\nBlessing %s\nCurse %s" % [
			String(entry.get("name", "")),
			String(entry.get("tier", "Common")),
			String(entry.get("title", "Route")),
			String(entry.get("curse_name", "Curse"))
		])
	var pending_tier_name: String = "None"
	if _pending_hand_result != null:
		pending_tier_name = String(_get_hand_tier_data(_pending_hand_result.rank).get("name", "Common"))
	return {
		"card_count": collected_cards,
		"cards": _build_card_slot_data(),
		"pending_hand_name": pending_hand_name,
		"pending_tier_name": pending_tier_name,
		"active_hand_name": active_hand_name,
		"active_tier_name": active_hand_tier,
		"active_blessing_title": active_blessing_title,
		"active_blessing_text": active_blessing_text,
		"active_curse_name": active_curse_name,
		"active_curse_text": active_curse_text,
		"can_lock": can_lock_hand(),
		"selection_pending": not _pending_hand_choices.is_empty(),
		"history_text": "\n\n".join(history_lines),
		"royal_flush_achieved": _royal_flush_achieved
	}

func _build_card_slot_data() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card in _hand_cards:
		if card is PokerHandEvaluator.Card:
			cards.append(_card_to_display_data(card as PokerHandEvaluator.Card))
	while cards.size() < 5:
		cards.append({"empty": true})
	return cards

func _card_to_display_data(card: PokerHandEvaluator.Card) -> Dictionary:
	return {
		"empty": false,
		"value_text": card.get_display_value(),
		"suit": card.suit,
		"suit_symbol": _get_card_suit_symbol(card.suit),
		"suit_name": card.suit.capitalize(),
		"code_text": _card_to_short_text(card)
	}

func _card_to_short_text(card: PokerHandEvaluator.Card) -> String:
	return "%s%s" % [card.get_display_value(), _get_card_suit_symbol(card.suit)]

func _get_card_suit_symbol(suit: String) -> String:
	var suit_icon: String = "?"
	match suit:
		"spades":
			suit_icon = "S"
		"clubs":
			suit_icon = "C"
		"hearts":
			suit_icon = "H"
		"diamonds":
			suit_icon = "D"
	return suit_icon

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
	if current_health < get_effective_max_health():
		var heal_amount: int = max(int(round(health_regen_rate * health_regen_interval)), 1)
		heal(heal_amount)

func _update_screen_shake(delta: float) -> void:
	if _camera == null:
		return
	if _shake_time_remaining <= 0.0 or _shake_strength <= 0.0:
		if _camera.offset != Vector2.ZERO:
			_camera.offset = Vector2.ZERO
		return
	_shake_time_remaining = max(_shake_time_remaining - delta, 0.0)
	var falloff: float = _shake_time_remaining / _shake_duration
	var current_strength: float = _shake_strength * falloff
	_camera.offset = Vector2(
		randf_range(-current_strength, current_strength),
		randf_range(-current_strength, current_strength)
	)
	if _shake_time_remaining <= 0.0:
		_shake_strength = 0.0
		_camera.offset = Vector2.ZERO

func _ensure_hit_flash_material() -> void:
	if _hit_flash_target == null:
		return
	var shader_material: ShaderMaterial = _hit_flash_target.material as ShaderMaterial
	if shader_material == null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = HIT_FLASH_SHADER
		_hit_flash_target.material = shader_material
	elif shader_material.shader == null:
		shader_material.shader = HIT_FLASH_SHADER
	shader_material.set_shader_parameter("flash_amount", 0.0)

func _trigger_hit_flash() -> void:
	_hit_flash_time_remaining = HIT_FLASH_DURATION
	_set_hit_flash_amount(1.0)

func _update_hit_flash(delta: float) -> void:
	if _hit_flash_time_remaining <= 0.0:
		return
	_hit_flash_time_remaining = max(_hit_flash_time_remaining - delta, 0.0)
	var flash_amount: float = _hit_flash_time_remaining / HIT_FLASH_DURATION
	_set_hit_flash_amount(flash_amount)

func _set_hit_flash_amount(amount: float) -> void:
	if _hit_flash_target == null:
		return
	var shader_material: ShaderMaterial = _hit_flash_target.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("flash_amount", clampf(amount, 0.0, 1.0))

func _materialize_upgrade(base_entry: Dictionary) -> Dictionary:
	var rarity: Dictionary = _roll_rarity()
	var entry: Dictionary = base_entry.duplicate(true)
	entry["rarity"] = rarity["name"]
	entry["rarity_color"] = rarity["color"]
	match String(entry.get("id", "")):
		"max_health":
			var max_health_value: int = int(round(_roll_value(rarity, 12.0, 80.0)))
			entry["value"] = max_health_value
			entry["description"] = "+%d max health and heal %d" % [max_health_value, max_health_value]
		"move_speed":
			var move_speed_value: float = _roll_value(rarity, 10.0, 52.0)
			entry["value"] = move_speed_value
			entry["description"] = "+%.0f move speed" % move_speed_value
		"projectile_damage":
			var projectile_damage_value: int = max(int(round(_roll_value(rarity, 1.0, 3.4))), 1)
			entry["value"] = projectile_damage_value
			entry["description"] = "+%d projectile damage" % projectile_damage_value
		"attack_speed":
			var attack_speed_value: float = _roll_value(rarity, 0.04, 0.22)
			entry["value"] = attack_speed_value
			entry["description"] = "+%.0f%% attack speed" % (attack_speed_value * 100.0)
		"range":
			var range_value: float = _roll_value(rarity, 12.0, 72.0)
			entry["value"] = range_value
			entry["description"] = "+%.0f attack range" % range_value
		"regen":
			var regen_value: float = _roll_value(rarity, 0.1, 1.0)
			entry["value"] = snappedf(regen_value, 0.1)
			entry["description"] = "+%.1f HP/s regen" % entry["value"]
		"lifesteal":
			var lifesteal_value: float = _roll_value(rarity, 0.01, 0.08)
			entry["value"] = snappedf(lifesteal_value, 0.01)
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

func _get_required_experience_for_level(level: int) -> int:
	var base_requirement: int = 5
	if level > 1:
		base_requirement += int(round(pow(float(level - 1), 1.24) * 2.6))
	return max(int(round(float(base_requirement) * 1.2)), 1)

func _build_hand_choices(result: PokerHandEvaluator.HandResult) -> Array[Dictionary]:
	var templates: Array = HAND_CHOICE_TEMPLATES.duplicate(true)
	var choices: Array[Dictionary] = []
	while choices.size() < 3 and not templates.is_empty():
		var index: int = randi_range(0, templates.size() - 1)
		var template: Dictionary = templates[index]
		templates.remove_at(index)
		choices.append(_materialize_hand_choice(template, result))
	return choices

func _materialize_hand_choice(template: Dictionary, result: PokerHandEvaluator.HandResult) -> Dictionary:
	var tier: Dictionary = _get_hand_tier_data(result.rank)
	var choice_id: String = "%s_%d" % [template.get("id", "choice"), int(result.rank)]
	var player_profile: Dictionary = _scale_percentage_profile(
		template.get("player_stats", {}),
		float(tier.get("player_scale", 1.0))
	)
	var enemy_profile: Dictionary = _scale_percentage_profile(
		template.get("enemy_stats", {}),
		float(tier.get("enemy_scale", 1.0))
	)
	return {
		"id": choice_id,
		"title": String(template.get("title", "Route")),
		"curse_name": String(template.get("curse_name", "Curse")),
		"tier_name": String(tier.get("name", "Common")),
		"rarity": String(tier.get("name", "Common")),
		"rarity_color": tier.get("color", Color.WHITE),
		"hand_name": result.name,
		"player_profile": player_profile,
		"enemy_profile": enemy_profile,
		"player_text": _format_profile_text(player_profile, PLAYER_STAT_LABELS, "Blessing"),
		"enemy_text": _format_profile_text(enemy_profile, ENEMY_STAT_LABELS, "Curse"),
		"description": "%s\n%s" % [
			_format_profile_text(player_profile, PLAYER_STAT_LABELS, "Blessing"),
			_format_profile_text(enemy_profile, ENEMY_STAT_LABELS, "Curse")
		]
	}

func _build_hand_choice_summary() -> Dictionary:
	var summary: Dictionary = get_level_up_summary()
	if _pending_hand_result != null:
		summary["hand_text"] = "Cards %d / 5\nLocked %s [%s]\nPick one route\nNext curse applies immediately" % [
			collected_cards,
			_pending_hand_result.name,
			String(_get_hand_tier_data(_pending_hand_result.rank).get("name", "Common"))
		]
	return summary

func _get_hand_tier_data(rank: int) -> Dictionary:
	if HAND_TIER_DATA.has(rank):
		return HAND_TIER_DATA[rank]
	return HAND_TIER_DATA[PokerHandEvaluator.HandRank.HIGH_CARD]

func _scale_percentage_profile(base_profile: Dictionary, profile_scale: float) -> Dictionary:
	var scaled: Dictionary = {}
	for key in base_profile.keys():
		scaled[key] = 1.0 + float(base_profile[key]) * profile_scale
	return scaled

func _apply_profile_modifiers(target: Dictionary, modifiers: Dictionary) -> void:
	for key in modifiers.keys():
		target[key] = float(target.get(key, 1.0)) * float(modifiers[key])

func _format_profile_text(profile: Dictionary, labels: Dictionary, prefix: String) -> String:
	var parts: Array[String] = []
	for key in profile.keys():
		var label: String = String(labels.get(key, key))
		var percent: float = (float(profile[key]) - 1.0) * 100.0
		parts.append("+%d%% %s" % [int(round(percent)), label])
	return "%s %s" % [prefix, ", ".join(parts)]

func _enemy_safe_duplicate(source: Dictionary) -> Dictionary:
	return source.duplicate(true)
