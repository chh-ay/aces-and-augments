class_name CombatProfile
extends Resource
##
## Typed per-character combat tuning. Multipliers apply on top of the
## player's exported base stats, so difficulty and test-ground overrides
## keep working. `melee_hit_delay` lines damage up with the attack
## animation's contact frame.
##
## Authored as .tres files in res://resources/combat_profiles/ and loaded
## through CharacterLibrary.get_combat_profile().
##

@export var melee: bool = false
@export var damage_mult: float = 1.0
@export var interval_mult: float = 1.0
@export var range_mult: float = 1.0
@export var max_health_mult: float = 1.0
@export var move_speed_mult: float = 1.0
@export var damage_taken_mult: float = 1.0
@export var sfx_pitch: float = 1.0

@export_group("Projectiles")
@export var projectile_count: int = 1
@export var spread_degrees: float = 0.0
@export var jitter_degrees: float = 0.0
@export var pierce: int = 0
@export var projectile_speed: float = 460.0
@export var projectile_scale: Vector2 = Vector2.ONE
@export var projectile_color: Color = Color(1.0, 0.56, 0.5)
@export var projectile_texture: Texture2D

@export_group("Melee")
@export var melee_arc_degrees: float = 80.0
@export var melee_hit_delay: float = 0.0
