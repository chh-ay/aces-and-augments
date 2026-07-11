extends Node
##
## Headless checks for the rectangular arena cutover: clamp/inside math,
## all four corners reachable and made of land-capable chunks, outward
## velocity removed (tangential kept) at edges and corners, spawn
## validation accepting the corners, and camera limits sized so the
## shoreline peek can never reveal unloaded void.
## Run: godot --headless --path . res://tests/arena_bounds_test.tscn
##

var _failures: int = 0


func _ready() -> void:
	var main_scene: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main_scene)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var arena: Arena = main_scene.get_node("Arena") as Arena
	var floor_generator: FloorGenerator = main_scene.get_node("FloorGenerator") as FloorGenerator
	var player: PlayerController = main_scene.get_node("Player") as PlayerController
	var spawner: EnemySpawner = main_scene.get_node("EnemySpawner") as EnemySpawner

	_check_bounds_sync(arena, floor_generator)
	_check_rect_math(arena)
	_check_corner_chunks_are_land(floor_generator)
	_check_player_clamp_and_slide(arena, player)
	_check_spawn_validation(spawner, arena)
	_check_camera_limits(player, arena, floor_generator)

	print("---")
	print("FAILED %d checks" % _failures if _failures > 0 else "ALL CHECKS PASSED")
	get_tree().quit(1 if _failures > 0 else 0)


func _check_bounds_sync(arena: Arena, floor_generator: FloorGenerator) -> void:
	_check(arena.half_extents == floor_generator.get_playable_radius_world(),
		"arena bounds synced from floor generator (%s)" % arena.half_extents)


func _check_rect_math(arena: Arena) -> void:
	var inside_all: bool = true
	var outside_all: bool = true
	for corner_sign in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		inside_all = inside_all and arena.is_world_position_inside(corner_sign * 4000.0)
		outside_all = outside_all and not arena.is_world_position_inside(corner_sign * 4200.0)
	_check(inside_all, "all four corners inside at 4000")
	_check(outside_all, "all four corners outside at 4200")
	_check(arena.clamp_world_position(Vector2(9000, 9000), 20.0) == Vector2(4076, 4076),
		"clamp reaches the corner")


## The fixed half-open land predicate: land chunks are [-inner, inner) on
## both axes, so the shoreline sits exactly on the clamp rect everywhere.
func _check_corner_chunks_are_land(floor_generator: FloorGenerator) -> void:
	var land_ok: bool = true
	for chunk in [Vector2i(1, 1), Vector2i(-2, -2), Vector2i(1, -2), Vector2i(-2, 1)]:
		land_ok = land_ok and not floor_generator._is_chunk_in_border_ring(chunk)
	_check(land_ok, "innermost corner chunks are land")
	var water_ok: bool = true
	for chunk in [Vector2i(2, 2), Vector2i(2, 0), Vector2i(0, 2), Vector2i(-3, 0), Vector2i(0, -3)]:
		water_ok = water_ok and floor_generator._is_chunk_in_border_ring(chunk)
	_check(water_ok, "first out-of-bounds chunks are shoreline water")


func _check_player_clamp_and_slide(arena: Arena, player: PlayerController) -> void:
	var corners_ok: bool = true
	for corner_sign in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		player.global_position = corner_sign * 9000.0
		player.velocity = Vector2.ZERO
		player._clamp_to_arena()
		corners_ok = corners_ok and arena.is_world_position_inside(player.global_position) \
			and player.global_position.distance_to(corner_sign * 4076.0) < 64.0
	_check(corners_ok, "player clamp reaches all four corners")

	# East edge: outward x removed, tangential y kept.
	player.global_position = Vector2(9000.0, 0.0)
	player.velocity = Vector2(100.0, 50.0)
	player._clamp_to_arena()
	_check(absf(player.velocity.x) < 0.01 and absf(player.velocity.y - 50.0) < 0.01,
		"edge slide keeps tangential velocity (%s)" % player.velocity)

	# Corner: fully outward velocity removed entirely.
	player.global_position = Vector2(9000.0, 9000.0)
	player.velocity = Vector2(100.0, 100.0)
	player._clamp_to_arena()
	_check(player.velocity.length() < 0.01,
		"corner slide removes outward velocity (%s)" % player.velocity)

	# Corner: tangential velocity untouched.
	player.global_position = Vector2(9000.0, 9000.0)
	player.velocity = Vector2(100.0, -100.0)
	player._clamp_to_arena()
	_check(player.velocity.distance_to(Vector2(100.0, -100.0)) < 0.01,
		"corner slide keeps tangential velocity (%s)" % player.velocity)
	player.global_position = Vector2.ZERO
	player.velocity = Vector2.ZERO


func _check_spawn_validation(spawner: EnemySpawner, arena: Arena) -> void:
	var corner: Vector2 = arena.get_half_extents(28.0) - Vector2(10.0, 10.0)
	_check(spawner._is_valid_spawn_position(corner),
		"enemy spawn validation accepts the corner")
	_check(not spawner._is_valid_spawn_position(arena.half_extents + Vector2(100.0, 100.0)),
		"enemy spawn validation rejects beyond the rect")


func _check_camera_limits(player: PlayerController, arena: Arena, floor_generator: FloorGenerator) -> void:
	var camera: Camera2D = player.get_node("Camera2D") as Camera2D
	var expected: int = int(arena.half_extents.x + player.camera_shore_peek)
	_check(camera.limit_right == expected and camera.limit_left == -expected
		and camera.limit_bottom == expected and camera.limit_top == -expected,
		"camera limits = playable rect + shore peek (%d)" % expected)
	var ring_width: float = float(floor_generator.border_thickness_chunks) \
		* floor_generator.get_chunk_world_size().x
	_check(player.camera_shore_peek < ring_width,
		"shore peek (%.0f) well inside water ring (%.0f) - void never visible"
		% [player.camera_shore_peek, ring_width])
	var dim: Polygon2D = arena.get_node("OutOfBoundsDim") as Polygon2D
	_check(dim != null and dim.invert_enabled
		and dim.polygon.size() == 4 and Vector2(dim.polygon[2]) == arena.half_extents
		and dim.invert_border >= player.camera_shore_peek + 1024.0,
		"out-of-bounds dim covers the visible strip beyond the rect")


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)
