class_name LightPropSpawner
extends Node2D
##
## Scatters animated light props (torches, lamps, fire pits, braziers) across
## generated land chunks. Animations are editor-authored SpriteFrames
## (res://resources/sprite_frames/light_props.tres, one animation per prop).
## Purely decorative: no collision. Placement is deterministic per chunk and
## avoids water via FloorGenerator.is_cell_water().
##

const FRAMES: SpriteFrames = preload("res://resources/sprite_frames/light_props.tres")
const PROP_Z_INDEX: int = -5

const PROP_TYPES: Array[Dictionary] = [
	{"id": "torch", "weight": 4.0},
	{"id": "lamp", "weight": 3.0},
	{"id": "fire_pit", "weight": 2.0},
	{"id": "brazier", "weight": 1.0},
]

@export var generator_path: NodePath
@export var props_per_chunk: int = 6
@export var placement_attempts_per_prop: int = 6

var _generator: FloorGenerator
var _props_by_chunk: Dictionary = {}
var _pending_chunks: Array[Vector2i] = []
var _pending_lookup: Dictionary = {}


func _ready() -> void:
	z_index = PROP_Z_INDEX
	_generator = get_node_or_null(generator_path) as FloorGenerator
	if _generator == null:
		set_process(false)
		return
	_generator.chunk_generated.connect(_on_chunk_generated)
	_generator.chunk_cleared.connect(_on_chunk_cleared)
	# Initial chunks are generated during FloorGenerator._ready, before this
	# node connects: backfill them.
	for chunk in _generator.get_generated_chunks():
		_on_chunk_generated(chunk)


func _process(_delta: float) -> void:
	if _pending_chunks.is_empty():
		return
	var chunk: Vector2i = _pending_chunks.pop_front()
	_pending_lookup.erase(chunk)
	_spawn_props_for_chunk(chunk)


func _on_chunk_generated(chunk: Vector2i) -> void:
	if _pending_lookup.has(chunk) or _props_by_chunk.has(chunk):
		return
	_pending_chunks.append(chunk)
	_pending_lookup[chunk] = true


func _on_chunk_cleared(chunk: Vector2i) -> void:
	if _pending_lookup.has(chunk):
		_pending_lookup.erase(chunk)
		_pending_chunks.erase(chunk)
	var nodes: Array = _props_by_chunk.get(chunk, [])
	for node in nodes:
		if is_instance_valid(node):
			node.queue_free()
	_props_by_chunk.erase(chunk)


func _spawn_props_for_chunk(chunk: Vector2i) -> void:
	var chunk_size: Vector2i = _generator.get_chunk_size()
	var tile_size: Vector2i = _generator.get_tile_size()
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = hash(chunk)
	var nodes: Array[Node] = []
	var used_cells: Dictionary = {}
	for _prop_index in range(props_per_chunk):
		for _attempt in range(placement_attempts_per_prop):
			var cell: Vector2i = Vector2i(
				chunk.x * chunk_size.x + rng.randi_range(1, chunk_size.x - 2),
				chunk.y * chunk_size.y + rng.randi_range(1, chunk_size.y - 2)
			)
			if used_cells.has(cell) or _generator.is_cell_water(cell.x, cell.y):
				continue
			used_cells[cell] = true
			var prop: AnimatedSprite2D = _create_prop(_pick_type(rng), rng)
			prop.position = Vector2(
				float(cell.x * tile_size.x) + float(tile_size.x) * 0.5,
				float(cell.y * tile_size.y) + float(tile_size.y) * 0.5
			)
			add_child(prop)
			nodes.append(prop)
			break
	_props_by_chunk[chunk] = nodes


func _pick_type(rng: RandomNumberGenerator) -> String:
	var total_weight: float = 0.0
	for prop_type in PROP_TYPES:
		total_weight += float(prop_type.get("weight", 1.0))
	var roll: float = rng.randf() * total_weight
	for prop_type in PROP_TYPES:
		roll -= float(prop_type.get("weight", 1.0))
		if roll <= 0.0:
			return String(prop_type.get("id", "torch"))
	return "torch"


func _create_prop(type_id: String, rng: RandomNumberGenerator) -> AnimatedSprite2D:
	var sprite: AnimatedSprite2D = AnimatedSprite2D.new()
	sprite.sprite_frames = FRAMES
	sprite.set_meta("prop_type", type_id)
	sprite.animation = type_id
	sprite.frame = rng.randi_range(0, maxi(FRAMES.get_frame_count(type_id) - 1, 0))
	sprite.play()
	return sprite
