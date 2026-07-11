class_name LevelUpPanel
extends Control
##
## Three-choice level-up modal. All styling comes from the Theme. The script
## only routes data into pre-existing labels and emits the chosen id.
##

signal option_selected(stat_id: String)

@onready var _stats_label: Label = %StatsLabel
@onready var _hand_label: Label = %HandLabel
@onready var _choice_a: Button = %ChoiceA
@onready var _choice_b: Button = %ChoiceB
@onready var _choice_c: Button = %ChoiceC

var _buttons: Array[Button] = []
var _choice_ids: Array[String] = []
var _card_contents: Array[ChoiceCardContent] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_buttons = [_choice_a, _choice_b, _choice_c]
	for index in range(_buttons.size()):
		_buttons[index].pressed.connect(_on_choice_pressed.bind(index))
		_card_contents.append(ChoiceCardContent.attach(_buttons[index]))
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
	button.text = ""
	var content: ChoiceCardContent = _card_contents[_buttons.find(button)]
	content.set_choice(
		String(choice.get("rarity", "Common")),
		choice.get("rarity_color", Color.WHITE),
		String(choice.get("title", "Upgrade")),
		String(choice.get("description", ""))
	)
