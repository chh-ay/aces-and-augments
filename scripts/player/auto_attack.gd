class_name AutoAttack
extends Node
##
## Drives the player's projectile cadence. Targets via RunContext / groups,
## spawns via PoolManager.
##

@export var projectile_scene: PackedScene
@export var spawn_distance: float = 18.0

var _cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	var player: PlayerController = RunContext.player
	if player == null or player.is_dead() or projectile_scene == null:
		return
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0:
		return
	var direction: Vector2 = _resolve_aim(player)
	if direction == Vector2.ZERO:
		return
	_fire_projectile(player, direction)
	_cooldown = player.get_effective_attack_interval()


func _resolve_aim(player: PlayerController) -> Vector2:
	if player.is_manual_aim_enabled():
		return player.get_manual_aim_direction()
	var target: Node2D = _find_target(player)
	if target == null:
		return Vector2.ZERO
	var to_target: Vector2 = target.global_position - player.global_position
	return to_target.normalized() if to_target != Vector2.ZERO else Vector2.RIGHT


func _fire_projectile(player: PlayerController, direction: Vector2) -> void:
	var projectile: PlayerProjectile = PoolManager.spawn(projectile_scene, get_tree().current_scene) as PlayerProjectile
	if projectile == null:
		return
	projectile.global_position = player.global_position + direction * spawn_distance
	projectile.configure(direction, player.get_effective_projectile_damage(), player)
	AudioManager.play_sfx("shoot", randf_range(0.96, 1.04), -8.0)


func _find_target(player: PlayerController) -> Node2D:
	var best_target: Node2D = null
	var best_distance_sq: float = player.get_effective_attack_range() * player.get_effective_attack_range()
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		var enemy: Node2D = enemy_node as Node2D
		if enemy == null:
			continue
		var distance_sq: float = player.global_position.distance_squared_to(enemy.global_position)
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			best_target = enemy
	return best_target
