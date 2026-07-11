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
signal aim_mode_changed(is_manual: bool)

## Hard ceilings for the multiplicative augment profile; picks past the cap
## are removed from the level-up pool.
const AUGMENT_CAPS: Dictionary = {
	"damage": 4.0,
	"move_speed": 2.0,
	"attack_speed": 2.8,
	"range": 2.0,
	"max_health": 3.5
}
const LIFESTEAL_CAP: float = 0.3
const REGEN_CAP: float = 3.5
const MELEE_REACH_CAP: float = 150.0
const LUCK_CAP: int = 3
## Each repeat pick of the same stat is worth this fraction of the last one.
const REPEAT_PICK_FALLOFF: float = 0.85

enum AimMode {
	AUTO,
	MANUAL
}

@export var move_speed: float = 200.0
@export var max_health: int = 100
@export var arena_path: NodePath
@export var floor_generator_path: NodePath
@export var arena_padding: float = 8.0
## How far past the playable rect the camera may scroll: shows a strip of
## shoreline water at the edge. MUST stay well under the border ring
## thickness (2 chunks = 4096 px) so unloaded void is never visible.
@export var camera_shore_peek: float = 192.0
@export var projectile_damage: int = 1
@export var attack_interval: float = 0.65
@export var attack_range: float = 234.0
@export var health_regen_interval: float = 10.0
@export var health_regen_rate: float = 0.0
@export_range(0.0, 0.5, 0.01) var lifesteal_ratio: float = 0.0
@export var min_effective_move_speed: float = 80.0
@export var max_effective_move_speed: float = 360.0
@export_range(0.1, 1.0, 0.05) var upper_terrain_move_multiplier: float = 0.72
@export var aim_mode: int = AimMode.AUTO
@export var manual_aim_deadzone: float = 10.0
@export_range(0.5, 4.0, 0.05) var camera_zoom_scale: float = 1.4
@export var dash_speed_multiplier: float = 3.2
@export var dash_duration: float = 0.16
@export var dash_cooldown: float = 2.6
@export var discard_cooldown: float = 6.0

var current_health: int = 0
var current_experience: int = 0
var current_level: int = 1
var required_experience: int = 6
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
var _is_dead: bool = false
var _facing: Vector2 = Vector2.DOWN
var _combat_profile: CombatProfile = CombatProfile.new()
var _arena: Arena
var _floor_generator: FloorGenerator
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
@onready var _aim_crosshair: AimCrosshair = $AimCrosshair
@onready var _hand: HandManager = $HandManager

var _shake_strength: float = 0.0
var _shake_time_remaining: float = 0.0
var _shake_duration: float = 0.0
var _hit_flash_time_remaining: float = 0.0
var _attack_time_remaining: float = 0.0
var _stat_pick_counts: Dictionary = {}
var _dash_time_remaining: float = 0.0
var _dash_cooldown_remaining: float = 0.0
var _dash_direction: Vector2 = Vector2.RIGHT
var _dash_cooldown_multiplier: float = 1.0
var bonus_pierce: int = 0
var melee_full_circle: bool = false
## Each point rerolls upgrade rarity and keeps the best result.
var luck: int = 0

func _ready() -> void:
	add_to_group("player")
	RunContext.register_player(self)
	var character_id: String = GameManager.get_selected_character_id()
	_combat_profile = CharacterLibrary.get_combat_profile(character_id)
	_anim.sprite_frames = CharacterLibrary.load_sprite_frames(character_id)
	_arena = (get_node_or_null(arena_path) as Arena) if arena_path else RunContext.arena
	_floor_generator = (get_node_or_null(floor_generator_path) as FloorGenerator) if floor_generator_path else RunContext.floor_generator
	required_experience = _get_required_experience_for_level(current_level)
	current_health = get_effective_max_health()
	health_changed.emit(current_health)
	experience_changed.emit(current_experience, required_experience, current_level)
	_hand.discard_cooldown = discard_cooldown
	_hand.updated.connect(_emit_hand_updated)
	_hand.selection_requested.connect(_on_hand_selection_requested)
	_hand.choice_applied.connect(_on_hand_choice_applied)
	_emit_hand_updated()
	_regen_timer = health_regen_interval
	_ensure_hit_flash_material()
	_apply_camera_zoom()
	_apply_camera_limits()
	_update_animation()
	_clamp_to_arena()
	_update_aim_mode_visuals()
	aim_mode_changed.emit(is_manual_aim_enabled())


