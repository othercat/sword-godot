# SPDX-License-Identifier: MIT
extends SceneTree
## The recovered T121 map transition engine: real per-lane pixel work per
## phase, an exact endpoint publish, and named approximations. The renderer
## shortcut still refuses; only the bounded owner advances and finishes.
const Renderer = preload("res://src/native_pal98_scene_render.gd")
const Package = preload("res://src/native_package.gd")
class Clock:
	var calls := 0
	var units := 0
	func consume(units: int) -> Dictionary:
		calls += 1; self.units += units; return {"consumed": units, "total": self.units}
class EmptyClock:
	func consume(_units: int) -> Dictionary: return {"error": "clock stopped"}
var checks: Array = []
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: push_error(label)
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]): quit(2); return
	var package = Package.new()
	if not package.load_package(args[0]): push_error(package.error); quit(2); return
	var renderer = Renderer.new(); renderer.bind(package.pal98_graphics.open_records())
	var a = {"globals":{"loaded_map_id":20,"viewport_x":448,"viewport_y":368,
		"view_offset_x":13,"view_offset_y":9,"previous_viewport_x":0,"previous_viewport_y":0,"battle_mode":0}}
	var b = a.duplicate(true); b.globals.loaded_map_id = 12
	check(not renderer.render(a).has("error"), "current MAP20 page renders")
	var base_rgba: PackedByteArray = renderer.current_rgba()
	check(not renderer.render(b).has("error"), "target MAP12 background renders")
	check(not renderer.render(a).has("error"), "current page is live again")
	var no_clock = renderer.begin_clear_cross_fade(b, 0, 3)
	check(no_clock.has("error") and str(no_clock.error).contains("logical clock"), "begin requires the bound logical clock")
	var clock := Clock.new()
	check(renderer.bind_transition_clock(clock), "clock binds")
	var battle = b.duplicate(true); battle.globals.battle_mode = 1
	check(renderer.begin_clear_cross_fade(battle, 0, 3).has("error"), "battle branch stays unowned")
	check(renderer.begin_clear_cross_fade(b, 32768, 1).has("error"), "arguments outside I2 are refused")
	var begun: Dictionary = renderer.begin_clear_cross_fade(b, 0, 3)
	check(not begun.has("error") and begun.phases == 89, "default phases are the inclusive 0..88 = 89 rounds")
	var owner = begun.owner
	check(renderer.restore_dialog_background().has("error") == false, "pushscr captured the live page into G00C0")
	var g00c0_rgba: PackedByteArray = renderer.current_rgba()
	check(g00c0_rgba == base_rgba, "G00C0 holds the pre-transition page")
	check(owner.frame_rgba().has("completed") and owner.frame_rgba().rgba.size() == 320 * 200 * 4, "phase frames compose as real RGBA")
	var first: Dictionary = owner.advance()
	check(not first.has("error"), "phase 0 advances: " + str(first.get("error", "ok")))
	check(first.get("receipt", {}).get("changed_pixels", 0) > 0, "phase 0 changes real pixels instead of only consuming the clock")
	check(first.get("receipt", {}).get("phase", -1) == 0 and first.get("receipt", {}).get("step", "") == "adpic0"
		and first.get("receipt", {}).get("lane", -1) == 0 and first.get("receipt", {}).get("lane_gap", -1) == 0, "phase 0 assimilates lane gap 0")
	var second: Dictionary = owner.advance()
	check(not second.has("error"), "phase 1 advances: " + str(second.get("error", "ok")))
	check(second.get("receipt", {}).get("step", "") == "adpic0" and second.get("receipt", {}).get("lane_gap", -1) == 3, "phase 1 uses the reconstructed lane gap 3")
	for phase in range(2, 89):
		var step: Dictionary = owner.advance()
		if step.has("error"): check(false, "phase " + str(phase) + " advances: " + str(step.get("error"))); break
		if phase < 6 and step.receipt.step != "adpic0": check(false, "adpic0 gate below phase 6"); break
		if phase >= 6 and step.receipt.step != "adpic": check(false, "later phases use adpic steps"); break
		if step.receipt.lane != phase % 6: check(false, "lane rotation follows phase % 6"); break
	check(owner.complete(), "all 89 rounds ran")
	check(clock.calls == 89 and clock.units == 267, "every phase consumed wtime(3) through the clock")
	check(owner.advance().has("error"), "exhausted phases refuse further advances")
	check(renderer.current_rgba() == base_rgba, "no phase replaced the displayed page before the endpoint")
	var endpoint: Dictionary = owner.finish()
	check(endpoint.get("completed", false), "the endpoint acknowledges the transition once: " + str(endpoint.get("error", "ok")))
	if endpoint.get("completed", false):
		check(endpoint.receipt.endpoint_sha256 == endpoint.receipt.target_sha256, "the published page is the exact prepared target")
		check(endpoint.receipt.phases == 89 and endpoint.receipt.pixels_per_lane == 0x29AC, "receipt pins the recovered structure")
		check(endpoint.receipt.named_gaps.size() == 3, "the named approximations travel with the receipt")
		check(endpoint.state.globals.view_offset_x == 0 and endpoint.state.globals.previous_viewport_x == 448,
			"endpoint hands back the T244 candidate state")
	check(renderer.current_rgba() != base_rgba and not renderer.current_rgba().is_empty(), "the displayed page changed at the endpoint")
	check(owner.finish().has("error"), "a second finish refuses")
	var explicit: Dictionary = renderer.begin_clear_cross_fade(b, 3, 1)
	check(not explicit.has("error") and explicit.phases == 4, "explicit phases keep the inclusive upper bound (0..3): " + str(explicit.get("error", "ok")))
	var small = explicit.get("owner")
	var small_ok := true
	for round in range(4):
		if small.advance().has("error"): small_ok = false; break
	var small_endpoint: Dictionary = small.finish()
	check(small_ok and small_endpoint.get("completed", false) and small_endpoint.receipt.phases == 4, "small transitions finish the same way")
	var cancellable: Dictionary = renderer.begin_clear_cross_fade(b, 0, 2)
	var cancel_owner = cancellable.owner
	var before_cancel: Dictionary = renderer.capture_page()
	cancel_owner.cancel()
	check(cancel_owner.advance().has("error") and cancel_owner.finish().has("error"), "a cancelled owner advances and finishes nothing")
	var restored: Dictionary = renderer.restore_dialog_background()
	check(not restored.has("error") and restored.get("receipt", {}).get("page_sha256", "") == before_cancel.receipt.page_sha256,
		"cancel restores the pre-transition G00C0")
	renderer.bind_transition_clock(EmptyClock.new())
	var failing: Dictionary = renderer.begin_clear_cross_fade(b, 0, 1)
	var failing_owner = failing.owner
	check(failing_owner.advance().has("error"), "a failing clock publishes no phase")
	check(failing_owner.finish().has("error"), "a failed owner cannot acknowledge")
	check(renderer.bind_transition_clock(clock), "the recovered clock rebinds after a failure")
	var after_failure: Dictionary = renderer.begin_clear_cross_fade(b, 0, 1)
	check(not after_failure.has("error"), "the renderer stays reusable after a failed owner")
	var refused: Dictionary = renderer.answer({"kind":"clear_effective_cross_fade","state":b,"first":0,"second":3})
	check(refused.has("error") and refused.get("prepared", false) and not refused.get("completed", false),
		"the renderer-scoped shortcut still refuses; completion belongs to the production host")
	var failed: int = checks.filter(func(x): return not x.passed).size()
	var f = FileAccess.open(args[1], FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed, "failed": failed}, "  ")); f.close()
	quit(1 if failed else 0)
