class_name UpgradeShop
extends Control

signal closed

var _scrap_label: Label
var _rows: Array[Dictionary] = []

func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_STOP
	_scrap_label = get_node_or_null("Panel/Margin/VBox/ScrapLabel") as Label
	var close_button: Button = get_node_or_null("Panel/Margin/VBox/Buttons/CloseButton") as Button
	if close_button != null:
		close_button.pressed.connect(dismiss)
	_build_rows()
	if GameManager != null:
		GameManager.scrap_changed.connect(_refresh)
		GameManager.upgrades_changed.connect(_refresh)
	_refresh()

func present() -> void:
	visible = true
	_refresh()
	if not _rows.is_empty():
		var first_button: Button = _rows[0].get("button", null) as Button
		if first_button != null:
			first_button.grab_focus()

func dismiss() -> void:
	if not visible:
		return
	visible = false
	closed.emit()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		dismiss()

func _build_rows() -> void:
	_rows.clear()
	for index in range(3):
		_rows.append({
			"name": get_node_or_null("Panel/Margin/VBox/Rows/Upgrade%d/NameLabel" % (index + 1)) as Label,
			"desc": get_node_or_null("Panel/Margin/VBox/Rows/Upgrade%d/DescriptionLabel" % (index + 1)) as Label,
			"cost": get_node_or_null("Panel/Margin/VBox/Rows/Upgrade%d/CostLabel" % (index + 1)) as Label,
			"button": get_node_or_null("Panel/Margin/VBox/Rows/Upgrade%d/BuyButton" % (index + 1)) as Button,
			"id": ""
		})
	var definitions: Array[Dictionary] = GameManager.get_upgrade_definitions() if GameManager != null else []
	for index in range(min(_rows.size(), definitions.size())):
		var row: Dictionary = _rows[index]
		var upgrade_id: String = String(definitions[index].get("id", ""))
		row["id"] = upgrade_id
		var button: Button = row.get("button", null) as Button
		if button != null:
			button.pressed.connect(_on_buy_pressed.bind(upgrade_id))
		_rows[index] = row

func _refresh(_arg1 = null, _arg2 = null) -> void:
	if _scrap_label != null and GameManager != null:
		_scrap_label.text = "Scrap %d" % GameManager.get_total_scrap()
	for row in _rows:
		var upgrade_id: String = String(row.get("id", ""))
		if upgrade_id.is_empty():
			continue
		var summary: Dictionary = GameManager.get_upgrade_summary(upgrade_id) if GameManager != null else {}
		var name_label: Label = row.get("name", null) as Label
		var desc_label: Label = row.get("desc", null) as Label
		var cost_label: Label = row.get("cost", null) as Label
		var button: Button = row.get("button", null) as Button
		if name_label != null:
			name_label.text = "%s  Lv.%d/%d" % [
				String(summary.get("name", "Upgrade")),
				int(summary.get("level", 0)),
				int(summary.get("max_level", 0))
			]
		if desc_label != null:
			desc_label.text = String(summary.get("description", ""))
		if cost_label != null:
			if bool(summary.get("purchased", false)):
				cost_label.text = "MAXED"
			else:
				cost_label.text = "Cost %d" % int(summary.get("cost", 0))
		if button != null:
			var purchased: bool = bool(summary.get("purchased", false))
			button.disabled = purchased or not bool(summary.get("can_purchase", false))
			button.text = "Maxed" if purchased else "Buy"

func _on_buy_pressed(upgrade_id: String) -> void:
	if GameManager != null:
		GameManager.purchase_upgrade(upgrade_id)
	_refresh()
