class_name HandManager
extends Node
##
## Owns the poker-hand loop: collected cards, discard selection/cooldown,
## hand evaluation, blessing/curse choice generation (suit-biased), the
## active blessing record, and hand history.
##
## Deliberately side-effect free toward gameplay: it never touches player
## stats, health, audio, or camera. PlayerController listens to
## `choice_applied` for stat application and re-emits its public signals.
##

signal updated
signal selection_requested(choices: Array)
signal choice_applied(choice: Dictionary)

const HAND_TIER_DATA: Dictionary = {
	PokerHandEvaluator.HandRank.HIGH_CARD: {"name": "Common", "color": Color("c7d0d9"), "player_scale": 0.55, "enemy_scale": 0.60},
	PokerHandEvaluator.HandRank.PAIR: {"name": "Common", "color": Color("c7d0d9"), "player_scale": 0.72, "enemy_scale": 0.76},
	PokerHandEvaluator.HandRank.TWO_PAIR: {"name": "Uncommon", "color": Color("73d98c"), "player_scale": 0.86, "enemy_scale": 0.88},
	PokerHandEvaluator.HandRank.THREE_OF_A_KIND: {"name": "Rare", "color": Color("56b7ff"), "player_scale": 1.00, "enemy_scale": 1.00},
	PokerHandEvaluator.HandRank.STRAIGHT: {"name": "Rare", "color": Color("56b7ff"), "player_scale": 1.08, "enemy_scale": 1.06},
	PokerHandEvaluator.HandRank.FLUSH: {"name": "Rare", "color": Color("56b7ff"), "player_scale": 1.08, "enemy_scale": 1.06},
	PokerHandEvaluator.HandRank.FULL_HOUSE: {"name": "Epic", "color": Color("d182ff"), "player_scale": 1.20, "enemy_scale": 1.16},
	PokerHandEvaluator.HandRank.FOUR_OF_A_KIND: {"name": "Epic", "color": Color("d182ff"), "player_scale": 1.30, "enemy_scale": 1.22},
	PokerHandEvaluator.HandRank.STRAIGHT_FLUSH: {"name": "Legendary", "color": Color("ffcc55"), "player_scale": 1.45, "enemy_scale": 1.30},
	PokerHandEvaluator.HandRank.ROYAL_FLUSH: {"name": "Mythic", "color": Color("ff8b39"), "player_scale": 1.80, "enemy_scale": 1.40}
}

## `suit` biases which blessings surface when locking a hand of that
## dominant suit: spades=aggression, hearts=survival, diamonds=reach/tempo,
## clubs=defense-tempo hybrids.
const HAND_CHOICE_TEMPLATES: Array[Dictionary] = [
	{
		"id": "kill_chain",
		"title": "Kill Chain",
		"suit": "spades",
		"curse_name": "Thick Hide",
		"player_stats": {"damage": 0.18, "attack_speed": 0.14},
		"enemy_stats": {"health": 0.07}
	},
	{
		"id": "vector_lens",
		"title": "Vector Lens",
		"suit": "diamonds",
		"curse_name": "Pursuit Grid",
		"player_stats": {"range": 0.22, "move_speed": 0.11},
		"enemy_stats": {"speed": 0.07}
	},
	{
		"id": "fortress_stack",
		"title": "Fortress Stack",
		"suit": "hearts",
		"curse_name": "War Engine",
		"player_stats": {"max_health": 0.24},
		"enemy_stats": {"health": 0.08, "damage": 0.05}
	},
	{
		"id": "overdrive_loop",
		"title": "Overdrive Loop",
		"suit": "clubs",
		"curse_name": "Hot Pursuit",
		"player_stats": {"move_speed": 0.13, "attack_speed": 0.13},
		"enemy_stats": {"speed": 0.08, "damage": 0.03}
	},
	{
		"id": "breach_rounds",
		"title": "Breach Rounds",
		"suit": "spades",
		"curse_name": "Bulwark Swarm",
		"player_stats": {"damage": 0.13, "range": 0.16},
		"enemy_stats": {"health": 0.08, "speed": 0.04}
	},
	{
		"id": "vampiric_pact",
		"title": "Vampiric Pact",
		"suit": "hearts",
		"curse_name": "Blood Frenzy",
		"player_stats": {"max_health": 0.16, "damage": 0.10},
		"enemy_stats": {"damage": 0.06}
	},
	{
		"id": "gamblers_edge",
		"title": "Gambler's Edge",
		"suit": "diamonds",
		"curse_name": "Loaded Dice",
		"player_stats": {"attack_speed": 0.19},
		"enemy_stats": {"speed": 0.09}
	},
	{
		"id": "iron_ante",
		"title": "Iron Ante",
		"suit": "clubs",
		"curse_name": "Rust Tax",
		"player_stats": {"max_health": 0.13, "range": 0.13},
		"enemy_stats": {"health": 0.05, "damage": 0.04}
	}
]

