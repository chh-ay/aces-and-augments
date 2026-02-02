class_name BasicEnemy
extends CharacterBody2D

@export var move_speed: float = 120.0

func _physics_process(_delta: float) -> void:
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
		return
	velocity = Vector2.ZERO
	move_and_slide()
