class_name BossCore
extends AbstractEnemy

signal defeated(defeat_position: Vector2)

@export var chase_speed_scale: float = 0.82
@export var dash_speed_multiplier: float = 2.45
@export var dash_duration: float = 0.4
@export var dash_cooldown: float = 2.6
@export var dash_trigger_distance: float = 320.0

var _player: PlayerController
var _dash_cooldown_remaining: float = 1.2
var _dash_time_remaining: float = 0.0
var _dash_direction: Vector2 = Vector2.ZERO

func _ready() -> void:
	super._ready()
	_player = get_tree().get_first_node_in_group("player") as PlayerController

func _physics_process(delta: float) -> void:
	_damage_cooldown = max(_damage_cooldown - delta, 0.0)
	_dash_cooldown_remaining = max(_dash_cooldown_remaining - delta, 0.0)
	var player: PlayerController = _get_target_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return

	var to_player: Vector2 = player.global_position - global_position
	if _dash_time_remaining > 0.0:
		_dash_time_remaining = max(_dash_time_remaining - delta, 0.0)
		velocity = _dash_direction * _current_move_speed * dash_speed_multiplier
	else:
		if _dash_cooldown_remaining <= 0.0 and to_player.length_squared() <= dash_trigger_distance * dash_trigger_distance:
			_dash_direction = to_player.normalized()
			if _dash_direction == Vector2.ZERO:
				_dash_direction = Vector2.DOWN
			_dash_time_remaining = dash_duration
			_dash_cooldown_remaining = dash_cooldown
			velocity = _dash_direction * _current_move_speed * dash_speed_multiplier
		else:
			velocity = to_player.normalized() * _current_move_speed * chase_speed_scale
	move_and_slide()
	_try_damage(player)

func _die() -> void:
	defeated.emit(global_position)
	super._die()

func _get_target_player() -> PlayerController:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as PlayerController
	return _player

func _get_death_sfx_id() -> String:
	return "boss_defeat"
