class_name CardCache
extends Area2D
##
## Map objective: a chest that grants cards and scrap when the player
## touches it. Gives the terrain a reason to be crossed.
##

const CARD_SUITS: Array[String] = ["hearts", "diamonds", "clubs", "spades"]

@export var card_count: int = 3
@export var scrap_reward: int = 8

var _opened: bool = false

@onready var _sprite: Sprite2D = $Sprite


func _ready() -> void:
	add_to_group("card_cache")
	body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node) -> void:
	if _opened:
		return
	var player: PlayerController = body as PlayerController
	if player == null:
		return
	_opened = true
	_sprite.frame = 1
	for _index in range(card_count):
		player.add_card_to_hand(CARD_SUITS[randi_range(0, CARD_SUITS.size() - 1)], randi_range(1, 13))
	GameManager.add_run_scrap(scrap_reward)
	AudioManager.play_sfx("card_pickup", 1.1, -2.0)
	set_deferred("monitoring", false)
