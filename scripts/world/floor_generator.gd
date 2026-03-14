class_name FloorGenerator
extends Node

signal chunk_generated(chunk: Vector2i)
signal chunk_cleared(chunk: Vector2i)
signal initial_chunks_ready

# Algorithm overview:
# - Corner-based Wang tiling: each tile corner (NW/NE/SW/SE) is classified as "upper" or "lower"
#   using smoothed procedural noise values and `upper_threshold`.
# - The 4-corner signature maps to a tile coordinate loaded from `data/arena_tileset.json`.
# - Base layer always uses the base tile; detail layer uses the mapped tile when any corner is "upper".
# - Optional border ring forces "upper" at the world edge to create a clear boundary.

const DEFAULT_CHUNK_SIZE: Vector2i = Vector2i(64, 64)
const DEFAULT_TILE_SIZE: Vector2i = Vector2i(32, 32) # Matches arena_tileset.json tile size.
const ALL_UPPER_KEY: String = "upper|upper|upper|upper"
const ALL_LOWER_KEY: String = "lower|lower|lower|lower"
const WORLD_LIMIT_DISABLED: int = 0
# Sentinel outside any reasonable world radius so the first update always runs.
const INVALID_CHUNK: Vector2i = Vector2i(1_000_000, 1_000_000)
# Keep a small extra ring beyond the render radius to reduce churn while moving.
const CHUNK_LIMIT_PADDING: int = 1
const FLOOR_BASE_Z_INDEX: int = -30
const FLOOR_DETAIL_Z_INDEX: int = -20

class SimpleNoise2D:
	extends RefCounted

	var seed: int = 0
	var frequency: float = 0.04

	func get_noise_2d(x: float, y: float) -> float:
		var scaled_x: float = x * frequency
		var scaled_y: float = y * frequency
		var x0: int = int(floor(scaled_x))
		var y0: int = int(floor(scaled_y))
		var x1: int = x0 + 1
		var y1: int = y0 + 1
		var tx: float = scaled_x - float(x0)
		var ty: float = scaled_y - float(y0)
		var sx: float = tx * tx * (3.0 - 2.0 * tx)
		var sy: float = ty * ty * (3.0 - 2.0 * ty)
		var n00: float = _sample(x0, y0)
		var n10: float = _sample(x1, y0)
		var n01: float = _sample(x0, y1)
		var n11: float = _sample(x1, y1)
		var ix0: float = lerpf(n00, n10, sx)
		var ix1: float = lerpf(n01, n11, sx)
		return lerpf(ix0, ix1, sy)

	func _sample(ix: int, iy: int) -> float:
		var value: int = ix * 374761393 + iy * 668265263 + seed * 700001
		value = int((value ^ (value >> 13)) * 1274126177)
		value = value ^ (value >> 16)
		return (float(value & 0x7fffffff) / 1073741823.5) - 1.0

@export var player_path: NodePath
@export var floor_base_path: NodePath
@export var floor_detail_path: NodePath

@export var chunk_size: Vector2i = DEFAULT_CHUNK_SIZE # Tiles per chunk (X,Y).
@export var chunk_radius: int = 1 # How many chunks around the player to keep generated.
@export var chunk_limit: int = 2 # Max chunk distance before pruning (>= chunk_radius + padding).
@export var world_radius_chunks: int = 2 # World half-size in chunks; 0 disables the limit.
@export var use_border_ring: bool = true # Force a ring at the world edge to visually cap the map.
@export var border_thickness_chunks: int = 1 # Ring thickness in chunks.
@export var use_detail_layer: bool = true
@export var upper_threshold: float = 0.12 # Noise cutoff; higher = fewer "upper" tiles.
@export var noise_frequency: float = 0.04 # Noise scale; lower = larger blobs.
@export var noise_smoothing_radius: int = 1 # Box blur radius for smoother terrain.
@export var generate_initial_chunks_immediately: bool = true
@export var max_chunk_rows_generated_per_frame: int = 8
@export var max_chunk_rows_cleared_per_frame: int = 12

var _player: Node2D
var _floor_base: TileMapLayer
var _floor_detail: TileMapLayer
var _noise: SimpleNoise2D
var _mapping: Dictionary = {}
var _base_coords: Vector2i = Vector2i.ZERO
var _border_coords: Vector2i = Vector2i.ZERO
var _base_source_id: int = -1
var _detail_source_id: int = -1
var _atlas: TileSetAtlasSource
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
	_player = get_node_or_null(player_path) as Node2D
	_floor_base = get_node_or_null(floor_base_path) as TileMapLayer
	_floor_detail = get_node_or_null(floor_detail_path) as TileMapLayer
	_setup_render_layers()
	_init_floor()

