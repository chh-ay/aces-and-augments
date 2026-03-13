class_name CardPickup
extends Node2D

@export var attract_radius: float = 116.0
@export var move_speed: float = 230.0

const PICKUP_RADIUS_SQ: float = 18.0 * 18.0
const LOGIC_INTERVAL_MIN: float = 0.06
const LOGIC_INTERVAL_MAX: float = 0.12

var suit: String = "spades"
var value: int = 1
var _player: PlayerController
var _logic_interval: float = LOGIC_INTERVAL_MIN
var _logic_cooldown: float = 0.0
var _magnet_direction: Vector2 = Vector2.ZERO
var _is_attracting: bool = false

@onready var _visual: Polygon2D = $Visual

func _ready() -> void:
	on_spawned_from_pool()

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

func on_spawned_from_pool() -> void:
	_player = null
	_logic_interval = randf_range(LOGIC_INTERVAL_MIN, LOGIC_INTERVAL_MAX)
	_logic_cooldown = randf() * _logic_interval
	_is_attracting = false
	_magnet_direction = Vector2.ZERO
	suit = "spades"
	value = 1
	visible = true
	set_physics_process(true)
	if _visual != null:
		_visual.color = Color(0.92, 0.92, 0.96, 0.95)

func on_released_to_pool() -> void:
	_player = null
	_is_attracting = false
	_magnet_direction = Vector2.ZERO
	visible = false
	set_physics_process(false)

func configure_card(card_suit: String, card_value: int) -> void:
	suit = card_suit
	value = card_value
	if _visual == null:
		return
	if suit == "hearts" or suit == "diamonds":
		_visual.color = Color(0.98, 0.38, 0.36, 0.95)
	else:
		_visual.color = Color(0.86, 0.9, 0.96, 0.95)

func _run_logic_tick() -> bool:
	if _player == null:
		_is_attracting = false
		_magnet_direction = Vector2.ZERO
		return false
	var distance_sq: float = global_position.distance_squared_to(_player.global_position)
	if distance_sq <= PICKUP_RADIUS_SQ:
		_player.add_card_to_hand(suit, value)
		_release_to_pool()
		return true
	_is_attracting = distance_sq <= attract_radius * attract_radius
	if _is_attracting:
		_magnet_direction = (_player.global_position - global_position).normalized()
	else:
		_magnet_direction = Vector2.ZERO
	return false

func _release_to_pool() -> void:
	var pool_manager: Node = get_tree().get_first_node_in_group("pool_manager")
	if pool_manager != null and pool_manager.has_method("release"):
		pool_manager.call_deferred("release", self)
		return
	queue_free()
