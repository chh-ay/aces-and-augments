class_name XpOrb
extends Node2D

const DEFAULT_FRAME: Rect2 = Rect2(24, 16, 12, 16)
const PICKUP_RADIUS_SQ: float = 18.0 * 18.0
const LOGIC_INTERVAL_MIN: float = 0.06
const LOGIC_INTERVAL_MAX: float = 0.12

@export var xp_amount: int = 1
@export var attract_radius: float = 120.0
@export var move_speed: float = 220.0

var _logic_interval: float = LOGIC_INTERVAL_MIN
var _logic_cooldown: float = 0.0
var _magnet_direction: Vector2 = Vector2.ZERO
var _is_attracting: bool = false

@onready var _visual: Sprite2D = $Visual


func _ready() -> void:
	on_spawned_from_pool()


func _physics_process(delta: float) -> void:
	var player: PlayerController = RunContext.player
	if player == null:
		return
	_logic_cooldown -= delta
	if _logic_cooldown <= 0.0:
		_logic_cooldown += _logic_interval
		if _try_pickup_or_track(player):
			return
	if _is_attracting:
		global_position += _magnet_direction * move_speed * delta


func set_xp_amount(amount: int) -> void:
	xp_amount = max(amount, 1)
	_apply_visual_frame()


func on_spawned_from_pool() -> void:
	_logic_interval = randf_range(LOGIC_INTERVAL_MIN, LOGIC_INTERVAL_MAX)
	_logic_cooldown = randf() * _logic_interval
	_is_attracting = false
	_magnet_direction = Vector2.ZERO
	visible = true
	set_physics_process(true)
	_apply_visual_frame()


func on_released_to_pool() -> void:
	_is_attracting = false
	_magnet_direction = Vector2.ZERO
	visible = false
	set_physics_process(false)


func _try_pickup_or_track(player: PlayerController) -> bool:
	var distance_sq: float = global_position.distance_squared_to(player.global_position)
	if distance_sq <= PICKUP_RADIUS_SQ:
		player.add_experience(xp_amount)
		AudioManager.play_sfx("xp_pickup", randf_range(0.96, 1.08), -13.0)
		PoolManager.release.call_deferred(self)
		return true
	_is_attracting = distance_sq <= attract_radius * attract_radius
	_magnet_direction = (player.global_position - global_position).normalized() if _is_attracting else Vector2.ZERO
	return false


func _apply_visual_frame() -> void:
	if _visual == null:
		return
	_visual.region_enabled = true
	_visual.region_rect = DEFAULT_FRAME
	_visual.offset = Vector2(0.0, -1.0)
