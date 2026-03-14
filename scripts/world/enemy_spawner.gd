class_name EnemySpawner
extends Node

@export var enemy_scene: PackedScene
@export var enemy_scenes: Array[PackedScene] = []
@export var enemy_container_path: NodePath
@export var player_path: NodePath
@export var floor_generator_path: NodePath
@export var arena_path: NodePath
@export var run_director_path: NodePath

@export var spawn_interval: float = 2.1
@export var minimum_spawn_interval: float = 1.0
@export var max_enemies: int = 10
@export var spawn_rect_size: Vector2 = Vector2(520.0, 300.0)
@export var min_spawn_distance: float = 120.0
@export var enemy_despawn_distance: float = 900.0
@export var run_duration_seconds: float = 600.0
@export var peak_enemy_count: int = 32
@export var burst_count_base: int = 5
@export var burst_count_peak: int = 9
@export var burst_spread_radius: float = 52.0
@export var peak_speed_multiplier: float = 1.35
@export var peak_health_multiplier: float = 1.9
@export var peak_damage_multiplier: float = 1.25
@export_range(0.2, 1.0, 0.05) var peak_spawn_interval_scale: float = 0.48
@export var despawn_check_interval: float = 0.4

var _spawn_timer: float = 0.0
var _active: bool = true
var _enemy_container: Node2D
var _player: PlayerController
var _floor_generator: FloorGenerator
var _arena: Arena
var _run_director: RunDirector
var _elapsed_run_time: float = 0.0
var _despawn_timer: float = 0.0
var _base_spawn_interval: float = 0.0
var _difficulty_spawn_interval: float = 0.0
var _enemy_mutation_profile: Dictionary = {
	"health": 1.0,
	"damage": 1.0,
	"speed": 1.0
}
var _difficulty_speed_multiplier: float = 1.0
var _difficulty_health_multiplier: float = 1.0
var _difficulty_damage_multiplier: float = 1.0
var _difficulty_card_drop_multiplier: float = 1.0
var _pool_manager: Node

func _ready() -> void:
	_enemy_container = get_node_or_null(enemy_container_path) as Node2D
	_player = get_node_or_null(player_path) as PlayerController
	_floor_generator = get_node_or_null(floor_generator_path) as FloorGenerator
	_arena = get_node_or_null(arena_path) as Arena
	_run_director = get_node_or_null(run_director_path) as RunDirector
	_pool_manager = get_tree().get_first_node_in_group("pool_manager")
	if _arena == null:
		_arena = get_tree().get_first_node_in_group("arena") as Arena
	if _run_director == null:
		_run_director = get_tree().get_first_node_in_group("run_director") as RunDirector
	if _run_director != null:
		run_duration_seconds = max(_run_director.run_duration_seconds, 0.0)
	_base_spawn_interval = max(spawn_interval, minimum_spawn_interval)
	_apply_selected_difficulty()
	_spawn_timer = _get_current_spawn_interval()

func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _enemy_container == null or _player == null:
		return
	_elapsed_run_time += delta
	_spawn_timer = max(_spawn_timer - delta, 0.0)
	_despawn_timer = max(_despawn_timer - delta, 0.0)
	if _spawn_timer <= 0.0:
		_spawn_timer = _get_current_spawn_interval()
		_spawn_enemy_burst()
	if _despawn_timer <= 0.0:
		_despawn_timer = despawn_check_interval
		_despawn_far_enemies()

func set_active(is_active: bool) -> void:
	_active = is_active

func stop_enemies() -> void:
	var enemies: Array[Node] = get_tree().get_nodes_in_group("enemy")
	for enemy_node in enemies:
		if enemy_node is BasicEnemy:
			var enemy: BasicEnemy = enemy_node as BasicEnemy
			enemy.set_physics_process(false)
			enemy.velocity = Vector2.ZERO

