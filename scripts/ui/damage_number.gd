class_name DamageNumber
extends Label
##
## Floating combat number: drifts up and fades, then frees itself.
##

static func spawn(parent: Node, world_position: Vector2, amount: int) -> void:
	if parent == null:
		return
	var number: DamageNumber = DamageNumber.new()
	number.text = str(amount)
	number.global_position = world_position
	parent.add_child(number)


func _init() -> void:
	z_index = 20
	add_theme_font_size_override("font_size", 13)
	add_theme_color_override("font_color", Color(1.0, 0.92, 0.75))
	add_theme_color_override("font_outline_color", Color(0.1, 0.08, 0.12, 0.9))
	add_theme_constant_override("outline_size", 3)


func _ready() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position:y", position.y - 22.0, 0.55)
	tween.tween_property(self, "modulate:a", 0.0, 0.55).set_ease(Tween.EASE_IN)
	tween.chain().tween_callback(queue_free)
