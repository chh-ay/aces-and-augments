class_name HowToPlayMenu
extends Control
##
## Run briefing: controls as keycap chips and the run loop as numbered
## steps, built from the const tables below so copy edits stay one-liners.
##

signal closed

const SECTION_COLOR: Color = Color(0.95, 0.77, 0.24, 0.9)
const BODY_COLOR: Color = Color(0.78, 0.85, 0.92, 1.0)
const MUTED_COLOR: Color = Color(0.62, 0.7, 0.78, 0.92)

## key label -> action
const CONTROLS: Array[Array] = [
	["WASD", "Move"],
	["Shift", "Dash (brief invulnerability)"],
	["Q", "Toggle auto / manual aim"],
	["Space", "Lock a 5-card hand"],
	["X / C", "Select / discard a card"],
	["Esc", "Pause"],
]

const LOOP_STEPS: Array[String] = [
	"Kill enemies; grab XP and cards.",
	"Lock 5 cards; blessings curse foes.",
	"Survive to the boss and kill it.",
	"Take the exit to bank your scrap.",
	"Royal Flush exit = good ending.",
]

@onready var _controls_section: VBoxContainer = %ControlsSection
@onready var _loop_section: VBoxContainer = %LoopSection
@onready var _close_button: Button = %CloseButton

var _keycap_style: StyleBoxFlat


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(dismiss)
	_build_controls()
	_build_loop()


func present() -> void:
	visible = true
	_close_button.grab_focus()


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


# -- Section construction ----------------------------------------------------

func _build_controls() -> void:
	_keycap_style = StyleBoxFlat.new()
	_keycap_style.bg_color = Color(0.08, 0.1, 0.13, 0.95)
	_keycap_style.set_border_width_all(1)
	_keycap_style.border_color = Color(0.95, 0.77, 0.24, 0.5)
	_keycap_style.set_corner_radius_all(4)
	_keycap_style.content_margin_left = 8.0
	_keycap_style.content_margin_right = 8.0
	_keycap_style.content_margin_top = 1.0
	_keycap_style.content_margin_bottom = 1.0
	_controls_section.add_child(_make_section_header("CONTROLS"))
	for binding in CONTROLS:
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var keycap: PanelContainer = PanelContainer.new()
		keycap.add_theme_stylebox_override("panel", _keycap_style)
		keycap.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		keycap.custom_minimum_size = Vector2(64, 0)
		var key_label: Label = Label.new()
		key_label.text = String(binding[0])
		key_label.add_theme_font_size_override("font_size", 12)
		key_label.add_theme_color_override("font_color", SECTION_COLOR)
		key_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		keycap.add_child(key_label)
		row.add_child(keycap)
		var action_label: Label = Label.new()
		action_label.text = String(binding[1])
		action_label.add_theme_font_size_override("font_size", 13)
		action_label.add_theme_color_override("font_color", MUTED_COLOR)
		action_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(action_label)
		_controls_section.add_child(row)


func _build_loop() -> void:
	_loop_section.add_child(_make_section_header("THE LOOP"))
	for index in range(LOOP_STEPS.size()):
		var row: HBoxContainer = HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var number_label: Label = Label.new()
		number_label.text = "%d" % (index + 1)
		number_label.add_theme_font_size_override("font_size", 14)
		number_label.add_theme_color_override("font_color", SECTION_COLOR)
		number_label.custom_minimum_size = Vector2(18, 0)
		number_label.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		row.add_child(number_label)
		var step_label: Label = Label.new()
		step_label.text = LOOP_STEPS[index]
		step_label.add_theme_font_size_override("font_size", 13)
		step_label.add_theme_color_override("font_color", BODY_COLOR)
		step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		step_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(step_label)
		_loop_section.add_child(row)


func _make_section_header(text_value: String) -> Label:
	var header: Label = Label.new()
	header.text = text_value
	header.add_theme_font_size_override("font_size", 12)
	header.add_theme_color_override("font_color", SECTION_COLOR)
	return header
