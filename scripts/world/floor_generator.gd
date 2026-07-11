class_name FloorGenerator
extends Node
##
## Streams floor tiles around the player.
##
## Base layer: land floor variants (grass / dirt decor) picked by cell hash.
## Detail layer: cell-based water regions rendered with a 47-tile blob
## autotile (32rogues watertiles; mask table verified against the pack's
## Tiled wang set). Full-water cells use an animated wave tile.
##
## Both TileMapLayer nodes MUST have `tile_set` assigned in the editor
## (res://resources/tilesets/floor_tileset.tres). Source 0 = base floor
## variants (7 tiles in one row). Source 1 = water blob atlas.
##
## `is_cell_water()` is the single terrain predicate shared by rendering,
## movement slowdown, and prop placement: a noise-water cell with no
## edge-adjacent water is normalized to land (the blob set has no
## isolated-puddle tile). That normalization is closed: any remaining
## water cell keeps at least one water edge neighbor, so its blob mask
## is never 0.
##

signal chunk_generated(chunk: Vector2i)
signal chunk_cleared(chunk: Vector2i)
signal initial_chunks_ready

const DEFAULT_CHUNK_SIZE: Vector2i = Vector2i(64, 64)
const DEFAULT_TILE_SIZE: Vector2i = Vector2i(32, 32)
const BASE_SOURCE_INDEX: int = 0
const WATER_SOURCE_INDEX: int = 1
const WORLD_LIMIT_DISABLED: int = 0
const INVALID_CHUNK: Vector2i = Vector2i(1_000_000, 1_000_000)
const CHUNK_LIMIT_PADDING: int = 1
const FLOOR_BASE_Z_INDEX: int = -30
const FLOOR_DETAIL_Z_INDEX: int = -20

## Base floor variants (atlas x in source 0): blank, dirt 1-3, grass 1-3.
const BASE_BLANK: Vector2i = Vector2i(0, 0)
const BASE_DECOR: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0),
	Vector2i(4, 0), Vector2i(5, 0), Vector2i(6, 0),
]
## Rocky biome patches (second noise channel) use these tiles instead.
const STONE_BLANK: Vector2i = Vector2i(7, 0)
const STONE_DECOR: Array[Vector2i] = [
	Vector2i(8, 0), Vector2i(9, 0), Vector2i(10, 0),
]
const STONE_ZONE_THRESHOLD: float = 0.3
## Fraction of land cells that get a decor variant instead of blank floor.
const BASE_DECOR_CHANCE: float = 0.16

## Blob mask -> water atlas coords. Bits: N=1, NE=2, E=4, SE=8, S=16,
## SW=32, W=64, NW=128; corner bits only count when both adjacent edge
## bits are set. Full water (255) is the animated wave tile.
const WATER_TILES: Dictionary = {
	1: Vector2i(0, 3),
	4: Vector2i(1, 3),
	5: Vector2i(1, 2),
	7: Vector2i(8, 3),
	16: Vector2i(0, 0),
	17: Vector2i(0, 1),
	20: Vector2i(1, 0),
	21: Vector2i(1, 1),
	23: Vector2i(4, 2),
	28: Vector2i(8, 0),
	29: Vector2i(4, 1),
	31: Vector2i(8, 1),
	64: Vector2i(3, 3),
	65: Vector2i(3, 2),
	68: Vector2i(2, 3),
	69: Vector2i(2, 2),
	71: Vector2i(5, 3),
	80: Vector2i(3, 0),
	81: Vector2i(3, 1),
	84: Vector2i(2, 0),
	85: Vector2i(2, 1),
	87: Vector2i(7, 0),
	92: Vector2i(5, 0),
	93: Vector2i(7, 3),
	95: Vector2i(8, 2),
	112: Vector2i(11, 0),
	113: Vector2i(7, 1),
	116: Vector2i(6, 0),
	117: Vector2i(4, 3),
	119: Vector2i(9, 1),
	124: Vector2i(10, 0),
	125: Vector2i(9, 0),
	127: Vector2i(5, 1),
	193: Vector2i(11, 3),
	197: Vector2i(6, 3),
	199: Vector2i(9, 3),
	209: Vector2i(7, 2),
	213: Vector2i(4, 0),
	215: Vector2i(10, 3),
	221: Vector2i(10, 2),
	223: Vector2i(5, 2),
	241: Vector2i(11, 2),
	245: Vector2i(11, 1),
	247: Vector2i(6, 2),
	253: Vector2i(6, 1),
	255: Vector2i(0, 4),
}


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
## Guaranteed-land radius around the spawn point; the clearing fades out
## through noise up to twice this radius, keeping the shoreline organic.
@export var spawn_clearing_radius_tiles: int = 10
@export var generate_initial_chunks_immediately: bool = true
@export var max_chunk_rows_generated_per_frame: int = 8
@export var max_chunk_rows_cleared_per_frame: int = 12

