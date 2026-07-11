class_name AbilityChip
extends PanelContainer
##
## Compact HUD display for an ability cooldown and contextual detail.
##

const READY_LABEL_COLOR: Color = Color(1.0, 0.86, 0.42, 1.0)
const CHARGING_LABEL_COLOR: Color = Color(0.62, 0.70, 0.78, 0.9)
const READY_FILL_COLOR: Color = Color(0.38, 0.87, 0.44, 1.0)
const CHARGING_FILL_COLOR: Color = Color(0.92, 0.56, 0.18, 1.0)

@export var ability_name: String = "Ability"
@export var keybind_text: String = ""
## Embedded mode: drops the chip's own panel border/background so it can
## sit flush inside a parent panel (e.g. the hand panel).
@export var flat: bool = false

@onready var _title_label: Label = %TitleLabel
@onready var _detail_label: Label = %DetailLabel
@onready var _progress_bar: ProgressBar = %ProgressBar

var _fill_style: StyleBoxFlat
var _is_ready_state: bool = false


func _ready() -> void:
	_title_label.text = "%s %s" % [ability_name, keybind_text]
	if flat:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		var margin: MarginContainer = $Margin
		for side in ["margin_left", "margin_top", "margin_right", "margin_bottom"]:
			margin.add_theme_constant_override(side, 0)
	_fill_style = (_progress_bar.get_theme_stylebox("fill") as StyleBoxFlat).duplicate()
	_progress_bar.add_theme_stylebox_override("fill", _fill_style)
	_apply_ready_state(true)
	update_state(0.0, 0.0, "")

## Updates the charge fill and the chip's ready/charging presentation.
func update_state(remaining: float, total: float, detail: String) -> void:
	var is_ready: bool = total <= 0.0 or remaining <= 0.0
	_progress_bar.value = 1.0 if is_ready else clampf(1.0 - remaining / total, 0.0, 1.0)
	_detail_label.text = detail
	if is_ready == _is_ready_state:
		return
	_apply_ready_state(is_ready)
	if is_ready:
		_flash_ready()


## Style transitions happen only when readiness flips, never per frame.
func _apply_ready_state(is_ready: bool) -> void:
	_is_ready_state = is_ready
	_fill_style.bg_color = READY_FILL_COLOR if is_ready else CHARGING_FILL_COLOR
	_title_label.modulate = READY_LABEL_COLOR if is_ready else CHARGING_LABEL_COLOR
	_detail_label.modulate = Color.WHITE if is_ready else CHARGING_LABEL_COLOR


## Brief brightness pop so a cooldown finishing catches the eye mid-fight.
func _flash_ready() -> void:
	var tween: Tween = create_tween()
	modulate = Color(1.7, 1.7, 1.35, 1.0)
	tween.tween_property(self, "modulate", Color.WHITE, 0.35)
