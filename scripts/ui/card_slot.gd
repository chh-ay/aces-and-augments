class_name CardSlot
extends PanelContainer

const CARD_SHEET: Texture2D = preload("res://assets/sprites/cards/cards_sheet.png")
const CARD_SIZE: Vector2 = Vector2(16, 24)
const EMPTY_BG: Color = Color(0.06, 0.08, 0.11, 0.92)
const EMPTY_BORDER: Color = Color(0.18, 0.28, 0.35, 0.55)
const EMPTY_TEXT: Color = Color(0.54, 0.60, 0.68, 0.88)
const FACE_BG: Color = Color(0.08, 0.11, 0.16, 0.98)
const SUIT_COLORS: Dictionary = {
	"hearts": Color(1.0, 0.43, 0.48, 1.0),
	"diamonds": Color(1.0, 0.68, 0.38, 1.0),
	"clubs": Color(0.72, 0.88, 0.92, 1.0),
	"spades": Color(0.88, 0.92, 1.0, 1.0)
}
const SUIT_ROWS: Dictionary = {
	"hearts": 0,
	"diamonds": 1,
	"clubs": 2,
	"spades": 3
}
const SUIT_SYMBOLS: Dictionary = {
	"hearts": "H",
	"diamonds": "D",
	"clubs": "C",
	"spades": "S"
}

@onready var _face_texture: TextureRect = $Margin/Face
@onready var _placeholder_label: Label = $Margin/Placeholder

var _base_panel_style: StyleBoxFlat
var _card_texture_cache: Dictionary = {}

func _ready() -> void:
	_base_panel_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	set_card_data({})

func set_card_data(card_data: Dictionary) -> void:
	var panel_style: StyleBoxFlat = _base_panel_style.duplicate() as StyleBoxFlat
	var is_empty: bool = bool(card_data.get("empty", true))
	if is_empty:
		panel_style.bg_color = EMPTY_BG
		panel_style.border_color = EMPTY_BORDER
		_face_texture.texture = null
		_face_texture.visible = false
		_placeholder_label.visible = true
		_placeholder_label.text = "DRAW"
		_placeholder_label.modulate = EMPTY_TEXT
	else:
		var suit: String = String(card_data.get("suit", "spades"))
		var accent: Color = SUIT_COLORS.get(suit, Color.WHITE)
		panel_style.bg_color = FACE_BG
		panel_style.border_color = accent
		_face_texture.texture = _get_card_texture(suit, int(card_data.get("rank_value", 1)))
		_face_texture.visible = _face_texture.texture != null
		_placeholder_label.visible = not _face_texture.visible
		_placeholder_label.text = String(card_data.get("code_text", "%s%s" % [card_data.get("value_text", "?"), card_data.get("suit_symbol", SUIT_SYMBOLS.get(suit, "?"))]))
		_placeholder_label.modulate = accent
	add_theme_stylebox_override("panel", panel_style)

func _get_card_texture(suit: String, rank_value: int) -> Texture2D:
	var safe_rank: int = clampi(rank_value, 1, 13)
	var cache_key: String = "%s:%d" % [suit, safe_rank]
	if _card_texture_cache.has(cache_key):
		return _card_texture_cache[cache_key] as Texture2D
	var row: int = int(SUIT_ROWS.get(suit, 3))
	var atlas := AtlasTexture.new()
	atlas.atlas = CARD_SHEET
	atlas.region = Rect2(Vector2((safe_rank - 1) * CARD_SIZE.x, row * CARD_SIZE.y), CARD_SIZE)
	_card_texture_cache[cache_key] = atlas
	return atlas
