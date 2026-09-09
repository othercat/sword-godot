# SPDX-License-Identifier: MIT
extends SceneTree
## Real Native/TileMap window with synthetic marker frames over a retained test map.
const App = preload("res://scenes/main.tscn")
const Save = preload("res://src/native_save.gd")
const MapPerformance = preload("res://src/native_performance.gd")
const Schema = preload("res://src/native_schema.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
var checks: Array = []
var failures: int = 0
var output: String
var images: Array = []

func check(value: bool, label: String) -> void:
	checks.append({"name": label, "passed": value})
	if not value: failures += 1; push_error(label)

func _initialize() -> void: _run.call_deferred()

func capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var folder = ProjectSettings.globalize_path("res://generated/pal/visual_tests/performance")
	DirAccess.make_dir_recursive_absolute(folder)
	var path: String = folder.path_join(label + ".png")
	check(root.get_texture().get_image().save_png(path) == OK, "capture actual window " + label)
	images.append(path)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(1280, 800)
	var app = App.instantiate(); root.add_child(app)
	app.set_process(false); app.set_physics_process(false)
	app.saves = Save.new(output.path_join("saves"))
	check(app.open_package(args[0]), "loader validates performance capability, schema hash and frame PNGs")
	if app.session.state.is_empty(): finish(); return
	var s = app.session; var world = app.world_view
	world.set_process(false); s.focused = true
	var row: Dictionary = MapPerformance.for_node(s.package.world, s.state.cursor.node_id)
	check(s.performance_open() and not s.dialogue_open and not s.battle_open(), "entry stops at named map performance")
	check(s.state.scopes.run["flag.performance.fixture"] and s.state.committed_effect_ids.size() == 1, "preceding effect commits exactly once")
	check(world.tiles is TileMapLayer and not world.terrain_layers.is_empty(), "formal TileMap terrain is retained")
	var track: Dictionary = row.tracks[0]
	var owner: String = track.actor_id; var hidden: String = track.hide_actor_ids[0]
	check(not world.actors[hidden].visible and world.actors[owner].visible, "composite hides only declared participant visual")
	check(app.dialogue_text.text == row.display_name, "actual app shows authored performance name")
	check(app.equipment_button.disabled and not app.save_button.disabled, "actual UI blocks equipment and keeps saving")
	var skip_button: Button = null
	for button in app.options.get_children():
		if button is Button and button.text == "跳过演出": skip_button = button
	check(skip_button != null, "ordinary UI exposes authored skip")
	await capture("01-start")
	var original_entities: Array = s.state.entities.duplicate(true)
	var initial: Dictionary = s.snapshot()
	check(not s.move(Vector2i.RIGHT) and not s.interact() and not s.change_equipment(owner, "none"), "map input and equipment cannot alter performance")
	check(s.state == initial, "blocked actions preserve all authoritative state")
	app.battle_view.presentation.active = true
	app._physics_process(1.0 / 60.0)
	check(s.state == initial, "app defers map timeline while preceding battle presentation is active")
	app.battle_view.presentation.active = false
	for flag in ["paused", "modal", "focused"]:
		if flag == "paused": s.set_pause(true, 0)
		elif flag == "modal": s.set_modal(true, 0)
		else: s.set_focus(false, 0)
		var before: Dictionary = s.snapshot()
		for i in 10: s.tick()
		check(s.state == before and not s.skip_performance(), flag + " freezes timeline and skip")
		if flag == "paused": s.set_pause(false, 0)
		elif flag == "modal": s.set_modal(false, 0)
		else: s.set_focus(true, 0)
	for i in 30: s.tick()
	world._process(0)
	check(s.state.extensions[MapPerformance.KEY].active.elapsed_ticks == 30, "half-second advances exactly thirty logic ticks")
	check(world.visuals[owner].displayed_frame.frame_id == "frame.performance.fixture.1", "shared frame sampler selects second size at authored time")
	var visual = world.visuals[owner]
	check(visual.sprite.position + Vector2(32, 64) * visual.sprite.scale == Vector2.ZERO, "different frame dimensions keep the same local foot")
	var actor: Dictionary = s.entity(owner)
	check(world.actors[owner].position == MapProjection.project(Vector2(actor.position.x, actor.position.y), world._map.coordinates) + Vector2(17, -7), "authored offset moves presentation without changing world coordinates")
	var render_state: Dictionary = s.snapshot()
	for fps in [30, 60, 100, 144]:
		for i in fps: world._process(1.0 / fps)
		check(s.state == render_state, "%d render-only steps never advance effects or timeline" % fps)
	check(app.saves.save(s), "real immutable save transaction writes active performance")
	var saved: String = app.saves.last_path
	var middle: Dictionary = s.snapshot()
	await capture("02-middle")
	for defect in ["missing", "null", "finished", "node", "battle", "participant"]:
		var bad: Dictionary = middle.duplicate(true)
		match defect:
			"missing": bad.extensions.erase(MapPerformance.KEY)
			"null": bad.extensions[MapPerformance.KEY].active = null
			"finished": bad.extensions[MapPerformance.KEY].active.elapsed_ticks = 60
			"node": bad.extensions[MapPerformance.KEY].active.node_id = "node.unknown"
			"battle": bad.extensions["pal.native.battle"] = {}
			"participant": bad.entities.filter(func(e): return e.instance_id == hidden)[0].scene_id = "scene.unknown"
		check(not s.restore(bad, 0) and s.state == middle, "invalid " + defect + " restore preserves live state")
	for i in 30: s.tick()
	world._process(0)
	check(not s.performance_open() and s.current_node().id == row.next_node_id, "finish enters authored continuation through normal executor")
	check(world.actors[hidden].visible and s.state.entities == original_entities, "finish restores participants without merging identity HP or pose")
	check(s.state.committed_effect_ids.size() == 1, "completion does not repeat preceding effect")
	await capture("03-finished")
	check(app.saves.load_into(s, saved, 0), "save reader restores exact active timeline")
	world._process(0)
	check(s.performance_open() and s.state.extensions[MapPerformance.KEY].active.elapsed_ticks == 30 and not world.actors[hidden].visible, "load resets visual history and composite at saved tick")
	check(s.movement_rule() == "pal.walk.v1", "gap regression uses the actual PAL walk consumer")
	var pose: Dictionary = s.entity(owner).components["pal.native.pose"]
	pose.step_phase = 3; pose.moving_until_tick = s.state.clock.logic_tick + 4
	var gap_entities: Array = s.state.entities.duplicate(true)
	s.set_pause(true, 0)
	var paused_gap: Dictionary = s.snapshot()
	app._last_physics_usec = Time.get_ticks_usec() - 300001
	app._physics_process(1.0 / 60.0)
	check(s.state == paused_gap, "paused app gap preserves the complete active performance state")
	s.set_pause(false, 0)
	app._last_physics_usec = Time.get_ticks_usec() - 300001
	app._physics_process(1.0 / 60.0)
	check(s.state.entities == gap_entities and s.state.extensions[MapPerformance.KEY].active.elapsed_ticks == 31, "app gap during performance does not reset participant walking pose")
	check(app.saves.load_into(s, saved, 0), "gap diagnostic returns to exact saved timeline")
	row.skippable = false
	var before_skip: Dictionary = s.snapshot()
	check(not s.skip_performance() and s.state == before_skip, "unskippable policy is enforced by session")
	row.skippable = true
	var next: String = row.next_node_id; row.next_node_id = "node.missing"
	check(not s.skip_performance() and s.state == before_skip, "failed skip continuation rolls back complete transaction")
	for i in 29: s.tick()
	var before_finish: Dictionary = s.snapshot(); s.tick()
	check(s.state == before_finish and s.performance_open(), "failed natural completion retains previous tick and effects")
	row.next_node_id = next
	check(app.saves.load_into(s, saved, 0), "valid saved performance remains recoverable after failure")
	app._refresh()
	for button in app.options.get_children():
		if button is Button and button.text == "跳过演出": button.pressed.emit(); break
	world._process(0)
	check(not s.performance_open() and world.actors[hidden].visible and s.state.committed_effect_ids.size() == 1, "actual skip button restores visuals and does not duplicate effects")
	check(s.state.entities == original_entities, "all participants retain independent gameplay state after save skip and finish")
	await capture("04-skipped")
	app.queue_free(); await process_frame
	finish()

func finish() -> void:
	var report = {"success": failures == 0, "checks": checks, "images": images, "scope": "real TileMap window, synthetic frames, injected UI/session calls; not artwork or full-play acceptance"}
	FileAccess.open(output.path_join("report.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "  "))
	print(JSON.stringify({"checks": checks.size(), "failures": failures, "output": output}))
	quit(0 if failures == 0 else 1)
