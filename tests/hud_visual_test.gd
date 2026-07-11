extends Node
##
## Visual harness: stages the HUD with charging Dash/Discard chips and a
## selected card slot, saves a screenshot, and exits.
## Run (needs a display): godot --path . res://tests/hud_visual_test.tscn
##

func _ready() -> void:
	var player: PlayerController = (load("res://scenes/player/player.tscn") as PackedScene).instantiate() as PlayerController
	add_child(player)
	var hud: Hud = (load("res://scenes/ui/hud.tscn") as PackedScene).instantiate() as Hud
	add_child(hud)
	hud.bind_player(player)
	player.add_card_to_hand("hearts", 12)
	player.add_card_to_hand("spades", 1)
	player.add_card_to_hand("clubs", 7)
	player.cycle_discard_selection()
	player.discard_card()
	player.cycle_discard_selection()
	player.start_dash()
	await get_tree().create_timer(0.9).timeout
	await RenderingServer.frame_post_draw
	var image: Image = get_viewport().get_texture().get_image()
	image.save_png("res://tests/hud_visual.png")
	print("screenshot saved")
	get_tree().quit(0)
