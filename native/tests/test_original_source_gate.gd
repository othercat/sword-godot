# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed: int = 0

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void: run.call_deferred()

func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 3: quit(2); return
	var output: String = args[2]
	if FileAccess.file_exists(output.path_join("results.json")): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1100,760)
	var source = Package.new()
	check(source.load_package(args[0]), "source container remains valid for inspection")
	check(source.manifest.get("provenance", {}).get("source_id", "") == "source.pal98.complete-package", "fixture is an actual original-source author build")
	var app = App.instantiate(); root.add_child(app)
	await process_frame; await process_frame
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	check(not app.open_package(args[0]), "normal application refuses original-source seed execution")
	check(app.session.state.is_empty() and app.session.package == null, "no fake original session or clock was created")
	check("original_source_only" in app.message.text, "normal player explains missing original execution")
	check(app.open_package(args[1]), "existing independent practice content still activates")
	var previous: Dictionary = app.session.snapshot().duplicate(true)
	var previous_package = app.session.package
	check(not app.open_package(args[0]), "source-only switch is refused with a live session")
	check(app.session.package == previous_package and app.session.snapshot() == previous, "rejected source switch preserves all live state and clock")
	check(app.open_package(args[1]), "normal content can be reopened after refusal")
	if DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("preserved-practice-window.png"))
	FileAccess.open(output.path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify({"success": failed == 0, "checks": checks, "original_gameplay": false, "physical_input": false, "windowed": DisplayServer.get_name() != "headless"}, "\t"))
	print("original source gate checks=%d failed=%d" % [checks.size(),failed])
	app.queue_free(); await process_frame
	quit(0 if failed == 0 else 1)
