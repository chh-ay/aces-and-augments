class_name ChoiceCardContent
extends MarginContainer
##
## Structured content for a three-choice card button: small colored rarity
## eyebrow, prominent title, then either a simple description line
## (level-up) or tinted inset sections with a header and one row per stat
## (hand-lock blessing/curse). Replaces flat Button.text so the hierarchy
## reads at a glance.
##

const BLESSING_COLOR: Color = Color(0.55, 0.85, 0.55)
const CURSE_COLOR: Color = Color(0.92, 0.55, 0.5)
const BODY_COLOR: Color = Color(0.78, 0.84, 0.9)

var _rarity_label: Label
var _title_label: Label
var _body: VBoxContainer


static func attach(button: Button) -> ChoiceCardContent:
	var content: ChoiceCardContent = ChoiceCardContent.new()
	button.add_child(content)
	return content


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
		add_theme_constant_override(side, 16)
	var column: VBoxContainer = VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 8)
	_rarity_label = Label.new()
	_rarity_label.add_theme_font_size_override("font_size", 12)
	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 19)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_body = VBoxContainer.new()
	_body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_theme_constant_override("separation", 8)
	column.add_child(_rarity_label)
	column.add_child(_title_label)
	column.add_child(_make_spacer(2))
	column.add_child(_body)
	add_child(column)


## Simple variant: one plain description line under the title.
func set_choice(rarity: String, rarity_color: Color, title: String, description: String) -> void:
	_set_header(rarity, rarity_color, title)
	_clear_body()
	var label: Label = _make_line(description, BODY_COLOR, 14)
	_body.add_child(label)


## Sectioned variant. Each section: {"header": String, "color": Color,
## "lines": Array of String} rendered as a tinted inset block with one row
## per stat.
func set_choice_sections(rarity: String, rarity_color: Color, title: String, sections: Array) -> void:
	_set_header(rarity, rarity_color, title)
	_clear_body()
	for section in sections:
		var color: Color = section.get("color", BODY_COLOR)
		var block: PanelContainer = PanelContainer.new()
		block.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var style: StyleBoxFlat = StyleBoxFlat.new()
		style.bg_color = Color(color.r, color.g, color.b, 0.07)
		style.border_color = Color(color.r, color.g, color.b, 0.35)
		style.border_width_left = 3
		style.corner_radius_top_left = 4
		style.corner_radius_top_right = 4
		style.corner_radius_bottom_right = 4
		style.corner_radius_bottom_left = 4
		style.content_margin_left = 12.0
		style.content_margin_right = 10.0
		style.content_margin_top = 8.0
		style.content_margin_bottom = 8.0
		block.add_theme_stylebox_override("panel", style)
		var rows: VBoxContainer = VBoxContainer.new()
		rows.mouse_filter = Control.MOUSE_FILTER_IGNORE
		rows.add_theme_constant_override("separation", 3)
		var header: Label = _make_line(String(section.get("header", "")).to_upper(), color, 11)
		rows.add_child(header)
		for line in section.get("lines", []):
			rows.add_child(_make_line(String(line), BODY_COLOR, 14))
		block.add_child(rows)
		_body.add_child(block)


func _set_header(rarity: String, rarity_color: Color, title: String) -> void:
	visible = not title.is_empty() or not rarity.is_empty()
	_rarity_label.text = rarity.to_upper()
	_rarity_label.add_theme_color_override("font_color", rarity_color)
	_title_label.text = title


func _clear_body() -> void:
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()


func _make_line(text: String, color: Color, font_size: int) -> Label:
	var label: Label = Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_spacer(height: float) -> Control:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return spacer