func set_enemy_mutation_profile(profile: Dictionary) -> void:
	_enemy_mutation_profile = profile.duplicate(true)
	if _enemy_container == null:
		return
	for child in _enemy_container.get_children():
		if child.has_method("apply_mutation_profile"):
			child.call("apply_mutation_profile", _enemy_mutation_profile)

func _spawn_enemy_burst() -> void:
	var current_max_enemies: int = _get_current_max_enemies()
	var available_slots: int = current_max_enemies - _enemy_container.get_child_count()
	if available_slots <= 0:
		return
	var burst_count: int = min(_get_burst_count(), available_slots)
	if burst_count <= 0:
		return
	var anchor_position: Vector2 = _pick_spawn_position()
	for burst_index in range(burst_count):
		var scene_to_spawn: PackedScene = _pick_enemy_scene()
		if scene_to_spawn == null:
			continue
		_spawn_single_enemy(scene_to_spawn, anchor_position, burst_index)

func _spawn_single_enemy(scene_to_spawn: PackedScene, anchor_position: Vector2, burst_index: int) -> void:
	if _pool_manager == null or not is_instance_valid(_pool_manager):
		_pool_manager = get_tree().get_first_node_in_group("pool_manager")
	var enemy_node: Node = _pool_manager.call("spawn", scene_to_spawn, _enemy_container) as Node if _pool_manager != null else scene_to_spawn.instantiate()
	if enemy_node is Node2D:
		var enemy2d: Node2D = enemy_node as Node2D
		if enemy2d.get_parent() == null:
			_enemy_container.add_child(enemy2d)
		if not enemy2d.is_in_group("enemy"):
			enemy2d.add_to_group("enemy")
		enemy2d.global_position = _pick_burst_position(anchor_position, burst_index)
		if "card_drop_chance" in enemy2d:
			var card_drop_chance: float = float(enemy2d.get("card_drop_chance"))
			enemy2d.set("card_drop_chance", clamp(card_drop_chance * _difficulty_card_drop_multiplier, 0.0, 1.0))
		_apply_enemy_scaling(enemy2d, _get_run_progress())

func _pick_enemy_scene() -> PackedScene:
	if not enemy_scenes.is_empty():
		var available: Array[PackedScene] = []
		for scene in enemy_scenes:
			if scene != null:
				available.append(scene)
		if not available.is_empty():
			return available[randi_range(0, available.size() - 1)]
	return enemy_scene

func _pick_spawn_position() -> Vector2:
	if _arena == null or not is_instance_valid(_arena):
		_arena = get_tree().get_first_node_in_group("arena") as Arena
	var half: Vector2 = spawn_rect_size * 0.5
	var attempt: int = 0
	while attempt < 12:
		attempt += 1
		var x: float = randf_range(-half.x, half.x)
		var y: float = randf_range(-half.y, half.y)
		var offset: Vector2 = Vector2(x, y)
		if offset.length() < min_spawn_distance:
			continue
		var candidate: Vector2 = _player.global_position + offset
		var within_floor: bool = _floor_generator == null or _floor_generator.is_world_position_within_limit(candidate)
		var within_arena: bool = _arena == null or _arena.is_world_position_inside(candidate, 28.0)
		if within_floor and within_arena:
			return candidate
	var fallback: Vector2 = _player.global_position + Vector2(min_spawn_distance + 16.0, 0.0)
	if _arena != null:
		return _arena.clamp_world_position(fallback, 28.0)
	return fallback

func _pick_burst_position(anchor_position: Vector2, burst_index: int) -> Vector2:
	if burst_index == 0:
		return anchor_position
	var attempts: int = 0
	var angle_step: float = TAU / max(float(_get_burst_count()), 1.0)
	while attempts < 6:
		var radius: float = randf_range(18.0, burst_spread_radius)
		var angle: float = angle_step * float(burst_index) + randf_range(-0.45, 0.45)
		var candidate: Vector2 = anchor_position + Vector2.RIGHT.rotated(angle) * radius
		var within_floor: bool = _floor_generator == null or _floor_generator.is_world_position_within_limit(candidate)
		var within_arena: bool = _arena == null or _arena.is_world_position_inside(candidate, 28.0)
		if within_floor and within_arena:
			return candidate
		attempts += 1
	if _arena != null:
		return _arena.clamp_world_position(anchor_position, 28.0)
	return anchor_position

