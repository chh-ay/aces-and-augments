class_name FloorGenerator
extends Node
##
## Streams floor tiles around the player using Wang-corner tiling.
##
## Both TileMapLayer nodes MUST have `tile_set` assigned in the editor
## (res://resources/tilesets/floor_tileset.tres). Source 0 = base atlas
## (single (0,0) tile). Source 1 = detail atlas (7x7 grid of wang tiles).
##

signal chunk_generated(chunk: Vector2i)
signal chunk_cleared(chunk: Vector2i)
signal initial_chunks_ready

const TILESET_MAPPING_PATH: String = "res://data/arena_tileset.json"
const DEFAULT_CHUNK_SIZE: Vector2i = Vector2i(64, 64)
const DEFAULT_TILE_SIZE: Vector2i = Vector2i(32, 32)
const BASE_SOURCE_INDEX: int = 0
const DETAIL_SOURCE_INDEX: int = 1
const BASE_COORDS: Vector2i = Vector2i.ZERO
const ALL_UPPER_KEY: String = "upper|upper|upper|upper"
const ALL_LOWER_KEY: String = "lower|lower|lower|lower"
const WORLD_LIMIT_DISABLED: int = 0
const INVALID_CHUNK: Vector2i = Vector2i(1_000_000, 1_000_000)
const CHUNK_LIMIT_PADDING: int = 1
const FLOOR_BASE_Z_INDEX: int = -30
const FLOOR_DETAIL_Z_INDEX: int = -20


class SimpleNoise2D:
	extends RefCounted

	var noise_seed: int = 0
	var frequency: float = 0.04

	func get_noise_2d(x: float, y: float) -> float:
		var scaled_x: float = x * frequency
		var scaled_y: float = y * frequency
		var x0: int = int(floor(scaled_x))
		var y0: int = int(floor(scaled_y))
		var tx: float = scaled_x - float(x0)
		var ty: float = scaled_y - float(y0)
		var sx: float = tx * tx * (3.0 - 2.0 * tx)
		var sy: float = ty * ty * (3.0 - 2.0 * ty)
		var n00: float = _sample(x0, y0)
		var n10: float = _sample(x0 + 1, y0)
		var n01: float = _sample(x0, y0 + 1)
		var n11: float = _sample(x0 + 1, y0 + 1)
		return lerpf(lerpf(n00, n10, sx), lerpf(n01, n11, sx), sy)

	func _sample(ix: int, iy: int) -> float:
		var value: int = ix * 374761393 + iy * 668265263 + noise_seed * 700001
		value = int((value ^ (value >> 13)) * 1274126177)
		value = value ^ (value >> 16)
		return (float(value & 0x7fffffff) / 1073741823.5) - 1.0


@export var player_path: NodePath
@export var floor_base_path: NodePath
@export var floor_detail_path: NodePath
@export var chunk_size: Vector2i = DEFAULT_CHUNK_SIZE
@export var chunk_radius: int = 1
@export var chunk_limit: int = 2
@export var world_radius_chunks: int = 2
@export var use_border_ring: bool = true
@export var border_thickness_chunks: int = 1
@export var use_detail_layer: bool = true
@export var upper_threshold: float = 0.12
@export var noise_frequency: float = 0.04
@export var noise_smoothing_radius: int = 1
@export var generate_initial_chunks_immediately: bool = true
@export var max_chunk_rows_generated_per_frame: int = 8
@export var max_chunk_rows_cleared_per_frame: int = 12

var _player: Node2D
var _floor_base: TileMapLayer
var _floor_detail: TileMapLayer
var _noise: SimpleNoise2D
var _detail_atlas: TileSetAtlasSource
var _mapping: Dictionary = {}
var _border_coords: Vector2i = Vector2i.ZERO
var _tile_size: Vector2i = DEFAULT_TILE_SIZE
var _chunk_world_size: Vector2 = Vector2.ZERO
var _playable_radius_world: Vector2 = Vector2.ZERO
var _generated_chunks: Dictionary = {}
var _last_chunk: Vector2i = INVALID_CHUNK
var _queued_chunks: Array[Vector2i] = []
var _queued_chunk_lookup: Dictionary = {}
var _active_chunk_job: Dictionary = {}
var _queued_clear_chunks: Array[Vector2i] = []
var _queued_clear_lookup: Dictionary = {}
var _active_clear_job: Dictionary = {}
var _initial_chunks_ready: bool = false


