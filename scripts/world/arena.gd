class_name Arena
extends Node2D

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

func _ready() -> void:
	add_to_group("arena")
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
	var points: PackedVector2Array = _build_visual_boundary()

	if floor_fill != null:
		floor_fill.polygon = points
		floor_fill.color = fill_color
	if fog_mask != null:
		fog_mask.visible = enable_fog_mask
		if not enable_fog_mask:
			return
		var mask_extent: float = radius + fog_padding
		fog_mask.polygon = PackedVector2Array([
			Vector2(-mask_extent, -mask_extent),
			Vector2(mask_extent, -mask_extent),
			Vector2(mask_extent, mask_extent),
			Vector2(-mask_extent, mask_extent)
		])
		var fog_material: ShaderMaterial = fog_mask.material as ShaderMaterial
		if fog_material != null:
			fog_material.set_shader_parameter("arena_radius", radius)
			fog_material.set_shader_parameter("edge_softness", edge_softness)
			fog_material.set_shader_parameter("fog_color", fog_color)
			fog_material.set_shader_parameter("wobble_primary", wobble_primary)
			fog_material.set_shader_parameter("wobble_secondary", wobble_secondary)
	if boundary_line == null:
		return

	boundary_line.width = line_width
	boundary_line.default_color = line_color
	boundary_line.clear_points()
	for point in points:
		boundary_line.add_point(point)

func _build_visual_boundary() -> PackedVector2Array:
	var points: PackedVector2Array = PackedVector2Array()
	for i: int in range(segments):
		var angle: float = TAU * float(i) / float(segments)
		var visual_radius: float = radius
		visual_radius += sin(angle * 3.0 + 0.4) * wobble_primary
		visual_radius += cos(angle * 5.0 - 0.2) * wobble_secondary
		points.append(Vector2(cos(angle), sin(angle)) * visual_radius)
	return points
