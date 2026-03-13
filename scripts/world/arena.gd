class_name Arena
extends Node2D

@export var floor_generator_path: NodePath
@export var radius: float = 14_336.0
@export var segments: int = 64
@export var line_width: float = 24.0
@export var line_color: Color = Color(1.0, 0.78, 0.2, 0.95)
@export var fill_color: Color = Color(0.09, 0.10, 0.12, 0.92)
@export var enable_fog_mask: bool = false
@export var edge_softness: float = 384.0
@export var fog_padding: float = 4_096.0
@export var fog_color: Color = Color(0.02, 0.03, 0.05, 0.32)
@export var wobble_primary: float = 160.0
@export var wobble_secondary: float = 96.0

@onready var boundary_line: Line2D = $BoundaryLine
@onready var floor_fill: Polygon2D = $FloorFill
@onready var fog_mask: Polygon2D = $FogMask
@onready var _floor_generator: FloorGenerator = get_node_or_null(floor_generator_path) as FloorGenerator

func _ready() -> void:
	add_to_group("arena")
	_sync_radius_from_floor_generator()
	_update_boundary()

func get_inner_radius(margin: float = 0.0) -> float:
	return max(radius - margin, 0.0)

func is_world_position_inside(world_position: Vector2, margin: float = 0.0) -> bool:
	return world_position.distance_to(global_position) <= get_inner_radius(margin)

func clamp_world_position(world_position: Vector2, margin: float = 0.0) -> Vector2:
	var offset: Vector2 = world_position - global_position
	var max_distance: float = get_inner_radius(margin)
	if offset.length() <= max_distance:
		return world_position
	if offset == Vector2.ZERO:
		return global_position
	return global_position + offset.normalized() * max_distance

func _update_boundary() -> void:
	var boundary_points: PackedVector2Array = _build_visual_boundary()

	if floor_fill != null:
		floor_fill.visible = false
		floor_fill.polygon = _build_fill_polygon(boundary_points)
		floor_fill.color = fill_color
	if fog_mask != null:
		fog_mask.visible = enable_fog_mask
		if enable_fog_mask:
			fog_mask.polygon = boundary_points
			fog_mask.color = fog_color
			fog_mask.invert_enabled = true
			fog_mask.invert_border = radius + fog_padding
	if boundary_line == null:
		return

	boundary_line.visible = true
	boundary_line.width = line_width
	boundary_line.default_color = line_color
	boundary_line.clear_points()
	for point in boundary_points:
		boundary_line.add_point(point)

func _build_visual_boundary() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		var direction: Vector2 = Vector2(cos(angle), sin(angle))
		points.append(direction * _get_visual_radius(direction))
	return points

func _build_fill_polygon(boundary_points: PackedVector2Array) -> PackedVector2Array:
	var fill_points: PackedVector2Array = PackedVector2Array([Vector2.ZERO])
	for point in boundary_points:
		fill_points.append(point)
	return fill_points

func _get_visual_radius(direction: Vector2) -> float:
	var wobble: float = (direction.x * direction.y * 2.0) * wobble_primary
	wobble += (direction.x * direction.x - direction.y * direction.y) * wobble_secondary
	return radius + wobble

func _sync_radius_from_floor_generator() -> void:
	if _floor_generator == null:
		return
	var playable_radius_world: Vector2 = _floor_generator.get_playable_radius_world()
	if playable_radius_world == Vector2.ZERO:
		return
	radius = min(playable_radius_world.x, playable_radius_world.y)
