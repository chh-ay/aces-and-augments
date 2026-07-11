class_name AutoAttack
extends Node
##
## Drives the player's attack cadence. Behavior comes from the selected
## character's combat profile: sword sweeps (damage lands on the smear
## contact frame) or projectiles. Melee acquisition, aim, and hit checks all
## share get_effective_melee_range() so they can never diverge.
##

@export var projectile_scene: PackedScene
@export var spawn_distance: float = 18.0

var _cooldown: float = 0.0
var _pending_strike: Dictionary = {}


func _physics_process(delta: float) -> void:
	var player: PlayerController = RunContext.player
	if player == null or player.is_dead() or projectile_scene == null:
		_pending_strike.clear()
		return
	_tick_pending_strike(player, delta)
	_cooldown = maxf(_cooldown - delta, 0.0)
	if _cooldown > 0.0 or not _pending_strike.is_empty():
		return
	var combat: CombatProfile = player.get_combat_profile()
	var is_melee: bool = combat.melee
	var acquire_range: float = player.get_effective_melee_range() if is_melee else player.get_effective_attack_range()
	var direction: Vector2 = _resolve_aim(player, acquire_range)
	if direction == Vector2.ZERO:
		return
	if is_melee:
		_begin_melee_strike(direction, combat, player)
	else:
		_fire_projectiles(player, direction, combat)
	player.play_attack(direction)
	AudioManager.play_sfx("shoot", combat.sfx_pitch * randf_range(0.96, 1.04), -8.0)
	_cooldown = player.get_effective_attack_interval()


func _resolve_aim(player: PlayerController, acquire_range: float) -> Vector2:
	if player.is_manual_aim_enabled():
		return player.get_manual_aim_direction()
	var target: Node2D = _find_target(player, acquire_range)
	if target == null:
		return Vector2.ZERO
	var to_target: Vector2 = target.global_position - player.global_position
	return to_target.normalized() if to_target != Vector2.ZERO else Vector2.RIGHT


func _fire_projectiles(player: PlayerController, direction: Vector2, combat: CombatProfile) -> void:
	var count: int = max(combat.projectile_count, 1)
	var spread: float = deg_to_rad(combat.spread_degrees)
	var jitter: float = deg_to_rad(combat.jitter_degrees)
	var damage: int = player.get_effective_projectile_damage()
	var total_pierce: int = combat.pierce + player.bonus_pierce
	for index in range(count):
		var offset: float = 0.0
		if count > 1:
			offset = lerpf(-spread * 0.5, spread * 0.5, float(index) / float(count - 1))
		offset += randf_range(-jitter, jitter)
		var shot_direction: Vector2 = direction.rotated(offset)
		var projectile: PlayerProjectile = PoolManager.spawn(projectile_scene, get_tree().current_scene) as PlayerProjectile
		if projectile == null:
			return
		projectile.global_position = player.global_position + shot_direction * spawn_distance
		projectile.configure(shot_direction, damage, player, combat, total_pierce)


## Melee damage is deferred to the smear contact frame of the attack
## animation; the strike is dropped if the player dies in the meantime.
func _begin_melee_strike(direction: Vector2, combat: CombatProfile, player: PlayerController) -> void:
	var arc: float = TAU if player.melee_full_circle else deg_to_rad(combat.melee_arc_degrees)
	_pending_strike = {
		"direction": direction,
		"delay": combat.melee_hit_delay,
		"arc": arc,
	}


func _tick_pending_strike(player: PlayerController, delta: float) -> void:
	if _pending_strike.is_empty():
		return
	var delay: float = float(_pending_strike["delay"]) - delta
	if delay > 0.0:
		_pending_strike["delay"] = delay
		return
	var direction: Vector2 = _pending_strike["direction"]
	var arc: float = float(_pending_strike["arc"])
	_pending_strike.clear()
	_apply_melee_damage(player, direction, arc)


func _apply_melee_damage(player: PlayerController, direction: Vector2, arc: float) -> void:
	var reach: float = player.get_effective_melee_range()
	var damage: int = player.get_effective_projectile_damage()
	var half_arc: float = arc * 0.5
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		var enemy: Node2D = enemy_node as Node2D
		if enemy == null:
			continue
		var to_enemy: Vector2 = enemy.global_position - player.global_position
		if to_enemy.length_squared() > reach * reach:
			continue
		if arc < TAU and to_enemy != Vector2.ZERO and absf(direction.angle_to(to_enemy)) > half_arc:
			continue
		if enemy.has_method("take_damage"):
			enemy.take_damage(damage)
			player.apply_lifesteal(damage)
	var slash: MeleeSlash = MeleeSlash.new()
	player.add_child(slash)
	slash.setup(direction, reach, arc)


func _find_target(player: PlayerController, acquire_range: float) -> Node2D:
	var best_target: Node2D = null
	var best_distance_sq: float = acquire_range * acquire_range
	for enemy_node in get_tree().get_nodes_in_group("enemy"):
		var enemy: Node2D = enemy_node as Node2D
		if enemy == null:
			continue
		var distance_sq: float = player.global_position.distance_squared_to(enemy.global_position)
		if distance_sq <= best_distance_sq:
			best_distance_sq = distance_sq
			best_target = enemy
	return best_target
