class_name MeleeSlash
extends Node2D
##
## Transient sword-sweep visual: a fan that fades out over its lifetime.
## Spawned by AutoAttack for melee characters; frees itself.
##

const LIFETIME: float = 0.18
const SEGMENTS: int = 12
const COLOR: Color = Color(1.0, 0.96, 0.82, 0.85)

var _radius: float = 80.0
var _arc: float = deg_to_rad(110.0)
var _elapsed: float = 0.0


func setup(direction: Vector2, radius: float, arc_radians: float) -> void:
	rotation = direction.angle()
	_radius = radius
	_arc = arc_radians


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed >= LIFETIME:
		queue_free()
		return
	modulate.a = 1.0 - (_elapsed / LIFETIME)
	queue_redraw()


func _draw() -> void:
	## A full-circle sweep (Cyclone Edge) has no wedge: the fan's first and
	## last rays coincide and polygon triangulation fails. Draw a disc.
	if _arc >= TAU - 0.001:
		draw_circle(Vector2.ZERO, _radius, COLOR)
		return
	var points: PackedVector2Array = PackedVector2Array()
	points.append(Vector2.ZERO)
	for segment in range(SEGMENTS + 1):
		var angle: float = lerpf(-_arc * 0.5, _arc * 0.5, float(segment) / float(SEGMENTS))
		points.append(Vector2.RIGHT.rotated(angle) * _radius)
	draw_colored_polygon(points, COLOR)
