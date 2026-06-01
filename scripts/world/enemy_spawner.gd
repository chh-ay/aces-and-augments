class_name EnemySpawner
extends Node
##
## Spawns waves of enemies in a RING around the player.
##
## Each burst picks a single rotating base_angle, then evenly distributes
## burst_count enemies around the player at radii in [spawn_radius_min,
## spawn_radius_max]. Per-enemy angular and radial jitter keep the ring from
## looking robotic. Invalid positions (outside arena / off chunked floor) try
## a falling-back radius before giving up the slot.
##

@export var enemy_scene: PackedScene
@export var enemy_scenes: Array[PackedScene] = []
@export var enemy_container_path: NodePath
@export var player_path: NodePath
@export var floor_generator_path: NodePath
@export var arena_path: NodePath
@export var run_director_path: NodePath

@export_group("Cadence")
@export var spawn_interval: float = 2.1
@export var minimum_spawn_interval: float = 1.0
@export var max_enemies: int = 10
@export var peak_enemy_count: int = 64
@export var burst_count_base: int = 5
@export var burst_count_peak: int = 9
@export_range(0.2, 1.0, 0.05) var peak_spawn_interval_scale: float = 0.48

@export_group("Ring placement")
## Minimum spawn radius (just outside the camera frame is a good default).
@export var spawn_radius_min: float = 220.0
## Maximum spawn radius (close enough to engage quickly).
@export var spawn_radius_max: float = 320.0
## Per-enemy angle jitter around the evenly-spaced slot (radians).
@export_range(0.0, 1.5, 0.05) var ring_angle_jitter: float = 0.25
## Per-enemy radial jitter on top of the base radius (world units).
@export var ring_radial_jitter: float = 28.0
## Fallback radius used when the preferred slot is outside the floor/arena.
@export var fallback_spawn_radius: float = 180.0

@export_group("Despawn / scaling")
@export var enemy_despawn_distance: float = 900.0
@export var run_duration_seconds: float = 600.0
@export var peak_speed_multiplier: float = 1.5
@export var peak_health_multiplier: float = 2.4
@export var peak_damage_multiplier: float = 1.6
@export var despawn_check_interval: float = 0.4
@export_range(0, 256, 1) var prewarm_per_scene: int = 12

var _active: bool = true
var _spawn_timer: float = 0.0
var _despawn_timer: float = 0.0
var _elapsed_run_time: float = 0.0
var _base_spawn_interval: float = 0.0
var _difficulty_spawn_interval: float = 0.0
var _enemy_mutation_profile: Dictionary = {"health": 1.0, "damage": 1.0, "speed": 1.0}
var _difficulty_speed_multiplier: float = 1.0
var _difficulty_health_multiplier: float = 1.0
var _difficulty_damage_multiplier: float = 1.0
var _difficulty_card_drop_multiplier: float = 1.0

var _enemy_container: Node2D
var _player_override: PlayerController
var _floor_generator_override: FloorGenerator
var _arena_override: Arena
var _run_director: RunDirector


func _ready() -> void:
	_enemy_container = get_node_or_null(enemy_container_path) as Node2D
	_player_override = get_node_or_null(player_path) as PlayerController
	_floor_generator_override = get_node_or_null(floor_generator_path) as FloorGenerator
	_arena_override = get_node_or_null(arena_path) as Arena
	_run_director = get_node_or_null(run_director_path) as RunDirector
	if _run_director != null:
		run_duration_seconds = max(_run_director.run_duration_seconds, 0.0)
	_base_spawn_interval = max(spawn_interval, minimum_spawn_interval)
	_apply_selected_difficulty()
	_prewarm_pool()
	_spawn_timer = _get_current_spawn_interval()


