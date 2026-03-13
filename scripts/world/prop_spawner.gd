class_name PropSpawner
extends Node2D

@export var generator_path: NodePath
@export var enabled: bool = false
@export var prop_count_per_chunk: int = 5
@export var prop_edge_bias: float = 0.2
@export var enable_blocking_props: bool = false
@export var max_prop_chunks_per_frame: int = 1

var _generator: FloorGenerator
var _props_by_chunk: Dictionary = {}
var _tile_size: Vector2i = Vector2i(32, 32)
var _chunk_size: Vector2i = Vector2i(13, 11)
var _pending_chunks: Array[Vector2i] = []
var _pending_lookup: Dictionary = {}

func _ready() -> void:
	z_index = -5
	if not enabled:
		set_process(false)
		return
	_generator = get_node_or_null(generator_path) as FloorGenerator
	if _generator == null:
		return
	_generator.chunk_generated.connect(_on_chunk_generated)
	_generator.chunk_cleared.connect(_on_chunk_cleared)
	_tile_size = _generator.get_tile_size()
	_chunk_size = _generator.get_chunk_size()

func _process(_delta: float) -> void:
	if not enabled:
		return
	var budget: int = max(max_prop_chunks_per_frame, 1)
	while budget > 0 and not _pending_chunks.is_empty():
		var chunk: Vector2i = _pending_chunks.pop_front()
		_pending_lookup.erase(chunk)
		_spawn_props_for_chunk(chunk)
		budget -= 1

func _on_chunk_generated(chunk: Vector2i) -> void:
	if not enabled:
		return
	if _pending_lookup.has(chunk):
		return
	_pending_chunks.append(chunk)
	_pending_lookup[chunk] = true

func _on_chunk_cleared(chunk: Vector2i) -> void:
	if _pending_lookup.has(chunk):
		_pending_lookup.erase(chunk)
		_pending_chunks.erase(chunk)
	_clear_chunk(chunk)

func _spawn_props_for_chunk(chunk: Vector2i) -> void:
	if _generator == null:
		return
	var prop_defs: Array[Dictionary] = _build_prop_defs()
	if prop_defs.is_empty():
		return

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = _hash_chunk(chunk)
	var templates: Array[Dictionary] = _build_cluster_templates(prop_defs)
	var used_cells: Dictionary = {}
	var nodes: Array[Node] = []
	var start_x: float = float(chunk.x * _chunk_size.x * _tile_size.x)
	var start_y: float = float(chunk.y * _chunk_size.y * _tile_size.y)

	var cluster_count: int = 2 + int(rng.randi() % 2)
	for i in range(cluster_count):
		var anchor: Vector2i = Vector2i(
			rng.randi_range(1, _chunk_size.x - 2),
			rng.randi_range(1, _chunk_size.y - 2)
		)
		var template: Dictionary = _pick_weighted_template(rng, templates)
		var items: Array = template["items"]
		for item in items:
			var offset: Vector2i = item["offset"]
			var cell: Vector2i = Vector2i(
				clamp(anchor.x + offset.x, 0, _chunk_size.x - 1),
				clamp(anchor.y + offset.y, 0, _chunk_size.y - 1)
			)
			if used_cells.has(cell):
				continue
			if not _is_cell_valid_for_prop(chunk, cell, item.get("edge_bias", prop_edge_bias)):
				continue
			var prop_def: Dictionary = item["def"]
			var prop_node: Node2D = _create_prop_node(prop_def)
			prop_node.position = Vector2(
				start_x + float(cell.x * _tile_size.x) + float(_tile_size.x) * 0.5,
				start_y + float(cell.y * _tile_size.y) + float(_tile_size.y) * 0.5
			)
			add_child(prop_node)
			nodes.append(prop_node)
			used_cells[cell] = true

	var attempts: int = prop_count_per_chunk * 8
	var placed: int = nodes.size()
	while placed < prop_count_per_chunk and attempts > 0:
		attempts -= 1
		var cell_x: int = rng.randi_range(0, _chunk_size.x - 1)
		var cell_y: int = rng.randi_range(0, _chunk_size.y - 1)
		var cell_key: Vector2i = Vector2i(cell_x, cell_y)
		if used_cells.has(cell_key):
			continue
		if not _is_cell_valid_for_prop(chunk, cell_key, prop_edge_bias):
			continue
		var chosen_def: Dictionary = _pick_weighted_def(rng, prop_defs)
		var prop_node: Node2D = _create_prop_node(chosen_def)
		prop_node.position = Vector2(
			start_x + float(cell_x * _tile_size.x) + float(_tile_size.x) * 0.5,
			start_y + float(cell_y * _tile_size.y) + float(_tile_size.y) * 0.5
		)
		add_child(prop_node)
		nodes.append(prop_node)
		used_cells[cell_key] = true
		placed += 1
	_props_by_chunk[chunk] = nodes

