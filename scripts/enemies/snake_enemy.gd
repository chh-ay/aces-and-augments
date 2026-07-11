class_name SnakeEnemy
extends BasicEnemy
##
## Telegraphed lunger: slithers toward the player, rears back (windup
## animation, stands still), then lunges in a fast straight dash. Punishes
## standing still; the windup is the dodge cue.
##
## Animations expected on the sprite: "slither", "windup", "lunge".
##

enum State { SLITHER, WINDUP, LUNGE, RECOVER }

@export var lunge_trigger_range: float = 150.0
@export var windup_duration: float = 0.45
@export var lunge_speed: float = 360.0
@export var lunge_duration: float = 0.34
@export var recover_duration: float = 0.6

var _state: State = State.SLITHER
var _state_time: float = 0.0
var _lunge_direction: Vector2 = Vector2.RIGHT


func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	_damage_cooldown = maxf(_damage_cooldown - delta, 0.0)
	var player: PlayerController = _get_target_player()
	if player == null:
		velocity = Vector2.ZERO
		move_and_slide()
		return
	_state_time += delta
	match _state:
		State.SLITHER:
			_drive_toward(player)
			_play("slither")
			if global_position.distance_squared_to(player.global_position) <= lunge_trigger_range * lunge_trigger_range:
				_enter(State.WINDUP)
		State.WINDUP:
			velocity = Vector2.ZERO
			_play("windup")
			_lunge_direction = (player.global_position - global_position).normalized()
			if _state_time >= windup_duration:
				_enter(State.LUNGE)
		State.LUNGE:
			velocity = _lunge_direction * lunge_speed * _difficulty_speed_multiplier
			_play("lunge")
			if _state_time >= lunge_duration:
				_enter(State.RECOVER)
		State.RECOVER:
			velocity = Vector2.ZERO
			_play("slither")
			if _state_time >= recover_duration:
				_enter(State.SLITHER)
	_face_by_state()
	move_and_slide()
	_try_damage(player)


## The sheet's wiggle frames face right while windup/lunge frames face left,
## so facing is resolved per state instead of the generic velocity flip.
func _face_by_state() -> void:
	if _sprite_target == null:
		return
	match _state:
		State.SLITHER, State.RECOVER:
			if absf(velocity.x) > 4.0:
				_sprite_target.set("flip_h", velocity.x < 0.0)
		State.WINDUP, State.LUNGE:
			_sprite_target.set("flip_h", _lunge_direction.x > 0.0)


func _enter(next_state: State) -> void:
	_state = next_state
	_state_time = 0.0


func _play(animation_name: String) -> void:
	var animated: AnimatedSprite2D = _sprite_target as AnimatedSprite2D
	if animated == null or animated.sprite_frames == null:
		return
	if not animated.sprite_frames.has_animation(animation_name):
		return
	if animated.animation != animation_name:
		animated.play(animation_name)


func on_spawned_from_pool() -> void:
	super.on_spawned_from_pool()
	_enter(State.SLITHER)
