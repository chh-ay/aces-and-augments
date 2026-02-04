extends Node

const ENV_TEXTURES: Dictionary = {
	"terminal": preload("res://assets/sprites/environment/prop_terminal.png"),
	"barrel": preload("res://assets/sprites/environment/prop_barrel.png"),
	"scrap": preload("res://assets/sprites/environment/prop_scrap.png"),
	"pipes": preload("res://assets/sprites/environment/prop_pipes.png"),
	"warning_sign": preload("res://assets/sprites/environment/prop_warning_sign.png"),
	"cable_bundle": preload("res://assets/sprites/environment/prop_cable_bundle.png"),
	"oil_spill": preload("res://assets/sprites/environment/prop_oil_spill.png"),
	"floor_grate": preload("res://assets/sprites/environment/prop_floor_grate.png"),
	"machinery": preload("res://assets/sprites/environment/prop_machinery.png")
}

const TILESET_TEXTURES: Dictionary = {
	"floor_base": preload("res://assets/tilesets/floor_tile.png"),
	"floor_detail": preload("res://assets/tilesets/arena_tileset.png"),
}


func get_env_texture(_name: String) -> Texture2D:
	var texture: Texture2D = ENV_TEXTURES.get(_name, null)
	return texture


func get_tileset_texture(_name: String) -> Texture2D:
	var texture: Texture2D = TILESET_TEXTURES.get(_name, null)
	return texture