func _process(_delta: float) -> void:
	if _player == null or _noise == null:
		return
	_update_floor_chunks()
	_drain_chunk_queue()

func get_chunk_size() -> Vector2i:
	return chunk_size

func get_tile_size() -> Vector2i:
	return _tile_size

func get_chunk_world_size() -> Vector2:
	return _chunk_world_size

func get_playable_radius_world() -> Vector2:
	return _playable_radius_world

func get_playable_radius_chunks() -> int:
	return _get_playable_radius_chunks()

func get_noise() -> SimpleNoise2D:
	return _noise

func get_upper_threshold() -> float:
	return upper_threshold

func has_initial_chunks_ready() -> bool:
	return _initial_chunks_ready

func _refresh_cached_metrics() -> void:
	_chunk_world_size = Vector2(
		float(chunk_size.x) * float(_tile_size.x),
		float(chunk_size.y) * float(_tile_size.y)
	)
	var playable_radius_chunks: int = _get_playable_radius_chunks()
	_playable_radius_world = Vector2(
		float(playable_radius_chunks) * _chunk_world_size.x,
		float(playable_radius_chunks) * _chunk_world_size.y
	)


func _validate_chunk_settings() -> void:
	# Ensure we keep at least one extra ring so chunks don't thrash in/out while moving.
	if chunk_limit < chunk_radius + CHUNK_LIMIT_PADDING:
		chunk_limit = chunk_radius + CHUNK_LIMIT_PADDING
	if border_thickness_chunks < 0:
		border_thickness_chunks = 0
	if world_radius_chunks > WORLD_LIMIT_DISABLED and border_thickness_chunks >= world_radius_chunks:
		# Keep at least one playable chunk inside the border.
		border_thickness_chunks = max(world_radius_chunks - 1, 0)

func is_world_position_within_limit(world_pos: Vector2) -> bool:
	if world_radius_chunks <= WORLD_LIMIT_DISABLED:
		return true
	return abs(world_pos.x) <= _playable_radius_world.x and abs(world_pos.y) <= _playable_radius_world.y

func is_world_position_in_upper_terrain(world_pos: Vector2) -> bool:
	if _noise == null or _chunk_world_size == Vector2.ZERO:
		return false
	var local_x: float = world_pos.x / float(_tile_size.x)
	var local_y: float = world_pos.y / float(_tile_size.y)
	var tile_x: int = int(floor(local_x))
	var tile_y: int = int(floor(local_y))
	if _is_chunk_in_border_ring(_world_to_chunk(world_pos)):
		return true
	var nw: String = _corner_type(_noise, tile_x, tile_y)
	var ne: String = _corner_type(_noise, tile_x + 1, tile_y)
	var sw: String = _corner_type(_noise, tile_x, tile_y + 1)
	var se: String = _corner_type(_noise, tile_x + 1, tile_y + 1)
	return nw == "upper" or ne == "upper" or sw == "upper" or se == "upper"

func _init_floor() -> void:
	if _floor_base == null or _floor_detail == null:
		_finish_boot_fallback("Missing floor layers")
		return
	var tileset: TileSet = _create_floor_tileset()
	if tileset == null:
		_finish_boot_fallback("Failed to create floor tileset")
		return
	_floor_base.tile_set = tileset
	_floor_detail.tile_set = tileset

	_base_source_id = -1
	_detail_source_id = -1
	if tileset.get_source_count() > 0:
		_base_source_id = tileset.get_source_id(0)
	if use_detail_layer and tileset.get_source_count() > 1:
		_detail_source_id = tileset.get_source_id(1)
	if _base_source_id == -1:
		_finish_boot_fallback("Missing floor base source")
		return

	if use_detail_layer:
		_atlas = tileset.get_source(_detail_source_id) as TileSetAtlasSource
	else:
		_atlas = tileset.get_source(_base_source_id) as TileSetAtlasSource
	if _atlas == null:
		_finish_boot_fallback("Missing floor atlas source")
		return

	_mapping = _load_tileset_mapping()
	_base_coords = _mapping.get("BASE", _mapping.get(ALL_LOWER_KEY, Vector2i.ZERO))
	_border_coords = _mapping.get(ALL_UPPER_KEY, _base_coords)
	if _mapping.has("BASE_OVERRIDE"):
		_base_coords = _mapping["BASE_OVERRIDE"]

	_tile_size = tileset.tile_size
	_validate_chunk_settings()
	_refresh_cached_metrics()

	_noise = SimpleNoise2D.new()
	_noise.seed = randi()
	_noise.frequency = noise_frequency

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
	if generate_initial_chunks_immediately:
		_generate_initial_chunks()
		_mark_initial_chunks_ready()
	else:
		_update_floor_chunks()

