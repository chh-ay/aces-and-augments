class_name UpgradeShop
extends Control
##
## Between-runs meta shop. Rows are generated from
## GameManager.get_upgrade_definitions() so the catalogue can grow without
## touching the scene. Level progress renders as pips; costs go muted red
## when unaffordable and green MAXED when finished. Purchases flash the row
## and pop the scrap chip.
##

signal closed

const NAME_COLOR: Color = Color(0.88, 0.92, 0.97, 1.0)
const DESCRIPTION_COLOR: Color = Color(0.72, 0.78, 0.84, 0.92)
const COST_COLOR: Color = Color(0.95, 0.77, 0.24, 0.95)
const COST_BLOCKED_COLOR: Color = Color(0.88, 0.42, 0.38, 0.9)
const MAXED_COLOR: Color = Color(0.45, 0.87, 0.5, 0.95)
const PIP_FILLED_COLOR: Color = Color(0.95, 0.77, 0.24, 1.0)
const PIP_EMPTY_COLOR: Color = Color(0.2, 0.26, 0.32, 0.9)
const PIP_SIZE: Vector2 = Vector2(10, 10)
const MAXED_ROW_ALPHA: float = 0.72
const PURCHASE_FLASH_COLOR: Color = Color(1.5, 1.35, 0.9, 1.0)

@onready var _panel: PanelContainer = %Panel
@onready var _scrap_chip: PanelContainer = %ScrapChip
@onready var _scrap_label: Label = %ScrapLabel
@onready var _rows_container: VBoxContainer = %Rows
@onready var _close_button: Button = %CloseButton

## upgrade_id -> {pips: Array[ColorRect], cost: Label, button: Button, row: PanelContainer}
var _rows: Dictionary = {}
var _row_style: StyleBoxFlat
var _row_focus_style: StyleBoxFlat


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_close_button.pressed.connect(dismiss)
	_build_rows()
	GameManager.scrap_changed.connect(_refresh)
	GameManager.upgrades_changed.connect(_refresh)
	_refresh()


func present() -> void:
	visible = true
	_refresh()
	_focus_first_buyable()
	_play_entrance()


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


# -- Row construction -------------------------------------------------------

func _build_rows() -> void:
	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Color(0.075, 0.105, 0.14, 0.92)
	_row_style.set_border_width_all(1)
	_row_style.border_color = Color(0.18, 0.74, 0.92, 0.3)
	_row_style.set_corner_radius_all(8)
	_row_focus_style = _row_style.duplicate() as StyleBoxFlat
	_row_focus_style.border_color = Color(0.95, 0.77, 0.24, 0.8)
	_row_focus_style.bg_color = Color(0.09, 0.125, 0.16, 0.95)
	for definition in GameManager.get_upgrade_definitions():
		_add_row(definition)


func _add_row(definition: Dictionary) -> void:
	var upgrade_id: String = String(definition.get("id", ""))
	var row: PanelContainer = PanelContainer.new()
	row.add_theme_stylebox_override("panel", _row_style)
	var margin: MarginContainer = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 8)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 8)
	row.add_child(margin)
	var columns: HBoxContainer = HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	margin.add_child(columns)

	var copy: VBoxContainer = VBoxContainer.new()
	copy.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	copy.add_theme_constant_override("separation", 2)
	columns.add_child(copy)
	var name_row: HBoxContainer = HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 10)
	copy.add_child(name_row)
	var name_label: Label = Label.new()
	name_label.text = String(definition.get("name", "Upgrade"))
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", NAME_COLOR)
	name_row.add_child(name_label)
	var pips: Array[ColorRect] = _add_pips(name_row, int(definition.get("max_level", 0)))
	var description_label: Label = Label.new()
	description_label.text = String(definition.get("description", ""))
	description_label.add_theme_font_size_override("font_size", 12)
	description_label.add_theme_color_override("font_color", DESCRIPTION_COLOR)
	copy.add_child(description_label)

	var meta: VBoxContainer = VBoxContainer.new()
	meta.alignment = BoxContainer.ALIGNMENT_CENTER
	meta.add_theme_constant_override("separation", 4)
	columns.add_child(meta)
	var cost_label: Label = Label.new()
	cost_label.add_theme_font_size_override("font_size", 12)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	meta.add_child(cost_label)
	var buy_button: Button = Button.new()
	buy_button.custom_minimum_size = Vector2(96, 30)
	buy_button.text = "Buy"
	buy_button.pressed.connect(_on_buy_pressed.bind(upgrade_id))
	buy_button.focus_entered.connect(_set_row_highlight.bind(row, true))
	buy_button.focus_exited.connect(_set_row_highlight.bind(row, false))
	buy_button.mouse_entered.connect(_set_row_highlight.bind(row, true))
	buy_button.mouse_exited.connect(_set_row_highlight.bind(row, false))
	meta.add_child(buy_button)

	_rows_container.add_child(row)
	_rows[upgrade_id] = {"pips": pips, "cost": cost_label, "button": buy_button, "row": row}


