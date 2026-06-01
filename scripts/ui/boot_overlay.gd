class_name BootOverlay
extends Control
##
## Holds the player in a "Generating sector" loading state while the
## FloorGenerator streams its initial chunks. Auto-dismisses on the
## generator signal or after a watchdog timeout, whichever comes first.
##

signal finished

@export var watchdog_seconds: float = 2.0

var _finished: bool = false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = true


func bind(floor_generator: FloorGenerator) -> void:
	if floor_generator == null:
		_finish()
		return
	if floor_generator.has_initial_chunks_ready():
		_finish.call_deferred()
		return
	floor_generator.initial_chunks_ready.connect(_finish, CONNECT_ONE_SHOT)
	_arm_watchdog()


func _arm_watchdog() -> void:
	await get_tree().create_timer(watchdog_seconds, true, false, true).timeout
	if not _finished:
		push_warning("[Boot] Watchdog forced overlay release")
		_finish()


func _finish() -> void:
	if _finished:
		return
	_finished = true
	visible = false
	finished.emit()
