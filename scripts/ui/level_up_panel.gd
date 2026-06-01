class_name LevelUpPanel
extends Control
##
## Three-choice level-up modal. All styling comes from the Theme. The script
## only routes data into pre-existing labels and emits the chosen id.
##

signal option_selected(stat_id: String)

@onready var _stats_label: Label = $Center/Panel/Margin/VBox/SummaryRow/StatsCard/Margin/StatsLabel
@onready var _hand_label: Label = $Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandLabel
@onready var _choice_a: Button = $Center/Panel/Margin/VBox/ChoicesRow/ChoiceA
@onready var _choice_b: Button = $Center/Panel/Margin/VBox/ChoicesRow/ChoiceB
@onready var _choice_c: Button = $Center/Panel/Margin/VBox/ChoicesRow/ChoiceC

var _buttons: Array[Button] = []
var _choice_ids: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_buttons = [_choice_a, _choice_b, _choice_c]
	for index in range(_buttons.size()):
		_buttons[index].pressed.connect(_on_choice_pressed.bind(index))
	hide()


func present(choices: Array, summary: Dictionary = {}) -> void:
	_choice_ids.clear()
	_stats_label.text = String(summary.get("stats_text", ""))
	_hand_label.text = String(summary.get("hand_text", ""))
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		var choice: Dictionary = choices[index] if index < choices.size() else {}
		_choice_ids.append(String(choice.get("id", "")))
		_bind_choice(button, choice)
	show()
	_buttons[0].grab_focus()


func dismiss() -> void:
	hide()


# -- Internals -------------------------------------------------------------

func _on_choice_pressed(index: int) -> void:
	if index < 0 or index >= _choice_ids.size():
		return
	option_selected.emit(_choice_ids[index])


func _bind_choice(button: Button, choice: Dictionary) -> void:
	button.disabled = choice.is_empty()
	var rarity: String = String(choice.get("rarity", "Common")).to_upper()
	var title: String = String(choice.get("title", "Upgrade"))
	var description: String = String(choice.get("description", ""))
	button.text = "%s\n%s\n%s" % [rarity, title, description]
	var rarity_color: Color = choice.get("rarity_color", Color.WHITE)
	button.add_theme_color_override("font_color", rarity_color)
