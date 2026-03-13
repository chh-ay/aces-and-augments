class_name LuckyTerminal
extends Node2D

@export_multiline var message: String = "CHEAT CODE FOUND\nTHE HOUSE ALWAYS DRAWS ACES"
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
	if _activated or not body.is_in_group("player"):
		return
	_activated = true
	_message_panel.visible = true
	_timer.start(message_duration)
	CustomLogger.info("Lucky terminal discovered", "EasterEgg")

func _on_hide_timer_timeout() -> void:
	_message_panel.visible = false
