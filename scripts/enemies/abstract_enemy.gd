@abstract
class_name AbstractEnemy
extends CharacterBody2D

const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const HIT_FLASH_DURATION: float = 0.10
const HIT_FLASH_PULSES: float = 2.5

@export var move_speed: float = 120.0
@export var contact_damage: int = 10
@export var damage_interval: float = 0.5
@export var damage_range: float = 24.0
@export var body_spacing: float = 3.0
@export var max_health: int = 3
@export var xp_reward: int = 1
@export var scrap_reward: int = 1
@export_range(0.0, 1.0, 0.05) var hit_flash_strength: float = 0.6
@export var hit_flash_color: Color = Color(1.0, 0.48, 0.48, 1.0)
@export var xp_orb_scene: PackedScene
@export var card_pickup_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var card_drop_chance: float = 0.18

var _damage_cooldown: float = 0.0
var _current_health: int = 0
var _current_move_speed: float = -1.0
var _current_contact_damage: int = -1
var _current_max_health: int = -1
var _difficulty_speed_multiplier: float = 1.0
var _difficulty_health_multiplier: float = 1.0
var _difficulty_damage_multiplier: float = 1.0
var _mutation_profile: Dictionary = {
	"health": 1.0,
	"damage": 1.0,
	"speed": 1.0
}
var _hit_flash_time_remaining: float = 0.0

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite_target: CanvasItem = get_node_or_null("Sprite") as CanvasItem if get_node_or_null("Sprite") != null else get_node_or_null("Sprite2D") as CanvasItem

func _ready() -> void:
	add_to_group("enemy")
	_ensure_hit_flash_material()
	if _current_move_speed <= 0.0 or _current_contact_damage <= 0 or _current_max_health <= 0:
		apply_difficulty_scaling(1.0, 1.0, 1.0)
	elif _current_health <= 0:
		_current_health = _current_max_health

func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	_damage_cooldown = max(_damage_cooldown - delta, 0.0)
	var player: PlayerController = _get_target_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	var distance_sq: float = to_player.length_squared()
	var stand_off_distance: float = _get_stand_off_distance(player)
	var stand_off_sq: float = stand_off_distance * stand_off_distance
	if distance_sq > stand_off_sq:
		var direction: Vector2 = to_player / max(sqrt(distance_sq), 0.001)
		velocity = direction * _current_move_speed
	elif distance_sq > 0.0001:
		var overlap_distance: float = stand_off_distance - sqrt(distance_sq)
		var push_strength: float = min(overlap_distance * 10.0, _current_move_speed * 0.65)
		velocity = (-to_player.normalized()) * push_strength
	else:
		velocity = Vector2.ZERO
	move_and_slide()
	_try_damage(player)


func _try_damage(player: PlayerController) -> void:
	if _damage_cooldown > 0.0:
		return
	if player.global_position.distance_squared_to(global_position) <= damage_range * damage_range:
		player.take_damage(_current_contact_damage)
		_damage_cooldown = damage_interval

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	_current_health = max(_current_health - amount, 0)
	_trigger_hit_flash()
	if _current_health > 0 and AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx("enemy_hit", randf_range(0.95, 1.08), -9.0)
	if _current_health <= 0:
		_die()

func _die() -> void:
	if AudioManager != null and AudioManager.has_method("play_sfx"):
		AudioManager.play_sfx(_get_death_sfx_id(), randf_range(0.96, 1.04), -5.0)
	if GameManager != null and GameManager.has_method("add_run_scrap"):
		GameManager.call("add_run_scrap", scrap_reward)
	if xp_orb_scene != null:
		var orb_node: Node = _spawn_pooled_node(xp_orb_scene, get_tree().current_scene)
		if orb_node is Node2D:
			var orb: Node2D = orb_node as Node2D
			if orb.get_parent() == null:
				get_tree().current_scene.add_child(orb)
			orb.global_position = global_position
			if orb.has_method("set_xp_amount"):
				orb.call("set_xp_amount", xp_reward)
	if card_pickup_scene != null and randf() <= card_drop_chance:
		var card_node: Node = _spawn_pooled_node(card_pickup_scene, get_tree().current_scene)
		if card_node is Node2D:
			var pickup: Node2D = card_node as Node2D
			if pickup.get_parent() == null:
				get_tree().current_scene.add_child(pickup)
			pickup.global_position = global_position + Vector2(12.0, -8.0)
			if pickup.has_method("configure_card"):
				var suits: PackedStringArray = ["hearts", "diamonds", "clubs", "spades"]
				pickup.call("configure_card", suits[randi_range(0, suits.size() - 1)], randi_range(1, 13))
	_release_to_pool()

func on_spawned_from_pool() -> void:
	_damage_cooldown = 0.0
	velocity = Vector2.ZERO
	_mutation_profile = {
		"health": 1.0,
		"damage": 1.0,
		"speed": 1.0
	}
	_difficulty_speed_multiplier = 1.0
	_difficulty_health_multiplier = 1.0
	_difficulty_damage_multiplier = 1.0
	visible = true
	set_physics_process(true)
	_hit_flash_time_remaining = 0.0
	_set_hit_flash_amount(0.0)
	if _collision_shape != null:
		_collision_shape.disabled = false
	if not is_in_group("enemy"):
		add_to_group("enemy")
	_refresh_scaled_stats(true)

