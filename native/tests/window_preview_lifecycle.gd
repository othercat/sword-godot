# SPDX-License-Identifier: MIT
extends SceneTree
## Operational lifecycle of the experimental preview in a real window:
## start, park, stop, restart, and stop again - each stage named, no stale
## session leaking into the next one.
const App = preload("res://src/native_app.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var details: Dictionary = {}
var args: PackedStringArray
var app
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok: push_error(name)
func _initialize() -> void:
	args = OS.get_cmdline_user_args()
	if args.size() != 2 or DisplayServer.get_name() == "headless": quit(2); return
	call_deferred("run")
func run() -> void:
	get_root().size = Vector2i(960, 640)
	app = App.new(); get_root().add_child(app); await process_frame
	app.open_package(args[0])
	check(app.start_original_experiment(), "the first explicit start opens the preview")
	if app.pal98 == null or not app.pal98.active(): finish(); return
	app.set_physics_process(false)
	var host = app.pal98.host
	var keys := PackedInt32Array([0,0,0,0,0,0,0,0,0])
	var parked_kind := ""
	for step in range(600):
		var result: Dictionary = await host.tick_frame(keys, true)
		if result.has("error") or result.get("pending_kind", "") != "" \
				or app.pal98.game.is_dialogue_parked() or app.pal98.game.pending_kind() != "":
			parked_kind = str(result.get("pending_kind", app.pal98.game.pending_kind()))
			break
	check(parked_kind != "" or app.pal98.game.is_dialogue_parked(), "the first session reaches a named park")
	var first_describe: Dictionary = app.pal98.describe()
	details.first = {"pending": parked_kind, "seed": first_describe.get("seed")}
	app._stop_pal98()
	check(not app.pal98.active(), "stop deactivates the session")
	check(app.pal98.game == null, "stop releases the game owner")
	check(app.start_original_experiment(), "an explicit restart opens a fresh session")
	if app.pal98 == null or not app.pal98.active(): finish(); return
	app.set_physics_process(false)
	var second: Dictionary = app.pal98.describe()
	details.second = {"pending": second.get("pending_kind"), "seed": second.get("seed")}
	check(second.get("active", false), "the restarted session is active")
	check(second.get("frame_count", -1) == 1, "the restarted session counts its own fresh first frame")
	var stale: Dictionary = await host.tick_frame(keys, true) if app.pal98.host != null else {}
	# The old host binding was released with the first session; a restarted
	# session owns a new host. Drive the fresh one briefly.
	var fresh_host = app.pal98.host
	check(fresh_host != null and fresh_host != host, "the restart binds a fresh window host")
	var result: Dictionary = await fresh_host.tick_frame(keys, true)
	check(not result.has("error"), "the fresh session ticks without the old session's state: " + str(result.get("error", "")))
	app._stop_pal98()
	check(not app.pal98.active(), "the final stop deactivates cleanly")
	finish()
func finish() -> void:
	if app != null and app.pal98 != null: app._stop_pal98()
	var failed: int = checks.filter(func(row): return not row.passed).size()
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks": checks, "passed": checks.size()-failed, "failed": failed,
		"details": details, "scope": "real window lifecycle; no original-gameplay acceptance"}, "  ")); file.close()
	quit(1 if failed else 0)