func _physics_process(delta: float) -> void:
	if not _active or _enemy_container == null:
		return
	var player: PlayerController = _resolve_player()
	if player == null:
		return
	_elapsed_run_time += delta
	_spawn_timer = maxf(_spawn_timer - delta, 0.0)
	_despawn_timer = maxf(_despawn_timer - delta, 0.0)
	if _spawn_timer <= 0.0:
		_spawn_timer = _get_current_spawn_interval()
		_spawn_ring(player)
	if _despawn_timer <= 0.0:
		_despawn_timer = despawn_check_interval
		_despawn_far_enemies(player)


# -- Public API ------------------------------------------------------------

func set_active(is_active: bool) -> void:
	_active = is_active


func stop_enemies() -> void:
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		var enemy: AbstractEnemy = enemy_node as AbstractEnemy
		if enemy == null:
			continue
		enemy.set_physics_process(false)
		enemy.velocity = Vector2.ZERO


func set_enemy_mutation_profile(profile: Dictionary) -> void:
	_enemy_mutation_profile = profile.duplicate(true)
	if _enemy_container == null:
		return
	for child in _enemy_container.get_children():
		var enemy: AbstractEnemy = child as AbstractEnemy
		if enemy != null:
			enemy.apply_mutation_profile(_enemy_mutation_profile)


# -- Spawning --------------------------------------------------------------

func _spawn_ring(player: PlayerController) -> void:
	var slots_available: int = _get_current_max_enemies() - _enemy_container.get_child_count()
	if slots_available <= 0:
		return
	var burst_count: int = mini(_get_burst_count(), slots_available)
	if burst_count <= 0:
		return
	var base_angle: float = randf() * TAU
	var step: float = TAU / float(burst_count)
	for index in range(burst_count):
		var scene: PackedScene = _pick_enemy_scene()
		if scene == null:
			continue
		var angle: float = base_angle + step * float(index) + randf_range(-ring_angle_jitter, ring_angle_jitter)
		var radius: float = randf_range(spawn_radius_min, spawn_radius_max) + randf_range(-ring_radial_jitter, ring_radial_jitter)
		var position: Vector2 = _resolve_ring_position(player, angle, radius)
		if position == Vector2.INF:
			continue
		_spawn_single_enemy(scene, position)


func _resolve_ring_position(player: PlayerController, angle: float, radius: float) -> Vector2:
	var direction: Vector2 = Vector2.RIGHT.rotated(angle)
	var candidate: Vector2 = player.global_position + direction * radius
	if _is_valid_spawn_position(candidate):
		return candidate
	# Pull inward to the fallback radius and try again, keeping the angle.
	var fallback_candidate: Vector2 = player.global_position + direction * fallback_spawn_radius
	if _is_valid_spawn_position(fallback_candidate):
		return fallback_candidate
	# Last resort: clamp the original candidate inside the arena.
	var arena: Arena = _resolve_arena()
	if arena != null:
		var clamped: Vector2 = arena.clamp_world_position(candidate, 28.0)
		if clamped != player.global_position:
			return clamped
	return Vector2.INF


func _spawn_single_enemy(scene: PackedScene, position: Vector2) -> void:
	var enemy: AbstractEnemy = PoolManager.spawn(scene, _enemy_container) as AbstractEnemy
	if enemy == null:
		return
	enemy.global_position = position
	enemy.card_drop_chance = clampf(enemy.card_drop_chance * _difficulty_card_drop_multiplier, 0.0, 1.0)
	_apply_enemy_scaling(enemy)


func _apply_enemy_scaling(enemy: AbstractEnemy) -> void:
	var progress: float = _get_run_progress()
	var eased: float = progress * progress * (3.0 - 2.0 * progress)
	var speed_multiplier: float = lerpf(1.0, peak_speed_multiplier, eased) * _difficulty_speed_multiplier
	var health_multiplier: float = lerpf(1.0, peak_health_multiplier, eased) * _difficulty_health_multiplier
	var damage_multiplier: float = lerpf(1.0, peak_damage_multiplier, eased) * _difficulty_damage_multiplier
	enemy.apply_difficulty_scaling(speed_multiplier, health_multiplier, damage_multiplier)
	enemy.apply_mutation_profile(_enemy_mutation_profile)


