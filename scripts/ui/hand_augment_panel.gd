class_name HandAugmentPanel
extends Control
##
## Three-choice "lock the hand" modal. Same shape as LevelUpPanel: the
## script writes text into labels declared in the .tscn and forwards button
## presses as a typed signal. All visuals come from the Theme.
##

signal option_selected(choice_id: String)

@onready var _stats_label: Label = $Center/Panel/Margin/VBox/SummaryRow/StatsCard/Margin/StatsLabel
@onready var _hand_label: Label = $Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandVBox/HandLabel
@onready var _choice_a: Button = $Center/Panel/Margin/VBox/ChoicesRow/ChoiceA
@onready var _choice_b: Button = $Center/Panel/Margin/VBox/ChoicesRow/ChoiceB
@onready var _choice_c: Button = $Center/Panel/Margin/VBox/ChoicesRow/ChoiceC
@onready var _card_slots: Array[CardSlot] = [
	$Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandVBox/CardsRow/CardSlot1,
	$Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandVBox/CardsRow/CardSlot2,
	$Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandVBox/CardsRow/CardSlot3,
	$Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandVBox/CardsRow/CardSlot4,
	$Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandVBox/CardsRow/CardSlot5,
]

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
	var rarity: String = String(choice.get("rarity", "Common")).to_upper()
	var title: String = String(choice.get("title", "Route"))
	var blessing: String = String(choice.get("player_text", "Blessing"))
	var curse: String = String(choice.get("enemy_text", "Curse"))
	button.text = "%s\n%s\n\n%s\n\n%s" % [rarity, title, blessing, curse]
	var rarity_color: Color = choice.get("rarity_color", Color.WHITE)
	button.add_theme_color_override("font_color", rarity_color)
