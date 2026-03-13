class_name BasicEnemy
extends AbstractEnemy

var _player: PlayerController


func _ready() -> void:
	super._ready()
	_player = get_tree().get_first_node_in_group("player") as PlayerController


func _get_target_player() -> PlayerController:
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player") as PlayerController
	return _player
