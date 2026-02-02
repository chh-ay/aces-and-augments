class_name PlayerController
extends CharacterBody2D

signal health_changed(hp: int)

@export var move_speed: float = 200.0
@export var max_health: int = 100

var current_health: int = 0

func _ready() -> void:
	add_to_group("player")
	current_health = max_health
	health_changed.emit(current_health)

func _physics_process(_delta: float) -> void:
	var input_vector: Vector2 = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	velocity = input_vector * move_speed
	move_and_slide()

func take_damage(amount: int) -> void:
	var next_health: int = max(current_health - amount, 0)
	current_health = next_health
	health_changed.emit(current_health)