func _pick_enemy_scene() -> PackedScene:
	if not enemy_scenes.is_empty():
		var available: Array[PackedScene] = []
		for scene in enemy_scenes:
			if scene != null:
				available.append(scene)
		if not available.is_empty():
			return available[randi_range(0, available.size() - 1)]
	return enemy_scene


# -- Validation ------------------------------------------------------------

func _is_valid_spawn_position(candidate: Vector2) -> bool:
	var floor_gen: FloorGenerator = _resolve_floor_generator()
	if floor_gen != null and not floor_gen.is_world_position_within_limit(candidate):
		return false
	var arena: Arena = _resolve_arena()
	if arena != null and not arena.is_world_position_inside(candidate, 28.0):
		return false
	return true


# -- Despawn ---------------------------------------------------------------

func _despawn_far_enemies(player: PlayerController) -> void:
	var max_distance_sq: float = enemy_despawn_distance * enemy_despawn_distance
	for child in _enemy_container.get_children():
		var enemy: Node2D = child as Node2D
		if enemy == null:
			continue
		if enemy.global_position.distance_squared_to(player.global_position) > max_distance_sq:
			PoolManager.release(enemy)


# -- Difficulty / pacing ---------------------------------------------------

func _get_run_progress() -> float:
	if run_duration_seconds <= 0.0:
		return 1.0
	if _run_director != null:
		var duration: float = max(_run_director.run_duration_seconds, 0.0)
		if duration <= 0.0:
			return 1.0
		return clampf(1.0 - (_run_director.remaining_seconds / duration), 0.0, 1.0)
	return clampf(_elapsed_run_time / run_duration_seconds, 0.0, 1.0)


func _get_group_pressure_progress() -> float:
	return clampf(pow(_get_run_progress(), 0.62), 0.0, 1.0)


func _get_burst_count() -> int:
	return max(int(round(lerpf(float(burst_count_base), float(burst_count_peak), _get_group_pressure_progress()))), 1)


func _get_current_max_enemies() -> int:
	return max(int(round(lerpf(float(max_enemies), float(peak_enemy_count), _get_group_pressure_progress()))), 1)


func _get_current_spawn_interval() -> float:
	var interval_start: float = maxf(_difficulty_spawn_interval, minimum_spawn_interval)
	return maxf(lerpf(interval_start, minimum_spawn_interval, _get_group_pressure_progress()), minimum_spawn_interval)


func _apply_selected_difficulty() -> void:
	var config: Dictionary = GameManager.get_selected_difficulty()
	_difficulty_speed_multiplier = float(config.get("enemy_speed", 1.0))
	_difficulty_health_multiplier = float(config.get("enemy_health", 1.0))
	_difficulty_damage_multiplier = float(config.get("enemy_damage", 1.0))
	_difficulty_card_drop_multiplier = float(config.get("card_drop", 1.0))
	var spawn_rate_multiplier: float = maxf(float(config.get("spawn_rate", 1.0)), 0.1)
	_difficulty_spawn_interval = maxf(_base_spawn_interval / spawn_rate_multiplier, minimum_spawn_interval)


func _prewarm_pool() -> void:
	if prewarm_per_scene <= 0:
		return
	for scene in enemy_scenes:
		PoolManager.prewarm(scene, prewarm_per_scene)
	if enemy_scene != null:
		PoolManager.prewarm(enemy_scene, prewarm_per_scene)


# -- Reference resolution --------------------------------------------------

func _resolve_player() -> PlayerController:
	if _player_override != null and is_instance_valid(_player_override):
		return _player_override
	return RunContext.player


func _resolve_arena() -> Arena:
	if _arena_override != null and is_instance_valid(_arena_override):
		return _arena_override
	return RunContext.arena


func _resolve_floor_generator() -> FloorGenerator:
	if _floor_generator_override != null and is_instance_valid(_floor_generator_override):
		return _floor_generator_override
	return RunContext.floor_generator
