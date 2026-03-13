class_name RunDirector
extends Node

signal time_updated(remaining_seconds: float)
signal time_expired

@export var run_duration_seconds: float = 600.0

var remaining_seconds: float = 0.0
var _last_emitted_second: int = -1
var _expired: bool = false

func _ready() -> void:
	remaining_seconds = max(run_duration_seconds, 0.0)
	_emit_time_if_needed(true)

func _process(delta: float) -> void:
	if _expired:
		return
	remaining_seconds = max(remaining_seconds - delta, 0.0)
	_emit_time_if_needed(false)
	if remaining_seconds <= 0.0:
		remaining_seconds = 0.0
		_expired = true
		time_expired.emit()

func reset() -> void:
	remaining_seconds = max(run_duration_seconds, 0.0)
	_expired = false
	_last_emitted_second = -1
	_emit_time_if_needed(true)

func stop() -> void:
	_expired = true
	_emit_time_if_needed(true)

func _emit_time_if_needed(force: bool) -> void:
	var shown_second: int = int(ceil(remaining_seconds))
	if not force and shown_second == _last_emitted_second:
		return
	_last_emitted_second = shown_second
	time_updated.emit(remaining_seconds)
