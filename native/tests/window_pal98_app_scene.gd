# SPDX-License-Identifier: MIT
extends SceneTree
## The formal app's production pal98 display path: opening an original-source
## package hosts the verified scene window on the real app window, the real
## startup-capture opening reaches its named park with the loaded state
## adopted, and the current map/party/palette stay visible. No probe doubles
## exist here; the parked presentation is reported, never faked.
const App = preload("res://src/native_app.gd")
const Schema = preload("res://src/native_schema.gd")

var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
var app

func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)

func _window_pixels() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var pixels: Image = get_root().get_texture().get_image()
	pixels.convert(Image.FORMAT_RGBA8)
	return pixels

func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 4 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("_run")

func _run() -> void:
	get_root().title = "PAL Wanxiang | production pal98 scene path probe"
	get_root().size = Vector2i(960, 640)
	app = App.new()
	get_root().add_child(app)
	await process_frame
	app.session.set_focus(true)

	var before: Image = await _window_pixels()
	check(before.get_size() == Vector2i(960, 640), "the real window captures before the package opens")
	details.before_sha256 = Schema.digest(before.get_data())

	# The original-source package: the formal session refuses it, the
	# production pal98 display path starts instead.
	app.open_package(args[0])
	await process_frame
	await process_frame
	check(app.pal98 != null and app.pal98.active(),
		"the original package starts the production pal98 scene session")
	if app.pal98 == null or not app.pal98.active(): finish(); return
	var state: Dictionary = app.pal98.describe()
	details.describe = state
	check(state.get("current_scene") == 1 and state.get("loaded_map_id") == 20,
		"the real opening adopted the loaded scene 1 on MAP20: " + str(state))
	check(state.get("pending_kind") == "restore_background" and state.get("has_pending_presentation"),
		"the opening parks at the named initial-page restore, not an error")
	check(app.message.text.contains("原版开场显示已接入") and app.message.text.contains("未证实"),
		"the app reports the connected display and the unverified inputs")
	check(app.admission_picker.visible, "the capability report is still presented")

	# Palette: the active variant derives from the day/night word and the
	# installed colors match it.
	check(state.get("palette_variant") == 0, "the active palette variant follows the day/night word")

	# The window shows the composed scene frame.
	var shown: Image = await _window_pixels()
	check(shown.get_data() != before.get_data(), "the hosted scene changed the real window pixels")
	check(shown.save_png(args[1]) == OK, "the hosted scene PNG saved")

	# Ticks at the park: reported by name, state preserved, no fake movement.
	var world_before: Vector2i = Vector2i(app.pal98.game.state.globals.world_x, app.pal98.game.state.globals.world_y)
	var parked: Dictionary
	var stable := true
	for frame in range(12):
		parked = app.pal98.tick(1.0 / 60.0, PackedInt32Array([0,0,0,0,0,0,0,0,0]))
		if parked.has("error"): stable = false; break
	check(stable and parked.get("parked") == "restore_background" and parked.get("owner") == "dialogue_page",
		"parked ticks report the dialogue-page owner by name: " + str(parked))
	var after_state: Dictionary = app.pal98.describe()
	check(after_state.get("current_scene") == 1 and after_state.get("loaded_map_id") == 20,
		"parked ticks preserve the adopted opening state")
	check(Vector2i(app.pal98.game.state.globals.world_x, app.pal98.game.state.globals.world_y) == world_before,
		"no movement is faked while the opening presentation is parked")

	# Rebind the same path: the session restarts cleanly over the old one.
	app.open_package(args[0])
	await process_frame
	check(app.pal98.active() and app.pal98.describe().get("current_scene") == 1,
		"reopening the original package rebinds a fresh session")
	var rebound: Image = await _window_pixels()
	check(rebound.get_data() != before.get_data(), "the rebound session keeps presenting the scene")

	# A author (non-original) package closes the pal98 path: one live display.
	var author: bool = app.open_package(args[3])
	check(author and not app.session.state.is_empty(), "the author package opens the formal session")
	check(app.pal98 == null or not app.pal98.active(), "the author session stops the pal98 display path")
	finish()

func finish() -> void:
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size() - failed,
		"failed": failed, "success": failed == 0, "details": details,
		"original_gameplay": false, "injected_logical_input": true,
		"scope": "formal app production pal98 display path; probe initialization via the real startup capture; named parks retained"}, "  "))
	file.close(); quit(1 if failed else 0)
