class_name EnemySpawner
extends Node

@export var enemy_scene: PackedScene
@export var enemy_container_path: NodePath
@export var player_path: NodePath
@export var floor_generator_path: NodePath

@export var spawn_interval: float = 1.5
@export var max_enemies: int = 8
@export var spawn_rect_size: Vector2 = Vector2(520.0, 300.0)
@export var min_spawn_distance: float = 120.0
@export var enemy_despawn_distance: float = 900.0

var _spawn_timer: float = 0.0
var _active: bool = true
var _enemy_container: Node2D
var _player: PlayerController
var _floor_generator: FloorGenerator

func _ready() -> void:
	_enemy_container = get_node_or_null(enemy_container_path) as Node2D
	_player = get_node_or_null(player_path) as PlayerController
	_floor_generator = get_node_or_null(floor_generator_path) as FloorGenerator
	_spawn_timer = spawn_interval

func _physics_process(delta: float) -> void:
	if not _active:
		return
	if _enemy_container == null or _player == null:
		return
	_spawn_timer = max(_spawn_timer - delta, 0.0)
	if _spawn_timer <= 0.0:
		_spawn_timer = spawn_interval
		_spawn_enemy()
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

func _spawn_enemy() -> void:
	if enemy_scene == null:
		return
	if _enemy_container.get_child_count() >= max_enemies:
		return
	var enemy_node: Node = enemy_scene.instantiate()
	if enemy_node is Node2D:
		var enemy2d: Node2D = enemy_node as Node2D
		_enemy_container.add_child(enemy2d)
		enemy2d.add_to_group("enemy")
		enemy2d.global_position = _pick_spawn_position()

func _pick_spawn_position() -> Vector2:
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
		if _floor_generator == null or _floor_generator.is_world_position_within_limit(candidate):
			return candidate
	return _player.global_position + Vector2(half.x, 0.0)

func _despawn_far_enemies() -> void:
	for child in _enemy_container.get_children():
		if child is Node2D:
			var enemy: Node2D = child as Node2D
			if enemy.global_position.distance_to(_player.global_position) > enemy_despawn_distance:
				enemy.queue_free()