var _player: Node2D
var _floor_base: TileMapLayer
var _floor_detail: TileMapLayer
var _noise: SimpleNoise2D
var _zone_noise: SimpleNoise2D
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


func get_generated_chunks() -> Array:
	return _generated_chunks.keys()


func is_world_position_within_limit(world_pos: Vector2) -> bool:
	if world_radius_chunks <= WORLD_LIMIT_DISABLED:
		return true
	return absf(world_pos.x) <= _playable_radius_world.x and absf(world_pos.y) <= _playable_radius_world.y


func is_world_position_in_upper_terrain(world_pos: Vector2) -> bool:
	if _noise == null or _chunk_world_size == Vector2.ZERO:
		return false
	var cell: Vector2i = Vector2i(
		int(floor(world_pos.x / float(_tile_size.x))),
		int(floor(world_pos.y / float(_tile_size.y)))
	)
	return is_cell_water(cell.x, cell.y)


## Single terrain predicate shared by rendering, movement, and props.
func is_cell_water(x: int, y: int) -> bool:
	if _noise == null:
		return false
	if not _raw_water(x, y):
		return false
	return _raw_water(x, y - 1) or _raw_water(x + 1, y) or _raw_water(x, y + 1) or _raw_water(x - 1, y)


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
	_tile_size = tileset.tile_size
	_validate_chunk_settings()
	_refresh_cached_metrics()
	_noise = SimpleNoise2D.new()
	_noise.noise_seed = randi()
	_noise.frequency = noise_frequency
	_zone_noise = SimpleNoise2D.new()
	_zone_noise.noise_seed = _noise.noise_seed + 977
	_zone_noise.frequency = noise_frequency * 0.45
	_reset_streaming_state()
	if generate_initial_chunks_immediately:
		_generate_initial_chunks()
		_mark_initial_chunks_ready()
	else:
		_update_floor_chunks()


func _verify_sources(tileset: TileSet) -> bool:
	if tileset.get_source_count() < 2:
		_finish_boot_fallback("Floor tileset needs 2 sources (base + water)")
		return false
	var base_source: TileSetSource = tileset.get_source(BASE_SOURCE_INDEX)
	var water_source: TileSetSource = tileset.get_source(WATER_SOURCE_INDEX)
	if base_source == null or water_source == null:
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
		"start_x": start_x,
		"start_y": start_y,
		"raw_water": _build_raw_water_grid(start_x, start_y),
		"row_index": 0
	}


## Raw water cached for the chunk plus a 2-cell margin: normalization needs
## direct neighbors, and each cell's blob mask needs its neighbors' own
## normalized state (neighbors-of-neighbors).
func _build_raw_water_grid(start_x: int, start_y: int) -> Array:
	var width: int = chunk_size.x + 4
	var height: int = chunk_size.y + 4
	var grid: Array = []
	grid.resize(width)
	for gx in range(width):
		var column: Array = []
		column.resize(height)
		for gy in range(height):
			column[gy] = _raw_water(start_x + gx - 2, start_y + gy - 2)
		grid[gx] = column
	return grid


func _generate_chunk_row(job: Dictionary) -> void:
	var start_x: int = int(job["start_x"])
	var start_y: int = int(job["start_y"])
	var row_index: int = int(job["row_index"])
	var y: int = start_y + row_index
	var grid: Array = job["raw_water"]
	for x in range(start_x, start_x + chunk_size.x):
		var local_x: int = x - start_x
		_floor_base.set_cell(Vector2i(x, y), BASE_SOURCE_INDEX, _base_variant(x, y))
		if not use_detail_layer:
			continue
		if not _grid_water(grid, local_x, row_index):
			_floor_detail.erase_cell(Vector2i(x, y))
			continue
		var mask: int = _blob_mask(grid, local_x, row_index)
		if mask == 0:
			_floor_detail.erase_cell(Vector2i(x, y))
			continue
		_floor_detail.set_cell(Vector2i(x, y), WATER_SOURCE_INDEX, WATER_TILES.get(mask, WATER_TILES[255]))
	job["row_index"] = row_index + 1