func on_released_to_pool() -> void:
	_damage_cooldown = 0.0
	velocity = Vector2.ZERO
	visible = false
	set_physics_process(false)
	_hit_flash_time_remaining = 0.0
	_set_hit_flash_amount(0.0)
	if _collision_shape != null:
		_collision_shape.disabled = true
	if is_in_group("enemy"):
		remove_from_group("enemy")


func apply_difficulty_scaling(speed_multiplier: float, health_multiplier: float, damage_multiplier: float) -> void:
	_difficulty_speed_multiplier = speed_multiplier
	_difficulty_health_multiplier = health_multiplier
	_difficulty_damage_multiplier = damage_multiplier
	_refresh_scaled_stats(_current_max_health <= 0)

func apply_mutation_profile(profile: Dictionary) -> void:
	_mutation_profile = profile.duplicate(true)
	_refresh_scaled_stats(_current_max_health <= 0)

func _refresh_scaled_stats(reset_health: bool) -> void:
	var health_ratio: float = 1.0
	if _current_max_health > 0:
		health_ratio = clamp(float(_current_health) / float(_current_max_health), 0.0, 1.0)
	var speed_multiplier: float = float(_mutation_profile.get("speed", 1.0))
	var damage_multiplier: float = float(_mutation_profile.get("damage", 1.0))
	var health_multiplier: float = float(_mutation_profile.get("health", 1.0))
	_current_move_speed = max(move_speed * _difficulty_speed_multiplier * speed_multiplier, 1.0)
	_current_contact_damage = max(int(round(float(contact_damage) * _difficulty_damage_multiplier * damage_multiplier)), 1)
	_current_max_health = max(int(round(float(max_health) * _difficulty_health_multiplier * health_multiplier)), 1)
	if reset_health:
		_current_health = _current_max_health
	else:
		_current_health = max(int(round(float(_current_max_health) * health_ratio)), 1)

func get_collision_radius() -> float:
	if _collision_shape == null:
		return 8.0
	var circle: CircleShape2D = _collision_shape.shape as CircleShape2D
	if circle != null:
		return circle.radius
	return 8.0

func _get_stand_off_distance(player: PlayerController) -> float:
	var player_radius: float = 12.0
	if player != null and player.has_method("get_collision_radius"):
		player_radius = float(player.call("get_collision_radius"))
	return max(player_radius + get_collision_radius() + body_spacing, damage_range * 0.72)

func _spawn_pooled_node(scene: PackedScene, parent: Node) -> Node:
	var pool_manager: Node = get_tree().get_first_node_in_group("pool_manager")
	if pool_manager != null and pool_manager.has_method("spawn"):
		return pool_manager.call("spawn", scene, parent) as Node
	return scene.instantiate()

func _release_to_pool() -> void:
	var pool_manager: Node = get_tree().get_first_node_in_group("pool_manager")
	if pool_manager != null and pool_manager.has_method("release"):
		pool_manager.call_deferred("release", self)
		return
	call_deferred("queue_free")


@abstract func _get_target_player() -> PlayerController

func _get_death_sfx_id() -> String:
	return "enemy_die"

func _ensure_hit_flash_material() -> void:
	if _sprite_target == null:
		return
	var shader_material: ShaderMaterial = _sprite_target.material as ShaderMaterial
	if shader_material == null:
		shader_material = ShaderMaterial.new()
		shader_material.shader = HIT_FLASH_SHADER
		_sprite_target.material = shader_material
	elif shader_material.shader == null:
		shader_material.shader = HIT_FLASH_SHADER
	shader_material.set_shader_parameter("flash_amount", 0.0)
	shader_material.set_shader_parameter("flash_color", hit_flash_color)

func _trigger_hit_flash() -> void:
	_hit_flash_time_remaining = HIT_FLASH_DURATION
	_set_hit_flash_amount(hit_flash_strength)

func _update_hit_flash(delta: float) -> void:
	if _hit_flash_time_remaining <= 0.0:
		return
	_hit_flash_time_remaining = max(_hit_flash_time_remaining - delta, 0.0)
	var normalized_remaining: float = _hit_flash_time_remaining / HIT_FLASH_DURATION
	var progress: float = 1.0 - normalized_remaining
	var pulse_wave: float = absf(sin(progress * PI * HIT_FLASH_PULSES))
	var pulse_amount: float = 0.28 + pulse_wave * 0.72
	_set_hit_flash_amount(normalized_remaining * pulse_amount * hit_flash_strength)

func _set_hit_flash_amount(amount: float) -> void:
	if _sprite_target == null:
		return
	var shader_material: ShaderMaterial = _sprite_target.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("flash_amount", clampf(amount, 0.0, 1.0))
