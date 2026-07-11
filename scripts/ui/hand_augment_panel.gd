class_name HandAugmentPanel
extends Control
##
## Three-choice "lock the hand" modal. Same shape as LevelUpPanel: the
## script writes text into labels declared in the .tscn and forwards button
## presses as a typed signal. All visuals come from the Theme.
##

signal option_selected(choice_id: String)

@onready var _stats_label: Label = %StatsLabel
@onready var _hand_label: Label = %HandLabel
@onready var _choice_a: Button = %ChoiceA
@onready var _choice_b: Button = %ChoiceB
@onready var _choice_c: Button = %ChoiceC
@onready var _card_slots: Array[CardSlot] = [
	%CardSlot1,
	%CardSlot2,
	%CardSlot3,
	%CardSlot4,
	%CardSlot5,
]

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
	var cards: Array = summary.get("cards", [])
	for index in range(_card_slots.size()):
		_card_slots[index].set_card_data(cards[index] if index < cards.size() else {"empty": true})
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
	content.set_choice_sections(
		String(choice.get("rarity", "Common")),
		choice.get("rarity_color", Color.WHITE),
		String(choice.get("title", "Route")),
		[
			{"header": "Blessing", "color": ChoiceCardContent.BLESSING_COLOR, "lines": choice.get("player_lines", [])},
			{"header": "Curse", "color": ChoiceCardContent.CURSE_COLOR, "lines": choice.get("enemy_lines", [])},
		]
	)
