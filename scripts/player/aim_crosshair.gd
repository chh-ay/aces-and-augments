class_name AimCrosshair
extends Node2D

@export var outer_radius: float = 7.0
@export var inner_gap: float = 3.0
@export var line_length: float = 5.0
@export var line_width: float = 1.6
@export var crosshair_color: Color = Color(0.12, 0.86, 0.98, 0.9)

func _ready() -> void:
	visible = false
	z_index = 50

func set_active(is_active: bool) -> void:
	if visible == is_active:
		return
	visible = is_active
	queue_redraw()

func set_world_position(world_position: Vector2) -> void:
	global_position = world_position

func _draw() -> void:
	if not visible:
		return
	draw_arc(Vector2.ZERO, outer_radius, 0.0, TAU, 24, crosshair_color, line_width, true)
	draw_line(Vector2(-inner_gap - line_length, 0.0), Vector2(-inner_gap, 0.0), crosshair_color, line_width)
	draw_line(Vector2(inner_gap, 0.0), Vector2(inner_gap + line_length, 0.0), crosshair_color, line_width)
	draw_line(Vector2(0.0, -inner_gap - line_length), Vector2(0.0, -inner_gap), crosshair_color, line_width)
	draw_line(Vector2(0.0, inner_gap), Vector2(0.0, inner_gap + line_length), crosshair_color, line_width)