func _exit_tree() -> void:
	RunContext.unregister_player(self)

func _physics_process(delta: float) -> void:
	if _is_dead:
		return
	_attack_time_remaining = maxf(_attack_time_remaining - delta, 0.0)
	_dash_cooldown_remaining = maxf(_dash_cooldown_remaining - delta, 0.0)
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if _dash_time_remaining > 0.0:
		_dash_time_remaining = maxf(_dash_time_remaining - delta, 0.0)
		velocity = _dash_direction * get_effective_move_speed() * dash_speed_multiplier
	else:
		velocity = input_vector * get_effective_move_speed()
	move_and_slide()
	_clamp_to_arena()
	_update_animation()
	_tick_regen(delta)

func _process(delta: float) -> void:
	_update_screen_shake(delta)
	_update_hit_flash(delta)
	_update_crosshair()

func _apply_camera_zoom() -> void:
	if _camera == null:
		return
	var clamped_zoom: float = clampf(camera_zoom_scale, 0.5, 4.0)
	_camera.zoom = Vector2.ONE * clamped_zoom

## Hard camera bounds at the playable rect plus a shoreline peek strip.
## Camera2D limits account for viewport size and zoom on the engine side,
## so this is exact at any resolution or aspect ratio.
func _apply_camera_limits() -> void:
	if _camera == null or _arena == null or not is_instance_valid(_arena):
		return
	var center: Vector2 = _arena.global_position
	var extent: Vector2 = _arena.get_half_extents() + Vector2(camera_shore_peek, camera_shore_peek)
	_camera.limit_left = int(center.x - extent.x)
	_camera.limit_right = int(center.x + extent.x)
	_camera.limit_top = int(center.y - extent.y)
	_camera.limit_bottom = int(center.y + extent.y)
	_camera.limit_smoothed = true

func _unhandled_input(event: InputEvent) -> void:
	if _is_dead or get_tree().paused:
		return
	if event.is_action_pressed("lock_hand"):
		get_viewport().set_input_as_handled()
		lock_current_hand()
	elif event.is_action_pressed("toggle_aim_mode"):
		get_viewport().set_input_as_handled()
		toggle_aim_mode()
	elif event.is_action_pressed("dash"):
		get_viewport().set_input_as_handled()
		start_dash()
	elif event.is_action_pressed("discard_card"):
		get_viewport().set_input_as_handled()
		cycle_discard_selection()
	elif event.is_action_pressed("discard_confirm"):
		get_viewport().set_input_as_handled()
		discard_card()

func take_damage(amount: int) -> void:
	if _is_dead:
		return
	if _dash_time_remaining > 0.0:
		return
	var reduced: int = max(int(round(float(amount) * _combat_profile.damage_taken_mult)), 1)
	var next_health: int = max(current_health - reduced, 0)
	current_health = next_health
	health_changed.emit(current_health)
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
	if leveled_up:
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
	var value: float = float(choice.get("value", 0.0))
	match stat_id:
		"max_health":
			var previous_effective_max: int = get_effective_max_health()
			_multiply_augment("max_health", 1.0 + value)
			var next_effective_max: int = get_effective_max_health()
			if next_effective_max >= previous_effective_max:
				current_health = min(current_health + (next_effective_max - previous_effective_max), next_effective_max)
			else:
				current_health = min(current_health, next_effective_max)
			health_changed.emit(current_health)
		"move_speed":
			_multiply_augment("move_speed", 1.0 + value)
		"projectile_damage":
			_multiply_augment("damage", 1.0 + value)
		"attack_speed":
			_multiply_augment("attack_speed", 1.0 + value)
		"range":
			_multiply_augment("range", 1.0 + value)
		"regen":
			health_regen_rate = minf(health_regen_rate + value, REGEN_CAP)
		"lifesteal":
			lifesteal_ratio = minf(lifesteal_ratio + value, LIFESTEAL_CAP)
		"keystone_cyclone":
			melee_full_circle = true
		"keystone_ricochet":
			bonus_pierce += 2
		"keystone_adrenaline":
			_dash_cooldown_multiplier = 0.6
		"luck":
			luck = mini(luck + 1, LUCK_CAP)
		_:
			return
	_stat_pick_counts[stat_id] = int(_stat_pick_counts.get(stat_id, 0)) + 1
	_active_level_up_choices.clear()
	_emit_level_up_if_ready()
	_emit_hand_updated()


