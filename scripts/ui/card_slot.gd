class_name CardSlot
extends PanelContainer

const EMPTY_BG: Color = Color(0.06, 0.08, 0.11, 0.92)
const EMPTY_BORDER: Color = Color(0.18, 0.28, 0.35, 0.55)
const EMPTY_TEXT: Color = Color(0.54, 0.60, 0.68, 0.88)
const SUIT_COLORS: Dictionary = {
	"hearts": Color(1.0, 0.43, 0.48, 1.0),
	"diamonds": Color(1.0, 0.68, 0.38, 1.0),
	"clubs": Color(0.72, 0.88, 0.92, 1.0),
	"spades": Color(0.88, 0.92, 1.0, 1.0)
}
const SUIT_SYMBOLS: Dictionary = {
	"hearts": "H",
	"diamonds": "D",
	"clubs": "C",
	"spades": "S"
}

@onready var _value_label: Label = $Margin/VBox/ValueLabel
@onready var _suit_label: Label = $Margin/VBox/SuitLabel
@onready var _name_label: Label = $Margin/VBox/NameLabel

var _base_panel_style: StyleBoxFlat

func _ready() -> void:
	_base_panel_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	set_card_data({})

func set_card_data(card_data: Dictionary) -> void:
	var panel_style: StyleBoxFlat = _base_panel_style.duplicate() as StyleBoxFlat
	var is_empty: bool = bool(card_data.get("empty", true))
	if is_empty:
		panel_style.bg_color = EMPTY_BG
		panel_style.border_color = EMPTY_BORDER
		_value_label.text = "--"
		_suit_label.text = "+"
		_name_label.text = "DRAW"
		_apply_text_color(EMPTY_TEXT)
	else:
		var suit: String = String(card_data.get("suit", "spades"))
		var accent: Color = SUIT_COLORS.get(suit, Color.WHITE)
		panel_style.bg_color = Color(0.10, 0.12, 0.15, 0.96)
		panel_style.border_color = accent
		_value_label.text = String(card_data.get("value_text", "?"))
		_suit_label.text = String(card_data.get("suit_symbol", SUIT_SYMBOLS.get(suit, "?")))
		_name_label.text = String(card_data.get("suit_name", suit.capitalize()))
		_apply_text_color(accent)
	add_theme_stylebox_override("panel", panel_style)

func _apply_text_color(accent: Color) -> void:
	_value_label.modulate = accent
	_suit_label.modulate = accent
	_name_label.modulate = accent.lightened(0.08)