const PLAYER_STAT_LABELS: Dictionary = {
	"damage": "damage",
	"move_speed": "move speed",
	"attack_speed": "atk speed",
	"range": "range",
	"max_health": "max HP"
}

const ENEMY_STAT_LABELS: Dictionary = {
	"health": "enemy HP",
	"damage": "enemy damage",
	"speed": "enemy speed"
}

@export var discard_cooldown: float = 6.0

var collected_cards: int = 0
var pending_hand_name: String = "No Hand"
var active_hand_name: String = "No Hand"
var active_hand_tier: String = "None"
var active_blessing_title: String = "No Blessing"
var active_blessing_text: String = "No active blessing"
var active_curse_name: String = "No Curse"
var active_curse_text: String = "No enemy mutation"

var _cards: Array = []
var _pending_result: PokerHandEvaluator.HandResult
var _pending_choices: Array[Dictionary] = []
var _history: Array[Dictionary] = []
var _royal_flush_achieved: bool = false
var _discard_index: int = -1
var _discard_cooldown_remaining: float = 0.0


func _process(delta: float) -> void:
	_discard_cooldown_remaining = maxf(_discard_cooldown_remaining - delta, 0.0)


# -- Card intake and locking ------------------------------------------------

func add_card(suit: String, value: int) -> void:
	if _cards.size() >= 5 or not _pending_choices.is_empty():
		return
	_cards.append(PokerHandEvaluator.Card.new(suit, value))
	_refresh_pending_state()
	updated.emit()


func can_lock() -> bool:
	return _pending_result != null and _cards.size() == 5 and _pending_choices.is_empty()


func lock() -> void:
	if not can_lock():
		return
	_pending_choices = _build_choices(_pending_result)
	updated.emit()
	selection_requested.emit(_pending_choices)


## Books the chosen blessing/curse and clears the hand; stat application is
## the listener's job (choice carries `player_profile` / `enemy_profile`).
func apply_choice(choice_id: String) -> void:
	if _pending_result == null:
		return
	var choice: Dictionary = {}
	for entry in _pending_choices:
		if String(entry.get("id", "")) == choice_id:
			choice = entry
			break
	if choice.is_empty():
		return
	active_hand_name = _pending_result.name
	active_hand_tier = String(choice.get("tier_name", "Common"))
	active_blessing_title = String(choice.get("title", "Blessing"))
	active_blessing_text = String(choice.get("player_text", ""))
	active_curse_name = String(choice.get("curse_name", "Curse"))
	active_curse_text = String(choice.get("enemy_text", ""))
	_history.append({
		"name": _pending_result.name,
		"tier": active_hand_tier,
		"title": active_blessing_title,
		"curse_name": active_curse_name
	})
	if _pending_result.is_royal_flush:
		_royal_flush_achieved = true
	_cards.clear()
	collected_cards = 0
	pending_hand_name = "No Hand"
	_pending_result = null
	_pending_choices.clear()
	updated.emit()
	choice_applied.emit(choice)


func has_royal_flush() -> bool:
	return _royal_flush_achieved


## Debug helper: fabricates a Royal Flush and applies the first choice.
func force_royal_flush() -> void:
	_pending_result = PokerHandEvaluator.HandResult.new(PokerHandEvaluator.HandRank.ROYAL_FLUSH, [])
	pending_hand_name = _pending_result.name
	_pending_choices = _build_choices(_pending_result)
	if _pending_choices.is_empty():
		return
	apply_choice(String(_pending_choices[0].get("id", "")))


# -- Discard ----------------------------------------------------------------

## Cycles which card the next discard removes. Returns true when it moved.
func cycle_discard_selection() -> bool:
	if _cards.is_empty() or not _pending_choices.is_empty():
		return false
	_discard_index = wrapi(_discard_index + 1, 0, _cards.size())
	updated.emit()
	return true


