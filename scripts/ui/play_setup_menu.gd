class_name PlaySetupMenu
extends Control
##
## Pre-run loadout screen: pick a character and a difficulty, then start.
## Character cards are built from CharacterLibrary.CHARACTERS so the roster
## can change without touching this scene.
##

signal closed
signal start_requested

@onready var _cards_row: HBoxContainer = %Cards
@onready var _difficulty_button: Button = %DifficultyButton
@onready var _difficulty_hint: Label = %DifficultyHint
@onready var _start_button: Button = %StartButton
@onready var _back_button: Button = %BackButton

var _card_group: ButtonGroup = ButtonGroup.new()
var _card_buttons: Dictionary = {}


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_character_cards()
	_difficulty_button.pressed.connect(_on_difficulty_pressed)
	_start_button.pressed.connect(_on_start_pressed)
	_back_button.pressed.connect(dismiss)


func present() -> void:
	visible = true
	_sync_selection()
	_refresh_difficulty()
	_start_button.grab_focus()


func dismiss() -> void:
	if not visible:
		return
	visible = false
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismiss()


func _build_character_cards() -> void:
	for character in CharacterLibrary.CHARACTERS:
		var character_id: String = String(character.get("id", ""))
		var card: Button = Button.new()
		card.toggle_mode = true
		card.button_group = _card_group
		card.custom_minimum_size = Vector2(210, 225)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.pressed.connect(_on_card_pressed.bind(character_id))
		var content: VBoxContainer = VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 6)
		var margin: MarginContainer = MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.set_anchors_preset(Control.PRESET_FULL_RECT)
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			margin.add_theme_constant_override(side, 12)
		var preview: TextureRect = TextureRect.new()
		preview.custom_minimum_size = Vector2(96, 96)
		preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		preview.texture = CharacterLibrary.build_preview_texture(character_id)
		preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var name_label: Label = Label.new()
		name_label.text = "%s — %s" % [String(character.get("name", "")), String(character.get("role", ""))]
		name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_label.add_theme_font_size_override("font_size", 15)
		var blurb_label: Label = Label.new()
		blurb_label.text = String(character.get("blurb", ""))
		blurb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blurb_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		blurb_label.custom_minimum_size = Vector2(170, 0)
		blurb_label.add_theme_font_size_override("font_size", 12)
		blurb_label.add_theme_color_override("font_color", Color(0.62, 0.7, 0.78, 0.9))
		content.add_child(preview)
		content.add_child(name_label)
		content.add_child(blurb_label)
		margin.add_child(content)
		card.add_child(margin)
		_cards_row.add_child(card)
		_card_buttons[character_id] = card


func _sync_selection() -> void:
	var selected_id: String = GameManager.get_selected_character_id()
	for character_id in _card_buttons.keys():
		(_card_buttons[character_id] as Button).set_pressed_no_signal(character_id == selected_id)


func _on_card_pressed(character_id: String) -> void:
	GameManager.set_selected_character(character_id)


func _on_difficulty_pressed() -> void:
	GameManager.cycle_difficulty()
	_refresh_difficulty()


func _refresh_difficulty() -> void:
	_difficulty_button.text = GameManager.get_difficulty_button_text()
	var config: Dictionary = GameManager.get_selected_difficulty()
	_difficulty_hint.text = "Enemy speed %.0f%%  |  HP %.0f%%  |  spawn %.0f%%  |  cards %.0f%%" % [
		float(config.get("enemy_speed", 1.0)) * 100.0,
		float(config.get("enemy_health", 1.0)) * 100.0,
		float(config.get("spawn_rate", 1.0)) * 100.0,
		float(config.get("card_drop", 1.0)) * 100.0,
	]


func _on_start_pressed() -> void:
	visible = false
	start_requested.emit()
