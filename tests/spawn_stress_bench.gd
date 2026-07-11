extends Node2D
##
## Headless physics stress bench for enemy population scaling.
## Run: godot --headless --path . res://tests/spawn_stress_bench.tscn
##
## Spawns real basic_enemy instances in rings around a live player and
## measures physics frame time once the horde has converged into the
## worst-case clump. Contact damage is disabled (damage_range = 0) so the
## player survives; chasing, standoff push, and body-vs-body collision
## stay fully real.
##

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/basic_enemy.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

const STEPS: Array[int] = [100, 250, 500, 1000]
const WARMUP_FRAMES: int = 240
const MEASURE_FRAMES: int = 240

var _step_index: int = -1
var _population: int = 0
var _frame: int = 0
var _accum_ms: float = 0.0
var _worst_ms: float = 0.0
var _player: PlayerController


func _ready() -> void:
	_player = PLAYER_SCENE.instantiate() as PlayerController
	add_child(_player)
	_player.global_position = Vector2.ZERO
	var auto_attack: Node = _player.get_node_or_null("AutoAttack")
	if auto_attack != null:
		auto_attack.set_physics_process(false)
	_advance_step()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame > WARMUP_FRAMES:
		var frame_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
		_accum_ms += frame_ms
		_worst_ms = maxf(_worst_ms, frame_ms)
	if _frame >= WARMUP_FRAMES + MEASURE_FRAMES:
		var avg_ms: float = _accum_ms / float(MEASURE_FRAMES)
		print("enemies=%4d  physics avg %6.2f ms  worst %6.2f ms  (~%d FPS physics-bound)"
			% [_population, avg_ms, _worst_ms, int(1000.0 / maxf(avg_ms, 0.001))])
		_advance_step()


func _advance_step() -> void:
	_step_index += 1
	if _step_index >= STEPS.size():
		get_tree().quit(0)
		return
	var target: int = STEPS[_step_index]
	var ring: int = 0
	while _population < target:
		var enemy: AbstractEnemy = ENEMY_SCENE.instantiate() as AbstractEnemy
		enemy.damage_range = 0.0
		add_child(enemy)
		var angle: float = randf() * TAU
		var radius: float = 120.0 + float(ring % 12) * 24.0
		enemy.global_position = Vector2.RIGHT.rotated(angle) * radius
		_population += 1
		ring += 1
	_frame = 0
	_accum_ms = 0.0
	_worst_ms = 0.0