## Removes the selected card (newest when nothing is selected). Returns true
## when a card was discarded.
func discard_selected() -> bool:
	if _cards.is_empty() or not _pending_choices.is_empty() or _discard_cooldown_remaining > 0.0:
		return false
	var index: int = _discard_index if _discard_index >= 0 and _discard_index < _cards.size() else _cards.size() - 1
	_cards.remove_at(index)
	_discard_index = -1
	_discard_cooldown_remaining = discard_cooldown
	_refresh_pending_state()
	updated.emit()
	return true


func get_discard_cooldown_remaining() -> float:
	return _discard_cooldown_remaining


## Label of the card a discard currently targets, e.g. "Q spades".
func get_discard_target_label() -> String:
	var card: PokerHandEvaluator.Card = _discard_target()
	if card == null:
		return ""
	return "%s %s" % [card.get_display_value(), card.suit]


func _discard_target() -> PokerHandEvaluator.Card:
	if _cards.is_empty():
		return null
	if _discard_index >= 0 and _discard_index < _cards.size():
		return _cards[_discard_index] as PokerHandEvaluator.Card
	return _cards.back() as PokerHandEvaluator.Card


# -- State for the HUD -------------------------------------------------------

func get_state() -> Dictionary:
	var history_lines: Array[String] = []
	for entry in _history.slice(max(_history.size() - 3, 0), _history.size()):
		history_lines.append("%s [%s]\nBlessing %s\nCurse %s" % [
			String(entry.get("name", "")),
			String(entry.get("tier", "Common")),
			String(entry.get("title", "Route")),
			String(entry.get("curse_name", "Curse"))
		])
	var pending_tier_name: String = "None"
	if _pending_result != null:
		pending_tier_name = String(_get_tier_data(_pending_result.rank).get("name", "Common"))
	return {
		"card_count": collected_cards,
		"cards": _build_card_slot_data(),
		"pending_hand_name": pending_hand_name,
		"pending_tier_name": pending_tier_name,
		"active_hand_name": active_hand_name,
		"active_tier_name": active_hand_tier,
		"active_blessing_title": active_blessing_title,
		"active_blessing_text": active_blessing_text,
		"active_curse_name": active_curse_name,
		"active_curse_text": active_curse_text,
		"can_lock": can_lock(),
		"selection_pending": not _pending_choices.is_empty(),
		"history_text": "\n\n".join(history_lines),
		"royal_flush_achieved": _royal_flush_achieved,
		"discard_index": _discard_index
	}


func get_hand_text() -> String:
	var hand_label: String = active_hand_name
	if not _pending_choices.is_empty():
		hand_label = "%s locked" % pending_hand_name
	return "Cards %d / 5\nPending %s\nActive %s [%s]\nBlessing %s\nCurse %s" % [
		collected_cards,
		pending_hand_name,
		hand_label,
		active_hand_tier,
		active_blessing_title,
		active_curse_name
	]


func get_locked_hand_text() -> String:
	if _pending_result == null:
		return ""
	return "Cards %d / 5\nLocked %s [%s]\nPick one route\nNext curse applies immediately" % [
		collected_cards,
		_pending_result.name,
		String(_get_tier_data(_pending_result.rank).get("name", "Common"))
	]


# -- Internals ---------------------------------------------------------------

func _refresh_pending_state() -> void:
	collected_cards = _cards.size()
	_discard_index = -1
	if collected_cards == 5:
		_pending_result = PokerHandEvaluator.evaluate_hand(_cards)
		pending_hand_name = _pending_result.name
	else:
		_pending_result = null
		pending_hand_name = "Drawing..."


func _build_choices(result: PokerHandEvaluator.HandResult) -> Array[Dictionary]:
	var templates: Array = HAND_CHOICE_TEMPLATES.duplicate(true)
	var choices: Array[Dictionary] = []
	## The dominant suit of the locked hand guarantees one matching blessing.
	var favored_suit: String = _dominant_suit()
	var favored: Array = templates.filter(func(t: Dictionary) -> bool: return String(t.get("suit", "")) == favored_suit)
	if not favored.is_empty():
		var pick: Dictionary = favored[randi_range(0, favored.size() - 1)]
		templates.erase(pick)
		choices.append(_materialize_choice(pick, result))
	while choices.size() < 3 and not templates.is_empty():
		var index: int = randi_range(0, templates.size() - 1)
		var template: Dictionary = templates[index]
		templates.remove_at(index)
		choices.append(_materialize_choice(template, result))
	return choices


