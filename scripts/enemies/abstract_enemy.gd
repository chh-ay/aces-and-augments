@abstract
class_name AbstractEnemy
extends CharacterBody2D
##
## Base for chasing/contact-damage enemies. Concrete subclasses only override
## `_get_target_player()` (and optionally `_get_death_sfx_id()`). All scaling
## comes through `apply_difficulty_scaling` / `apply_mutation_profile`.
##

const HIT_FLASH_SHADER: Shader = preload("res://assets/shaders/hit_flash.gdshader")
const CARD_SUITS: Array[String] = ["hearts", "diamonds", "clubs", "spades"]

## Enemies live on their own physics layer and only collide with the world
## (walls, arena, player). Enemy-vs-enemy spacing is handled by the shared
## separation grid below — physics pair solving between hundreds of clumped
## bodies was the single biggest frame cost (~2x whole-frame physics time).
const ENEMY_COLLISION_LAYER: int = 1 << 1
const WORLD_COLLISION_MASK: int = 1 << 0

## Spatial hash for enemy-vs-enemy separation. Rebuilt at most every
## REFRESH_INTERVAL physics frames; each enemy also recomputes its push on
## that cadence (staggered by instance id) and reuses the cached vector in
## between. Separation tolerates ~50 ms of staleness, physics does not.
const SEPARATION_CELL_SIZE: float = 16.0
const SEPARATION_REFRESH_INTERVAL: int = 3
## Hard cap on candidates scanned per query: bounds worst-case cost when
## the horde is densest, which is exactly when contact pairs used to blow up.
const SEPARATION_MAX_CANDIDATES: int = 24
static var _separation_grid: Dictionary = {}
static var _separation_grid_frame: int = -1

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
@export var hit_flash_duration: float = 0.10
@export var hit_flash_pulses: float = 2.5
@export var xp_orb_scene: PackedScene
@export var card_pickup_scene: PackedScene
@export_range(0.0, 1.0, 0.01) var card_drop_chance: float = 0.18
## For side-facing sheets (art faces LEFT): mirror the sprite horizontally
## to match horizontal movement.
@export var face_velocity_x: bool = false

var _damage_cooldown: float = 0.0
var _current_health: int = 0
var _current_move_speed: float = -1.0
var _current_contact_damage: int = -1
var _current_max_health: int = -1
var _difficulty_speed_multiplier: float = 1.0
var _difficulty_health_multiplier: float = 1.0
var _difficulty_damage_multiplier: float = 1.0
var _mutation_profile: Dictionary = {"health": 1.0, "damage": 1.0, "speed": 1.0}
var _hit_flash_time_remaining: float = 0.0
var _cached_radius: float = 8.0

@onready var _collision_shape: CollisionShape2D = $CollisionShape2D
@onready var _sprite_target: CanvasItem = _resolve_sprite_target()


func _ready() -> void:
	add_to_group("enemy")
	collision_layer = ENEMY_COLLISION_LAYER
	collision_mask = WORLD_COLLISION_MASK
	_cached_radius = get_collision_radius()
	_ensure_hit_flash_material()
	if _current_max_health <= 0:
		apply_difficulty_scaling(1.0, 1.0, 1.0)
	elif _current_health <= 0:
		_current_health = _current_max_health


func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	_damage_cooldown = maxf(_damage_cooldown - delta, 0.0)
	var player: PlayerController = _get_target_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_drive_toward(player)
	_update_facing()
	move_and_slide()
	_try_damage(player)


func _update_facing() -> void:
	if not face_velocity_x or _sprite_target == null:
		return
	if absf(velocity.x) > 4.0:
		_sprite_target.set("flip_h", velocity.x > 0.0)


@abstract func _get_target_player() -> PlayerController


# -- Damage and death ------------------------------------------------------

## Runtime card-drop multiplier (difficulty + meta), set by the spawner per
## spawn; kept off the exported base chance so pooling never compounds it.
var card_drop_multiplier: float = 1.0
## Per-spawn scrap multiplier (elites); consumed at death, reset by pooling.
var scrap_reward_multiplier: float = 1.0

func take_damage(amount: int) -> void:
	if amount <= 0:
		return
	DamageNumber.spawn(get_tree().current_scene, global_position + Vector2(randf_range(-7.0, 7.0), -14.0), amount)
	_current_health = max(_current_health - amount, 0)
	_trigger_hit_flash()
	if _current_health > 0:
		AudioManager.play_sfx("enemy_hit", randf_range(0.95, 1.08), -9.0)
	else:
		_die()


## Common kills only sometimes pay scrap; elites/boss (multiplier > 1) always do.
@export_range(0.0, 1.0, 0.05) var scrap_drop_chance: float = 0.35

