extends RefCounted

## SlotClickHandler tests (QoL Cluster A — session-qol-cluster-a).
##
## 13 sub-suites covering refactor regression, shift+LMB matrix, ctrl+LMB
## picker semantics. See docs/superpowers/specs/2026-05-10-qol-cluster-a-design.md
## §7 for the full plan.

static func test_name() -> String:
	return "slot click handler (refactor regression + shift matrix + ctrl picker)"

static func run(parent: Node) -> Dictionary:
	var failures: Array = []

	# ---------- (split_half util sanity — used by every other sub-suite) ----------
	_check(failures, SlotClickHandler.split_half(0) == 0,
		"(util) split_half(0) should be 0")
	_check(failures, SlotClickHandler.split_half(1) == 1,
		"(util) split_half(1) should be 1 (ceil(0.5)=1)")
	_check(failures, SlotClickHandler.split_half(2) == 1,
		"(util) split_half(2) should be 1")
	_check(failures, SlotClickHandler.split_half(7) == 4,
		"(util) split_half(7) should be 4 (ceil(3.5)=4)")
	_check(failures, SlotClickHandler.split_half(100) == 50,
		"(util) split_half(100) should be 50")

	if failures.is_empty():
		return { "ok": true, "message": "split_half util passes (1 sub-suite stub — rest land in later tasks)" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), "; ".join(failures.slice(0, 6))] }

# ---------- helpers ----------

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
