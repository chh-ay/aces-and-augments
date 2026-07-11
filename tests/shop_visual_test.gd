extends Node
##
## Visual harness: stages the upgrade shop with a scrap balance and saves a
## screenshot. Pass scrap via `--scrap=<N>` after `++` on the command line.
## Run (needs a display): godot --path . res://tests/shop_visual_test.tscn
##
## NOTE: temporarily writes to the real save file; restores the previous
## scrap balance before quitting.
##

func _ready() -> void:
	var staged_scrap: int = 140
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--scrap="):
			staged_scrap = int(argument.trim_prefix("--scrap="))
	var previous_scrap: int = SaveManager.get_total_scrap(0)
	SaveManager.set_total_scrap(staged_scrap)
	var shop: UpgradeShop = (load("res://scenes/ui/upgrade_shop.tscn") as PackedScene).instantiate() as UpgradeShop
	add_child(shop)
	shop.present()
	await get_tree().create_timer(0.3).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/shop_visual.png")
	print("staged=%d actual=%d args=%s" % [staged_scrap, SaveManager.get_total_scrap(0), str(OS.get_cmdline_user_args())])
	SaveManager.set_total_scrap(previous_scrap)
	get_tree().quit(0)
