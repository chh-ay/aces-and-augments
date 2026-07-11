class_name PlayerProjectile
extends Area2D

const DEFAULT_SPEED: float = 460.0
const DEFAULT_SCALE: Vector2 = Vector2.ONE
const DEFAULT_COLOR: Color = Color(1.0, 0.56, 0.5)

@export var lifetime: float = 1.4

var _direction: Vector2 = Vector2.RIGHT
var _damage: int = 1
var _speed: float = DEFAULT_SPEED
var _pierce_remaining: int = 0
var _releasing: bool = false
var _hit_ids: Dictionary = {}
var _elapsed: float = 0.0
var _owner: PlayerController

@onready var _visual: Polygon2D = $Visual
@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	body_entered.connect(_on_body_entered)
	on_spawned_from_pool()


func _physics_process(delta: float) -> void:
	global_position += _direction * _speed * delta
	_elapsed += delta
	if _elapsed >= lifetime:
		_queue_release()


## Sets every per-shot field; pooled instances carry no state between owners.
func configure(direction: Vector2, damage: int, source_player: PlayerController = null, combat: CombatProfile = null, total_pierce: int = 0) -> void:
	_direction = direction.normalized()
	_damage = max(damage, 1)
	_owner = source_player
	_speed = combat.projectile_speed if combat != null else DEFAULT_SPEED
	_pierce_remaining = total_pierce
	rotation = _direction.angle()
	if _sprite != null:
		_sprite.texture = combat.projectile_texture if combat != null else null
		_sprite.scale = combat.projectile_scale if combat != null else DEFAULT_SCALE
		_sprite.visible = _sprite.texture != null
	if _visual != null:
		_visual.scale = combat.projectile_scale if combat != null else DEFAULT_SCALE
		_visual.color = combat.projectile_color if combat != null else DEFAULT_COLOR
		_visual.visible = combat == null or combat.projectile_texture == null


func _on_body_entered(body: Node) -> void:
	if _releasing or not body.is_in_group("enemy"):
		return
	var body_id: int = body.get_instance_id()
	if _hit_ids.has(body_id):
		return
	_hit_ids[body_id] = true
	if body.has_method("take_damage"):
		body.take_damage(_damage)
	if _owner != null and is_instance_valid(_owner):
		_owner.apply_lifesteal(_damage)
	if _pierce_remaining > 0:
		_pierce_remaining -= 1
		return
	_queue_release()


func _queue_release() -> void:
	if _releasing:
		return
	_releasing = true
	set_deferred("monitoring", false)
	set_physics_process(false)
	PoolManager.release.call_deferred(self)


func on_spawned_from_pool() -> void:
	_elapsed = 0.0
	_direction = Vector2.RIGHT
	_damage = 1
	_speed = DEFAULT_SPEED
	_pierce_remaining = 0
	_releasing = false
	_hit_ids.clear()
	_owner = null
	visible = true
	monitoring = true
	monitorable = true
	set_physics_process(true)


func on_released_to_pool() -> void:
	_elapsed = 0.0
	_direction = Vector2.RIGHT
	_damage = 1
	_speed = DEFAULT_SPEED
	_pierce_remaining = 0
	_releasing = false
	_hit_ids.clear()
	_owner = null
	visible = false
	monitoring = false
	monitorable = false
	set_physics_process(false)