func _multiply_augment(key: String, multiplier: float) -> void:
	var next: float = float(_player_augment_profile.get(key, 1.0)) * multiplier
	_player_augment_profile[key] = minf(next, float(AUGMENT_CAPS.get(key, 100.0)))

func is_dead() -> bool:
	return _is_dead

func add_card_to_hand(suit: String, value: int) -> void:
	_hand.add_card(suit, value)

func lock_current_hand() -> void:
	_hand.lock()

func apply_hand_choice(choice_id: String) -> void:
	_hand.apply_choice(choice_id)

func can_lock_hand() -> bool:
	return _hand.can_lock()

## Blessing/curse chosen: folds the choice profiles into player/enemy stats,
## adjusts current HP for the new max, and notifies the run (spawner, stats).
func _on_hand_choice_applied(choice: Dictionary) -> void:
	var previous_effective_max: int = get_effective_max_health()
	_apply_profile_modifiers(_player_augment_profile, choice.get("player_profile", {}))
	_apply_profile_modifiers(_enemy_mutation_profile, choice.get("enemy_profile", {}))
	var next_effective_max: int = get_effective_max_health()
	if next_effective_max >= previous_effective_max:
		current_health = min(current_health + (next_effective_max - previous_effective_max), next_effective_max)
	else:
		current_health = min(current_health, next_effective_max)
	health_changed.emit(current_health)
	hand_locked.emit(_hand.active_hand_name, _player_augment_profile.duplicate(true), _enemy_mutation_profile.duplicate(true))
	AudioManager.play_sfx("hand_lock", 1.0, -2.0)
	add_screen_shake(3.0, 0.12)

func _on_hand_selection_requested(choices: Array) -> void:
	var summary: Dictionary = get_level_up_summary()
	var locked_text: String = _hand.get_locked_hand_text()
	if not locked_text.is_empty():
		summary["hand_text"] = locked_text
	hand_selection_requested.emit(choices, summary)

func get_combat_profile() -> CombatProfile:
	return _combat_profile

func get_effective_projectile_damage() -> int:
	var base_damage: int = projectile_damage + int(_meta_upgrade_bonus.get("projectile_damage", 0))
	var damage: float = float(base_damage) * float(_player_augment_profile.get("damage", 1.0))
	return max(int(round(damage * _combat_profile.damage_mult)), 1)

func get_effective_move_speed() -> float:
	var base_speed: float = (move_speed + float(_meta_upgrade_bonus.get("move_speed", 0.0))) * _combat_profile.move_speed_mult
	var effective_speed: float = base_speed * float(_player_augment_profile.get("move_speed", 1.0))
	if _is_in_upper_terrain():
		effective_speed *= upper_terrain_move_multiplier
	return clampf(
		effective_speed,
		min_effective_move_speed,
		max(max_effective_move_speed, min_effective_move_speed)
	)

func get_effective_attack_interval() -> float:
	var speed_multiplier: float = float(_player_augment_profile.get("attack_speed", 1.0))
	var base_interval: float = attack_interval * _combat_profile.interval_mult
	return max(base_interval / max(speed_multiplier, 0.01), 0.12)

func get_effective_attack_range() -> float:
	return attack_range * float(_player_augment_profile.get("range", 1.0)) * _combat_profile.range_mult

## Melee reach: range upgrades apply at sqrt strength (the swept area grows
## with reach squared) and reach is hard-capped. Arc never scales.
func get_effective_melee_range() -> float:
	var reach: float = attack_range * _combat_profile.range_mult
	reach *= sqrt(float(_player_augment_profile.get("range", 1.0)))
	return minf(reach, MELEE_REACH_CAP)

