class_name Arena
extends Node2D
##
## Rectangular playable bounds, synced from the floor generator's playable
## area so the forced-water border ring is the visible boundary (the
## shoreline IS the wall). Every movement and spawn clamp flows through
## here; the camera limits in PlayerController use the same rect.
##

@export var floor_generator_path: NodePath
## Half extents of the playable rectangle. Overridden at runtime by the
## floor generator's playable area when one is wired up.
@export var half_extents: Vector2 = Vector2(4_096.0, 4_096.0)
## Debug outline of the exact clamp rect (the shoreline communicates the
## boundary in normal play).
@export var show_boundary_line: bool = false
@export var line_width: float = 24.0
@export var line_color: Color = Color(1.0, 0.78, 0.2, 0.95)
## Dim tint over everything beyond the clamp rect, so out-of-bounds ocean
## reads distinctly from in-bounds lakes. Purely visual.
@export var out_of_bounds_tint: Color = Color(0.01, 0.02, 0.05, 0.45)
## How far past the rect the dim extends; MUST cover the camera shore
## peek plus the widest view overhang (border ring is 4096 px, so 4096
## keeps the whole visible strip tinted).
@export var out_of_bounds_dim_extent: float = 4_096.0

@onready var boundary_line: Line2D = $BoundaryLine
@onready var out_of_bounds_dim: Polygon2D = $OutOfBoundsDim


func _ready() -> void:
	RunContext.register_arena(self)
	_sync_bounds_from_floor_generator()
	_update_boundary()


func _exit_tree() -> void:
	RunContext.unregister_arena(self)


func get_half_extents(margin: float = 0.0) -> Vector2:
	return Vector2(maxf(half_extents.x - margin, 0.0), maxf(half_extents.y - margin, 0.0))


func is_world_position_inside(world_position: Vector2, margin: float = 0.0) -> bool:
	var offset: Vector2 = world_position - global_position
	var inner: Vector2 = get_half_extents(margin)
	return absf(offset.x) <= inner.x and absf(offset.y) <= inner.y


func clamp_world_position(world_position: Vector2, margin: float = 0.0) -> Vector2:
	var offset: Vector2 = world_position - global_position
	var inner: Vector2 = get_half_extents(margin)
	return global_position + Vector2(
		clampf(offset.x, -inner.x, inner.x),
		clampf(offset.y, -inner.y, inner.y)
	)


func _update_boundary() -> void:
	if out_of_bounds_dim != null:
		var rect_points: PackedVector2Array = PackedVector2Array()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			rect_points.append(corner * half_extents)
		out_of_bounds_dim.polygon = rect_points
		out_of_bounds_dim.color = out_of_bounds_tint
		out_of_bounds_dim.invert_enabled = true
		out_of_bounds_dim.invert_border = out_of_bounds_dim_extent
	if boundary_line == null:
		return
	boundary_line.visible = show_boundary_line
	if not show_boundary_line:
		return
	boundary_line.width = line_width
	boundary_line.default_color = line_color
	boundary_line.closed = true
	boundary_line.clear_points()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		boundary_line.add_point(corner * half_extents)


func _sync_bounds_from_floor_generator() -> void:
	var floor_generator: FloorGenerator = get_node_or_null(floor_generator_path) as FloorGenerator
	if floor_generator == null:
		return
	var playable: Vector2 = floor_generator.get_playable_radius_world()
	if playable != Vector2.ZERO:
		half_extents = playable
