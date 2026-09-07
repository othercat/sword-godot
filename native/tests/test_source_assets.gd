# SPDX-License-Identifier: MIT
# Parameterized test: no original images, game data or local source paths in this repository.
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Save = preload("res://src/native_save.gd")
const Schema = preload("res://src/native_schema.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
const AppScene = preload("res://scenes/main.tscn")
var checks: Array = []
var failures: int = 0
var output: String

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok:
		failures += 1
		push_error(name)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	output = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var package = Package.new()
	check(package.load_package(args[0]), "source package passes the normal bounded loader and PNG decoder")
	if not package.error.is_empty():
		print(package.error)
		quit(1)
		return
	check(package.manifest.extensions.get("pal.native.distribution") == {"scope": "local-preview"}, "preview scope is explicit")
	check(package.world.assets.all(func(asset): return not asset.redistributable), "runtime preserves original false distribution registrations")
	var imports: Dictionary = package.world.extensions["pal.studio.resource_imports"]
	check(imports.size() == 2, "two explicit source groups retained")
	for source in imports.values():
		check(source.resource_family == "MGO" and not source.original_resource_set_verified and source.declared_content_lineage == "unknown", "exported source identity retains unverified original lineage " + str(source.resource_index))
		check(source.frames.size() == 12 and source.direction_layout == "down-left-up-right" and source.mapping_scope == "at-import", "four direction import receipt is complete " + str(source.resource_index))
	var app = AppScene.instantiate()
	root.size = Vector2i(1280, 800)
	root.add_child(app)
	await process_frame
	app.set_physics_process(false)
	check(app.open_package(args[0]), "production application activates the actual source package")
	app.session.advance_dialogue(); app.session.advance_dialogue(app.session.current_node().options[1].id)
	app.session.set_focus(true)
	var world = app.world_view
	world.set_process(false)
	var ids: Array = app.session.state.active_party
	var leader_id: String = ids[0]
	var leader: Dictionary = app.session.entity(leader_id)
	var map_data: Dictionary = app.session.package.index.maps[app.session.package.index.scenes[app.session.state.cursor.scene_id].map_id]
	# The sample starts near the west boundary and has an NPC to its east.
	var directions: Dictionary = {"down": Vector2i.DOWN, "right": Vector2i.RIGHT, "left": Vector2i.LEFT, "up": Vector2i.UP}
	for facing in directions:
		for step in range(4):
			for _tick in range(6): app.session.tick()
			leader = app.session.entity(leader_id)
			var before: Dictionary = leader.position.duplicate()
			check(app.session.move(directions[facing]), "accepted source movement " + facing + "/" + str(step))
			leader = app.session.entity(leader_id)
			world._process(0.1)
			check(Vector2i(leader.position.x - before.x, leader.position.y - before.y) == directions[facing], "PNG size does not change logical step " + facing + "/" + str(step))
			for party_index in range(2):
				var item: Dictionary = app.session.entity(ids[party_index])
				var visual = world.visuals[ids[party_index]]
				var pose: Dictionary = item.components["pal.native.pose"]
				var phase: int = ([0, 1, 0, 2] if party_index == 0 else [0, 2, 0, 1])[int(pose.step_phase)]
				var definition: Dictionary = app.session.package.index.actor_definitions[item.definition_id]
				var source: Dictionary = imports[definition.map_sprite_set]
				var matches: Array = source.frames.filter(func(row): return row.facing == pose.facing and int(row.phase_index) == phase)
				var frame: Dictionary = visual.displayed_frame
				check(matches.size() == 1 and frame.frame_id == matches[0].frame_id and frame.asset_id == matches[0].asset_id, "source direction and phase reach actual texture " + str(party_index) + "/" + facing + "/" + str(step))
				check((visual.sprite.position + Vector2(frame.anchor.x, frame.anchor.y) * visual.sprite.scale).is_zero_approx(), "source texture keeps foot anchor " + str(party_index) + "/" + facing + "/" + str(step))
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("source-" + facing + ".png"))
	app.session.stop_walking()
	world._process(0.0)
	check(world.visuals[leader_id].selection.begins_with("idle/"), "release uses the declared neutral source frame")
	world._process(0.5)
	check(world.actors[leader_id].position.distance_to(MapProjection.project(Vector2(leader.position.x, leader.position.y), map_data.coordinates)) < 0.01, "interpolated source foot converges to the logical map projection")
	for _tick in range(6): app.session.tick()
	var blocked: Dictionary = {"x": leader.position.x, "y": leader.position.y + 1}
	map_data.blocked.append(blocked)
	app.session.package.map_blocked[map_data.id][Vector2i(blocked.x, blocked.y)] = true
	var retained: Dictionary = app.session.snapshot()
	check(not app.session.move(Vector2i.DOWN) and app.session.snapshot() == retained, "real images do not bypass logical collision or mutate rejected state")
	map_data.blocked.erase(blocked)
	app.session.package.map_blocked[map_data.id].erase(Vector2i(blocked.x, blocked.y))
	check(app.session.move(Vector2i.DOWN), "unblocked source movement resumes")
	var storage = Save.new(output.path_join("saves"))
	var before_save: Dictionary = app.session.snapshot()
	check(storage.save(app.session), "source preview writes an actual isolated Native save")
	var save_path: String = storage.last_path
	for _tick in range(6): app.session.tick()
	app.session.move(Vector2i.UP)
	check(storage.load_into(app.session, save_path), "source preview save reloads with the same content identity")
	check(app.session.state.extensions["pal.native.walk"] == before_save.extensions["pal.native.walk"], "source preview save restores walking cadence")
	world._process(0.0)
	check(world.visuals[leader_id].elapsed_us == 0.0, "save load resets source animation history")
	retained = app.session.snapshot()
	for defect in ["missing-marker", "missing-capability", "wrong-scope", "null-approved", "extra-field"]:
		var bad: String = _variant(args[0], defect)
		check(not app.open_package(bad) and app.session.snapshot() == retained, "reject malformed preview before replacing active session: " + defect)
	check(Package.new().load_package(_variant(args[0], "approved")), "otherwise identical approved fixture is a valid distribution package")
	var report: Dictionary = {"passed": checks.size() - failures, "failed": failures, "checks": checks, "real_source_frames": true, "synthetic_map_and_story": true, "physical_input": false, "full_playthrough": false, "hd_art_acceptance": false, "save_path": save_path, "renderer": RenderingServer.get_current_rendering_method()}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print(JSON.stringify(report)); quit(0 if failures == 0 else 1)

