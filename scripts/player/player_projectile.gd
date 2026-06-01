class_name PlayerProjectile
extends Area2D

@export var speed: float = 460.0
@export var lifetime: float = 1.4

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _elapsed: float = 0.0
var _owner: PlayerController


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	on_spawned_from_pool()


func _physics_process(delta: float) -> void:
	global_position += _direction * speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		PoolManager.release.call_deferred(self)


func configure(direction: Vector2, damage: int, source_player: PlayerController = null) -> void:
	_direction = direction.normalized()
	_damage = max(damage, 1)
	_owner = source_player
	rotation = _direction.angle()


func _on_body_entered(body: Node) -> void:
	if not body.is_in_group("enemy"):
		return
	if body.has_method("take_damage"):
		body.take_damage(_damage)
	if _owner != null and is_instance_valid(_owner):
		_owner.apply_lifesteal(_damage)
	PoolManager.release.call_deferred(self)


func on_spawned_from_pool() -> void:
	_elapsed = 0.0
	_direction = Vector2.RIGHT
	_damage = 1
	_owner = null
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)


func on_released_to_pool() -> void:
	_elapsed = 0.0
	_direction = Vector2.RIGHT
	_damage = 1
	_owner = null
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)
