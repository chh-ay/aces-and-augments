class_name GameOverOverlay
extends Control
##
## Single end-of-run overlay. Caller (Main) hands in a result by calling
## `show_result(title, hint, art_texture)`. Visibility/lifetime is owned
## entirely by this scene; the caller never touches the inner labels.
##

@onready var _eyebrow: Label = $Center/Panel/Margin/VBox/Eyebrow
@onready var _title: Label = $Center/Panel/Margin/VBox/Title
@onready var _art_center: CenterContainer = $Center/Panel/Margin/VBox/ArtCenter
@onready var _ending_art: TextureRect = $Center/Panel/Margin/VBox/ArtCenter/EndingArt
@onready var _hint: Label = $Center/Panel/Margin/VBox/HintCard/Margin/Hint


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	hide()


func show_result(title_text: String, hint_text: String, art_texture: Texture2D = null, eyebrow_text: String = "RUN RESULT") -> void:
	_eyebrow.text = eyebrow_text
	_title.text = title_text
	_hint.text = hint_text
	if art_texture != null:
		_ending_art.texture = art_texture
		_art_center.visible = true
	else:
		_ending_art.texture = null
		_art_center.visible = false
	show()


func is_showing() -> bool:
	return visible


func dismiss() -> void:
	hide()