func _ready() -> void:
	RunContext.register_floor_generator(self)
	_player = get_node_or_null(player_path) as Node2D
	_floor_base = get_node_or_null(floor_base_path) as TileMapLayer
	_floor_detail = get_node_or_null(floor_detail_path) as TileMapLayer
	_setup_render_layers()
	_init_floor()


func _exit_tree() -> void:
	RunContext.unregister_floor_generator(self)


func _process(_delta: float) -> void:
	if _player == null or _noise == null:
		return
	_update_floor_chunks()
	_drain_chunk_queue()


# -- Public queries --------------------------------------------------------

func get_chunk_size() -> Vector2i: return chunk_size
func get_tile_size() -> Vector2i: return _tile_size
func get_chunk_world_size() -> Vector2: return _chunk_world_size
func get_playable_radius_world() -> Vector2: return _playable_radius_world
func get_playable_radius_chunks() -> int: return _get_playable_radius_chunks()
func get_noise() -> SimpleNoise2D: return _noise
func get_upper_threshold() -> float: return upper_threshold
func has_initial_chunks_ready() -> bool: return _initial_chunks_ready


func is_world_position_within_limit(world_pos: Vector2) -> bool:
	if world_radius_chunks <= WORLD_LIMIT_DISABLED:
		return true
	return absf(world_pos.x) <= _playable_radius_world.x and absf(world_pos.y) <= _playable_radius_world.y


func is_world_position_in_upper_terrain(world_pos: Vector2) -> bool:
	if _noise == null or _chunk_world_size == Vector2.ZERO:
		return false
	var tile_x: int = int(floor(world_pos.x / float(_tile_size.x)))
	var tile_y: int = int(floor(world_pos.y / float(_tile_size.y)))
	if _is_chunk_in_border_ring(_world_to_chunk(world_pos)):
		return true
	return (_corner_type(tile_x, tile_y) == "upper"
		or _corner_type(tile_x + 1, tile_y) == "upper"
		or _corner_type(tile_x, tile_y + 1) == "upper"
		or _corner_type(tile_x + 1, tile_y + 1) == "upper")


# -- Boot ------------------------------------------------------------------

func _init_floor() -> void:
	if _floor_base == null or _floor_detail == null:
		_finish_boot_fallback("Missing floor layers")
		return
	var tileset: TileSet = _floor_base.tile_set
	if tileset == null:
		_finish_boot_fallback("FloorBase has no tile_set")
		return
	if _floor_detail.tile_set == null:
		_floor_detail.tile_set = tileset
	if not _verify_sources(tileset):
		return
	_detail_atlas = tileset.get_source(DETAIL_SOURCE_INDEX) as TileSetAtlasSource
	_tile_size = tileset.tile_size
	_mapping = _load_tileset_mapping()
	_border_coords = _mapping.get(ALL_UPPER_KEY, BASE_COORDS)
	_validate_chunk_settings()
	_refresh_cached_metrics()
	_noise = SimpleNoise2D.new()
	_noise.noise_seed = randi()
	_noise.frequency = noise_frequency
	_reset_streaming_state()
	if generate_initial_chunks_immediately:
		_generate_initial_chunks()
		_mark_initial_chunks_ready()
	else:
		_update_floor_chunks()


func _verify_sources(tileset: TileSet) -> bool:
	if tileset.get_source_count() < 2:
		_finish_boot_fallback("Floor tileset needs 2 sources (base + detail)")
		return false
	var base_source: TileSetSource = tileset.get_source(BASE_SOURCE_INDEX)
	var detail_source: TileSetSource = tileset.get_source(DETAIL_SOURCE_INDEX)
	if base_source == null or detail_source == null:
		_finish_boot_fallback("Floor tileset sources resolved to null")
		return false
	return true


