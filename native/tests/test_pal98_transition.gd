# SPDX-License-Identifier: MIT
extends SceneTree
## The production T121 map execution: 88 default phases with an inclusive VB
## upper bound, lane = phase % 6, one wtime(delay) per phase through the bound
## logical clock, and the exact target page published only at the endpoint.
## The per-phase adpic pixel blend is an unrecovered PAL.dll helper and stays
## a named approximation; cancel and failure never publish a mixed page.
const Renderer = preload("res://src/native_pal98_scene_render.gd")
const Package = preload("res://src/native_package.gd")

class Clock:
	var units := 0
	var calls := 0
	var fail_at := -1
	func consume(units_in: int) -> Dictionary:
		if fail_at >= 0 and calls >= fail_at: return {"error": "injected clock failure"}
		units += units_in; calls += 1
		return {"consumed": units_in, "total": units}

var checks: Array = []
var failed := 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var records = package.pal98_graphics.open_records()

	var bare = Renderer.new(); bare.bind(records)
	var refused = bare.answer({"kind": "clear_effective_cross_fade",
		"state": {"globals": {"battle_mode": 0}}, "first": 0, "second": 1})
	check(refused.has("error") and str(refused.error).contains("bound logical clock"),
		"the host refuses a transition without a logical clock: " + str(refused.get("error", "")))
	check(not bare.bind_transition_clock(42), "a clock without consume is refused by name")

	var renderer = Renderer.new(); renderer.bind(records)
	var a = {"globals": {"loaded_map_id": 20, "viewport_x": 448, "viewport_y": 368,
		"view_offset_x": 13, "view_offset_y": 9, "previous_viewport_x": 0, "previous_viewport_y": 0, "battle_mode": 0}}
	check(not renderer.render(a).has("error"), "the pre-transition MAP20 page renders")
	var pixels_a = renderer.current_rgba()
	var b = a.duplicate(true); b.globals.loaded_map_id = 12
	renderer.render(b)
	var pixels_b = renderer.current_rgba()
	renderer.render(a)

	var clock = Clock.new()
	check(renderer.bind_transition_clock(clock), "the logical clock binds")
	var battle = b.duplicate(true); battle.globals.battle_mode = 1
	check(renderer.execute_clear_cross_fade(battle, 0, 1).has("error"),
		"the battle branch stays an explicitly unowned preparation")

	var done: Dictionary = renderer.execute_clear_cross_fade(b, 0, 3)
	check(done.get("completed") == true, "the default transition runs to its endpoint: " + str(done.get("error", "")))
	if not done.get("completed", false): finish(args); return
	var receipt: Dictionary = done.receipt
	check(receipt.phases == 89 and receipt.pixels_per_lane == 0x29AC and receipt.delay == 3,
		"the recovered phase count keeps the inclusive upper bound: 89 phases")
	check(clock.calls == 89 and clock.units == 267,
		"every phase consumed exactly one wtime(delay) through the logical clock")
	var lanes_ok := true
	for row in receipt.phase_receipts:
		if row.lane != row.phase % 6 or row.wtime != 3: lanes_ok = false
		if (row.phase < 6) != (row.step == "adpic0"): lanes_ok = false
	check(lanes_ok and receipt.phase_receipts[0].step == "adpic0" and receipt.phase_receipts[6].step == "adpic",
		"the lane rotation and the phase<6 adpic0 gate follow the recovered loop")
	check(receipt.named_gap.contains("adpic") and receipt.phase_receipts[0].presented == "pre_transition_page",
		"the unrecovered per-phase blend stays a named approximation in the receipt")
	check(renderer.current_rgba() == pixels_b and receipt.endpoint_sha256 != "",
		"only the exact target page is published, and only at the endpoint")
	var carried: Dictionary = done.state.globals
	check(carried.view_offset_x == 0 and carried.previous_viewport_x == 448,
		"the completed host carries the actual T244 state writeback")

	var custom = renderer.execute_clear_cross_fade(a, 5, 2)
	check(custom.get("completed") == true and custom.receipt.phases == 6
		and custom.receipt.phase_receipts[5].lane == 5,
		"an explicit phase argument keeps its inclusive bound: 6 phases for 5")
	check(renderer.current_rgba() != pixels_b, "the second transition publishes its own target page")

	var failing = Clock.new(); failing.fail_at = 3
	check(renderer.bind_transition_clock(failing), "the failing clock binds")
	var before = renderer.current_rgba()
	var cancelled: Dictionary = renderer.execute_clear_cross_fade(b, 0, 1)
	check(cancelled.has("error") and str(cancelled.error).contains("wtime"),
		"a clock failure mid-transition is returned by name: " + str(cancelled.get("error", "")))
	check(renderer.current_rgba() == before,
		"the interrupted transition publishes no mixed page")
	check(renderer.bind_transition_clock(clock), "the good clock rebinds")
	check(renderer.execute_clear_cross_fade(b, 0, 1).get("completed") == true,
		"the same owner recovers and completes after the interrupted attempt")

	finish(args)

func finish(args: Array) -> void:
	var output: Dictionary = {"suite": "test_pal98_transition",
		"scope": "recovered T121 phase/timing/endpoint execution; per-phase adpic blend is a named approximation",
		"checks": checks, "passed": checks.size() - failed, "failed": failed}
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify(output, "  ") + "\n"); file.close()
	print("PASS %d/%d" % [checks.size() - failed, checks.size()])
	quit(1 if failed > 0 else 0)
