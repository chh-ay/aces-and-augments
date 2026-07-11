class_name UpgradePool
##
## Level-up upgrade catalogue: pool building, availability gating (caps,
## keystones, weapon type), rarity rolls (with luck rerolls), and value
## materialization with repeat-pick falloff. Pure logic; reads player state
## through its public API only.
##

const RARITIES: Array[Dictionary] = [
	{"name": "Common", "weight": 60.0, "band_min": 0.00, "band_max": 0.24, "color": Color("c7d0d9")},
	{"name": "Uncommon", "weight": 25.0, "band_min": 0.25, "band_max": 0.49, "color": Color("73d98c")},
	{"name": "Rare", "weight": 10.0, "band_min": 0.50, "band_max": 0.72, "color": Color("56b7ff")},
	{"name": "Epic", "weight": 4.5, "band_min": 0.73, "band_max": 0.90, "color": Color("d182ff")},
	{"name": "Legendary", "weight": 0.5, "band_min": 0.91, "band_max": 1.00, "color": Color("ffcc55")}
]
const KEYSTONE_COLOR: Color = Color("ffcc55")

static var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

## id -> {title, weight, roll_min, roll_max, label ("%d%%" style handled below)}
const STAT_UPGRADES: Array[Dictionary] = [
	{"id": "max_health", "title": "Bulk Up", "weight": 1.0, "min": 0.08, "max": 0.30, "fmt": "+%d%% max HP"},
	{"id": "move_speed", "title": "Overclock", "weight": 1.0, "min": 0.06, "max": 0.22, "fmt": "+%d%% move speed"},
	{"id": "projectile_damage", "title": "Hot Hands", "weight": 0.85, "min": 0.10, "max": 0.32, "fmt": "+%d%% damage"},
	{"id": "attack_speed", "title": "Loaded Deck", "weight": 0.9, "min": 0.06, "max": 0.22, "fmt": "+%d%% attack speed"},
	{"id": "range", "title": "Long Reach", "weight": 0.8, "min": 0.08, "max": 0.25, "fmt": "+%d%% attack range"},
	{"id": "regen", "title": "Nanoforge", "weight": 0.28, "min": 0.1, "max": 0.8, "fmt": ""},
	{"id": "lifesteal", "title": "Blood Circuit", "weight": 0.22, "min": 0.01, "max": 0.06, "fmt": ""},
]

## Seeds upgrade rolls so callers can reproduce an entire run.
static func seed_run(seed_value: int) -> void:
	_rng.seed = seed_value


## Randomizes upgrade rolls when a reproducible run is not requested.
static func randomize_run() -> void:
	_rng.randomize()


static func build_choices(player: PlayerController) -> Array:
	var pool: Array[Dictionary] = []
	for entry in STAT_UPGRADES:
		pool.append(entry.duplicate())
	if player.luck < PlayerController.LUCK_CAP:
		pool.append({"id": "luck", "title": "Lucky Streak", "weight": 0.3})
	if player.get_combat_profile().melee:
		if not player.melee_full_circle:
			pool.append({"id": "keystone_cyclone", "title": "Cyclone Edge", "weight": 0.14})
	elif player.bonus_pierce == 0:
		pool.append({"id": "keystone_ricochet", "title": "Piercer Rounds", "weight": 0.14})
	if not player.has_adrenaline_keystone():
		pool.append({"id": "keystone_adrenaline", "title": "Adrenal Rush", "weight": 0.14})
	pool = pool.filter(func(entry: Dictionary) -> bool: return _is_available(player, entry))
	var choices: Array = []
	while choices.size() < 3 and not pool.is_empty():
		var total_weight: float = 0.0
		for entry in pool:
			total_weight += float(entry.get("weight", 1.0))
		var roll: float = _rng.randf() * total_weight
		var accumulated: float = 0.0
		for index in range(pool.size()):
			accumulated += float(pool[index].get("weight", 1.0))
			if roll <= accumulated:
				choices.append(_materialize(player, pool[index]))
				pool.remove_at(index)
				break
	return choices


