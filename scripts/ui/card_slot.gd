class_name CardSlot
extends PanelContainer
##
## Single card slot. Visual frame comes from the .tscn (PanelContainer styled
## by the Theme). This script only toggles a placeholder "+" label vs. the
## card art when a card is assigned.
##

const CARD_BASE_PATH: String = "res://assets/sprites/cards/kenney/card_%s_%s.png"
const PLACEHOLDER_TINT: Color = Color(0.54, 0.60, 0.68, 0.88)
const SELECTED_PANEL_STYLE: StyleBoxFlat = preload("res://resources/themes/card_slot_selected.tres")

@onready var _card_texture: TextureRect = %CardTexture
@onready var _placeholder_label: Label = %Placeholder

var _texture_cache: Dictionary = {}
var _normal_panel_style: StyleBox


func _ready() -> void:
	_normal_panel_style = get_theme_stylebox("panel")
	set_card_data({})


func set_card_data(card_data: Dictionary) -> void:
	if bool(card_data.get("empty", true)):
		_card_texture.visible = false
		_card_texture.texture = null
		_placeholder_label.visible = true
		_placeholder_label.modulate = PLACEHOLDER_TINT
		return
	_card_texture.visible = true
	_card_texture.texture = _get_card_texture(
		String(card_data.get("suit", "spades")),
		int(card_data.get("rank_value", 1))
	)
	_placeholder_label.visible = false


## Shows or clears the discard-selection outline without tinting the card art.
func set_selected(selected: bool) -> void:
	add_theme_stylebox_override(
		"panel",
		SELECTED_PANEL_STYLE if selected else _normal_panel_style
	)


func _get_card_texture(suit: String, rank_value: int) -> Texture2D:
	var safe_rank: int = clampi(rank_value, 1, 13)
	var key: String = "%s_%d" % [suit, safe_rank]
	if _texture_cache.has(key):
		return _texture_cache[key] as Texture2D
	var path: String = CARD_BASE_PATH % [suit, _rank_token(safe_rank)]
	var texture: Texture2D = load(path) as Texture2D
	_texture_cache[key] = texture
	return texture


static func _rank_token(rank_value: int) -> String:
	match rank_value:
		1: return "A"
		11: return "J"
		12: return "Q"
		13: return "K"
		_: return "%02d" % rank_value
