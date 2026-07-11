class_name Hud
extends CanvasLayer

@onready var _health_label: Label = %HealthLabel
@onready var _health_bar: ProgressBar = %HealthBar
@onready var _aim_label: Label = %AimLabel
@onready var _timer_label: Label = %TimerLabel
@onready var _dash_chip: AbilityChip = %DashChip
@onready var _discard_chip: AbilityChip = %DiscardChip
@onready var _announcement_label: Label = %AnnouncementLabel
@onready var _xp_label: Label = %XpLabel
@onready var _xp_bar: ProgressBar = %XpBar
@onready var _hand_summary_label: Label = %SummaryLabel
@onready var _lock_button: Button = %LockButton
@onready var _card_slots: Array[CardSlot] = [
	%CardSlot1,
	%CardSlot2,
	%CardSlot3,
	%CardSlot4,
	%CardSlot5,
]

var _player: PlayerController
var _announcement_tween: Tween


func bind_player(player: PlayerController) -> void:
	_player = player
	player.health_changed.connect(_on_health_changed)
	player.experience_changed.connect(_on_experience_changed)
	player.hand_updated.connect(_apply_hand_state)
	player.aim_mode_changed.connect(_on_aim_mode_changed)
	_lock_button.pressed.connect(_on_lock_button_pressed)
	_refresh_health()
	_refresh_experience()
	_on_aim_mode_changed(player.is_manual_aim_enabled())
	_apply_hand_state(player.get_hand_state())


func _process(_delta: float) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	var dash_remaining: float = _player.get_dash_cooldown_remaining()
	var dash_detail: String = "ready" if dash_remaining <= 0.0 else "%.1fs" % dash_remaining
	_dash_chip.update_state(dash_remaining, _player.get_dash_cooldown_total(), dash_detail)
	var discard_remaining: float = _player.get_discard_cooldown_remaining()
	var discard_target: String = _player.get_discard_target_label()
	_discard_chip.update_state(
		discard_remaining,
		_player.get_discard_cooldown_total(),
		discard_target if not discard_target.is_empty() else "no cards"
	)


func bind_run_director(run_director: RunDirector) -> void:
	run_director.time_updated.connect(_on_time_updated)
	_on_time_updated(run_director.remaining_seconds)


# -- Signal handlers -------------------------------------------------------

func _on_health_changed(_hp: int) -> void:
	_refresh_health()


func _on_experience_changed(_xp: int, _required: int, _level: int) -> void:
	_refresh_experience()


func _on_aim_mode_changed(is_manual: bool) -> void:
	_aim_label.text = "Aim %s [Q]" % ("Manual" if is_manual else "Auto")


func _on_time_updated(remaining_seconds: float) -> void:
	_timer_label.text = _format_time(remaining_seconds)


func _on_lock_button_pressed() -> void:
	if _player != null:
		_player.lock_current_hand()


# -- View refresh ----------------------------------------------------------

func _refresh_health() -> void:
	var max_hp: int = _player.get_effective_max_health()
	_health_bar.max_value = max_hp
	_health_bar.value = _player.current_health
	_health_label.text = "HP %d / %d" % [_player.current_health, max_hp]


func _refresh_experience() -> void:
	_xp_bar.max_value = _player.required_experience
	_xp_bar.value = _player.current_experience
	_xp_label.text = "LV %d  XP %d / %d" % [_player.current_level, _player.current_experience, _player.required_experience]


func _apply_hand_state(state: Dictionary) -> void:
	_hand_summary_label.text = _format_hand_summary(state)
	var cards: Array = state.get("cards", [])
	var discard_index: int = int(state.get("discard_index", -1))
	for index in range(_card_slots.size()):
		var data: Dictionary = cards[index] if index < cards.size() else {"empty": true}
		_card_slots[index].set_card_data(data)
		_card_slots[index].set_selected(index == discard_index)
	var can_lock: bool = bool(state.get("can_lock", false))
	_lock_button.disabled = not can_lock
	_lock_button.text = _format_lock_text(state, can_lock)


# -- Pure formatters -------------------------------------------------------
static func _format_time(remaining_seconds: float) -> String:
	var total: int = max(int(ceil(remaining_seconds)), 0)
	@warning_ignore("integer_division")
	return "%02d:%02d" % [total / 60, total % 60]


static func _format_hand_summary(state: Dictionary) -> String:
	var card_count: int = int(state.get("card_count", 0))
	var body: String = "Cards %d / 5" % card_count
	if bool(state.get("selection_pending", false)) or bool(state.get("can_lock", false)):
		body += "\nPending %s [%s]" % [
			String(state.get("pending_hand_name", "No Hand")),
			String(state.get("pending_tier_name", "None"))
		]
	elif card_count > 0:
		body += "\nBuilding %s" % String(state.get("pending_hand_name", "Drawing..."))
	else:
		body += "\nActive %s [%s]" % [
			String(state.get("active_hand_name", "No Hand")),
			String(state.get("active_tier_name", "None"))
		]
	return body


static func _format_lock_text(state: Dictionary, can_lock: bool) -> String:
	if can_lock:
		return "Press Space To Lock %s" % String(state.get("pending_hand_name", "Hand"))
	if bool(state.get("selection_pending", false)):
		return "Choose Route"
	return "Collect 5 Cards To Lock [Space]"


## Transient run-event banner ("A SWARM APPROACHES", boss arrival, ...).
func show_announcement(text: String) -> void:
	if _announcement_tween != null and _announcement_tween.is_valid():
		_announcement_tween.kill()
	_announcement_label.text = text
	_announcement_label.modulate.a = 1.0
	_announcement_label.visible = true
	_announcement_tween = _announcement_label.create_tween()
	_announcement_tween.tween_interval(2.0)
	_announcement_tween.tween_property(_announcement_label, "modulate:a", 0.0, 0.7)
	_announcement_tween.tween_callback(_announcement_label.hide)
