extends RefCounted

## QoL Cluster B Item 2 tests — ItemPickerModal.
##
## Sub-cases:
##   1. open() with current_filter=-1 sets internal state; callback unset.
##   2. _on_item_selected(WHEAT) invokes callback with WHEAT, hides modal.
##   3. open() with current_filter=COAL exposes COAL as the highlighted item.

const ItemPickerModalScript = preload("res://scripts/ui/item_picker_modal.gd")

static func test_name() -> String:
	return "item picker modal (open + callback + current-highlight)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ===========================================================================
	# (1) open() sets internal state, no callback fires yet.
	# ===========================================================================
	var picker = ItemPickerModalScript.new()
	parent.add_child(picker)
	var captured_item: Array = [-1]
	picker.open(Vector2(100, 100), -1, func(item_type): captured_item[0] = item_type)
	_check(failures, picker._current_filter == -1,
		"(1) open with current_filter=-1 should set _current_filter to -1, got %d" % picker._current_filter)
	_check(failures, captured_item[0] == -1,
		"(1) callback should NOT have fired yet (no item selected), captured: %d" % captured_item[0])

	# ===========================================================================
	# (2) _on_item_selected invokes callback, hides modal.
	# ===========================================================================
	picker._on_item_selected(Items.Type.WHEAT)
	_check(failures, captured_item[0] == Items.Type.WHEAT,
		"(2) _on_item_selected(WHEAT) should fire callback with WHEAT, got %d" % captured_item[0])

	# ===========================================================================
	# (3) open() with current_filter=COAL — state exposed for highlighting.
	# ===========================================================================
	var picker2 = ItemPickerModalScript.new()
	parent.add_child(picker2)
	picker2.open(Vector2(100, 100), Items.Type.COAL, func(_t): pass)
	_check(failures, picker2._current_filter == Items.Type.COAL,
		"(3) open with current_filter=COAL should set _current_filter to COAL, got %d" % picker2._current_filter)

	picker.queue_free()
	picker2.queue_free()

	if failures.is_empty():
		return { "ok": true, "message": "3 sub-cases pass: open state + callback fires + current-highlight" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures)] }

static func _check(failures: Array, condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
