class_name XpOrb
extends Node2D

@export var xp_amount: int = 1
@export var attract_radius: float = 120.0
@export var move_speed: float = 220.0

const DEFAULT_FRAME: Rect2 = Rect2(24, 16, 12, 16)
const PICKUP_RADIUS_SQ: float = 18.0 * 18.0
const LOGIC_INTERVAL_MIN: float = 0.06
const LOGIC_INTERVAL_MAX: float = 0.12

var _player: PlayerController
var _logic_interval: float = LOGIC_INTERVAL_MIN
var _logic_cooldown: float = 0.0
var _magnet_direction: Vector2 = Vector2.ZERO
var _is_attracting: bool = false

@onready var _visual: Sprite2D = $Visual

func _ready() -> void:
	_logic_interval = randf_range(LOGIC_INTERVAL_MIN, LOGIC_INTERVAL_MAX)
	_logic_cooldown = randf() * _logic_interval
	_apply_visual_frame()

func _physics_process(delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as PlayerController
		if _player == null:
			return
	_logic_cooldown -= delta
	if _logic_cooldown <= 0.0:
		_logic_cooldown += _logic_interval
		if _run_logic_tick():
			return
	if _is_attracting:
		global_position += _magnet_direction * move_speed * delta

func set_xp_amount(amount: int) -> void:
	xp_amount = max(amount, 1)
	_apply_visual_frame()

func _run_logic_tick() -> bool:
	if _player == null:
		_is_attracting = false
		_magnet_direction = Vector2.ZERO
		return false
	var distance_sq: float = global_position.distance_squared_to(_player.global_position)
	if distance_sq <= PICKUP_RADIUS_SQ:
		_player.add_experience(xp_amount)
		queue_free()
		return true
	_is_attracting = distance_sq <= attract_radius * attract_radius
	if _is_attracting:
		_magnet_direction = (_player.global_position - global_position).normalized()
	else:
		_magnet_direction = Vector2.ZERO
	return false

func _apply_visual_frame() -> void:
	if _visual == null:
		return
	_visual.region_enabled = true
	_visual.region_rect = DEFAULT_FRAME
	_visual.scale = Vector2.ONE
	_visual.offset = Vector2(0.0, -1.0)
