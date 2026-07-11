class_name MoleEnemy
extends BasicEnemy
##
## Stationary ranged thrower: hides underground (invisible, untargetable)
## until the player comes near, emerges, then lobs rocks on a cadence while
## the player stays in range. Forces target prioritization.
##
## Animations expected: "emerge", "holding", "throw".
##

enum State { BURIED, EMERGE, HOLDING, THROW }

@export var wake_range: float = 400.0
@export var throw_interval: float = 2.4
@export var rock_scene: PackedScene
@export var emerge_duration: float = 0.8
@export var throw_duration: float = 0.4

var _state: State = State.BURIED
var _state_time: float = 0.0
var _throw_timer: float = 0.0
var _rock_released: bool = false


func _ready() -> void:
	super._ready()
	_enter(State.BURIED)
	_bury.call_deferred()


func _physics_process(delta: float) -> void:
	_update_hit_flash(delta)
	_damage_cooldown = maxf(_damage_cooldown - delta, 0.0)
	velocity = Vector2.ZERO
	var player: PlayerController = _get_target_player()
	if player == null:
		return
	_state_time += delta
	var distance_sq: float = global_position.distance_squared_to(player.global_position)
	match _state:
		State.BURIED:
			if distance_sq <= wake_range * wake_range:
				visible = true
				if _collision_shape != null:
					_collision_shape.disabled = false
				if not is_in_group("enemy"):
					add_to_group("enemy")
				_play("emerge")
				_enter(State.EMERGE)
		State.EMERGE:
			if _state_time >= emerge_duration:
				_enter(State.HOLDING)
		State.HOLDING:
			_play("holding")
			_throw_timer -= delta
			if _throw_timer <= 0.0 and distance_sq <= wake_range * wake_range * 1.44:
				_throw_timer = throw_interval
				_rock_released = false
				_play("throw")
				_enter(State.THROW)
		State.THROW:
			if not _rock_released and _state_time >= throw_duration * 0.5:
				_rock_released = true
				_launch_rock(player)
			if _state_time >= throw_duration:
				_enter(State.HOLDING)


func _launch_rock(player: PlayerController) -> void:
	if rock_scene == null:
		return
	var rock: Node2D = rock_scene.instantiate() as Node2D
	if rock == null:
		return
	get_tree().current_scene.add_child(rock)
	rock.global_position = global_position + Vector2(0, -8)
	if rock.has_method("configure"):
		rock.call("configure", (player.global_position - rock.global_position).normalized(), _current_contact_damage)


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


func _bury() -> void:
	visible = false
	if _collision_shape != null:
		_collision_shape.disabled = true
	if is_in_group("enemy"):
		remove_from_group("enemy")


func on_spawned_from_pool() -> void:
	super.on_spawned_from_pool()
	_enter(State.BURIED)
	_throw_timer = throw_interval * 0.5
	_bury.call_deferred()
