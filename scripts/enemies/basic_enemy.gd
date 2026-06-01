class_name BasicEnemy
extends AbstractEnemy


func _get_target_player() -> PlayerController:
	return RunContext.player