func _clear_chunk(chunk: Vector2i) -> void:
	if not _props_by_chunk.has(chunk):
		return
	var nodes: Array[Node] = _props_by_chunk[chunk]
	for node in nodes:
		if node != null:
			node.queue_free()
	_props_by_chunk.erase(chunk)

func _hash_chunk(chunk: Vector2i) -> int:
	return int(chunk.x * 73856093) ^ int(chunk.y * 19349663)

func _build_prop_defs() -> Array[Dictionary]:
	var defs: Array[Dictionary] = []
	var terminal: Texture2D = AssetRegistry.get_env_texture("terminal")
	var barrel: Texture2D = AssetRegistry.get_env_texture("barrel")
	var scrap: Texture2D = AssetRegistry.get_env_texture("scrap")
	var pipes: Texture2D = AssetRegistry.get_env_texture("pipes")
	var warning_sign: Texture2D = AssetRegistry.get_env_texture("warning_sign")
	var cable_bundle: Texture2D = AssetRegistry.get_env_texture("cable_bundle")
	var oil_spill: Texture2D = AssetRegistry.get_env_texture("oil_spill")
	var floor_grate: Texture2D = AssetRegistry.get_env_texture("floor_grate")
	var machinery: Texture2D = AssetRegistry.get_env_texture("machinery")

	if terminal != null:
		defs.append(_prop_def("terminal", terminal, 0.8, true, 0.6))
	if barrel != null:
		defs.append(_prop_def("barrel", barrel, 0.6, true, 0.55))
	if scrap != null:
		defs.append(_prop_def("scrap", scrap, 1.1, false, 0.4))
	if pipes != null:
		defs.append(_prop_def("pipes", pipes, 0.5, true, 0.6))
	if warning_sign != null:
		defs.append(_prop_def("warning_sign", warning_sign, 0.4, true, 0.5))
	if cable_bundle != null:
		defs.append(_prop_def("cable_bundle", cable_bundle, 0.9, false, 0.4))
	if oil_spill != null:
		defs.append(_prop_def("oil_spill", oil_spill, 1.6, false, 0.3))
	if floor_grate != null:
		defs.append(_prop_def("floor_grate", floor_grate, 1.4, false, 0.3))
	if machinery != null:
		defs.append(_prop_def("machinery", machinery, 0.5, true, 0.6))
	return defs

func _prop_def(_name: String, texture: Texture2D, weight: float, blocking: bool, collider_scale: float) -> Dictionary:
	return {
		"name": _name,
		"texture": texture,
		"weight": weight,
		"blocking": blocking,
		"collider_scale": collider_scale
	}

func _pick_weighted_def(rng: RandomNumberGenerator, defs: Array[Dictionary]) -> Dictionary:
	var total: float = 0.0
	for def in defs:
		total += float(def.get("weight", 1.0))
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for def in defs:
		acc += float(def.get("weight", 1.0))
		if roll <= acc:
			return def
	return defs[defs.size() - 1]

