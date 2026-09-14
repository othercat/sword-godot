# SPDX-License-Identifier: MIT
extends SceneTree
## Actual optional preview window. These checks do not certify original gameplay.
const App = preload("res://src/native_app.gd")
const Schema = preload("res://src/native_schema.gd")
const Background = preload("res://src/native_pal98_map_background.gd")
const Occlusion = preload("res://src/native_pal98_map_occlusion.gd")
var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
var app
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 4 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("run")
func run() -> void:
	get_root().size = Vector2i(960, 640)
	app = App.new(); get_root().add_child(app); await process_frame
	check(not app.open_package(args[0]), "ordinary original admission remains guarded")
	check(app.pal98 == null and app.admission_picker.visible, "opening does not silently start provisional state")
	check(app.start_original_experiment(), "explicit experimental action starts the preview")
	if app.pal98 == null or not app.pal98.active(): finish(); return
	app.set_physics_process(false)
	details.describe = app.pal98.describe()
	check(app.message.text.contains("初值未证实"), "experimental inputs remain labeled")
	var host = app.pal98.host
	await process_frame; await RenderingServer.frame_post_draw
	check(host.frame_view.position == Vector2.ZERO and host.frame_view.size == Vector2(host.window.size), "preview fits its own 960x600 window")
	var image: Image = host.stage.get_texture().get_image(); image.convert(Image.FORMAT_RGBA8)
	check(image.get_size() == Vector2i(320, 200) and image.save_png(args[1]) == OK, "current rendered logical frame captured")
	details.frame_sha256 = Schema.digest(image.get_data())
	host.window.size = Vector2i(700, 430); await process_frame
	check(host.fit.scale == 2 and host.frame_view.position == Vector2(30, 15), "resize refits without parent offsets or clipping")
	check(host.window_to_content(Vector2i(30, 15)).get("position") == Vector2i.ZERO, "coordinate inverse matches displayed origin")
	var state: Dictionary = app.pal98.game.state.duplicate(true)
	for i in range(4):
		var parked: Dictionary = await app.pal98.tick(0.01, PackedInt32Array([0,0,0,0,0,0,0,0,0]))
		check(parked.get("parked") == "restore_background" and not parked.get("completed", false), "missing dialogue owner remains a named park")
	check(app.pal98.game.state == state, "parked ticks preserve state")
	# Diagnose background from the actual MAP/GOP/PAT chain, independently of cache claims.
	var background = Background.new(); var game = app.pal98.game
	check(background.load_source(game.records, game.state.globals.loaded_map_id, 0, 0), "actual map/GOP/PAT read succeeds")
	var cell: Dictionary = Occlusion.world_to_cell(game.state.globals.viewport_x, game.state.globals.viewport_y).value
	var plan: Dictionary = background.draw_plan(cell.x, cell.y, cell.half)
	var frames := {}; var nonblack := 0; var opaque := 0
	for placement in plan.value:
		frames[placement.lower.frame] = true
		if placement.upper.present: frames[placement.upper.frame] = true
	for index in frames:
		var decoded: Dictionary = background._image(index)
		if decoded.has("error"): details.background_error = decoded.error; continue
		var pixels: PackedByteArray = decoded.value.get_data()
		for at in range(0, pixels.size(), 4):
			if pixels[at+3] == 0: continue
			opaque += 1
			if pixels[at] + pixels[at+1] + pixels[at+2] > 0: nonblack += 1
	details.background = {"map_id": game.state.globals.loaded_map_id, "cell": cell, "frames": frames.keys(), "opaque_pixels": opaque, "nonblack_pixels": nonblack, "source": background.source()}
	app._save(); check(app.message.text.contains("不写存档"), "preview cannot write ordinary saves")
	app._stop_pal98(); check(not app.pal98.active(), "closing preview cancels its owner")
	check(app.start_original_experiment(), "same selected package can restart explicitly")
	app._stop_pal98()
	check(app.open_package(args[3]), "ordinary author package remains usable")
	check(not app.pal98.active(), "ordinary package retains a single active runtime")
	finish()
func finish() -> void:
	app._stop_pal98()
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[2], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size()-failed, "failed": failed, "details": details,
		"scope": "experimental window, no original-gameplay acceptance"}, "  ")); file.close()
	quit(1 if failed else 0)