func _update_floor_chunks() -> void:
	if _player == null:
		return
	var chunk: Vector2i = _world_to_chunk(_player.global_position)
	if chunk == _last_chunk:
		return
	_last_chunk = chunk
	for y in range(chunk.y - chunk_radius, chunk.y + chunk_radius + 1):
		for x in range(chunk.x - chunk_radius, chunk.x + chunk_radius + 1):
			var c: Vector2i = Vector2i(x, y)
			if not _is_chunk_within_world_limit(c):
				continue
			_cancel_chunk_clear(c)
			if not _generated_chunks.has(c):
				_queue_chunk_generation(c)
	_prune_chunks(chunk)

func _generate_initial_chunks() -> void:
	if _player == null:
		return
	var center_chunk: Vector2i = _world_to_chunk(_player.global_position)
	_last_chunk = center_chunk
	for y in range(center_chunk.y - chunk_radius, center_chunk.y + chunk_radius + 1):
		for x in range(center_chunk.x - chunk_radius, center_chunk.x + chunk_radius + 1):
			var chunk: Vector2i = Vector2i(x, y)
			if not _is_chunk_within_world_limit(chunk):
				continue
			if _generated_chunks.has(chunk):
				continue
			_generate_chunk(chunk)
	_prune_chunks(center_chunk)

func _generate_chunk(chunk: Vector2i) -> void:
	if _base_source_id == -1:
		return
	var job: Dictionary = _create_chunk_job(chunk)
	if job.is_empty():
		return
	while int(job.get("row_index", 0)) < chunk_size.y:
		_generate_chunk_row(job)
	_finalize_chunk_job(job)

func _create_chunk_job(chunk: Vector2i) -> Dictionary:
	if _base_source_id == -1:
		return {}
	var is_border_chunk: bool = _is_chunk_in_border_ring(chunk)
	var start_x: int = chunk.x * chunk_size.x
	var start_y: int = chunk.y * chunk_size.y
	var corner_types: Array = _build_corner_type_grid(start_x, start_y)
	return {
		"chunk": chunk,
		"is_border_chunk": is_border_chunk,
		"start_x": start_x,
		"start_y": start_y,
		"corner_types": corner_types,
		"row_index": 0
	}

func _generate_chunk_row(job: Dictionary) -> void:
	var start_x: int = int(job.get("start_x", 0))
	var start_y: int = int(job.get("start_y", 0))
	var row_index: int = int(job.get("row_index", 0))
	var y: int = start_y + row_index
	var is_border_chunk: bool = bool(job.get("is_border_chunk", false))
	var corner_types: Array = job.get("corner_types", [])
	for x in range(start_x, start_x + chunk_size.x):
		var base_coords: Vector2i = _base_coords
		var coords: Vector2i = _base_coords
		var has_upper: bool = false
		if is_border_chunk:
			coords = _border_coords
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
			coords = _mapping.get(key, _base_coords)
		if _atlas != null and not _atlas.has_tile(coords):
			coords = _base_coords
		if use_detail_layer:
			_floor_base.set_cell(Vector2i(x, y), _base_source_id, base_coords)
			if has_upper:
				_floor_detail.set_cell(Vector2i(x, y), _detail_source_id, coords)
			else:
				_floor_detail.erase_cell(Vector2i(x, y))
		else:
			_floor_base.set_cell(Vector2i(x, y), _base_source_id, coords)
			_floor_detail.erase_cell(Vector2i(x, y))
	job["row_index"] = row_index + 1

func _finalize_chunk_job(job: Dictionary) -> void:
	var chunk: Vector2i = job.get("chunk", INVALID_CHUNK)
	if chunk == INVALID_CHUNK:
		return
	_generated_chunks[chunk] = true
	chunk_generated.emit(chunk)

func _prune_chunks(center: Vector2i) -> void:
	var to_remove: Array[Vector2i] = []
	for key in _generated_chunks.keys():
		var chunk: Vector2i = key
		var dx: int = abs(chunk.x - center.x)
		var dy: int = abs(chunk.y - center.y)
		if max(dx, dy) > chunk_limit:
			to_remove.append(chunk)
	for chunk in to_remove:
		_queue_chunk_clear(chunk)