func _add_pips(parent: Control, max_level: int) -> Array[ColorRect]:
	var pips: Array[ColorRect] = []
	var pip_row: HBoxContainer = HBoxContainer.new()
	pip_row.add_theme_constant_override("separation", 4)
	pip_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(pip_row)
	for _index in range(max_level):
		var pip: ColorRect = ColorRect.new()
		pip.custom_minimum_size = PIP_SIZE
		pip.color = PIP_EMPTY_COLOR
		pip_row.add_child(pip)
		pips.append(pip)
	return pips


# -- State refresh ----------------------------------------------------------

func _refresh(_arg1 = null, _arg2 = null) -> void:
	_scrap_label.text = "SCRAP %d" % GameManager.get_total_scrap()
	for upgrade_id in _rows.keys():
		var summary: Dictionary = GameManager.get_upgrade_summary(String(upgrade_id))
		if summary.is_empty():
			continue
		var widgets: Dictionary = _rows[upgrade_id]
		var level: int = int(summary.get("level", 0))
		var purchased: bool = bool(summary.get("purchased", false))
		var pips: Array[ColorRect] = widgets.get("pips", [] as Array[ColorRect])
		for index in range(pips.size()):
			pips[index].color = PIP_FILLED_COLOR if index < level else PIP_EMPTY_COLOR
		var cost_label: Label = widgets.get("cost") as Label
		if purchased:
			cost_label.text = "MAXED"
			cost_label.add_theme_color_override("font_color", MAXED_COLOR)
		else:
			cost_label.text = "Cost %d" % int(summary.get("cost", 0))
			cost_label.add_theme_color_override(
				"font_color",
				COST_COLOR if bool(summary.get("can_purchase", false)) else COST_BLOCKED_COLOR
			)
		var buy_button: Button = widgets.get("button") as Button
		buy_button.disabled = purchased or not bool(summary.get("can_purchase", false))
		buy_button.text = "Maxed" if purchased else "Buy"
		var row: PanelContainer = widgets.get("row") as PanelContainer
		row.modulate.a = MAXED_ROW_ALPHA if purchased else 1.0


func _focus_first_buyable() -> void:
	for upgrade_id in _rows.keys():
		var button: Button = _rows[upgrade_id].get("button") as Button
		if not button.disabled:
			button.grab_focus()
			return
	_close_button.grab_focus()


# -- Feedback ----------------------------------------------------------------

func _set_row_highlight(row: PanelContainer, highlighted: bool) -> void:
	row.add_theme_stylebox_override("panel", _row_focus_style if highlighted else _row_style)


func _play_entrance() -> void:
	_panel.modulate.a = 0.0
	var tween: Tween = create_tween()
	tween.tween_property(_panel, "modulate:a", 1.0, 0.14).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	AudioManager.play_sfx("card_pickup", 0.9, -10.0)


func _on_buy_pressed(upgrade_id: String) -> void:
	if not GameManager.purchase_upgrade(upgrade_id):
		return
	AudioManager.play_sfx("level_up", 1.25, -6.0)
	var widgets: Dictionary = _rows.get(upgrade_id, {})
	var row: PanelContainer = widgets.get("row") as PanelContainer
	if row != null:
		## _refresh already ran off the purchase signals; keep the alpha it
		## chose (maxed rows dim) while the flash color settles back.
		var settled: Color = Color(1.0, 1.0, 1.0, row.modulate.a)
		row.modulate = PURCHASE_FLASH_COLOR
		var row_tween: Tween = create_tween()
		row_tween.tween_property(row, "modulate", settled, 0.3)
	_scrap_chip.pivot_offset = _scrap_chip.size * 0.5
	_scrap_chip.scale = Vector2(1.12, 1.12)
	var chip_tween: Tween = create_tween()
	chip_tween.tween_property(_scrap_chip, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	## The row that just maxed out (or ran past our scrap) loses focusability;
	## keep keyboard flow alive by re-focusing the next buyable option.
	var button: Button = widgets.get("button") as Button
	if button != null and button.disabled:
		_focus_first_buyable()
