class_name DeathEffect
extends AnimatedSprite2D
##
## One-shot enemy death puff. Animation is an editor-authored SpriteFrames
## (res://resources/sprite_frames/death_effect.tres). Spawn with
## `DeathEffect.spawn(parent, position)`; frees itself when finished.
##

const FRAMES: SpriteFrames = preload("res://resources/sprite_frames/death_effect.tres")


static func spawn(parent: Node, world_position: Vector2, effect_scale: float = 1.0) -> void:
	if parent == null:
		return
	var effect: DeathEffect = DeathEffect.new()
	effect.global_position = world_position
	effect.scale = Vector2.ONE * effect_scale
	parent.add_child(effect)


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite_frames = FRAMES
	animation_finished.connect(queue_free)
	play("default")