func _queue_chunk_generation(chunk: Vector2i) -> void:
	if _generated_chunks.has(chunk) or _queued_chunk_lookup.has(chunk):
		return
	_queued_chunks.append(chunk)
	_queued_chunk_lookup[chunk] = true

func _drain_chunk_queue() -> void:
	var budget: int = max(max_chunk_rows_generated_per_frame, 1)
	if budget <= 0:
		return
	while budget > 0:
		if _active_chunk_job.is_empty():
			if _queued_chunks.is_empty():
				break
			var chunk: Vector2i = _queued_chunks.pop_front()
			_queued_chunk_lookup.erase(chunk)
			if _generated_chunks.has(chunk):
				continue
			_active_chunk_job = _create_chunk_job(chunk)
			if _active_chunk_job.is_empty():
				continue
		_generate_chunk_row(_active_chunk_job)
		budget -= 1
		if int(_active_chunk_job.get("row_index", 0)) >= chunk_size.y:
			_finalize_chunk_job(_active_chunk_job)
			_active_chunk_job.clear()
	if not _initial_chunks_ready and _active_chunk_job.is_empty() and _queued_chunks.is_empty():
		_mark_initial_chunks_ready()
	_drain_chunk_clear_queue()

func _clear_chunk(chunk: Vector2i) -> void:
	var job: Dictionary = _create_chunk_clear_job(chunk)
	if job.is_empty():
		return
	while int(job.get("row_index", 0)) < chunk_size.y:
		_clear_chunk_row(job)
	_finalize_chunk_clear_job(job)

func _create_chunk_clear_job(chunk: Vector2i) -> Dictionary:
	var start_x: int = chunk.x * chunk_size.x
	var start_y: int = chunk.y * chunk_size.y
	return {
		"chunk": chunk,
		"start_x": start_x,
		"start_y": start_y,
		"row_index": 0,
		"regenerate": false
	}

func _clear_chunk_row(job: Dictionary) -> void:
	var start_x: int = int(job.get("start_x", 0))
	var start_y: int = int(job.get("start_y", 0))
	var row_index: int = int(job.get("row_index", 0))
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

func _queue_chunk_clear(chunk: Vector2i) -> void:
	if _queued_clear_lookup.has(chunk):
		return
	if _active_clear_job.get("chunk", INVALID_CHUNK) == chunk:
		return
	_queued_clear_chunks.append(chunk)
	_queued_clear_lookup[chunk] = true

func _drain_chunk_clear_queue() -> void:
	var budget: int = max(max_chunk_rows_cleared_per_frame, 1)
	if budget <= 0:
		return
	while budget > 0:
		if _active_clear_job.is_empty():
			if _queued_clear_chunks.is_empty():
				return
			var chunk: Vector2i = _queued_clear_chunks.pop_front()
			_queued_clear_lookup.erase(chunk)
			if not _generated_chunks.has(chunk):
				continue
			_active_clear_job = _create_chunk_clear_job(chunk)
			if _active_clear_job.is_empty():
				continue
		_clear_chunk_row(_active_clear_job)
		budget -= 1
		if int(_active_clear_job.get("row_index", 0)) >= chunk_size.y:
			_finalize_chunk_clear_job(_active_clear_job)
			_active_clear_job.clear()

func _cancel_chunk_clear(chunk: Vector2i) -> void:
	if _queued_clear_lookup.has(chunk):
		_queued_clear_lookup.erase(chunk)
		_queued_clear_chunks.erase(chunk)
		return
	if _active_clear_job.get("chunk", INVALID_CHUNK) == chunk:
		_active_clear_job["regenerate"] = true

func _corner_type(noise: SimpleNoise2D, x: int, y: int) -> String:
	var value: float = _smoothed_noise(noise, x, y)
	return "upper" if value > upper_threshold else "lower"

func _smoothed_noise(noise: SimpleNoise2D, x: int, y: int) -> float:
	if noise_smoothing_radius <= 0:
		return noise.get_noise_2d(float(x), float(y))
	var sum: float = 0.0
	var count: int = 0
	for oy in range(-noise_smoothing_radius, noise_smoothing_radius + 1):
		for ox in range(-noise_smoothing_radius, noise_smoothing_radius + 1):
			sum += noise.get_noise_2d(float(x + ox), float(y + oy))
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
	return max(abs(chunk.x), abs(chunk.y)) <= world_radius_chunks

