class_name PoolManager
extends Node

@export var enemy_scenes: Array[PackedScene] = []
@export var projectile_scenes: Array[PackedScene] = []
@export var pickup_scenes: Array[PackedScene] = []
@export var enemy_prewarm_count: int = 12
@export var projectile_prewarm_count: int = 20
@export var pickup_prewarm_count: int = 18

var _available_nodes: Dictionary = {}
var _active_keys: Dictionary = {}

func _ready() -> void:
	add_to_group("pool_manager")
	_prewarm_scene_list(enemy_scenes, enemy_prewarm_count)
	_prewarm_scene_list(projectile_scenes, projectile_prewarm_count)
	_prewarm_scene_list(pickup_scenes, pickup_prewarm_count)

func _exit_tree() -> void:
	for pool in _available_nodes.values():
		var nodes: Array = pool as Array
		for node_variant in nodes:
			var pooled_node: Node = node_variant as Node
			if pooled_node != null and is_instance_valid(pooled_node):
				pooled_node.free()
	_available_nodes.clear()
	_active_keys.clear()

func spawn(scene: PackedScene, parent: Node) -> Node:
	if scene == null or parent == null:
		return null
	var key: String = _scene_key(scene)
	var pooled_node: Node = _take_node(scene, key)
	if pooled_node == null:
		return null
	if pooled_node.get_parent() != null:
		pooled_node.get_parent().remove_child(pooled_node)
	parent.add_child(pooled_node)
	_active_keys[pooled_node.get_instance_id()] = key
	if pooled_node.has_method("on_spawned_from_pool"):
		pooled_node.call("on_spawned_from_pool")
	return pooled_node

func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var instance_id: int = node.get_instance_id()
	var key: String = String(_active_keys.get(instance_id, ""))
	if key.is_empty():
		node.queue_free()
		return
	_active_keys.erase(instance_id)
	if node.has_method("on_released_to_pool"):
		node.call("on_released_to_pool")
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	var pool: Array = _available_nodes.get(key, [])
	pool.append(node)
	_available_nodes[key] = pool

func _prewarm_scene_list(scenes: Array[PackedScene], count: int) -> void:
	for scene in scenes:
		if scene == null:
			continue
		_prewarm_scene(scene, count)

func _prewarm_scene(scene: PackedScene, count: int) -> void:
	var key: String = _scene_key(scene)
	if key.is_empty():
		return
	var pool: Array = _available_nodes.get(key, [])
	var needed: int = max(count - pool.size(), 0)
	for _i in range(needed):
		var pooled_node: Node = scene.instantiate()
		if pooled_node != null:
			pool.append(pooled_node)
	_available_nodes[key] = pool

func _take_node(scene: PackedScene, key: String) -> Node:
	var pool: Array = _available_nodes.get(key, [])
	if pool.is_empty():
		return scene.instantiate()
	var pooled_node: Node = pool.pop_back() as Node
	_available_nodes[key] = pool
	return pooled_node

func _scene_key(scene: PackedScene) -> String:
	return scene.resource_path