func start_dash() -> void:
	if _dash_cooldown_remaining > 0.0 or _dash_time_remaining > 0.0:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	_dash_direction = input_vector.normalized() if input_vector != Vector2.ZERO else _facing
	_dash_time_remaining = dash_duration
	_dash_cooldown_remaining = dash_cooldown * _dash_cooldown_multiplier
	AudioManager.play_sfx("shoot", 1.5, -12.0)

func get_dash_cooldown_remaining() -> float:
	return _dash_cooldown_remaining

func get_dash_cooldown_total() -> float:
	return dash_cooldown * _dash_cooldown_multiplier

## Public read API for UpgradePool (keeps the module off private fields).
func get_augment_value(key: String) -> float:
	return float(_player_augment_profile.get(key, 1.0))

func get_stat_pick_count(stat_id: String) -> int:
	return int(_stat_pick_counts.get(stat_id, 0))

func has_adrenaline_keystone() -> bool:
	return _dash_cooldown_multiplier < 1.0

func get_discard_cooldown_remaining() -> float:
	return _hand.get_discard_cooldown_remaining()

func get_discard_cooldown_total() -> float:
	return discard_cooldown

## Label of the card X currently targets (selected slot, newest by default).
func get_discard_target_label() -> String:
	return _hand.get_discard_target_label()

## X cycles which card the next discard removes.
func cycle_discard_selection() -> void:
	if _hand.cycle_discard_selection():
		AudioManager.play_sfx("card_pickup", 1.3, -14.0)

## C removes the selected card (newest when nothing is selected).
func discard_card() -> void:
	if _hand.discard_selected():
		AudioManager.play_sfx("card_pickup", 0.72, -6.0)

func is_manual_aim_enabled() -> bool:
	return aim_mode == AimMode.MANUAL

func toggle_aim_mode() -> void:
	aim_mode = AimMode.MANUAL if aim_mode == AimMode.AUTO else AimMode.AUTO
	_update_aim_mode_visuals()
	aim_mode_changed.emit(is_manual_aim_enabled())

func get_manual_aim_direction() -> Vector2:
	var aim_vector: Vector2 = get_global_mouse_position() - global_position
	if aim_vector.length_squared() <= manual_aim_deadzone * manual_aim_deadzone:
		return Vector2.ZERO
	return aim_vector.normalized()

func get_effective_max_health() -> int:
	var base_health: float = float(max_health + int(_meta_upgrade_bonus.get("max_health", 0))) * _combat_profile.max_health_mult
	return max(int(round(base_health * float(_player_augment_profile.get("max_health", 1.0)))), 1)

func apply_meta_upgrades(profile: Dictionary) -> void:
	var previous_max: int = get_effective_max_health()
	_meta_upgrade_bonus["max_health"] = int(profile.get("max_health", 0))
	_meta_upgrade_bonus["move_speed"] = float(profile.get("move_speed", 0.0))
	_meta_upgrade_bonus["projectile_damage"] = int(profile.get("projectile_damage", 0))
	health_regen_rate = minf(health_regen_rate + float(profile.get("regen", 0.0)), REGEN_CAP)
	var next_max: int = get_effective_max_health()
	if current_health > 0:
		current_health = min(current_health + max(next_max - previous_max, 0), next_max)
		health_changed.emit(current_health)
	_emit_hand_updated()

func get_enemy_mutation_profile() -> Dictionary:
	return _enemy_mutation_profile.duplicate(true)

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
		"hand_text": _hand.get_hand_text()
	}

func has_royal_flush_run() -> bool:
	return _hand.has_royal_flush()

func debug_force_royal_flush() -> void:
	_hand.force_royal_flush()

func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	AudioManager.play_sfx("player_defeat", 1.0, -1.0)
	_trigger_hit_flash()
	add_screen_shake(8.0, 0.26)
	died.emit()
	velocity = Vector2.ZERO
	_attack_time_remaining = 0.0
	_update_animation()

func add_screen_shake(strength: float, duration: float) -> void:
	if _camera == null:
		return
	_shake_strength = max(_shake_strength, strength)
	_shake_duration = max(duration, 0.01)
	_shake_time_remaining = max(_shake_time_remaining, duration)

