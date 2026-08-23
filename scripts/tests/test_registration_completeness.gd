extends RefCounted

## REGISTRATION COMPLETENESS — every test file on disk is actually run.
##
## This closes the one failure mode where a green suite means nothing: a test
## file that exists, compiles, and is never executed. Nothing else in the suite
## can see that. A dropped registration reddens no assertion, prints no
## warning, and lowers the passed-count by exactly the amount a reader would
## attribute to "I guess there are fewer tests than I remembered".
##
## WHY THIS EXISTS — it happened, on 2026-08-22.
##
## This repo is worked by two concurrent sessions sharing one git index (the
## gameplay session and an art pipeline). NOTES.md's "git commits with a
## concurrent pipeline" rule already required an explicit pathspec, which stops
## OUR commits absorbing the art session's files. It did nothing about the
## reverse: a reviewer ran `git checkout <ref> -- scripts/tests/test_runner.gd`
## to look at an older revision, that command STAGES, and the art session's
## next bare `git commit` swept the staged deletion into its own commit. HEAD
## lost this line:
##
##     preload("res://scripts/tests/test_mixed_tier_save_roundtrip.gd"),
##
## A clean checkout would then have run 45 tests, printed "45 passed, 0 failed"
## and been believed, while the save-round-trip coverage did not execute at all.
## The working tree was fine, so nobody editing locally would have noticed.
##
## The rule ("never leave the index dirty") is written down in NOTES.md. This
## file is what makes the rule survivable when someone eventually breaks it
## anyway — a rule with no detector is a rule you find out about later.
##
## SCOPE, deliberately narrow: this asserts every `test_*.gd` in the tests
## directory appears in TestRunner.TESTS. It does NOT check the reverse
## (TESTS naming a file that does not exist) — `preload` is resolved at parse
## time, so that case is already a hard compile error and kills the runner
## before it prints anything.

const TestRunnerScript = preload("res://scripts/tests/test_runner.gd")

const TESTS_DIR: String = "res://scripts/tests/"

## The runner itself lives in the tests directory and matches the `test_*.gd`
## pattern, but it is the harness rather than a test — it has no `test_name()`
## and registering it would recurse. Any future non-test helper that has to
## live here gets added to this list WITH A REASON, not silently.
const NOT_A_TEST: Array = [
	"test_runner.gd",
]

static func test_name() -> String:
	return "registration completeness (every test file on disk is actually run)"

static func run(_parent: Node) -> Dictionary:
	var failures: Array = []
	_case_every_file_registered(failures)
	if failures.is_empty():
		return { "ok": true, "message": "1 sub-case passes: every test file on disk is registered in the runner" }
	return { "ok": false, "message": "%d failures: %s" % [failures.size(), " | ".join(failures.slice(0, 16))] }

# ===========================================================================
# (1) EVERY test_*.gd IN THE TESTS DIRECTORY IS IN TestRunner.TESTS.
#
# Compares two sources that cannot drift without one of them being wrong:
#   - the FILESYSTEM, via DirAccess over the tests directory
#   - the RUNNER's own TESTS array, via each preloaded script's resource_path
#
# resource_path is used rather than parsing the source text because it is what
# the engine actually resolved. A preload of a path that does not exist is a
# parse error, so anything present in TESTS is real by construction; the only
# reachable asymmetry is a file on disk that nothing preloads, which is exactly
# the incident this guards.
# ===========================================================================
static func _case_every_file_registered(failures: Array) -> void:
	var on_disk: Array = _test_files_on_disk()
	# A directory read that comes back empty would make this sub-case vacuously
	# green — the same class of silent pass it exists to prevent. Pin a floor
	# well below the real count so it never needs maintenance, but high enough
	# that a failed or empty read cannot slip through.
	_check(failures, on_disk.size() >= 20,
		"(1) PREMISE: only %d test files found in %s. This sub-case compares disk against the runner, so an empty or failed directory read would pass it while checking nothing" % [on_disk.size(), TESTS_DIR])

	var registered: Dictionary = {}
	for script in TestRunnerScript.TESTS:
		registered[String(script.resource_path).get_file()] = true

	for file_name in on_disk:
		_check(failures, registered.has(file_name),
			"(1) %s exists in %s but is NOT in TestRunner.TESTS, so it never runs. A green suite does not cover it. Add a preload line, or add it to NOT_A_TEST with a reason if it is a helper rather than a test" % [file_name, TESTS_DIR])

## Every `test_*.gd` in the tests directory, excluding known non-tests.
## `.uid` sidecars and any other extension are filtered out.
static func _test_files_on_disk() -> Array:
	var out: Array = []
	var dir: DirAccess = DirAccess.open(TESTS_DIR)
	if dir == null:
		return out
	for file_name in dir.get_files():
		if not file_name.begins_with("test_"):
			continue
		if not file_name.ends_with(".gd"):
			continue
		if NOT_A_TEST.has(file_name):
			continue
		out.append(file_name)
	out.sort()
	return out

static func _check(failures: Array, condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)