func _create_prop_node(def: Dictionary) -> Node2D:
	var prop_root: Node2D = Node2D.new()
	var texture: Texture2D = def["texture"]
	var sprite: Sprite2D = Sprite2D.new()
	sprite.texture = texture
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	prop_root.add_child(sprite)

	var blocking: bool = enable_blocking_props and bool(def.get("blocking", false))
	if blocking:
		var body: StaticBody2D = StaticBody2D.new()
		var collider: CollisionShape2D = CollisionShape2D.new()
		var rect: RectangleShape2D = RectangleShape2D.new()
		var tex_size: Vector2 = texture.get_size()
		var _scale: float = float(def.get("collider_scale", 0.6))
		rect.size = Vector2(tex_size.x * _scale, tex_size.y * _scale)
		collider.shape = rect
		body.collision_layer = 1
		body.collision_mask = 1
		body.add_child(collider)
		prop_root.add_child(body)
	return prop_root

func _is_cell_valid_for_prop(chunk: Vector2i, cell: Vector2i, edge_bias: float) -> bool:
	if _generator == null:
		return false
	var noise_val: float = _generator.get_noise().get_noise_2d(
		float(cell.x + chunk.x * _chunk_size.x),
		float(cell.y + chunk.y * _chunk_size.y)
	)
	var threshold: float = _generator.get_upper_threshold()
	if noise_val > threshold:
		return false
	return abs(noise_val - threshold) > edge_bias

func _build_cluster_templates(prop_defs: Array[Dictionary]) -> Array[Dictionary]:
	var templates: Array[Dictionary] = []
	var def_by_name: Dictionary = _defs_by_name(prop_defs)
	if def_by_name.is_empty():
		return templates

	templates.append(_cluster_template(1.2, [
		_cluster_item(def_by_name["terminal"], Vector2i(0, 0), prop_edge_bias),
		_cluster_item(def_by_name["barrel"], Vector2i(1, 0), prop_edge_bias),
		_cluster_item(def_by_name["floor_grate"], Vector2i(0, 1), prop_edge_bias * 0.6)
	]))
	templates.append(_cluster_template(1.0, [
		_cluster_item(def_by_name["pipes"], Vector2i(0, 0), prop_edge_bias),
		_cluster_item(def_by_name["cable_bundle"], Vector2i(-1, 0), prop_edge_bias),
		_cluster_item(def_by_name["oil_spill"], Vector2i(0, 1), prop_edge_bias * 0.4)
	]))
	templates.append(_cluster_template(0.9, [
		_cluster_item(def_by_name["machinery"], Vector2i(0, 0), prop_edge_bias),
		_cluster_item(def_by_name["warning_sign"], Vector2i(1, 0), prop_edge_bias),
		_cluster_item(def_by_name["barrel"], Vector2i(0, -1), prop_edge_bias)
	]))
	templates.append(_cluster_template(1.1, [
		_cluster_item(def_by_name["scrap"], Vector2i(0, 0), prop_edge_bias),
		_cluster_item(def_by_name["scrap"], Vector2i(1, 1), prop_edge_bias),
		_cluster_item(def_by_name["oil_spill"], Vector2i(-1, 0), prop_edge_bias * 0.4)
	]))
	templates.append(_cluster_template(0.8, [
		_cluster_item(def_by_name["floor_grate"], Vector2i(0, 0), prop_edge_bias * 0.4),
		_cluster_item(def_by_name["floor_grate"], Vector2i(1, 0), prop_edge_bias * 0.4),
		_cluster_item(def_by_name["oil_spill"], Vector2i(0, -1), prop_edge_bias * 0.3)
	]))
	return templates

func _cluster_template(weight: float, items: Array) -> Dictionary:
	return {"weight": weight, "items": items}

func _cluster_item(def: Dictionary, offset: Vector2i, edge_bias: float) -> Dictionary:
	return {"def": def, "offset": offset, "edge_bias": edge_bias}

func _pick_weighted_template(rng: RandomNumberGenerator, templates: Array[Dictionary]) -> Dictionary:
	var total: float = 0.0
	for template in templates:
		total += float(template.get("weight", 1.0))
	var roll: float = rng.randf() * total
	var acc: float = 0.0
	for template in templates:
		acc += float(template.get("weight", 1.0))
		if roll <= acc:
			return template
	return templates[templates.size() - 1]

func _defs_by_name(prop_defs: Array[Dictionary]) -> Dictionary:
	var map: Dictionary = {}
	for def in prop_defs:
		var _name: String = def.get("name", "")
		if _name != "":
			map[_name] = def
	return map
