class_name AutoAttack
extends Node

@export var projectile_scene: PackedScene
@export var spawn_distance: float = 18.0

var _cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	var player: PlayerController = get_parent() as PlayerController
	if player == null or player.is_dead():
		return
	_cooldown = max(_cooldown - delta, 0.0)
	if _cooldown > 0.0:
		return
	var target: Node2D = _find_target(player)
	if target == null or projectile_scene == null:
		return
	var direction: Vector2 = (target.global_position - player.global_position).normalized()
	if direction == Vector2.ZERO:
		direction = Vector2.RIGHT
	var projectile_node: Node = projectile_scene.instantiate()
	if projectile_node is Area2D:
		var projectile: Area2D = projectile_node as Area2D
		projectile.global_position = player.global_position + direction * spawn_distance
		if projectile.has_method("configure"):
			projectile.call("configure", direction, player.get_effective_projectile_damage(), player)
		get_tree().current_scene.add_child(projectile)
		_cooldown = player.get_effective_attack_interval()

func _find_target(player: PlayerController) -> Node2D:
	var best_target: Node2D
	var best_distance_sq: float = player.get_effective_attack_range() * player.get_effective_attack_range()
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		if enemy_node is Node2D:
			var enemy: Node2D = enemy_node as Node2D
			var distance_sq: float = player.global_position.distance_squared_to(enemy.global_position)
			if distance_sq <= best_distance_sq:
				best_distance_sq = distance_sq
				best_target = enemy
	return best_target
