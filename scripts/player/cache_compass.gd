class_name CacheCompass
extends Node2D
##
## Small arrow orbiting the player that points at the nearest unopened
## card cache; hidden when none exist or one is already on screen (close).
##

const ORBIT_RADIUS: float = 52.0
const HIDE_DISTANCE: float = 320.0
const COLOR: Color = Color(0.95, 0.77, 0.24, 0.85)


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	var target: CardCache = _nearest_cache()
	if target == null:
		return
	var to_target: Vector2 = target.global_position - global_position
	if to_target.length() < HIDE_DISTANCE:
		return
	var direction: Vector2 = to_target.normalized()
	var tip: Vector2 = direction * ORBIT_RADIUS
	var side: Vector2 = direction.orthogonal() * 4.0
	var base: Vector2 = direction * (ORBIT_RADIUS - 9.0)
	draw_colored_polygon(PackedVector2Array([tip, base + side, base - side]), COLOR)


func _nearest_cache() -> CardCache:
	var best: CardCache = null
	var best_distance: float = INF
	for node in get_tree().get_nodes_in_group("card_cache"):
		var cache: CardCache = node as CardCache
		if cache == null or cache._opened:
			continue
		var distance: float = global_position.distance_squared_to(cache.global_position)
		if distance < best_distance:
			best_distance = distance
			best = cache
	return best