func _despawn_far_enemies() -> void:
	var max_distance_sq: float = enemy_despawn_distance * enemy_despawn_distance
	for child in _enemy_container.get_children():
		if child is Node2D:
			var enemy: Node2D = child as Node2D
			if enemy.global_position.distance_squared_to(_player.global_position) > max_distance_sq:
				if _pool_manager != null:
					_pool_manager.release(enemy)
				else:
					enemy.queue_free()

func _get_run_progress() -> float:
	if run_duration_seconds <= 0.0:
		return 1.0
	if _run_director != null:
		var duration: float = max(_run_director.run_duration_seconds, 0.0)
		if duration <= 0.0:
			return 1.0
		return clampf(1.0 - (_run_director.remaining_seconds / duration), 0.0, 1.0)
	return clamp(_elapsed_run_time / run_duration_seconds, 0.0, 1.0)

func _get_burst_count() -> int:
	var progress: float = _get_group_pressure_progress()
	return max(int(round(lerpf(float(burst_count_base), float(burst_count_peak), progress))), 1)

func _get_current_max_enemies() -> int:
	var progress: float = _get_group_pressure_progress()
	return max(int(round(lerpf(float(max_enemies), float(peak_enemy_count), progress))), 1)

func _get_scaled_run_progress() -> float:
	var progress: float = _get_run_progress()
	return progress * progress * (3.0 - 2.0 * progress)

func _get_group_pressure_progress() -> float:
	return clampf(pow(_get_run_progress(), 0.62), 0.0, 1.0)

func _get_current_spawn_interval() -> float:
	var interval_start: float = max(_difficulty_spawn_interval, minimum_spawn_interval)
	var interval_end: float = minimum_spawn_interval
	var progress: float = _get_group_pressure_progress()
	return max(lerpf(interval_start, interval_end, progress), minimum_spawn_interval)


func _apply_enemy_scaling(enemy_node: Node2D, progress: float) -> void:
	if not enemy_node.has_method("apply_difficulty_scaling"):
		return
	var eased: float = progress * progress * (3.0 - 2.0 * progress)
	var speed_multiplier: float = lerpf(1.0, peak_speed_multiplier, eased) * _difficulty_speed_multiplier
	var health_multiplier: float = lerpf(1.0, peak_health_multiplier, eased) * _difficulty_health_multiplier
	var damage_multiplier: float = lerpf(1.0, peak_damage_multiplier, eased) * _difficulty_damage_multiplier
	enemy_node.call("apply_difficulty_scaling", speed_multiplier, health_multiplier, damage_multiplier)
	if enemy_node.has_method("apply_mutation_profile"):
		enemy_node.call("apply_mutation_profile", _enemy_mutation_profile)

func _apply_selected_difficulty() -> void:
	if GameManager == null:
		return
	var config: Dictionary = GameManager.get_selected_difficulty()
	_difficulty_speed_multiplier = float(config.get("enemy_speed", 1.0))
	_difficulty_health_multiplier = float(config.get("enemy_health", 1.0))
	_difficulty_damage_multiplier = float(config.get("enemy_damage", 1.0))
	_difficulty_card_drop_multiplier = float(config.get("card_drop", 1.0))
	var spawn_rate_multiplier: float = max(float(config.get("spawn_rate", 1.0)), 0.1)
	_difficulty_spawn_interval = max(_base_spawn_interval / spawn_rate_multiplier, minimum_spawn_interval)
