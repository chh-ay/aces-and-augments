class_name CharacterLibrary
##
## Playable character roster. Animations are editor-authored SpriteFrames
## resources (res://resources/sprite_frames/character_*.tres) built from the
## "Time Elements" sheets by finalbossblues: walk_/idle_/attack_ per
## direction (south/west/east/north). Edit them in the SpriteFrames panel.
##

const DEFAULT_CHARACTER_ID: String = "ace"
const CHARACTERS: Array[Dictionary] = [
	{
		"id": "ace", "name": "Ace", "role": "Knight",
		"blurb": "Armored bruiser: takes 25% less damage and sweeps a short sword arc.",
		"frames": "res://resources/sprite_frames/character_ace.tres",
		"combat": "res://resources/combat_profiles/ace.tres",
	},
	{
		"id": "hood", "name": "Hood", "role": "Archer",
		"blurb": "Glass cannon: huge piercing arrow damage, but folds if caught.",
		"frames": "res://resources/sprite_frames/character_hood.tres",
		"combat": "res://resources/combat_profiles/hood.tres",
	},
]


static func get_combat_profile(character_id: String) -> CombatProfile:
	var profile_path: String = String(get_character(character_id).get("combat", ""))
	var profile: CombatProfile = load(profile_path) as CombatProfile
	return profile if profile != null else CombatProfile.new()


static func get_character(character_id: String) -> Dictionary:
	for character in CHARACTERS:
		if String(character.get("id", "")) == character_id:
			return character
	return CHARACTERS[0]


static func get_character_index(character_id: String) -> int:
	for index in range(CHARACTERS.size()):
		if String(CHARACTERS[index].get("id", "")) == character_id:
			return index
	return 0


static func is_valid_character_id(character_id: String) -> bool:
	for character in CHARACTERS:
		if String(character.get("id", "")) == character_id:
			return true
	return false


static func load_sprite_frames(character_id: String) -> SpriteFrames:
	return load(String(get_character(character_id).get("frames", ""))) as SpriteFrames


static func build_preview_texture(character_id: String) -> Texture2D:
	var frames: SpriteFrames = load_sprite_frames(character_id)
	if frames == null or not frames.has_animation("idle_south"):
		return null
	return frames.get_frame_texture("idle_south", 0)