func _reset_streaming_state() -> void:
	_floor_base.clear()
	_floor_detail.clear()
	_generated_chunks.clear()
	_queued_chunks.clear()
	_queued_chunk_lookup.clear()
	_active_chunk_job.clear()
	_queued_clear_chunks.clear()
	_queued_clear_lookup.clear()
	_active_clear_job.clear()
	_initial_chunks_ready = false
	_last_chunk = INVALID_CHUNK


func _validate_chunk_settings() -> void:
	if chunk_limit < chunk_radius + CHUNK_LIMIT_PADDING:
		chunk_limit = chunk_radius + CHUNK_LIMIT_PADDING
	if border_thickness_chunks < 0:
		border_thickness_chunks = 0
	if world_radius_chunks > WORLD_LIMIT_DISABLED and border_thickness_chunks >= world_radius_chunks:
		border_thickness_chunks = max(world_radius_chunks - 1, 0)


func _refresh_cached_metrics() -> void:
	_chunk_world_size = Vector2(
		float(chunk_size.x) * float(_tile_size.x),
		float(chunk_size.y) * float(_tile_size.y)
	)
	var playable: int = _get_playable_radius_chunks()
	_playable_radius_world = Vector2(
		float(playable) * _chunk_world_size.x,
		float(playable) * _chunk_world_size.y
	)


# -- Chunk streaming -------------------------------------------------------

func _update_floor_chunks() -> void:
	var chunk: Vector2i = _world_to_chunk(_player.global_position)
	if chunk == _last_chunk:
		return
	_last_chunk = chunk
	for y in range(chunk.y - chunk_radius, chunk.y + chunk_radius + 1):
		for x in range(chunk.x - chunk_radius, chunk.x + chunk_radius + 1):
			var candidate: Vector2i = Vector2i(x, y)
			if not _is_chunk_within_world_limit(candidate):
				continue
			_cancel_chunk_clear(candidate)
			if not _generated_chunks.has(candidate):
				_queue_chunk_generation(candidate)
	_prune_chunks(chunk)


func _generate_initial_chunks() -> void:
	if _player == null:
		return
	var center: Vector2i = _world_to_chunk(_player.global_position)
	_last_chunk = center
	for y in range(center.y - chunk_radius, center.y + chunk_radius + 1):
		for x in range(center.x - chunk_radius, center.x + chunk_radius + 1):
			var chunk: Vector2i = Vector2i(x, y)
			if not _is_chunk_within_world_limit(chunk) or _generated_chunks.has(chunk):
				continue
			var job: Dictionary = _create_chunk_job(chunk)
			while int(job.get("row_index", 0)) < chunk_size.y:
				_generate_chunk_row(job)
			_finalize_chunk_job(job)
	_prune_chunks(center)


func _create_chunk_job(chunk: Vector2i) -> Dictionary:
	var start_x: int = chunk.x * chunk_size.x
	var start_y: int = chunk.y * chunk_size.y
	return {
		"chunk": chunk,
		"is_border_chunk": _is_chunk_in_border_ring(chunk),
		"start_x": start_x,
		"start_y": start_y,
		"corner_types": _build_corner_type_grid(start_x, start_y),
		"row_index": 0
	}


func _generate_chunk_row(job: Dictionary) -> void:
	var start_x: int = int(job["start_x"])
	var start_y: int = int(job["start_y"])
	var row_index: int = int(job["row_index"])
	var y: int = start_y + row_index
	var is_border_chunk: bool = bool(job["is_border_chunk"])
	var corner_types: Array = job["corner_types"]
	for x in range(start_x, start_x + chunk_size.x):
		var detail_coords: Vector2i = BASE_COORDS
		var has_upper: bool = false
		if is_border_chunk:
			detail_coords = _border_coords
			has_upper = true
		else:
			var local_x: int = x - start_x
			var local_y: int = y - start_y
			var nw: String = corner_types[local_x][local_y]
			var ne: String = corner_types[local_x + 1][local_y]
			var sw: String = corner_types[local_x][local_y + 1]
			var se: String = corner_types[local_x + 1][local_y + 1]
			has_upper = nw == "upper" or ne == "upper" or sw == "upper" or se == "upper"
			var key: String = "%s|%s|%s|%s" % [nw, ne, sw, se]
			detail_coords = _mapping.get(key, BASE_COORDS)
		if _detail_atlas != null and not _detail_atlas.has_tile(detail_coords):
			detail_coords = BASE_COORDS
		_floor_base.set_cell(Vector2i(x, y), BASE_SOURCE_INDEX, BASE_COORDS)
		if use_detail_layer and has_upper:
			_floor_detail.set_cell(Vector2i(x, y), DETAIL_SOURCE_INDEX, detail_coords)
		else:
			_floor_detail.erase_cell(Vector2i(x, y))
	job["row_index"] = row_index + 1


