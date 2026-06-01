class_name CardPickup
extends Node2D

const PICKUP_RADIUS_SQ: float = 18.0 * 18.0
const LOGIC_INTERVAL_MIN: float = 0.06
const LOGIC_INTERVAL_MAX: float = 0.12
const RED_TINT: Color = Color(0.98, 0.38, 0.36, 0.95)
const COOL_TINT: Color = Color(0.86, 0.9, 0.96, 0.95)
const DEFAULT_TINT: Color = Color(0.92, 0.92, 0.96, 0.95)

@export var attract_radius: float = 116.0
@export var move_speed: float = 230.0

var suit: String = "spades"
var value: int = 1

var _logic_interval: float = LOGIC_INTERVAL_MIN
var _logic_cooldown: float = 0.0
var _magnet_direction: Vector2 = Vector2.ZERO
var _is_attracting: bool = false

@onready var _visual: Sprite2D = $CardEmpty


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


func configure_card(card_suit: String, card_value: int) -> void:
	suit = card_suit
	value = card_value
	if _visual == null:
		return
	_visual.self_modulate = RED_TINT if (suit == "hearts" or suit == "diamonds") else COOL_TINT


func on_spawned_from_pool() -> void:
	_logic_interval = randf_range(LOGIC_INTERVAL_MIN, LOGIC_INTERVAL_MAX)
	_logic_cooldown = randf() * _logic_interval
	_is_attracting = false
	_magnet_direction = Vector2.ZERO
	suit = "spades"
	value = 1
	visible = true
	set_physics_process(true)
	if _visual != null:
		_visual.self_modulate = DEFAULT_TINT


func on_released_to_pool() -> void:
	_is_attracting = false
	_magnet_direction = Vector2.ZERO
	visible = false
	set_physics_process(false)


func _try_pickup_or_track(player: PlayerController) -> bool:
	var distance_sq: float = global_position.distance_squared_to(player.global_position)
	if distance_sq <= PICKUP_RADIUS_SQ:
		player.add_card_to_hand(suit, value)
		AudioManager.play_sfx("card_pickup", randf_range(0.98, 1.04), -8.0)
		PoolManager.release.call_deferred(self)
		return true
	_is_attracting = distance_sq <= attract_radius * attract_radius
	_magnet_direction = (player.global_position - global_position).normalized() if _is_attracting else Vector2.ZERO
	return false
