class_name LuckyTerminal
extends Node2D

@export_multiline var message: String = "CHEAT CODE FOUND\nTHE HOUSE ALWAYS DRAWS ACES"
@export_multiline var empty_hand_message: String = "CHEAT CODE FOUND\nDRAW SOME CARDS FIRST"
@export_multiline var spent_message: String = "CHEAT CODE FOUND\nTHE HOUSE HAS NOTHING LEFT"
@export var message_duration: float = 2.8

var _activated: bool = false

@onready var _trigger: Area2D = $Trigger
@onready var _message_panel: Control = $CanvasLayer/MessagePanel
@onready var _message_label: Label = $CanvasLayer/MessagePanel/Margin/VBox/Message
@onready var _timer: Timer = $HideTimer

func _ready() -> void:
	_message_label.text = message.replace("\\n", "\n")
	_message_panel.visible = false
	_trigger.body_entered.connect(_on_trigger_body_entered)
	_timer.timeout.connect(_on_hide_timer_timeout)

func _on_trigger_body_entered(body: Node) -> void:
	if _activated:
		return
	var player: PlayerController = body as PlayerController
	if player == null:
		return
	var result: Dictionary = player.convert_random_hand_card_to_ace()
	if bool(result.get("applied", false)):
		_activated = true
		_show_message(_build_success_message(result))
		AudioManager.play_sfx("card_pickup", 0.92, -1.0)
		return
	var reason: String = String(result.get("reason", "no_cards"))
	if reason == "all_aces":
		_activated = true
		_show_message(spent_message)
	else:
		_show_message(empty_hand_message)

func _on_hide_timer_timeout() -> void:
	_message_panel.visible = false

func _show_message(text: String) -> void:
	_message_label.text = text.replace("\\n", "\n")
	_message_panel.visible = true
	_timer.start(message_duration)

func _build_success_message(result: Dictionary) -> String:
	var suit: String = String(result.get("suit", "spades")).capitalize()
	var previous_value: int = int(result.get("from_value", 0))
	var hand_name: String = String(result.get("hand_name", "Drawing..."))
	return "CHEAT CODE FOUND\n%s %s -> A %s\nHand %s" % [
		_value_to_label(previous_value),
		suit,
		suit,
		hand_name
	]

func _value_to_label(value: int) -> String:
	match value:
		1:
			return "A"
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		_:
			return str(value)