func _finalize_chunk_job(job: Dictionary) -> void:
	var chunk: Vector2i = job.get("chunk", INVALID_CHUNK)
	if chunk == INVALID_CHUNK:
		return
	_generated_chunks[chunk] = true
	chunk_generated.emit(chunk)


func _prune_chunks(center: Vector2i) -> void:
	for key in _generated_chunks.keys():
		var chunk: Vector2i = key
		if max(absi(chunk.x - center.x), absi(chunk.y - center.y)) > chunk_limit:
			_queue_chunk_clear(chunk)


func _queue_chunk_generation(chunk: Vector2i) -> void:
	if _generated_chunks.has(chunk) or _queued_chunk_lookup.has(chunk):
		return
	_queued_chunks.append(chunk)
	_queued_chunk_lookup[chunk] = true


func _drain_chunk_queue() -> void:
	var budget: int = max(max_chunk_rows_generated_per_frame, 1)
	while budget > 0:
		if _active_chunk_job.is_empty():
			if _queued_chunks.is_empty():
				break
			var chunk: Vector2i = _queued_chunks.pop_front()
			_queued_chunk_lookup.erase(chunk)
			if _generated_chunks.has(chunk):
				continue
			_active_chunk_job = _create_chunk_job(chunk)
		_generate_chunk_row(_active_chunk_job)
		budget -= 1
		if int(_active_chunk_job["row_index"]) >= chunk_size.y:
			_finalize_chunk_job(_active_chunk_job)
			_active_chunk_job.clear()
	if not _initial_chunks_ready and _active_chunk_job.is_empty() and _queued_chunks.is_empty():
		_mark_initial_chunks_ready()
	_drain_chunk_clear_queue()


func _queue_chunk_clear(chunk: Vector2i) -> void:
	if _queued_clear_lookup.has(chunk):
		return
	if _active_clear_job.get("chunk", INVALID_CHUNK) == chunk:
		return
	_queued_clear_chunks.append(chunk)
	_queued_clear_lookup[chunk] = true


func _drain_chunk_clear_queue() -> void:
	var budget: int = max(max_chunk_rows_cleared_per_frame, 1)
	while budget > 0:
		if _active_clear_job.is_empty():
			if _queued_clear_chunks.is_empty():
				return
			var chunk: Vector2i = _queued_clear_chunks.pop_front()
			_queued_clear_lookup.erase(chunk)
			if not _generated_chunks.has(chunk):
				continue
			_active_clear_job = {
				"chunk": chunk,
				"start_x": chunk.x * chunk_size.x,
				"start_y": chunk.y * chunk_size.y,
				"row_index": 0,
				"regenerate": false
			}
		_clear_chunk_row(_active_clear_job)
		budget -= 1
		if int(_active_clear_job["row_index"]) >= chunk_size.y:
			_finalize_chunk_clear_job(_active_clear_job)
			_active_clear_job.clear()


func _clear_chunk_row(job: Dictionary) -> void:
	var start_x: int = int(job["start_x"])
	var start_y: int = int(job["start_y"])
	var row_index: int = int(job["row_index"])
	var y: int = start_y + row_index
	for x in range(start_x, start_x + chunk_size.x):
		_floor_base.erase_cell(Vector2i(x, y))
		_floor_detail.erase_cell(Vector2i(x, y))
	job["row_index"] = row_index + 1


func _finalize_chunk_clear_job(job: Dictionary) -> void:
	var chunk: Vector2i = job.get("chunk", INVALID_CHUNK)
	if chunk == INVALID_CHUNK:
		return
	_generated_chunks.erase(chunk)
	chunk_cleared.emit(chunk)
	if bool(job.get("regenerate", false)):
		_queue_chunk_generation(chunk)


