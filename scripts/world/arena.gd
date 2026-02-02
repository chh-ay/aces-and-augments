class_name Arena
extends Node2D

@export var radius: float = 300.0
@export var segments: int = 64
@export var line_width: float = 4.0
@export var line_color: Color = Color(1.0, 0.8, 0.2)

@onready var boundary_line: Line2D = $BoundaryLine
@onready var boundary_shape: CollisionShape2D = $Boundary/CollisionShape2D

func _ready() -> void:
	_update_boundary()

func _update_boundary() -> void:
	if boundary_shape.shape is CircleShape2D:
		boundary_shape.shape.radius = radius
	boundary_line.width = line_width
	boundary_line.default_color = line_color
	boundary_line.clear_points()
	for i in range(segments + 1):
		var angle: float = TAU * float(i) / float(segments)
		var point: Vector2 = Vector2(cos(angle), sin(angle)) * radius
		boundary_line.add_point(point)