## Normalized water lookup in grid space (local chunk coords; margin 2).
func _grid_water(grid: Array, local_x: int, local_y: int) -> bool:
	var gx: int = local_x + 2
	var gy: int = local_y + 2
	if not grid[gx][gy]:
		return false
	return grid[gx][gy - 1] or grid[gx + 1][gy] or grid[gx][gy + 1] or grid[gx - 1][gy]


func _blob_mask(grid: Array, local_x: int, local_y: int) -> int:
	var n: bool = _grid_water(grid, local_x, local_y - 1)
	var e: bool = _grid_water(grid, local_x + 1, local_y)
	var s: bool = _grid_water(grid, local_x, local_y + 1)
	var w: bool = _grid_water(grid, local_x - 1, local_y)
	var mask: int = 0
	if n: mask |= 1
	if e: mask |= 4
	if s: mask |= 16
	if w: mask |= 64
	if n and e and _grid_water(grid, local_x + 1, local_y - 1): mask |= 2
	if s and e and _grid_water(grid, local_x + 1, local_y + 1): mask |= 8
	if s and w and _grid_water(grid, local_x - 1, local_y + 1): mask |= 32
	if n and w and _grid_water(grid, local_x - 1, local_y - 1): mask |= 128
	return mask


func _base_variant(x: int, y: int) -> Vector2i:
	var stony: bool = _zone_noise.get_noise_2d(float(x), float(y)) > STONE_ZONE_THRESHOLD
	var hash_value: int = _cell_hash(x, y)
	if float(hash_value & 0xffff) / 65535.0 >= BASE_DECOR_CHANCE:
		return STONE_BLANK if stony else BASE_BLANK
	if stony:
		return STONE_DECOR[(hash_value >> 16) % STONE_DECOR.size()]
	return BASE_DECOR[(hash_value >> 16) % BASE_DECOR.size()]


func _cell_hash(x: int, y: int) -> int:
	var value: int = x * 374761393 + y * 668265263 + _noise.noise_seed * 974634599
	value = int((value ^ (value >> 13)) * 1274126177)
	return (value ^ (value >> 16)) & 0x7fffffff


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

## Raw water predicate before isolation normalization: forced water outside
## the playable area and in the border ring; near the spawn point the noise
## is biased toward land so the player never spawns in a lake.
func _raw_water(x: int, y: int) -> bool:
	var chunk: Vector2i = Vector2i(
		int(floor(float(x) / float(chunk_size.x))),
		int(floor(float(y) / float(chunk_size.y)))
	)
	if not _is_chunk_within_world_limit(chunk):
		return true
	if _is_chunk_in_border_ring(chunk):
		return true
	return _smoothed_noise(x, y) - _spawn_clearing_bias(x, y) > upper_threshold


## Land bias near the spawn point: guaranteed inside the clearing radius,
## fading smoothly to zero at twice the radius so the shoreline stays
## noise-shaped instead of a hard square/circle.
func _spawn_clearing_bias(x: int, y: int) -> float:
	if spawn_clearing_radius_tiles <= 0:
		return 0.0
	var radius: float = float(spawn_clearing_radius_tiles)
	var distance: float = sqrt(float(x * x + y * y))
	if distance >= radius * 2.0:
		return 0.0
	if distance <= radius:
		return 2.0
	var t: float = (distance - radius) / radius
	return 2.0 * (1.0 - t * t * (3.0 - 2.0 * t))


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


## A chunk is land iff both axes fall in the half-open range
## [-inner, inner): land then spans exactly [-inner*chunk, +inner*chunk)
## in world space, matching `_playable_radius_world` on all four sides.
## (A symmetric closed range would leave a chunk of unreachable land past
## the east/south clamp edge because chunk indices come from floor().)
func _is_chunk_in_border_ring(chunk: Vector2i) -> bool:
	if not use_border_ring or world_radius_chunks <= WORLD_LIMIT_DISABLED or border_thickness_chunks <= 0:
		return false
	if not _is_chunk_within_world_limit(chunk):
		return false
	var inner: int = max(world_radius_chunks - border_thickness_chunks, 0)
	var land: bool = (chunk.x >= -inner and chunk.x < inner
		and chunk.y >= -inner and chunk.y < inner)
	return not land


func _world_to_chunk(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / _chunk_world_size.x)),
		int(floor(world_pos.y / _chunk_world_size.y))
	)


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
