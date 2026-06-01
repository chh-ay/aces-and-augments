extends Node
##
## Generic per-scene PackedScene pool. Lives as an autoload so any script can
## spawn/release without group lookups.
##
## Usage:
##     PoolManager.prewarm(my_scene, 20)
##     var inst: Node = PoolManager.spawn(my_scene, parent_node)
##     PoolManager.release(inst)            # when finished
##     PoolManager.clear()                  # on scene exit
##
## Pooled nodes may implement `on_spawned_from_pool()` and `on_released_to_pool()`
## to reset their own state.
##

var _available_nodes: Dictionary = {}      # resource_path -> Array[WeakRef]
var _active_keys: Dictionary = {}          # instance_id -> resource_path


## Ensure at least `count` instances of `scene` are warmed up in the pool.
func prewarm(scene: PackedScene, count: int) -> void:
	if scene == null or count <= 0:
		return
	var key: String = scene.resource_path
	var pool: Array = _available_nodes.get(key, [])
	var needed: int = count - pool.size()
	for _i in range(max(needed, 0)):
		var node: Node = scene.instantiate()
		if node != null:
			pool.append(weakref(node))
	_available_nodes[key] = pool


## Take a pooled instance (or instantiate a new one) and attach it to `parent`.
func spawn(scene: PackedScene, parent: Node) -> Node:
	if scene == null or parent == null:
		return null
	var key: String = scene.resource_path
	var node: Node = _take(key)
	if node == null:
		node = scene.instantiate()
		if node == null:
			return null
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	parent.add_child(node)
	_active_keys[node.get_instance_id()] = key
	if node.has_method("on_spawned_from_pool"):
		node.on_spawned_from_pool()
	return node


## Return a node to its pool. Falls back to queue_free if it was not tracked.
func release(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	var id: int = node.get_instance_id()
	var key: String = String(_active_keys.get(id, ""))
	if key.is_empty():
		node.queue_free()
		return
	_active_keys.erase(id)
	if node.has_method("on_released_to_pool"):
		node.on_released_to_pool()
	if node.get_parent() != null:
		node.get_parent().remove_child(node)
	var pool: Array = _available_nodes.get(key, [])
	pool.append(weakref(node))
	_available_nodes[key] = pool


## Drop every pooled and active reference. Active nodes are NOT freed -- they
## belong to whoever currently parents them; the pool just forgets they exist.
## Pooled nodes are freed because nothing owns them in the tree.
func clear() -> void:
	for pool in _available_nodes.values():
		for entry in pool:
			var weak: WeakRef = entry as WeakRef
			if weak == null:
				continue
			var node: Node = weak.get_ref() as Node
			if node != null and is_instance_valid(node) and node.get_parent() == null:
				node.free()
	_available_nodes.clear()
	_active_keys.clear()


func _take(key: String) -> Node:
	var pool: Array = _available_nodes.get(key, [])
	while not pool.is_empty():
		var weak: WeakRef = pool.pop_back() as WeakRef
		if weak == null:
			continue
		var node: Node = weak.get_ref() as Node
		if node != null and is_instance_valid(node):
			_available_nodes[key] = pool
			return node
	_available_nodes[key] = pool
	return null
