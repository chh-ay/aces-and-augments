extends Node
##
## Headless smoke test for the hand loop and level-up RNG.
## Run: godot --headless --path . res://tests/smoke_test.tscn
## Exit code 0 = all checks passed.
##
## Runs as a scene so autoload singletons (RunContext, GameManager, ...)
## are registered. Covers: card intake -> evaluation -> lock ->
## blessing/curse application (through the PlayerController facade and
## HandManager), discard selection/cooldown rules, and UpgradePool seed
## determinism.
##

var _failures: int = 0


func _ready() -> void:
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: PlayerController = player_scene.instantiate() as PlayerController
	add_child(player)
	_run_hand_loop(player)
	_run_discard_rules(player)
	_run_upgrade_determinism(player)
	player.free()
	print("---")
	print("FAILED %d checks" % _failures if _failures > 0 else "ALL CHECKS PASSED")
	get_tree().quit(1 if _failures > 0 else 0)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		_failures += 1
		print("FAIL: %s" % label)


func _run_hand_loop(player: PlayerController) -> void:
	var updates: Array = []
	var selections: Array = []
	var locks: Array = []
	player.hand_updated.connect(func(state: Dictionary) -> void: updates.append(state))
	player.hand_selection_requested.connect(func(choices: Array, summary: Dictionary) -> void: selections.append([choices, summary]))
	player.hand_locked.connect(func(hand_name: String, player_profile: Dictionary, enemy_profile: Dictionary) -> void: locks.append([hand_name, player_profile, enemy_profile]))

	for value in [1, 13, 12, 11, 10]:
		player.add_card_to_hand("spades", value)
	var state: Dictionary = player.get_hand_state()
	_check(int(state.get("card_count", -1)) == 5, "5 cards collected")
	_check(bool(state.get("can_lock", false)), "hand lockable at 5 cards")
	_check(String(state.get("pending_hand_name", "")) == "Royal Flush", "royal flush recognized")
	_check(not updates.is_empty(), "hand_updated emitted on intake")

	player.add_card_to_hand("hearts", 2)
	_check(int(player.get_hand_state().get("card_count", -1)) == 5, "6th card rejected")

	player.lock_current_hand()
	_check(selections.size() == 1, "selection requested exactly once")
	var choices: Array = selections[0][0] if not selections.is_empty() else []
	_check(choices.size() == 3, "3 blessing routes offered")
	var summary: Dictionary = selections[0][1] if not selections.is_empty() else {}
	_check(String(summary.get("hand_text", "")).contains("Locked Royal Flush"), "summary shows locked hand")
	var first_id: String = String(choices[0].get("id", "")) if not choices.is_empty() else ""
	_check(first_id.begins_with("kill_chain") or first_id.begins_with("breach_rounds"), "dominant suit (spades) guarantees a spades blessing")

	player.apply_hand_choice(first_id)
	_check(locks.size() == 1, "hand_locked emitted")
	_check(String(locks[0][0]) == "Royal Flush" if not locks.is_empty() else false, "locked hand name carried")
	_check(player.has_royal_flush_run(), "royal flush achievement recorded")
	state = player.get_hand_state()
	_check(int(state.get("card_count", -1)) == 0, "hand cleared after choice")
	_check(not bool(state.get("selection_pending", true)), "no pending selection after choice")
	_check(String(state.get("active_hand_name", "")) == "Royal Flush", "active hand shown in state")
	var blessed: bool = false
	for key in ["damage", "move_speed", "attack_speed", "range", "max_health"]:
		if absf(player.get_augment_value(String(key)) - 1.0) > 0.0001:
			blessed = true
	_check(blessed, "blessing folded into augment profile")
	var mutated: bool = false
	var mutation: Dictionary = player.get_enemy_mutation_profile()
	for key in mutation.keys():
		if absf(float(mutation[key]) - 1.0) > 0.0001:
			mutated = true
	_check(mutated, "curse folded into enemy mutation profile")


func _run_discard_rules(player: PlayerController) -> void:
	player.add_card_to_hand("hearts", 5)
	player.add_card_to_hand("clubs", 7)
	_check(player.get_discard_target_label() == "7 clubs", "newest card is default discard target")
	player.cycle_discard_selection()
	_check(int(player.get_hand_state().get("discard_index", -99)) == 0, "discard selection cycles to first card")
	_check(player.get_discard_target_label() == "5 hearts", "selected card is discard target")
	player.discard_card()
	_check(int(player.get_hand_state().get("card_count", -1)) == 1, "selected card discarded")
	_check(player.get_discard_cooldown_remaining() > 0.0, "discard cooldown started")
	player.discard_card()
	_check(int(player.get_hand_state().get("card_count", -1)) == 1, "discard blocked while on cooldown")
	_check(player.get_discard_cooldown_total() > 0.0, "discard cooldown total exposed")
	_check(player.get_dash_cooldown_total() > 0.0, "dash cooldown total exposed")


func _run_upgrade_determinism(player: PlayerController) -> void:
	UpgradePool.seed_run(1234)
	var first: Array = UpgradePool.build_choices(player)
	UpgradePool.seed_run(1234)
	var second: Array = UpgradePool.build_choices(player)
	_check(not first.is_empty() and str(first) == str(second), "same seed reproduces level-up choices")
	UpgradePool.seed_run(4321)
	var third: Array = UpgradePool.build_choices(player)
	_check(str(first) != str(third), "different seed varies level-up choices")
