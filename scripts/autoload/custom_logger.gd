# custom_logger.gd
# Debug logging system for Aces & Augments
# Add as Autoload: Project → Project Settings → Autoload → CustomLogger
# Place in: res://scripts/autoload/custom_logger.gd

extends Node

enum Level { DEBUG, INFO, WARN, ERROR }

const LEVEL_NAMES := ["DEBUG", "INFO", "WARN", "ERROR"]
const LEVEL_COLORS := {
	Level.DEBUG: "gray",
	Level.INFO: "white",
	Level.WARN: "yellow",
	Level.ERROR: "red"
}

## Current minimum log level. Messages below this level are ignored.
var current_level: Level = Level.DEBUG

## Enable to write logs to file in addition to console.
var log_to_file: bool = false

## Path for log file. Uses Godot's user:// directory.
var log_file_path: String = "user://game.log"

## Include timestamps in log messages.
var show_timestamps: bool = true

## Include frame number in log messages (useful for per-frame debugging).
var show_frame: bool = false

var _file: FileAccess
var _frame_count: int = 0
var _logged_once: Dictionary = {}


func _ready() -> void:
	# Auto-set log level based on build type
	if OS.is_debug_build():
		current_level = Level.DEBUG
	else:
		current_level = Level.WARN
		log_to_file = true  # Enable file logging for release builds

	if log_to_file:
		_open_log_file()

	info("CustomLogger initialized", "System")


func _process(_delta: float) -> void:
	_frame_count += 1


func _exit_tree() -> void:
	if _file:
		_file.close()


func _open_log_file() -> void:
	_file = FileAccess.open(log_file_path, FileAccess.WRITE)
	if _file:
		_file.store_line("=== Log started: %s ===" % Time.get_datetime_string_from_system())
	else:
		push_warning("CustomLogger: Could not open log file at %s" % log_file_path)


## Set the minimum log level.
func set_level(level: Level) -> void:
	current_level = level
	info("Log level set to %s" % LEVEL_NAMES[level], "CustomLogger")


## Log a DEBUG message. Use for verbose development info.
func debug(message: String, context: String = "") -> void:
	_log(Level.DEBUG, message, context)


## Log an INFO message. Use for general game events.
func info(message: String, context: String = "") -> void:
	_log(Level.INFO, message, context)


## Log a WARN message. Use for recoverable issues.
func warn(message: String, context: String = "") -> void:
	_log(Level.WARN, message, context)


## Log an ERROR message. Use for serious problems.
func error(message: String, context: String = "") -> void:
	_log(Level.ERROR, message, context)


func _log(level: Level, message: String, context: String) -> void:
	if level < current_level:
		return

	var parts: PackedStringArray = []

	# Timestamp
	if show_timestamps:
		parts.append("[%s]" % Time.get_time_string_from_system())

	# Frame number
	if show_frame:
		parts.append("[F%d]" % _frame_count)

	# Level
	parts.append("[%s]" % LEVEL_NAMES[level])

	# Context
	if context:
		parts.append("[%s]" % context)

	# Message
	parts.append(message)

	var formatted := " ".join(parts)

	# Console output with color
	var color: String = LEVEL_COLORS[level]
	print_rich("[color=%s]%s[/color]" % [color, formatted])

	# File output (no color codes)
	if _file:
		_file.store_line(formatted)
		_file.flush()


# =============================================================================
# SHORTHAND METHODS - Use these for common systems
# =============================================================================

## Log player-related events
func player(message: String) -> void:
	debug(message, "Player")


## Log enemy-related events
func enemy(message: String) -> void:
	debug(message, "Enemy")


## Log card system events
func card(message: String) -> void:
	debug(message, "Card")


## Log combat events (damage, kills, etc.)
func combat(message: String) -> void:
	debug(message, "Combat")


## Log UI events
func ui(message: String) -> void:
	debug(message, "UI")


## Log spawner events
func spawner(message: String) -> void:
	debug(message, "Spawner")


## Log pickup events
func pickup(message: String) -> void:
	debug(message, "Pickup")


## Log game state changes
func state(message: String) -> void:
	info(message, "State")


# =============================================================================
# UTILITY METHODS
# =============================================================================

## Log with automatic variable formatting
## Usage: CustomLogger.fmt("Player HP: {hp}, Pos: {pos}", {"hp": 100, "pos": Vector2(10, 20)})
func fmt(template: String, values: Dictionary, level: Level = Level.DEBUG, context: String = "") -> void:
	var message := template
	for key in values:
		message = message.replace("{%s}" % key, str(values[key]))
	_log(level, message, context)


## Time a block of code
## Usage: var timer = CustomLogger.start_timer("Loading")
##        ... do stuff ...
##        CustomLogger.end_timer(timer)
func start_timer(label: String) -> Dictionary:
	return {"label": label, "start": Time.get_ticks_msec()}


func end_timer(timer: Dictionary) -> void:
	var elapsed: int = Time.get_ticks_msec() - timer.start
	debug("%s completed in %d ms" % [timer.label, elapsed], "Timer")


## Log once per key (useful for per-frame checks that shouldn't spam)
func once(key: String, message: String, context: String = "") -> void:
	if key in _logged_once:
		return
	_logged_once[key] = true
	debug(message, context)


## Reset "log once" tracking
func reset_once() -> void:
	_logged_once.clear()


# =============================================================================
# USAGE EXAMPLES
# =============================================================================
#
# Basic logging:
#   CustomLogger.debug("This is a debug message")
#   CustomLogger.info("Game started", "Main")
#   CustomLogger.warn("Low health!", "Player")
#   CustomLogger.error("Failed to load save", "SaveManager")
#
# Shorthand methods:
#   CustomLogger.player("Taking 10 damage")
#   CustomLogger.enemy("Spawned at (100, 200)")
#   CustomLogger.card("Collected Ace of Spades")
#   CustomLogger.combat("Dealt 50 damage to Slime")
#
# Formatted logging:
#   CustomLogger.fmt("HP: {hp}/{max}", {"hp": 50, "max": 100}, CustomLogger.Level.INFO, "Player")
#
# Timing:
#   var t = CustomLogger.start_timer("Wave spawn")
#   spawn_enemies(100)
#   CustomLogger.end_timer(t)  # Output: "Wave spawn completed in 45 ms"
#
# Log once (won't spam in _process):
#   func _process(delta):
#       if player.is_invincible:
#           CustomLogger.once("invincible", "Player is invincible", "Player")
#
# Change log level at runtime:
#   CustomLogger.set_level(CustomLogger.Level.WARN)  # Only warnings and errors
#
# Enable file logging:
#   CustomLogger.log_to_file = true
#   CustomLogger._open_log_file()
#
