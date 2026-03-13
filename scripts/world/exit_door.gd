class_name ExitDoor
extends Node2D

signal player_exited

@export var prompt_text: String = "EXIT"

@onready var _trigger: Area2D = $Trigger
@onready var _label: Label = $CanvasLayer/PromptPanel/Margin/Label
@onready var _panel: Panel = $CanvasLayer/PromptPanel

var _activated: bool = false

func _ready() -> void:
	_panel.visible = false
	if _label != null:
		_label.text = prompt_text
	if _trigger != null:
		_trigger.monitoring = true
		_trigger.monitorable = true
		_trigger.collision_layer = 0
		_trigger.collision_mask = 1
		_trigger.body_entered.connect(_on_body_entered)
		_trigger.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node) -> void:
	if _activated:
		return
	if body is PlayerController:
		_activated = true
		_panel.visible = true
		call_deferred("_emit_player_exited")

func _on_body_exited(body: Node) -> void:
	if body is PlayerController:
		_panel.visible = false

func _emit_player_exited() -> void:
	player_exited.emit()