## Capped-out stats never appear as dead picks.
static func _is_available(player: PlayerController, entry: Dictionary) -> bool:
	match String(entry.get("id", "")):
		"max_health", "move_speed", "attack_speed", "range":
			var key: String = String(entry.get("id", ""))
			return player.get_augment_value(key) < float(PlayerController.AUGMENT_CAPS.get(key, 100.0)) - 0.001
		"projectile_damage":
			return player.get_augment_value("damage") < float(PlayerController.AUGMENT_CAPS.get("damage", 100.0)) - 0.001
		"regen":
			return player.health_regen_rate < PlayerController.REGEN_CAP - 0.001
		"lifesteal":
			return player.lifesteal_ratio < PlayerController.LIFESTEAL_CAP - 0.001
	return true


static func _materialize(player: PlayerController, base_entry: Dictionary) -> Dictionary:
	var rarity: Dictionary = _roll_rarity(player.luck)
	var entry: Dictionary = base_entry.duplicate(true)
	entry["rarity"] = rarity["name"]
	entry["rarity_color"] = rarity["color"]
	var upgrade_id: String = String(entry.get("id", ""))
	## Repeat picks of the same stat decay so no single stat can be spammed
	## to degeneracy (e.g. pure-lifesteal builds).
	var falloff: float = pow(PlayerController.REPEAT_PICK_FALLOFF, player.get_stat_pick_count(upgrade_id))
	match upgrade_id:
		"regen":
			entry["value"] = snappedf(_roll_value(rarity, 0.1, 0.8) * falloff, 0.1)
			entry["description"] = "+%.1f HP/s regen" % entry["value"]
		"lifesteal":
			entry["value"] = snappedf(_roll_value(rarity, 0.01, 0.06) * falloff, 0.01)
			entry["description"] = "+%.0f%% lifesteal" % (entry["value"] * 100.0)
		"keystone_cyclone":
			entry["rarity"] = "Keystone"
			entry["rarity_color"] = KEYSTONE_COLOR
			entry["description"] = "Sword sweeps hit in a full circle"
		"keystone_ricochet":
			entry["rarity"] = "Keystone"
			entry["rarity_color"] = KEYSTONE_COLOR
			entry["description"] = "Shots pierce 2 more enemies"
		"keystone_adrenaline":
			entry["rarity"] = "Keystone"
			entry["rarity_color"] = KEYSTONE_COLOR
			entry["description"] = "Dash cooldown reduced by 40%"
		"luck":
			entry["value"] = 1.0
			entry["description"] = "+1 luck: rarer upgrades appear more often"
		_:
			var value: float = _roll_value(rarity, float(entry.get("min", 0.05)), float(entry.get("max", 0.2))) * falloff
			entry["value"] = value
			entry["description"] = String(entry.get("fmt", "+%d%%")) % int(round(value * 100.0))
	return entry


static func _roll_rarity(luck: int) -> Dictionary:
	var best: Dictionary = _roll_rarity_once()
	for _extra in range(luck):
		var candidate: Dictionary = _roll_rarity_once()
		if float(candidate.get("band_min", 0.0)) > float(best.get("band_min", 0.0)):
			best = candidate
	return best


static func _roll_rarity_once() -> Dictionary:
	var total_weight: float = 0.0
	for rarity in RARITIES:
		total_weight += float(rarity.get("weight", 1.0))
	var roll: float = _rng.randf() * total_weight
	var accumulated: float = 0.0
	for rarity in RARITIES:
		accumulated += float(rarity.get("weight", 1.0))
		if roll <= accumulated:
			return rarity
	return RARITIES[0]


static func _roll_value(rarity: Dictionary, min_value: float, max_value: float) -> float:
	var t: float = _rng.randf_range(float(rarity["band_min"]), float(rarity["band_max"]))
	return lerpf(min_value, max_value, t)
