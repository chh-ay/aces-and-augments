@abstract
class_name AbstractEnemy
extends CharacterBody2D

@export var move_speed: float = 120.0
@export var contact_damage: int = 10
@export var damage_interval: float = 0.5
@export var damage_range: float = 24.0

var _damage_cooldown: float = 0.0


func _physics_process(delta: float) -> void:
	_damage_cooldown = max(_damage_cooldown - delta, 0.0)
	var player: PlayerController = _get_target_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var direction: Vector2 = (player.global_position - global_position).normalized()
	velocity = direction * move_speed
	move_and_slide()
	_try_damage(player)


func _try_damage(player: PlayerController) -> void:
	if _damage_cooldown > 0.0:
		return
	if player.global_position.distance_to(global_position) <= damage_range:
		player.take_damage(contact_damage)
		_damage_cooldown = damage_interval


@abstract func _get_target_player() -> PlayerController
