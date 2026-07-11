class_name EnemyRock
extends Area2D
##
## Simple enemy projectile: flies straight, damages the player on contact,
## frees itself on hit or after its lifetime.
##

@export var speed: float = 240.0
@export var lifetime: float = 2.5

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 8
var _elapsed: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func configure(direction: Vector2, damage: int) -> void:
	_direction = direction.normalized()
	_damage = max(damage, 1)
	rotation = _direction.angle()


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		queue_free()


func _on_body_entered(body: Node) -> void:
	var player: PlayerController = body as PlayerController
	if player == null:
		return
	player.take_damage(_damage)
	queue_free()
