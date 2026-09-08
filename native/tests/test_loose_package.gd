# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Package = preload("res://src/native_package.gd")
const Save = preload("res://src/native_save.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var saves: Array = []
var failed: int = 0
var output: String
func check(ok: bool, label: String) -> void:
	checks.append({"name":label,"passed":ok})
	if not ok: failed += 1; push_error(label)
func _initialize() -> void: run.call_deferred()
func settle() -> void:
	await process_frame; await process_frame; await process_frame
func stable(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for key in ["session_id", "timeline_epoch", "state_revision", "clock"]: result.erase(key)
	return result
func run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	var plan: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	output = args[1]; DirAccess.make_dir_recursive_absolute(output); root.size = Vector2i(1280,800)
	var app = App.instantiate(); root.add_child(app); await settle()
	app.set_process(false); app.set_physics_process(false); app.battle_view.set_process(false)
	app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(plan.zip), "unchanged ZIP admission works")
	if app.session.package == null: finish(); return
	var zipped = app.session.package
	check(app.open_package(plan.directory), "directory root opens through production application")
	check(app.session.package.content_lock == zipped.content_lock and app.session.package.world == zipped.world, "directory preserves exact content and rules identity")
	for id in zipped.textures:
		check(app.session.package.textures[id].get_image().get_data() == zipped.textures[id].get_image().get_data(), "directory texture equals ZIP " + id)
	check(app.open_package(plan.directory.path_join("manifest.json")), "manifest file opens through production application")
	check("manifest.json ; 万相 MOD 目录入口" in app.picker.filters, "player file picker exposes directory manifest entry")
	for original in plan.old_saves:
		check(app.saves.load_into(app.session,original), "prior real-package save loads from directory: " + original.get_file())
	for foreign in plan.foreign_saves:
		var before: Dictionary = app.session.snapshot()
		check(not app.saves.load_into(app.session,foreign) and app.session.state == before, "different-content historical save stays rejected: " + foreign.get_file())
	check(app.saves.load_into(app.session,plan.old_saves[0]), "restore retained initial battle save")
	app.saves.envelope_extensions["test.directory.roundtrip"] = {"unknown_field":"preserve"}
	var original_state = stable(app.session.state)
	check(app.saves.save(app.session), "save from active directory")
	var directory_save: String = app.saves.last_path
	saves.append({"save_path":directory_save,"package_path":plan.zip,"direction":"directory-to-zip"})
	check(app.open_package(plan.zip) and app.saves.load_into(app.session,directory_save), "ZIP runtime loads directory save")
	check(stable(app.session.state) == original_state, "ZIP load preserves actors, party, inventory, story and pending battle")
	check(app.saves.envelope_extensions.get("test.directory.roundtrip") == {"unknown_field":"preserve"}, "unknown save extension survives directory-to-ZIP")
	check(app.saves.save(app.session), "save from active ZIP")
	var zip_save: String = app.saves.last_path
	saves.append({"save_path":zip_save,"package_path":plan.zip,"direction":"zip-to-directory"})
	check(app.open_package(plan.directory) and app.saves.load_into(app.session,zip_save), "directory runtime loads ZIP save")
	check(stable(app.session.state) == original_state, "directory load preserves complete gameplay state")
	var prior_epoch: int = app.session.state.timeline_epoch
	var prior_rta: int = app.session.state.clock.rta_usec
	check(app.saves.load_into(app.session,directory_save) and app.session.state.timeline_epoch == prior_epoch + 1 and app.session.state.clock.rta_usec >= prior_rta, "existing epoch and monotonic timing policy applies across storage")
	await settle(); await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("loose-battle-save.png"))
	for fixture in plan.cases:
		var before: Dictionary = app.session.snapshot()
		var accepted: bool = app.open_package(fixture.path)
		check(accepted == fixture.accepted, fixture.name + " admission")
		if not accepted: check(app.session.state == before, fixture.name + " preserves active session")
		elif fixture.get("same_identity",true): check(app.session.package.content_lock == zipped.content_lock, fixture.name + " preserves content lock")
		else:
			check(app.session.package.content_lock != zipped.content_lock, "manifest whitespace is a different content lock")
			before = app.session.snapshot()
			check(not app.saves.load_into(app.session,directory_save) and app.session.state == before, "different manifest bytes reject old save without migration")
	# A loaded package owns validated bytes/textures. On-disk edits are seen only
	# on a new admission, never halfway through a battle.
	check(app.open_package(plan.mutable), "ordinary mutable copy initially loads")
	var snapshot: Dictionary = app.session.snapshot()
	var lock: String = app.session.package.content_lock
	FileAccess.open(plan.mutable.path_join("content/world.json"),FileAccess.WRITE).store_string("corrupt local test copy")
	check(app.session.state == snapshot and app.session.package.content_lock == lock, "loaded session remains an immutable snapshot")
	check(not app.open_package(plan.mutable) and app.session.state == snapshot, "later load rejects modified external bytes and retains session")
	finish()
func finish() -> void:
	var report = {"success":failed == 0,"checks":checks,"saves":saves,"physical_input":false,"full_playthrough":false,"engine_injected_input":true}
	FileAccess.open(output.path_join("results.json"),FileAccess.WRITE).store_string(JSON.stringify(report,"\t"))
	print("directory checks=%d failed=%d" % [checks.size(),failed]); quit(0 if failed == 0 else 1)