func _dominant_suit() -> String:
	var counts: Dictionary = {}
	for card in _cards:
		var typed_card: PokerHandEvaluator.Card = card as PokerHandEvaluator.Card
		if typed_card != null:
			counts[typed_card.suit] = int(counts.get(typed_card.suit, 0)) + 1
	var best_suit: String = ""
	var best_count: int = 0
	for suit in counts.keys():
		if int(counts[suit]) > best_count:
			best_count = int(counts[suit])
			best_suit = String(suit)
	return best_suit


func _materialize_choice(template: Dictionary, result: PokerHandEvaluator.HandResult) -> Dictionary:
	var tier: Dictionary = _get_tier_data(result.rank)
	var player_profile: Dictionary = _scale_percentage_profile(
		template.get("player_stats", {}),
		float(tier.get("player_scale", 1.0))
	)
	var enemy_profile: Dictionary = _scale_percentage_profile(
		template.get("enemy_stats", {}),
		float(tier.get("enemy_scale", 1.0))
	)
	return {
		"id": "%s_%d" % [template.get("id", "choice"), int(result.rank)],
		"title": String(template.get("title", "Route")),
		"curse_name": String(template.get("curse_name", "Curse")),
		"tier_name": String(tier.get("name", "Common")),
		"rarity": String(tier.get("name", "Common")),
		"rarity_color": tier.get("color", Color.WHITE),
		"hand_name": result.name,
		"player_profile": player_profile,
		"enemy_profile": enemy_profile,
		"player_text": _format_profile_text(player_profile, PLAYER_STAT_LABELS, "Blessing"),
		"enemy_text": _format_profile_text(enemy_profile, ENEMY_STAT_LABELS, "Curse"),
		"player_lines": _profile_stat_lines(player_profile, PLAYER_STAT_LABELS),
		"enemy_lines": _profile_stat_lines(enemy_profile, ENEMY_STAT_LABELS),
		"description": "%s\n%s" % [
			_format_profile_text(player_profile, PLAYER_STAT_LABELS, "Blessing"),
			_format_profile_text(enemy_profile, ENEMY_STAT_LABELS, "Curse")
		]
	}


func _get_tier_data(rank: int) -> Dictionary:
	if HAND_TIER_DATA.has(rank):
		return HAND_TIER_DATA[rank]
	return HAND_TIER_DATA[PokerHandEvaluator.HandRank.HIGH_CARD]


func _scale_percentage_profile(base_profile: Dictionary, profile_scale: float) -> Dictionary:
	var scaled: Dictionary = {}
	for key in base_profile.keys():
		scaled[key] = 1.0 + float(base_profile[key]) * profile_scale
	return scaled


func _format_profile_text(profile: Dictionary, labels: Dictionary, prefix: String) -> String:
	return "%s %s" % [prefix, ", ".join(_profile_stat_lines(profile, labels))]


func _profile_stat_lines(profile: Dictionary, labels: Dictionary) -> Array[String]:
	var lines: Array[String] = []
	for key in profile.keys():
		var label: String = String(labels.get(key, key))
		var percent: float = (float(profile[key]) - 1.0) * 100.0
		lines.append("+%d%% %s" % [int(round(percent)), label])
	return lines


func _build_card_slot_data() -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	for card in _cards:
		if card is PokerHandEvaluator.Card:
			cards.append(_card_to_display_data(card as PokerHandEvaluator.Card))
	while cards.size() < 5:
		cards.append({"empty": true})
	return cards


func _card_to_display_data(card: PokerHandEvaluator.Card) -> Dictionary:
	return {
		"empty": false,
		"rank_value": card.value,
		"value_text": card.get_display_value(),
		"suit": card.suit,
		"suit_symbol": _get_card_suit_symbol(card.suit),
		"suit_name": card.suit.capitalize(),
		"code_text": "%s%s" % [card.get_display_value(), _get_card_suit_symbol(card.suit)]
	}


func _get_card_suit_symbol(suit: String) -> String:
	match suit:
		"spades": return "S"
		"clubs": return "C"
		"hearts": return "H"
		"diamonds": return "D"
	return "?"