func _variant(path: String, defect: String) -> String:
	# Test-only mutated copies; never alter source package or author registrations.
	var reader = ZIPReader.new(); reader.open(path)
	var files: Dictionary = {}
	for name in reader.get_files(): files[name] = reader.read_file(name)
	reader.close()
	var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
	if defect in ["approved", "null-approved"]:
		var content: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
		for asset in content.assets: asset.redistributable = true
		files["content/world.json"] = JSON.stringify(content).to_utf8_buffer()
		manifest.required_capabilities.erase("package.local-preview.v1")
		manifest.extensions.erase("pal.native.distribution")
		if defect == "null-approved": manifest.extensions["pal.native.distribution"] = null
	elif defect == "missing-marker": manifest.extensions.erase("pal.native.distribution")
	elif defect == "missing-capability": manifest.required_capabilities.erase("package.local-preview.v1")
	elif defect == "wrong-scope": manifest.extensions["pal.native.distribution"] = {"scope": "public"}
	elif defect == "extra-field": manifest.extensions["pal.native.distribution"] = {"scope": "local-preview", "ignore_hash": true}
	for row in manifest.files:
		row.sha256 = Schema.digest(files[row.path]); row.size_bytes = files[row.path].size()
	files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var result: String = output.path_join(defect + ".zip")
	var writer = ZIPPacker.new(); writer.open(result)
	for name in files:
		writer.start_file(name); writer.write_file(files[name]); writer.close_file()
	writer.close()
	return result
