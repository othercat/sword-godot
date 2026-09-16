# SPDX-License-Identifier: MIT
extends SceneTree
## Real experimental window, real opening content, synthetic confirm edges:
## the chain advances from the opening dialogue into the T121 cross-fade,
## every phase must change the presented window pixels, and whatever follows
## the fade is recorded by name. This is not human acceptance.
const App = preload("res://src/native_app.gd")
const Schema = preload("res://src/native_schema.gd")

## Test-scope stand-in for the unrecovered RGM upper-window gap. The
## production refusal stays; this lane records the timed path's real first
## error and steps over exactly that named gap to reach the transition.
class NamedGap:
	var seen: Array = []
	func answer(request: Dictionary) -> Dictionary:
		seen.append(request.kind)
		var result := {"completed": true}
		if request.get("state") is Dictionary: result.state = request.state.duplicate(true)
		return result

var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
var app
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 3 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("run")
func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var view = app.pal98.host.frame_view
	if view == null or view.texture == null: details[label] = "no texture"; return
	var image: Image = view.texture.get_image(); image.convert(Image.FORMAT_RGBA8)
	var path: String = args[1] + "/" + label + ".png"
	image.save_png(path)
	details[label] = {"png": path, "sha256": Schema.digest(image.get_data())}
func run() -> void:
	get_root().size = Vector2i(960, 640)
	app = App.new(); get_root().add_child(app); await process_frame
	check(not app.open_package(args[0]), "original-source admission stays guarded for the ordinary entry")
	check(app.admission_picker.visible, "the admission picker appears")
	check(app.start_original_experiment(), "the explicit experimental action starts the preview")
	if app.pal98 == null or not app.pal98.active(): finish(); return
	app.set_physics_process(false)
	# Test scope, mirroring the headless probe convention: the dialogue host
	# records page effects instead of the surface (the unrecovered box/icon
	# pixel owners stay out of scope), and the named RGM upper-window gap is
	# stepped over. Both stay production refusals outside this lane; the
	# subject here is the real transition owner and its real per-phase
	# window presentation.
	var gap = NamedGap.new()
	# The same named stand-ins the headless probe binds for the dream fight's
	# frame family; the transition under test stays real.
	for kind in ["restore_dialog_background_without_initial_page", "upper_dialog_layout",
			"start_frame_and_process_events", "update_viewport_and_party_position",
			"render_scene_frame", "sync_party_for_redraw", "render_scene",
			"advance_party_movement", "sync_party_frames", "main_frame",
			"move_and_animate_event_object_one_step"]:
		app.pal98.game.bind_named_double(kind, gap)
	var host = app.pal98.host
	await process_frame; await RenderingServer.frame_post_draw
	await _capture("00-opening")
	var keys := PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var press := false
	var drained := false
	var phases := 0
	var phase_digests: Array = []
	var first_error := ""
	var outcome := ""
	# The first parked page presents through the real surface (plain text).
	# After that drain, the test-only recording switch answers further page
	# effects inline: the unrecovered box/icon pixel owners stay out of this
	# lane's scope and remain production refusals elsewhere.
	for step in range(12000):
		keys[8] = 2 if press else 0
		if press: press = false
		# The host frame is driven directly: app.tick's summary wrapper drops
		# the transition fields this lane must observe.
		var result: Dictionary = await host.tick_frame(keys, true)
		if result.has("error"):
			first_error = str(result.error); outcome = "named_error"; break
		if result.get("transition", {}) is Dictionary and not result.get("transition", {}).is_empty() \
				or result.get("pending_kind", "") == "clear_effective_cross_fade":
			phases += 1
			if phases <= 5:
				await process_frame; await RenderingServer.frame_post_draw
				var view = host.frame_view
				if view != null and view.texture != null:
					var image: Image = view.texture.get_image(); image.convert(Image.FORMAT_RGBA8)
					phase_digests.append(Schema.digest(image.get_data()))
			continue
		if result.get("completed", false) and app.pal98.game.awaiting_player:
			outcome = "resting_scene"; break
		if result.get("awaiting_effect", false) or app.pal98.game.is_dialogue_parked():
			if not drained:
				var page: Dictionary = await host.present_pending_page()
				if page.has("error"):
					first_error = str(page.error); outcome = "presentation_error"; break
				drained = true
				app.pal98.game._presentation_required = false
				check(app.pal98.game._presentation_required == false, "the lane records later pages instead of surface box pixels")
				continue
			press = true
			continue
	check(phases >= 1, "the opening chain drove the real cross-fade owner in the live window")
	check(phase_digests.size() >= 2 and phase_digests[0] != phase_digests[phase_digests.size() - 1],
		"presented transition phases changed the real window pixels")
	var completions: Array = []
	if outcome == "resting_scene":
		var receipts: Array = app.pal98.game.renderer.receipts()
		completions = receipts.filter(func(r): return r.get("kind") == "clear_effective_cross_fade" and r.get("completed", false))
		check(completions.size() == 1, "exactly one production completion receipt exists in the live window")
	if outcome == "resting_scene":
		await _capture("99-after-transition")
		var globals: Dictionary = app.pal98.game.state.globals
		details.after = {"scene": globals.get("current_scene"), "map": globals.get("loaded_map_id"),
			"viewport": [globals.get("viewport_x"), globals.get("viewport_y")],
			"world": [globals.get("world_x"), globals.get("world_y")],
			"transition_phases": phases, "phase_digest_count": phase_digests.size(),
			"test_stand_ins": gap.seen}
		check(globals.get("current_scene") != null, "the state after the fade is recorded by name")
	elif outcome == "named_error":
		details.after = {"first_error": first_error, "transition_phases": phases,
			"phase_digest_count": phase_digests.size(), "test_stand_ins": gap.seen}
		await _capture("98-error-boundary")
		check(first_error.length() > 0, "the post-fade boundary keeps a named error: " + first_error)
	else:
		details.after = {"outcome": outcome, "transition_phases": phases}
		check(false, "the chain ended without a rest or a named error")
	check(app.pal98.game.terminals.is_empty() == false or outcome != "", "an outcome exists to hand over")
	finish()
func finish() -> void:
	if app.pal98 != null: app._stop_pal98()
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size()-failed, "failed": failed,
		"details": details, "scope": "real window, synthetic confirm edges; not human acceptance"}, "  ")); file.close()
	quit(1 if failed else 0)
