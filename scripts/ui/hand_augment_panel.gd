class_name HandAugmentPanel
extends Control

signal option_selected(choice_id: String)

var _buttons: Array[Button] = []
var _rarity_labels: Array[Label] = []
var _title_labels: Array[Label] = []
var _blessing_labels: Array[Label] = []
var _curse_labels: Array[Label] = []
var _stats_label: Label
var _hand_label: Label
var _choice_ids: Array[String] = []

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	hide()
	_buttons = [
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceA") as Button,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceB") as Button,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceC") as Button
	]
	_rarity_labels = [
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceA/Margin/VBox/RarityLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceB/Margin/VBox/RarityLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceC/Margin/VBox/RarityLabel") as Label
	]
	_title_labels = [
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceA/Margin/VBox/TitleLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceB/Margin/VBox/TitleLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceC/Margin/VBox/TitleLabel") as Label
	]
	_blessing_labels = [
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceA/Margin/VBox/BlessingLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceB/Margin/VBox/BlessingLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceC/Margin/VBox/BlessingLabel") as Label
	]
	_curse_labels = [
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceA/Margin/VBox/CurseLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceB/Margin/VBox/CurseLabel") as Label,
		get_node_or_null("Center/Panel/Margin/VBox/ChoicesRow/ChoiceC/Margin/VBox/CurseLabel") as Label
	]
	_stats_label = get_node_or_null("Center/Panel/Margin/VBox/SummaryRow/StatsCard/Margin/StatsLabel") as Label
	_hand_label = get_node_or_null("Center/Panel/Margin/VBox/SummaryRow/HandCard/Margin/HandLabel") as Label
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		if button == null:
			continue
		button.pressed.connect(_on_choice_pressed.bind(index))

func present(choices: Array, summary: Dictionary = {}) -> void:
	_choice_ids.clear()
	if _stats_label != null:
		_stats_label.text = String(summary.get("stats_text", ""))
	if _hand_label != null:
		_hand_label.text = String(summary.get("hand_text", ""))
	for index in range(_buttons.size()):
		var button: Button = _buttons[index]
		if button == null:
			continue
		var choice: Dictionary = choices[index] if index < choices.size() else {}
		_choice_ids.append(String(choice.get("id", "")))
		button.disabled = choice.is_empty()
		button.text = ""
		var rarity_color: Color = choice.get("rarity_color", Color.WHITE)
		_apply_button_style(button, rarity_color)
		var rarity_label: Label = _rarity_labels[index]
		if rarity_label != null:
			rarity_label.text = String(choice.get("rarity", "Common")).to_upper()
			rarity_label.add_theme_color_override("font_color", rarity_color)
		var title_label: Label = _title_labels[index]
		if title_label != null:
			title_label.text = String(choice.get("title", "Route"))
			title_label.add_theme_color_override("font_color", rarity_color)
		var blessing_label: Label = _blessing_labels[index]
		if blessing_label != null:
			blessing_label.text = String(choice.get("player_text", "Blessing"))
		var curse_label: Label = _curse_labels[index]
		if curse_label != null:
			curse_label.text = String(choice.get("enemy_text", "Curse"))
	show()

func dismiss() -> void:
	hide()

func _on_choice_pressed(index: int) -> void:
	if index < 0 or index >= _choice_ids.size():
		return
	option_selected.emit(_choice_ids[index])

func _apply_button_style(button: Button, rarity_color: Color) -> void:
	var normal_style: StyleBoxFlat = button.get_theme_stylebox("normal").duplicate() as StyleBoxFlat
	var hover_style: StyleBoxFlat = button.get_theme_stylebox("hover").duplicate() as StyleBoxFlat
	var focus_style: StyleBoxFlat = button.get_theme_stylebox("focus").duplicate() as StyleBoxFlat
	var pressed_style: StyleBoxFlat = button.get_theme_stylebox("pressed").duplicate() as StyleBoxFlat
	var border_color: Color = rarity_color.lerp(Color.WHITE, 0.16)
	normal_style.border_color = border_color.darkened(0.18)
	hover_style.border_color = border_color
	focus_style.border_color = border_color
	pressed_style.border_color = border_color
	button.add_theme_stylebox_override("normal", normal_style)
	button.add_theme_stylebox_override("hover", hover_style)
	button.add_theme_stylebox_override("focus", focus_style)
	button.add_theme_stylebox_override("pressed", pressed_style)