func _die() -> void:
	AudioManager.play_sfx(_get_death_sfx_id(), randf_range(0.96, 1.04), -5.0)
	if scrap_reward_multiplier > 1.0 or randf() <= scrap_drop_chance:
		GameManager.add_run_scrap(max(int(round(scrap_reward * scrap_reward_multiplier)), scrap_reward))
	GameManager.record_kill()
	DeathEffect.spawn(get_tree().current_scene, global_position, maxf(get_collision_radius() / 10.0, 1.0))
	_drop_xp_orb()
	_drop_card_pickup()
	PoolManager.release.call_deferred(self)


func _drop_xp_orb() -> void:
	if xp_orb_scene == null:
		return
	var orb: XpOrb = PoolManager.spawn(xp_orb_scene, get_tree().current_scene) as XpOrb
	if orb == null:
		return
	orb.global_position = global_position
	orb.set_xp_amount(xp_reward)


func _drop_card_pickup() -> void:
	if card_pickup_scene == null or randf() > clampf(card_drop_chance * card_drop_multiplier, 0.0, 1.0):
		return
	var pickup: CardPickup = PoolManager.spawn(card_pickup_scene, get_tree().current_scene) as CardPickup
	if pickup == null:
		return
	pickup.global_position = global_position + Vector2(12.0, -8.0)
	var suit: String = CARD_SUITS[randi_range(0, CARD_SUITS.size() - 1)]
	pickup.configure_card(suit, randi_range(1, 13))


func _try_damage(player: PlayerController) -> void:
	if _damage_cooldown > 0.0:
		return
	if player.global_position.distance_squared_to(global_position) <= damage_range * damage_range:
		player.take_damage(_current_contact_damage)
		_damage_cooldown = damage_interval


# -- Movement --------------------------------------------------------------

func _drive_toward(player: PlayerController) -> void:
	var to_player: Vector2 = player.global_position - global_position
	var distance_sq: float = to_player.length_squared()
	var stand_off: float = _get_stand_off_distance(player)
	var stand_off_sq: float = stand_off * stand_off
	if distance_sq > stand_off_sq:
		velocity = (to_player / sqrt(distance_sq)) * _current_move_speed
	elif distance_sq > 0.0001:
		var overlap: float = stand_off - sqrt(distance_sq)
		var push_strength: float = minf(overlap * 10.0, _current_move_speed * 0.65)
		velocity = -to_player.normalized() * push_strength
	else:
		velocity = Vector2.ZERO
	var separation: Vector2 = _get_separation_push()
	if separation != Vector2.ZERO:
		# Same overlap-to-speed gain as the stand-off push above; the cap
		# keeps chase direction dominant so packs still converge.
		velocity = (velocity + separation * 10.0).limit_length(_current_move_speed * 1.35)


var _cached_separation: Vector2 = Vector2.ZERO


static func _rebuild_separation_grid(tree: SceneTree) -> void:
	_separation_grid.clear()
	for node in tree.get_nodes_in_group("enemy"):
		var enemy: AbstractEnemy = node as AbstractEnemy
		if enemy == null:
			continue
		var cell: Vector2i = Vector2i((enemy.global_position / SEPARATION_CELL_SIZE).floor())
		if not _separation_grid.has(cell):
			_separation_grid[cell] = []
		(_separation_grid[cell] as Array).append(enemy)


## Accumulated push away from overlapping neighbors in the 3x3 cells
## around this enemy. Replaces body-vs-body physics collision 1:1.
func _get_separation_push() -> Vector2:
	var frame: int = int(Engine.get_physics_frames())
	if frame - _separation_grid_frame >= SEPARATION_REFRESH_INTERVAL:
		_separation_grid_frame = frame
		_rebuild_separation_grid(get_tree())
	if (frame + get_instance_id()) % SEPARATION_REFRESH_INTERVAL != 0:
		return _cached_separation
	var origin: Vector2i = Vector2i((global_position / SEPARATION_CELL_SIZE).floor())
	var push: Vector2 = Vector2.ZERO
	var scanned: int = 0
	for offset_y in range(-1, 2):
		for offset_x in range(-1, 2):
			var bucket: Array = _separation_grid.get(origin + Vector2i(offset_x, offset_y), []) as Array
			for other_node in bucket:
				var other: AbstractEnemy = other_node as AbstractEnemy
				if other == self or other == null:
					continue
				scanned += 1
				var away: Vector2 = global_position - other.global_position
				var distance_sq: float = away.length_squared()
				var min_distance: float = _cached_radius + other._cached_radius + body_spacing
				if distance_sq < min_distance * min_distance:
					if distance_sq < 0.01:
						# Perfectly stacked (e.g. splitter spawns): pick a side.
						away = Vector2.RIGHT.rotated(randf() * TAU)
						distance_sq = 1.0
					var distance: float = sqrt(distance_sq)
					push += (away / distance) * (min_distance - distance)
				if scanned >= SEPARATION_MAX_CANDIDATES:
					_cached_separation = push
					return push
	_cached_separation = push
	return push


