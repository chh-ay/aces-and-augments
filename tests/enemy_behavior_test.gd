extends Node2D
##
## Headless behavioral checks for the enemy physics-layer optimization:
## enemies must still separate (no sprite stacking), converge on the
## player (chase + stand-off), and be hittable by projectiles (mask 2).
## Run: godot --headless --path . res://tests/enemy_behavior_test.tscn
##

const ENEMY_SCENE: PackedScene = preload("res://scenes/enemies/basic_enemy.tscn")
const PROJECTILE_SCENE: PackedScene = preload("res://scenes/player/player_projectile.tscn")
const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

const CLUMP_COUNT: int = 30
const SETTLE_FRAMES: int = 180

var _failures: int = 0
var _frame: int = 0
var _player: PlayerController
var _enemies: Array[AbstractEnemy] = []
var _initial_spread: float = 0.0


func _ready() -> void:
	_player = PLAYER_SCENE.instantiate() as PlayerController
	add_child(_player)
	_player.global_position = Vector2.ZERO
	var auto_attack: Node = _player.get_node_or_null("AutoAttack")
	if auto_attack != null:
		auto_attack.set_physics_process(false)
	# Worst case for separation: the whole clump starts in one spot.
	for index in range(CLUMP_COUNT):
		var enemy: AbstractEnemy = ENEMY_SCENE.instantiate() as AbstractEnemy
		enemy.damage_range = 0.0
		add_child(enemy)
		enemy.global_position = Vector2(300.0, 0.0) + Vector2(randf(), randf())
		_enemies.append(enemy)
	_initial_spread = _mean_neighbor_distance()


func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == SETTLE_FRAMES:
		_run_checks()


func _run_checks() -> void:
	var spread: float = _mean_neighbor_distance()
	_check(spread > _initial_spread + 6.0,
		"clump separates (spread %.1f -> %.1f px)" % [_initial_spread, spread])
	var mean_player_distance: float = 0.0
	for enemy in _enemies:
		mean_player_distance += enemy.global_position.distance_to(_player.global_position)
	mean_player_distance /= float(_enemies.size())
	_check(mean_player_distance < 150.0,
		"pack converges on player (mean distance %.1f px)" % mean_player_distance)
	_check_projectile_hit()


func _check_projectile_hit() -> void:
	var health_before: int = _total_pack_health()
	var target: AbstractEnemy = _enemies[0]
	var projectile: PlayerProjectile = PROJECTILE_SCENE.instantiate() as PlayerProjectile
	add_child(projectile)
	projectile.global_position = target.global_position - Vector2(40.0, 0.0)
	projectile.configure(Vector2.RIGHT, 1, _player, _player.get_combat_profile(), 0)
	# Give the projectile a few frames to travel and overlap.
	await get_tree().create_timer(0.25).timeout
	_check(_total_pack_health() < health_before,
		"projectile still hits enemies on layer 2")
	_finish()


func _total_pack_health() -> int:
	var total: int = 0
	for enemy in _enemies:
		if is_instance_valid(enemy):
			total += enemy._current_health
	return total

func _mean_neighbor_distance() -> float:
	var total: float = 0.0
	var pairs: int = 0
	for i in range(_enemies.size()):
		for j in range(i + 1, _enemies.size()):
			total += _enemies[i].global_position.distance_to(_enemies[j].global_position)
			pairs += 1
	return total / float(maxi(pairs, 1))


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)


func _finish() -> void:
	print("---")
	print("FAILED %d checks" % _failures if _failures > 0 else "ALL CHECKS PASSED")
	get_tree().quit(1 if _failures > 0 else 0)
