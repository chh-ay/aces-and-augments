class_name Hud
extends CanvasLayer

@onready var _health_bar: ProgressBar = $TopCard/Margin/VBox/HealthBar
@onready var _health_label: Label = $TopCard/Margin/VBox/HealthHeader/HealthLabel
@onready var _xp_bar: ProgressBar = $BottomCard/Margin/VBox/XpBar
@onready var _xp_label: Label = $BottomCard/Margin/VBox/XpLabel
@onready var _hand_label: Label = $HandCard/Margin/HandLabel
@onready var _timer_label: Label = $TimerCard/Margin/TimerLabel

func bind_player(player: PlayerController) -> void:
	player.health_changed.connect(_on_health_changed)
	player.experience_changed.connect(_on_experience_changed)
	player.hand_updated.connect(_on_hand_updated)
	_health_bar.max_value = player.max_health
	_health_bar.value = player.current_health
	_health_label.text = "HP %d / %d" % [player.current_health, player.max_health]
	_xp_bar.max_value = player.required_experience
	_xp_bar.value = player.current_experience
	_xp_label.text = "LV %d  XP %d / %d" % [player.current_level, player.current_experience, player.required_experience]
	_hand_label.text = "Hand %d / 5\n%s\nBuff x%.2f" % [player.collected_cards, player.active_hand_name, player.active_augment_bonus]

func bind_run_director(run_director: RunDirector) -> void:
	if run_director == null:
		return
	run_director.time_updated.connect(_on_time_updated)
	_on_time_updated(run_director.remaining_seconds)

func _on_health_changed(hp: int) -> void:
	var player: PlayerController = get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	_health_bar.max_value = player.max_health
	_health_bar.value = hp
	_health_label.text = "HP %d / %d" % [hp, player.max_health]

func _on_experience_changed(current_xp: int, required_xp: int, level: int) -> void:
	_xp_bar.max_value = required_xp
	_xp_bar.value = current_xp
	_xp_label.text = "LV %d  XP %d / %d" % [level, current_xp, required_xp]

func _on_hand_updated(card_count: int, hand_name: String, augment_bonus: float) -> void:
	_hand_label.text = "Hand %d / 5\n%s\nBuff x%.2f" % [card_count, hand_name, augment_bonus]

func _on_time_updated(remaining_seconds: float) -> void:
	
	if _timer_label == null:
		return
	_timer_label.text = _format_time(remaining_seconds)

func _format_time(remaining_seconds: float) -> String:
	var total_seconds: int = max(int(ceil(remaining_seconds)), 0)
	var minutes: int = int(floor(float(total_seconds) / 60.0))
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]
