class_name PlayerController
extends CharacterBody2D

signal health_changed(hp: int)
signal died

@export var move_speed: float = 200.0
@export var max_health: int = 100

var current_health: int = 0
var _is_dead: bool = false
var _facing: Vector2 = Vector2.DOWN

@onready var _anim: AnimatedSprite2D = $AnimatedSprite2D
@onready var _camera: Camera2D = $Camera2D

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	health_changed.emit(current_health)
	_update_animation()


func _physics_process(_delta: float) -> void:
	if _is_dead:
		return
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * move_speed
	move_and_slide()
	_update_animation()
	_snap_camera()


func take_damage(amount: int) -> void:
	if _is_dead:
		return
	var next_health: int = max(current_health - amount, 0)
	current_health = next_health
	health_changed.emit(current_health)
	if current_health <= 0:
		_die()


func _die() -> void:
	if _is_dead:
		return
	_is_dead = true
	died.emit()
	velocity = Vector2.ZERO
	_update_animation()


func _update_animation() -> void:
	if _anim == null:
		return
	var is_moving: bool = velocity.length_squared() > 0.0
	if is_moving:
		_facing = velocity.normalized()
	var use_north: bool = _facing.y < 0.0 and abs(_facing.y) >= abs(_facing.x)
	if is_moving:
		if use_north:
			_play_animation("walk_north")
		else:
			_play_animation("walk_south")
	else:
		if use_north:
			_play_animation("idle_north")
		else:
			_play_animation("idle_south")
	_anim.flip_h = _facing.x < 0.0


func _play_animation(animation_name: String) -> void:
	if _anim == null:
		return
	var frames: SpriteFrames = _anim.sprite_frames
	if frames == null:
		return
	if frames.has_animation(animation_name):
		if _anim.animation != animation_name:
			_anim.animation = animation_name
		if not _anim.is_playing():
			_anim.play()
	else:
		if frames.has_animation("walk_south"):
			if _anim.animation != "walk_south":
				_anim.animation = "walk_south"
			if not _anim.is_playing():
				_anim.play()


func _snap_camera() -> void:
	if _camera == null:
		return
	var camera_pos: Vector2 = _camera.global_position
	_camera.global_position = Vector2(round(camera_pos.x), round(camera_pos.y))
