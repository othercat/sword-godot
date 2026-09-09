# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const WalkInput = preload("res://src/native_walk_input.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
const World = preload("res://src/native_world.gd")
const AppScene = preload("res://scenes/main.tscn")
var checks: Array = []
var failures: int = 0

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
	var output: String = args[1]
	DirAccess.make_dir_recursive_absolute(output)
	var package = Package.new()
	check(package.load_package(args[0]), "real Studio package accepts named movement and phase capabilities")
	if not package.error.is_empty():
		print(package.error)
		quit(1)
		return
	var input = WalkInput.new()
	for key in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]: input.key_event(key, true)
	check(input.sample("pal.walk.v1") == Vector2i.RIGHT, "simultaneous new directions prefer right")
	check(input.sample("pal.walk.v1") == Vector2i.ZERO, "held cross-axis and opposite directions stop")
	input.key_event(KEY_UP, false); input.key_event(KEY_UP, true)
	check(input.sample("pal.walk.v1") == Vector2i.UP, "release and repress between samples preserves a new edge")
	input.clear(); input.key_event(KEY_UP, true)
	check(input.sample("pal.walk.v1") == Vector2i.UP, "single direction moves")
	input.key_event(KEY_RIGHT, true)
	check(input.sample("pal.walk.v1") == Vector2i.RIGHT, "new direction overrides an older held axis")
	input.key_event(KEY_W, true)
	check(input.sample("pal.walk.v1") == Vector2i.ZERO, "same-direction alias does not create a new logical press")
	input.key_event(KEY_UP, false)
	check(input.sample("pal.walk.v1") == Vector2i.ZERO, "releasing one alias preserves other held alias")
	input.key_event(KEY_W, false)
	check(input.sample("pal.walk.v1") == Vector2i.RIGHT, "last alias release removes logical direction")
	input.key_event(KEY_UP, true, true)
	check(input.sample("pal.walk.v1") == Vector2i.RIGHT, "OS key repeat does not invent a new direction")
	input.clear()
	check(input.sample("pal.walk.v1") == Vector2i.ZERO, "focus or pause reset clears pending input")
	var session = Session.new(); session.activate(package, 1000000)
	if session.dialogue_open:
		session.advance_dialogue(); session.advance_dialogue(session.current_node().options[1].id)
	var leader_id: String = session.state.active_party[0]
	var leader: Dictionary = session.entity(leader_id)
	var before: Dictionary = leader.position.duplicate()
	var world = World.new(); root.add_child(world); world.bind(session)
	world.position = Vector2(800, -30); world.scale = Vector2.ONE * 1.1
	root.size = Vector2i(1280, 800)
	var map_data: Dictionary = package.index.maps[package.index.scenes[session.state.cursor.scene_id].map_id]
	var map_origin = Vector2i(map_data.coordinates.origin.x, map_data.coordinates.origin.y)
	for cell in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(0, 1), Vector2i(-3, 5)]:
		check((world.tiles.position + world.tiles.map_to_local(cell - map_origin)).is_equal_approx(MapProjection.project(cell, map_data.coordinates)), "local TileMap cells plus nonzero origin agree with contract " + str(cell))
	var foot: Vector2 = MapProjection.project(Vector2(leader.position.x, leader.position.y), map_data.coordinates)
	check(world.actors[leader_id].position.is_equal_approx(foot), "actor foot uses same zero-centered projection")
	var origins: Dictionary = {}
	for item in session.state.entities: origins[item.instance_id] = item.position.duplicate()
	var expected: Array = [1, 0, 2, 0]
	var expected_follower: Array = [2, 0, 1, 0]
	for step in range(4):
		check(session.move(Vector2i.DOWN), "accepted PAL step " + str(step))
		world._process(0.1)
		var visual = world.visuals[leader_id]
		check(visual.displayed_frame.frame_id == "frame." + str(expected[step]), "leader phase " + str(step))
		var follower_visual = world.visuals[session.state.active_party[1]]
		check(follower_visual.displayed_frame.frame_id == "frame." + str(expected_follower[step]), "follower phase " + str(step))
		check(not session.move(Vector2i.DOWN), "same-tick duplicate cannot increase speed " + str(step))
		for _tick in range(6): session.tick()
	check(session.entity(leader_id).position.y == before.y + 4, "four steps advance four logical cells, independent of pixels")
	session.stop_walking(); world._process(0.0)
	check(world.visuals[leader_id].selection.begins_with("idle/"), "stop selects declared idle and normalizes phase")
	leader = session.entity(leader_id)
	var blocked = {"x": leader.position.x, "y": leader.position.y + 1}
	map_data.blocked.append(blocked)
	package.map_blocked[map_data.id][Vector2i(blocked.x, blocked.y)] = true
	var rejected = session.snapshot()
	check(not session.move(Vector2i.DOWN) and session.snapshot() == rejected, "blocked candidate preserves whole party and stride")
	map_data.blocked.erase(blocked)
	package.map_blocked[map_data.id].erase(Vector2i(blocked.x, blocked.y))
	var npc = session.entity(package.world.entities[-1].instance_id)
	var npc_previous: Dictionary = npc.position.duplicate(); npc.position = blocked
	check(not session.move(Vector2i.DOWN), "nonparty occupancy blocks movement")
	npc.position = npc_previous
	var bad_position: Dictionary = leader.position.duplicate(); leader.position = map_data.coordinates.origin.duplicate()
	check(not session.move(Vector2i.LEFT), "map boundary rejects the entire step")
	leader.position = bad_position
	input.clear(); input.key_event(KEY_DOWN, true)
	check(session.sample_movement(input), "named input sample commits one accepted movement")
	var save_snapshot: Dictionary = session.snapshot()
	var saves = Save.new(output.path_join("saves"))
	check(saves.save(session), "real save writer stores cadence and stride")
	for _tick in range(6): session.tick()
	session.move(Vector2i.UP)
	check(saves.load_into(session, saves.generations(session)[0].path), "actual save restores named movement state")
	if session.dialogue_open:
		session.advance_dialogue(); session.advance_dialogue(session.current_node().options[1].id)
	check(session.state.extensions["pal.native.walk"] == save_snapshot.extensions["pal.native.walk"], "save retains next input sample tick")
	check(not session.move(Vector2i.DOWN), "load cannot bypass remaining movement cooldown")
	for _tick in range(6): session.tick()
	check(session.move(Vector2i.DOWN), "movement resumes when restored cooldown expires")
	var bad = session.snapshot(); bad.extensions["pal.native.walk"].next_tick = int(bad.clock.logic_tick) + 7
	var retained = session.snapshot()
	check(not session.restore(bad) and session.snapshot() == retained, "future cadence forgery rejects without replacing session")
	bad = session.snapshot(); bad.entities[0].components["pal.native.pose"].step_phase = 4
	check(not session.restore(bad), "invalid stride cursor rejected by shared schema")
	# Insert a synthetic second map/safe point only to challenge saved-state validation.
	var other_map: Dictionary = map_data.duplicate(true); other_map.id = "map.test.grid"; other_map.movement_rule = "native.grid.v1"; other_map.coordinates.kind = "orthogonal"
	package.index.maps[other_map.id] = other_map
	package.map_blocked[other_map.id] = package.map_blocked[map_data.id].duplicate()
	package.index.scenes["scene.test.grid"] = {"id": "scene.test.grid", "map_id": other_map.id}
	bad = session.snapshot(); bad.entities[0].scene_id = "scene.test.grid"
	check(not session.restore(bad), "active phase actor cannot leave the party scene in a save")
	bad = session.snapshot(); bad.entities[-1].scene_id = "scene.test.grid"
	check(not session.restore(bad) and session.error.contains("PAL phase"), "saved phase actor cannot switch to unsupported grid rules")
	for fps in [30, 60, 100, 144, 240]:
		var replay = Session.new(); replay.activate(package, 0); replay.advance_dialogue(); replay.advance_dialogue(replay.current_node().options[1].id)
		var ticks: int = 0; var moves: int = 0
		var held = WalkInput.new(); held.key_event(KEY_DOWN, true)
		for frame in range(fps):
			while ticks * fps < (frame + 1) * 60:
				replay.tick(); ticks += 1
				if replay.sample_movement(held): moves += 1
		check(moves == 10 and replay.entity(leader_id).position.y == before.y + 10, "synthetic one-second render schedule preserves ten steps at " + str(fps))
	world.queue_free(); await process_frame
	var app = AppScene.instantiate(); root.add_child(app); await process_frame
	app.set_physics_process(false); check(app.open_package(args[0]), "actual application accepts PAL-rule package")
	app.session.advance_dialogue(); app.session.advance_dialogue(app.session.current_node().options[1].id); app.session.set_focus(true)
	app._last_physics_usec = 1000000
	check(not app.movement_frame_allowed(1500000, 10) and not app.movement_frame_allowed(1500100, 10), "500 ms stall suppresses all catch-up movement in the same render frame")
	check(app.movement_frame_allowed(1516667, 11), "next rendered frame can resume after scheduling gap")
	app._movement_frame = 11
	check(not app.movement_frame_allowed(1516777, 11), "short-gap catch-up cannot commit a second step in one rendered frame")
	var app_start: Dictionary = app.session.entity(leader_id).position.duplicate()
	var press = InputEventKey.new(); press.keycode = KEY_DOWN; press.pressed = true
	root.push_input(press, true); await process_frame
	app.session.tick(); app.session.sample_movement(app.walk_input)
	var release = InputEventKey.new(); release.keycode = KEY_DOWN; release.pressed = false
	root.push_input(release, true); await process_frame
	check(app.session.entity(leader_id).position.y == app_start.y + 1, "window input routes through application named movement")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("walk-window.png"))
	var report = {"passed": checks.size() - failures, "failed": failures, "checks": checks, "synthetic_assets": true, "physical_input": false, "full_playthrough": false, "renderer": RenderingServer.get_current_rendering_method(), "save_path": saves.generations(session)[0].path}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print(JSON.stringify(report)); quit(0 if failures == 0 else 1)