# -- Pool lifecycle --------------------------------------------------------

func on_spawned_from_pool() -> void:
	_damage_cooldown = 0.0
	velocity = Vector2.ZERO
	_cached_separation = Vector2.ZERO
	card_drop_multiplier = 1.0
	scrap_reward_multiplier = 1.0
	scale = Vector2.ONE
	modulate = Color.WHITE
	_mutation_profile = {"health": 1.0, "damage": 1.0, "speed": 1.0}
	_difficulty_speed_multiplier = 1.0
	_difficulty_health_multiplier = 1.0
	_difficulty_damage_multiplier = 1.0
	_hit_flash_time_remaining = 0.0
	visible = true
	set_physics_process(true)
	_set_hit_flash_amount(0.0)
	if _collision_shape != null:
		_collision_shape.disabled = false
	if not is_in_group("enemy"):
		add_to_group("enemy")
	_refresh_scaled_stats(true)
	_desync_animation()


## Pooled enemies of one type would otherwise bounce in perfect sync.
func _desync_animation() -> void:
	var animated: AnimatedSprite2D = _sprite_target as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return
	var frame_count: int = animated.sprite_frames.get_frame_count(animated.animation)
	if frame_count > 1:
		animated.frame = randi_range(0, frame_count - 1)

func on_released_to_pool() -> void:
	_damage_cooldown = 0.0
	velocity = Vector2.ZERO
	_hit_flash_time_remaining = 0.0
	visible = false
	set_physics_process(false)
	_set_hit_flash_amount(0.0)
	if _collision_shape != null:
		_collision_shape.disabled = true
	if is_in_group("enemy"):
		remove_from_group("enemy")


# -- Scaling ---------------------------------------------------------------

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
		health_ratio = clampf(float(_current_health) / float(_current_max_health), 0.0, 1.0)
	var mutation_speed: float = float(_mutation_profile.get("speed", 1.0))
	var mutation_damage: float = float(_mutation_profile.get("damage", 1.0))
	var mutation_health: float = float(_mutation_profile.get("health", 1.0))
	_current_move_speed = maxf(move_speed * _difficulty_speed_multiplier * mutation_speed, 1.0)
	_current_contact_damage = max(int(round(float(contact_damage) * _difficulty_damage_multiplier * mutation_damage)), 1)
	_current_max_health = max(int(round(float(max_health) * _difficulty_health_multiplier * mutation_health)), 1)
	_current_health = (_current_max_health if reset_health
		else max(int(round(float(_current_max_health) * health_ratio)), 1))


# -- Helpers ---------------------------------------------------------------

func get_collision_radius() -> float:
	if _collision_shape == null:
		return 8.0
	var circle: CircleShape2D = _collision_shape.shape as CircleShape2D
	return circle.radius if circle != null else 8.0


func _get_stand_off_distance(player: PlayerController) -> float:
	var player_radius: float = player.get_collision_radius() if player != null else 12.0
	return maxf(player_radius + get_collision_radius() + body_spacing, damage_range * 0.72)


func _resolve_sprite_target() -> CanvasItem:
	var named_sprite: Node = get_node_or_null("Sprite")
	if named_sprite is CanvasItem:
		return named_sprite as CanvasItem
	return get_node_or_null("Sprite2D") as CanvasItem


func _get_death_sfx_id() -> String:
	return "enemy_die"


# -- Hit flash -------------------------------------------------------------

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
	_hit_flash_time_remaining = maxf(hit_flash_duration, 0.01)
	_set_hit_flash_amount(hit_flash_strength)


func _update_hit_flash(delta: float) -> void:
	if _hit_flash_time_remaining <= 0.0:
		return
	_hit_flash_time_remaining = maxf(_hit_flash_time_remaining - delta, 0.0)
	var remaining_ratio: float = _hit_flash_time_remaining / maxf(hit_flash_duration, 0.01)
	var progress: float = 1.0 - remaining_ratio
	var pulse_wave: float = absf(sin(progress * PI * hit_flash_pulses))
	var pulse_amount: float = 0.28 + pulse_wave * 0.72
	_set_hit_flash_amount(remaining_ratio * pulse_amount * hit_flash_strength)


func _set_hit_flash_amount(amount: float) -> void:
	if _sprite_target == null:
		return
	var shader_material: ShaderMaterial = _sprite_target.material as ShaderMaterial
	if shader_material == null:
		return
	shader_material.set_shader_parameter("flash_amount", clampf(amount, 0.0, 1.0))
