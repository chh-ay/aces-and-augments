class_name CardSlot
extends PanelContainer

const CARD_BASE_PATH: String = "res://assets/sprites/cards/kenney_large/card_%s_%s.png"
const CARD_FALLBACK_BASE_PATH: String = "res://assets/sprites/cards/kenney/card_%s_%s.png"
const EMPTY_BG: Color = Color(0.06, 0.08, 0.11, 0.92)
const EMPTY_BORDER: Color = Color(0.18, 0.28, 0.35, 0.55)
const FACE_BG: Color = Color(0.08, 0.11, 0.16, 0.98)
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

@onready var _card_texture: TextureRect = $Margin/CardTexture
@onready var _placeholder_label: Label = $Margin/Placeholder

var _base_panel_style: StyleBoxFlat
var _texture_cache: Dictionary = {}

func _ready() -> void:
	_base_panel_style = get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	set_card_data({})

func set_card_data(card_data: Dictionary) -> void:
	var panel_style: StyleBoxFlat = _base_panel_style.duplicate() as StyleBoxFlat
	var is_empty: bool = bool(card_data.get("empty", true))
	if is_empty:
		panel_style.bg_color = EMPTY_BG
		panel_style.border_color = EMPTY_BORDER
		_card_texture.visible = false
		_card_texture.texture = null
		_placeholder_label.visible = true
		_placeholder_label.text = "+"
		_placeholder_label.modulate = Color(0.54, 0.60, 0.68, 0.88)
	else:
		var suit: String = String(card_data.get("suit", "spades"))
		var accent: Color = SUIT_COLORS.get(suit, Color.WHITE)
		panel_style.bg_color = FACE_BG
		panel_style.border_color = accent
		_card_texture.visible = true
		_card_texture.modulate = Color.WHITE
		_card_texture.texture = _get_card_texture(suit, int(card_data.get("rank_value", 1)))
		_placeholder_label.visible = false
	add_theme_stylebox_override("panel", panel_style)

func _get_card_texture(suit: String, rank_value: int) -> Texture2D:
	var safe_rank: int = clampi(rank_value, 1, 13)
	var cache_key: String = "%s_%d" % [suit, safe_rank]
	if _texture_cache.has(cache_key):
		return _texture_cache[cache_key] as Texture2D
	var rank_token: String = _rank_to_token(safe_rank)
	var texture_path: String = CARD_BASE_PATH % [suit, rank_token]
	var texture: Texture2D = _load_texture_file(texture_path)
	if texture == null:
		texture = _load_texture_file(CARD_FALLBACK_BASE_PATH % [suit, rank_token])
	_texture_cache[cache_key] = texture
	return texture

func _load_texture_file(resource_path: String) -> Texture2D:
	var image: Image = Image.load_from_file(ProjectSettings.globalize_path(resource_path))
	if image == null or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _rank_to_token(rank_value: int) -> String:
	match rank_value:
		1:
			return "A"
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		_:
			return "%02d" % rank_value