func _is_chunk_in_border_ring(chunk: Vector2i) -> bool:
	if not use_border_ring:
		return false
	if world_radius_chunks <= WORLD_LIMIT_DISABLED:
		return false
	if border_thickness_chunks <= 0:
		return false
	var distance: int = max(abs(chunk.x), abs(chunk.y))
	var inner_radius: int = max(world_radius_chunks - border_thickness_chunks, 0)
	return distance > inner_radius and distance <= world_radius_chunks

func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	var cx: int = int(floor(world_pos.x / _chunk_world_size.x))
	var cy: int = int(floor(world_pos.y / _chunk_world_size.y))
	return Vector2i(cx, cy)

func _build_corner_type_grid(start_x: int, start_y: int) -> Array:
	# Cache corner classifications so each noise point is evaluated once per chunk.
	var grid_width: int = chunk_size.x + 1
	var grid_height: int = chunk_size.y + 1
	var grid: Array = []
	grid.resize(grid_width)
	for gx in range(grid_width):
		var column: Array = []
		column.resize(grid_height)
		for gy in range(grid_height):
			column[gy] = _corner_type(_noise, start_x + gx, start_y + gy)
		grid[gx] = column
	return grid

func _load_tileset_mapping() -> Dictionary:
	var mapping: Dictionary = {}
	var path: String = "res://data/arena_tileset.json"
	if not FileAccess.file_exists(path):
		return mapping
	var json_text: String = FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed is Dictionary:
		var data: Dictionary = parsed
		if data.has("tileset"):
			var tileset_data: Dictionary = data["tileset"]
			if tileset_data.has("tiles"):
				var tiles: Array = tileset_data["tiles"]
				for tile_data in tiles:
					if tile_data is Dictionary:
						var tile: Dictionary = tile_data
						if tile.has("corners") and tile.has("original_position"):
							var corners: Dictionary = tile["corners"]
							var pos: Dictionary = tile["original_position"]
							var key: String = "%s|%s|%s|%s" % [
								corners.get("NW", "lower"),
								corners.get("NE", "lower"),
								corners.get("SW", "lower"),
								corners.get("SE", "lower")
							]
							mapping[key] = Vector2i(
								int(pos.get("col", 0)),
								int(pos.get("row", 0))
							)
							if corners.get("NW") == "lower" and corners.get("NE") == "lower" and corners.get("SW") == "lower" and corners.get("SE") == "lower":
								mapping["BASE"] = mapping[key]
			if tileset_data.has("base_override"):
				var override_data: Dictionary = tileset_data["base_override"]
				mapping["BASE_OVERRIDE"] = Vector2i(
					int(override_data.get("col", 0)),
					int(override_data.get("row", 0))
				)
	return mapping

func _create_floor_tileset() -> TileSet:
	var base_tex: Texture2D = null
	var detail_tex: Texture2D = null
	if use_detail_layer:
		# Use AssetRegistry to keep tileset paths centralized.
		base_tex = AssetRegistry.get_tileset_texture("floor_base")
		detail_tex = AssetRegistry.get_tileset_texture("floor_detail")
	else:
		base_tex = AssetRegistry.get_tileset_texture("floor_wang")
	if base_tex == null:
		return null
	if use_detail_layer and detail_tex == null:
		return null
	var tileset: TileSet = TileSet.new()
	tileset.tile_size = DEFAULT_TILE_SIZE
	var base_atlas: TileSetAtlasSource = TileSetAtlasSource.new()
	base_atlas.texture = base_tex
	base_atlas.texture_region_size = tileset.tile_size
	base_atlas.create_tile(Vector2i.ZERO, Vector2i.ONE)
	tileset.add_source(base_atlas)

	if use_detail_layer:
		var detail_atlas: TileSetAtlasSource = TileSetAtlasSource.new()
		detail_atlas.texture = detail_tex
		detail_atlas.texture_region_size = tileset.tile_size
		var atlas_size: Vector2i = Vector2i(
			int(float(detail_tex.get_width()) / float(tileset.tile_size.x)),
			int(float(detail_tex.get_height()) / float(tileset.tile_size.y))
		)
		for y in range(atlas_size.y):
			for x in range(atlas_size.x):
				detail_atlas.create_tile(Vector2i(x, y), Vector2i.ONE)
		tileset.add_source(detail_atlas)
	return tileset

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
	if CustomLogger != null and CustomLogger.has_method("warn"):
		CustomLogger.warn("FloorGenerator boot fallback: %s" % reason, "Floor")
	_mark_initial_chunks_ready()
