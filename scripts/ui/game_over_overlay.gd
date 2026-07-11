class_name GameOverOverlay
extends Control
##
## Single end-of-run overlay. Caller (Main) hands in a result by calling
## `show_result(title, hint, art_texture, eyebrow, summary)`. Visibility and
## lifetime are owned entirely by this scene; the caller never touches the
## inner labels.
##

@onready var _eyebrow: Label = %Eyebrow
@onready var _title: Label = %Title
@onready var _art_center: CenterContainer = %ArtCenter
@onready var _ending_art: TextureRect = %EndingArt
@onready var _stats_card: PanelContainer = %StatsCard
@onready var _stats: Label = %Stats
@onready var _hint: Label = %Hint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func show_result(title_text: String, hint_text: String, art_texture: Texture2D = null, eyebrow_text: String = "RUN RESULT", summary: Dictionary = {}) -> void:
	_eyebrow.text = eyebrow_text
	_title.text = title_text
	_hint.text = hint_text
	if art_texture != null:
		_ending_art.texture = art_texture
		_art_center.visible = true
	else:
		_ending_art.texture = null
		_art_center.visible = false
	if summary.is_empty():
		_stats_card.visible = false
	else:
		_stats.text = _format_summary(summary)
		_stats_card.visible = true
	show()


func is_showing() -> bool:
	return visible


func dismiss() -> void:
	hide()


func _format_summary(summary: Dictionary) -> String:
	var total_seconds: int = int(summary.get("time_seconds", 0.0))
	var scrap: int = int(summary.get("scrap", 0))
	var scrap_line: String
	if scrap <= 0:
		scrap_line = "No scrap collected"
	elif bool(summary.get("banked", false)):
		scrap_line = "Scrap +%d banked" % scrap
	else:
		scrap_line = "Scrap %d lost — reach the exit to bank it" % scrap
	return "Survived %d:%02d  |  Level %d\nKills %d  |  Hands locked %d\n%s" % [
		int(total_seconds / 60.0),
		total_seconds % 60,
		int(summary.get("level", 1)),
		int(summary.get("kills", 0)),
		int(summary.get("hands_locked", 0)),
		scrap_line,
	]
