class_name Hud
extends CanvasLayer

@onready var _health_bar: ProgressBar = $TopCard/Margin/VBox/HealthBar
@onready var _health_label: Label = $TopCard/Margin/VBox/HealthHeader/HealthLabel
@onready var _aim_label: Label = $TopCard/Margin/VBox/AimLabel
@onready var _xp_bar: ProgressBar = $BottomCard/Margin/VBox/XpBar
@onready var _xp_label: Label = $BottomCard/Margin/VBox/XpLabel
@onready var _hand_summary_label: Label = $HandCard/Margin/VBox/SummaryLabel
@onready var _card_slots: Array[CardSlot] = [
	$HandCard/Margin/VBox/CardsRow/CardSlot1,
	$HandCard/Margin/VBox/CardsRow/CardSlot2,
	$HandCard/Margin/VBox/CardsRow/CardSlot3,
	$HandCard/Margin/VBox/CardsRow/CardSlot4,
	$HandCard/Margin/VBox/CardsRow/CardSlot5
]
@onready var _lock_button: Button = $HandCard/Margin/VBox/LockButton
@onready var _timer_label: Label = $TimerCard/Margin/TimerLabel

var _player: PlayerController

func bind_player(player: PlayerController) -> void:
	_player = player
	player.health_changed.connect(_on_health_changed)
	player.experience_changed.connect(_on_experience_changed)
	player.hand_updated.connect(_on_hand_updated)
	player.aim_mode_changed.connect(_on_aim_mode_changed)
	if _lock_button != null and not _lock_button.pressed.is_connected(_on_lock_button_pressed):
		_lock_button.pressed.connect(_on_lock_button_pressed)
	_health_bar.max_value = player.get_effective_max_health()
	_health_bar.value = player.current_health
	_health_label.text = "HP %d / %d" % [player.current_health, player.get_effective_max_health()]
	_xp_bar.max_value = player.required_experience
	_xp_bar.value = player.current_experience
	_xp_label.text = "LV %d" % player.current_level
	_on_aim_mode_changed(player.is_manual_aim_enabled())
	_apply_hand_state(player._build_hand_state())

func bind_run_director(run_director: RunDirector) -> void:
	if run_director == null:
		return
	run_director.time_updated.connect(_on_time_updated)
	_on_time_updated(run_director.remaining_seconds)

func _on_health_changed(hp: int) -> void:
	var player: PlayerController = get_tree().get_first_node_in_group("player") as PlayerController
	if player == null:
		return
	_health_bar.max_value = player.get_effective_max_health()
	_health_bar.value = hp
	_health_label.text = "HP %d / %d" % [hp, player.get_effective_max_health()]

func _on_experience_changed(current_xp: int, required_xp: int, level: int) -> void:
	_xp_bar.max_value = required_xp
	_xp_bar.value = current_xp
	_xp_label.text = "LV %d" % level

func _on_aim_mode_changed(is_manual: bool) -> void:
	if _aim_label == null:
		return
	_aim_label.text = "Aim %s [Q]" % ("Manual" if is_manual else "Auto")

func _on_hand_updated(state: Dictionary) -> void:
	_apply_hand_state(state)

func _on_time_updated(remaining_seconds: float) -> void:
	
	if _timer_label == null:
		return
	_timer_label.text = _format_time(remaining_seconds)

func _format_time(remaining_seconds: float) -> String:
	var total_seconds: int = max(int(ceil(remaining_seconds)), 0)
	var minutes: int = int(floor(float(total_seconds) / 60.0))
	var seconds: int = total_seconds % 60
	return "%02d:%02d" % [minutes, seconds]

func _apply_hand_state(state: Dictionary) -> void:
	if _hand_summary_label != null:
		_hand_summary_label.text = "Cards %d / 5" % int(state.get("card_count", 0))
	var cards: Array = state.get("cards", [])
	for index in range(_card_slots.size()):
		if _card_slots[index] == null:
			continue
		_card_slots[index].set_card_data(cards[index] if index < cards.size() else {"empty": true})
	if _lock_button != null:
		var can_lock: bool = bool(state.get("can_lock", false))
		_lock_button.disabled = not can_lock
		if can_lock:
			_lock_button.text = "Press Space To Lock %s" % String(state.get("pending_hand_name", "Hand"))
		elif bool(state.get("selection_pending", false)):
			_lock_button.text = "Choose Route"
		else:
			_lock_button.text = "Collect 5 Cards To Lock [Space]"

func _on_lock_button_pressed() -> void:
	if _player == null:
		return
	_player.lock_current_hand()