func _cancel_chunk_clear(chunk: Vector2i) -> void:
	if _queued_clear_lookup.has(chunk):
		_queued_clear_lookup.erase(chunk)
		_queued_clear_chunks.erase(chunk)
		return
	if _active_clear_job.get("chunk", INVALID_CHUNK) == chunk:
		_active_clear_job["regenerate"] = true


# -- Sampling helpers ------------------------------------------------------

func _corner_type(x: int, y: int) -> String:
	return "upper" if _smoothed_noise(x, y) > upper_threshold else "lower"


func _smoothed_noise(x: int, y: int) -> float:
	if noise_smoothing_radius <= 0:
		return _noise.get_noise_2d(float(x), float(y))
	var sum: float = 0.0
	var count: int = 0
	for oy in range(-noise_smoothing_radius, noise_smoothing_radius + 1):
		for ox in range(-noise_smoothing_radius, noise_smoothing_radius + 1):
			sum += _noise.get_noise_2d(float(x + ox), float(y + oy))
			count += 1
	return sum / float(count)


func _get_playable_radius_chunks() -> int:
	if world_radius_chunks <= WORLD_LIMIT_DISABLED:
		return world_radius_chunks
	if not use_border_ring:
		return world_radius_chunks
	return max(world_radius_chunks - border_thickness_chunks, 0)


func _is_chunk_within_world_limit(chunk: Vector2i) -> bool:
	if world_radius_chunks <= WORLD_LIMIT_DISABLED:
		return true
	return max(absi(chunk.x), absi(chunk.y)) <= world_radius_chunks


func _is_chunk_in_border_ring(chunk: Vector2i) -> bool:
	if not use_border_ring or world_radius_chunks <= WORLD_LIMIT_DISABLED or border_thickness_chunks <= 0:
		return false
	var distance: int = max(absi(chunk.x), absi(chunk.y))
	var inner: int = max(world_radius_chunks - border_thickness_chunks, 0)
	return distance > inner and distance <= world_radius_chunks


func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / _chunk_world_size.x)),
		int(floor(world_pos.y / _chunk_world_size.y))
	)


func _build_corner_type_grid(start_x: int, start_y: int) -> Array:
	var grid_width: int = chunk_size.x + 1
	var grid_height: int = chunk_size.y + 1
	var grid: Array = []
	grid.resize(grid_width)
	for gx in range(grid_width):
		var column: Array = []
		column.resize(grid_height)
		for gy in range(grid_height):
			column[gy] = _corner_type(start_x + gx, start_y + gy)
		grid[gx] = column
	return grid


func _load_tileset_mapping() -> Dictionary:
	var mapping: Dictionary = {}
	if not FileAccess.file_exists(TILESET_MAPPING_PATH):
		return mapping
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TILESET_MAPPING_PATH))
	if not (parsed is Dictionary):
		return mapping
	var tileset_data: Dictionary = parsed.get("tileset", {})
	for tile_data in tileset_data.get("tiles", []):
		if not (tile_data is Dictionary):
			continue
		var corners: Dictionary = tile_data.get("corners", {})
		var pos: Dictionary = tile_data.get("original_position", {})
		var key: String = "%s|%s|%s|%s" % [
			corners.get("NW", "lower"),
			corners.get("NE", "lower"),
			corners.get("SW", "lower"),
			corners.get("SE", "lower")
		]
		mapping[key] = Vector2i(int(pos.get("col", 0)), int(pos.get("row", 0)))
	return mapping


func _setup_render_layers() -> void:
	if _floor_base != null:
		_floor_base.z_index = FLOOR_BASE_Z_INDEX
		_floor_base.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if _floor_detail != null:
		_floor_detail.z_index = FLOOR_DETAIL_Z_INDEX
		_floor_detail.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		_floor_detail.visible = use_detail_layer


func _mark_initial_chunks_ready() -> void:
	if _initial_chunks_ready:
		return
	_initial_chunks_ready = true
	initial_chunks_ready.emit()


func _finish_boot_fallback(reason: String) -> void:
	push_warning("[Floor] Boot fallback: %s" % reason)
	_mark_initial_chunks_ready()
