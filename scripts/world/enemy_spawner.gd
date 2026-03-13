class_name EnemySpawner
extends Node

@export var enemy_scene: PackedScene
@export var enemy_scenes: Array[PackedScene] = []
@export var enemy_container_path: NodePath
@export var player_path: NodePath
@export var floor_generator_path: NodePath
@export var arena_path: NodePath

@export var spawn_interval: float = 1.5
@export var max_enemies: int = 8
@export var spawn_rect_size: Vector2 = Vector2(520.0, 300.0)
@export var min_spawn_distance: float = 120.0
@export var enemy_despawn_distance: float = 900.0
@export var run_duration_seconds: float = 600.0
@export var peak_enemy_count: int = 22
@export var peak_speed_multiplier: float = 1.35
@export var peak_health_multiplier: float = 1.7
@export var peak_damage_multiplier: float = 1.25
@export var despawn_check_interval: float = 0.4

var _spawn_timer: float = 0.0
var _active: bool = true
var _enemy_container: Node2D
var _player: PlayerController
var _floor_generator: FloorGenerator
var _arena: Arena
var _elapsed_run_time: float = 0.0
var _despawn_timer: float = 0.0
var _enemy_mutation_multiplier: float = 1.0

func _ready() -> void:
	_enemy_container = get_node_or_null(enemy_container_path) as Node2D
	_player = get_node_or_null(player_path) as PlayerController
	_floor_generator = get_node_or_null(floor_generator_path) as FloorGenerator
	_arena = get_node_or_null(arena_path) as Arena
	if _arena == null:
		_arena = get_tree().get_first_node_in_group("arena") as Arena
	_spawn_timer = spawn_interval

func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _enemy_container == null or _player == null:
		return
	_elapsed_run_time += delta
	_spawn_timer = max(_spawn_timer - delta, 0.0)
	_despawn_timer = max(_despawn_timer - delta, 0.0)
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_spawn_enemy()
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

func set_enemy_mutation_multiplier(multiplier: float) -> void:
	_enemy_mutation_multiplier = max(multiplier, 1.0)
	if _enemy_container == null:
		return
	for child in _enemy_container.get_children():
		if child.has_method("apply_mutation_scaling"):
			child.call("apply_mutation_scaling", _enemy_mutation_multiplier)

func _spawn_enemy() -> void:
	var scene_to_spawn: PackedScene = _pick_enemy_scene()
	if scene_to_spawn == null:
		return
	var current_max_enemies: int = int(round(lerpf(float(max_enemies), float(peak_enemy_count), _get_run_progress())))
	if _enemy_container.get_child_count() >= current_max_enemies:
		return
	var enemy_node: Node = scene_to_spawn.instantiate()
	if enemy_node is Node2D:
		var enemy2d: Node2D = enemy_node as Node2D
		_enemy_container.add_child(enemy2d)
		enemy2d.add_to_group("enemy")
		enemy2d.global_position = _pick_spawn_position()
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

func _despawn_far_enemies() -> void:
	var max_distance_sq: float = enemy_despawn_distance * enemy_despawn_distance
	for child in _enemy_container.get_children():
		if child is Node2D:
			var enemy: Node2D = child as Node2D
			if enemy.global_position.distance_squared_to(_player.global_position) > max_distance_sq:
				enemy.queue_free()

func _get_run_progress() -> float:
	if run_duration_seconds <= 0.0:
		return 1.0
	return clamp(_elapsed_run_time / run_duration_seconds, 0.0, 1.0)


func _apply_enemy_scaling(enemy_node: Node2D, progress: float) -> void:
	if not enemy_node.has_method("apply_difficulty_scaling"):
		return
	var eased: float = progress * progress * (3.0 - 2.0 * progress)
	var speed_multiplier: float = lerpf(1.0, peak_speed_multiplier, eased)
	var health_multiplier: float = lerpf(1.0, peak_health_multiplier, eased)
	var damage_multiplier: float = lerpf(1.0, peak_damage_multiplier, eased)
	enemy_node.call("apply_difficulty_scaling", speed_multiplier, health_multiplier, damage_multiplier)
	if enemy_node.has_method("apply_mutation_scaling"):
		enemy_node.call("apply_mutation_scaling", _enemy_mutation_multiplier)
