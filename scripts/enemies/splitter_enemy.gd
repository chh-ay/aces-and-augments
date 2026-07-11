class_name SplitterEnemy
extends BasicEnemy
##
## Big slime that splits into smaller enemies on death. Spawns inherit this
## enemy's difficulty multipliers so late-run splits stay threatening.
##

@export var split_scene: PackedScene
@export var split_count: int = 3
@export var split_spread: float = 18.0


func _die() -> void:
	_spawn_splits()
	super._die()


func _spawn_splits() -> void:
	if split_scene == null:
		return
	var parent: Node = get_parent()
	if parent == null:
		return
	for index in range(split_count):
		var child: AbstractEnemy = PoolManager.spawn(split_scene, parent) as AbstractEnemy
		if child == null:
			return
		var angle: float = TAU * float(index) / float(split_count) + randf_range(-0.4, 0.4)
		child.global_position = global_position + Vector2.RIGHT.rotated(angle) * split_spread
		child.apply_difficulty_scaling(
			_difficulty_speed_multiplier,
			_difficulty_health_multiplier,
			_difficulty_damage_multiplier
		)
		child.apply_mutation_profile(_mutation_profile)