## Faces the aim direction and plays the weapon animation once. Duration
## comes from the animation itself so edits in the SpriteFrames panel stick.
func play_attack(direction: Vector2) -> void:
	if direction != Vector2.ZERO:
		_facing = direction.normalized()
	_attack_time_remaining = 0.0
	if _anim == null or _anim.sprite_frames == null:
		return
	var attack_name: String = "attack_" + _facing_direction_name()
	var frames: SpriteFrames = _anim.sprite_frames
	if not frames.has_animation(attack_name):
		return
	var speed: float = maxf(frames.get_animation_speed(attack_name), 0.01)
	_attack_time_remaining = float(frames.get_frame_count(attack_name)) / speed
	_anim.play(attack_name)
	_anim.frame = 0

func is_attack_animation_active() -> bool:
	return _attack_time_remaining > 0.0

func _update_animation() -> void:
	if _anim == null:
		return
	if _attack_time_remaining > 0.0:
		_play_animation("attack_" + _facing_direction_name())
		return
	var is_moving: bool = velocity.length_squared() > 0.0
	if is_moving:
		_facing = velocity.normalized()
	var prefix: String = "walk_" if is_moving else "idle_"
	_play_animation(prefix + _facing_direction_name())

func _facing_direction_name() -> String:
	if absf(_facing.y) >= absf(_facing.x):
		return "north" if _facing.y < 0.0 else "south"
	return "west" if _facing.x < 0.0 else "east"

func _play_animation(animation_name: String) -> void:
	if _anim == null:
		return
	var frames: SpriteFrames = _anim.sprite_frames
	if frames == null:
		return
	if frames.has_animation(animation_name):
		if _anim.animation != animation_name:
			_anim.play(animation_name)
		elif not _anim.is_playing() and frames.get_animation_loop(animation_name):
			_anim.play()
	elif frames.has_animation("walk_south"):
		if _anim.animation != "walk_south":
			_anim.animation = "walk_south"
		if not _anim.is_playing():
			_anim.play()

func _clamp_to_arena() -> void:
	if _arena == null or not is_instance_valid(_arena):
		_arena = RunContext.arena
		if _arena == null:
			return
	var margin: float = get_collision_radius() + arena_padding
	var clamped_position: Vector2 = _arena.clamp_world_position(global_position, margin)
	if clamped_position.distance_squared_to(global_position) <= 0.01:
		return
	# Outward wall normal from the correction vector (axis-aligned on
	# edges, diagonal in corners), so sliding along the boundary works.
	var outward_normal: Vector2 = (global_position - clamped_position).normalized()
	global_position = clamped_position
	if outward_normal != Vector2.ZERO and velocity.dot(outward_normal) > 0.0:
		velocity = velocity.slide(outward_normal)

func _is_in_upper_terrain() -> bool:
	if _floor_generator == null or not is_instance_valid(_floor_generator):
		_floor_generator = RunContext.floor_generator
		if _floor_generator == null:
			return false
	return _floor_generator.is_world_position_in_upper_terrain(global_position)

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
	_active_level_up_choices = UpgradePool.build_choices(self)
	level_up_requested.emit(_active_level_up_choices)

func _emit_hand_updated() -> void:
	hand_updated.emit(_hand.get_state())

func get_hand_state() -> Dictionary:
	return _hand.get_state()

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

func _update_aim_mode_visuals() -> void:
	if _aim_crosshair != null:
		_aim_crosshair.set_active(is_manual_aim_enabled())

func _update_crosshair() -> void:
	if _aim_crosshair == null:
		return
	if not is_manual_aim_enabled() or _is_dead:
		_aim_crosshair.set_active(false)
		return
	_aim_crosshair.set_active(true)
	_aim_crosshair.set_world_position(get_global_mouse_position())

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

func _get_required_experience_for_level(level: int) -> int:
	var base_requirement: int = 5
	if level > 1:
		base_requirement += int(round(pow(float(level - 1), 1.24) * 2.6))
	return max(int(round(float(base_requirement) * 1.2)), 1)

func _apply_profile_modifiers(target: Dictionary, modifiers: Dictionary) -> void:
	for key in modifiers.keys():
		target[key] = float(target.get(key, 1.0)) * float(modifiers[key])
