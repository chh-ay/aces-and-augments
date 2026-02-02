class_name BasicEnemy
extends CharacterBody2D

@export var move_speed: float = 120.0
@export var contact_damage: int = 10
@export var damage_interval: float = 0.5
@export var damage_range: float = 18.0

var _damage_cooldown: float = 0.0

func _physics_process(delta: float) -> void:
	_damage_cooldown = max(_damage_cooldown - delta, 0.0)
	var player: Node = get_tree().get_first_node_in_group("player")
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	if player is Node2D:
		var player_node: Node2D = player
		var direction: Vector2 = (player_node.global_position - global_position).normalized()
		velocity = direction * move_speed
		move_and_slide()
		_try_damage(player_node)
		return
	velocity = Vector2.ZERO
	move_and_slide()

func _try_damage(player: Node2D) -> void:
	if _damage_cooldown > 0.0:
		return
	var distance: float = player.global_position.distance_to(global_position)
	if distance <= damage_range and player.has_method("take_damage"):
		player.take_damage(contact_damage)
		_damage_cooldown = damage_interval
