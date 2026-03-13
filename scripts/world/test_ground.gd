class_name TestGround
extends Main

const DEBUG_BOSS_DAMAGE: int = 9_999

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	if event is not InputEventKey:
		return
	var key_event: InputEventKey = event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F5:
			_on_run_time_expired()
		KEY_F6:
			_defeat_bosses()
		KEY_F7:
			_force_royal_flush()

func _defeat_bosses() -> void:
	if bosses == null:
		return
	for child in bosses.get_children():
		if child.has_method("take_damage"):
			child.call("take_damage", DEBUG_BOSS_DAMAGE)

func _force_royal_flush() -> void:
	if player == null:
		return
	player.active_hand_name = "Royal Flush"
	player.active_augment_bonus = 2.0
	player.hand_updated.emit(player.collected_cards, player.active_hand_name, player.active_augment_bonus)
