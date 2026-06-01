class_name TestGround
extends Main
##
## Adds debug hotkeys to the main run loop.
##   F5 - end run timer
##   F6 - kill every active boss
##   F7 - jump straight to a royal-flush hand lock
##

const DEBUG_BOSS_DAMAGE: int = 9_999


func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	var key_event: InputEventKey = event as InputEventKey
	if key_event == null or not key_event.pressed or key_event.echo:
		return
	match key_event.keycode:
		KEY_F5:
			_on_run_time_expired()
		KEY_F6:
			_defeat_bosses()
		KEY_F7:
			player.debug_force_royal_flush()


func _defeat_bosses() -> void:
	for child in bosses.get_children():
		var enemy: AbstractEnemy = child as AbstractEnemy
		if enemy != null:
			enemy.take_damage(DEBUG_BOSS_DAMAGE)
