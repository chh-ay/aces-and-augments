extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES: Array[String] = ["DEBUG", "INFO", "WARN", "ERROR"]
const LEVEL_COLORS: Dictionary = {
	Level.DEBUG: "gray",
	Level.INFO: "white",
	Level.WARN: "yellow",
	Level.ERROR: "red"
}

var current_level: Level = Level.DEBUG
var log_to_file: bool = false
var log_file_path: String = "user://game.log"
var _file: FileAccess

func _ready() -> void:
	if OS.is_debug_build():
		current_level = Level.DEBUG
	else:
		current_level = Level.WARN
	if log_to_file:
		_file = FileAccess.open(log_file_path, FileAccess.WRITE)

func debug(message: String, context: String = "") -> void:
	_log(Level.DEBUG, message, context)

func info(message: String, context: String = "") -> void:
	_log(Level.INFO, message, context)

func warn(message: String, context: String = "") -> void:
	_log(Level.WARN, message, context)

func error(message: String, context: String = "") -> void:
	_log(Level.ERROR, message, context)

func _log(level: Level, message: String, context: String) -> void:
	if level < current_level:
		return
	var timestamp: String = Time.get_datetime_string_from_system()
	var ctx: String = "[%s] " % context if context else ""
	var formatted: String = "[%s] [%s] %s%s" % [timestamp, LEVEL_NAMES[level], ctx, message]
	print_rich("[color=%s]%s[/color]" % [LEVEL_COLORS[level], formatted])
	if _file:
		_file.store_line(formatted)

func player(msg: String) -> void:
	debug(msg, "Player")

func enemy(msg: String) -> void:
	debug(msg, "Enemy")

func card(msg: String) -> void:
	debug(msg, "Card")

func combat(msg: String) -> void:
	debug(msg, "Combat")

func ui(msg: String) -> void:
	debug(msg, "UI")

func spawner(msg: String) -> void:
	debug(msg, "Spawner")
