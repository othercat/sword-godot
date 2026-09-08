# SPDX-License-Identifier: MIT
extends SceneTree
## Windowed, fixed-package measurement; no state/HP/cursor mutation or saves.
## frame_post_draw intervals are CPU-observed frames, not display latency.
const App = preload("res://scenes/main.tscn")
var app
var output: String
var report: Dictionary = {"phases": [], "operations": [], "success": false}
var route: Array[Vector2i] = [Vector2i(129, 74), Vector2i(129, 75), Vector2i(130, 75), Vector2i(130, 74)]
var waypoint: int = 0
var held: int = 0
var moves: int = 0
var previous_position: Vector2i

func _initialize() -> void: _run.call_deferred()
func require(ok: bool, message: String) -> bool:
	if not ok:
		report["error"] = message
		push_error(message)
	return ok
func key(code: int, down: bool) -> void:
	var event = InputEventKey.new(); event.keycode = code; event.physical_keycode = code; event.pressed = down
	Input.parse_input_event(event)
func position() -> Vector2i:
	var point: Dictionary = app.session.entity(app.session.state.active_party[0]).position
	return Vector2i(point.x, point.y)
func walk_frame() -> void:
	var current: Vector2i = position()
	if current != previous_position: moves += 1; previous_position = current
	if current == route[waypoint]: waypoint = (waypoint + 1) % route.size()
	var delta: Vector2i = route[waypoint] - current
	var code: int = (KEY_A if delta.x < 0 else KEY_D) if delta.x != 0 else (KEY_W if delta.y < 0 else KEY_S)
	if code != held:
		if held != 0: key(held, false)
		key(code, true); held = code
func warmup(seconds: float = 2.0) -> void:
	var until: int = Time.get_ticks_usec() + int(seconds * 1000000)
	while Time.get_ticks_usec() < until: await RenderingServer.frame_post_draw
func sample(label: String, seconds: float, walking: bool = false, fighting: bool = false) -> void:
	root.grab_focus()
	await warmup()
	var rows: Array = []
	var root_rid: RID = root.get_viewport_rid(); var world_rid: RID = app.viewport.get_viewport_rid()
	var begin: int = Time.get_ticks_usec(); var previous: int = begin
	var tick: int = app.session.state.clock.logic_tick
	var start_moves: int = moves; var focus_lost: int = 0
	var node_id: int = app.world_view.tiles.get_instance_id(); var rebuilds: int = 0
	var commands: int = 0
	while Time.get_ticks_usec() - begin < int(seconds * 1000000):
		if walking: walk_frame()
		if fighting and not app.battle_view.playing():
			if not app.session.battle_open(): break
			var target: String = ""
			for enemy in app.session.state.extensions[app.Battle.KEY].enemies:
				if enemy.hp > 0: target = enemy.instance_id; break
			if not require(app.session.battle_command("attack", target), "normal battle command: " + app.session.error): break
			commands += 1
		await RenderingServer.frame_post_draw
		var now: int = Time.get_ticks_usec()
		if not app.session.focused: focus_lost += 1
		if app.world_view.tiles.get_instance_id() != node_id:
			rebuilds += 1; node_id = app.world_view.tiles.get_instance_id()
		rows.append([float(now - previous) / 1000.0,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0,
			RenderingServer.get_frame_setup_time_cpu(),
			RenderingServer.viewport_get_measured_render_time_cpu(root_rid),
			RenderingServer.viewport_get_measured_render_time_cpu(world_rid),
			RenderingServer.viewport_get_measured_render_time_gpu(root_rid),
			RenderingServer.viewport_get_measured_render_time_gpu(world_rid),
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED),
			Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
		previous = now
	if held != 0: key(held, false); held = 0
	var file = FileAccess.open(output.path_join(label + ".csv"), FileAccess.WRITE)
	file.store_csv_line(PackedStringArray(["frame_ms", "process_ms", "physics_ms", "setup_cpu_ms", "root_cpu_ms", "world_cpu_ms", "root_gpu_ms", "world_gpu_ms", "draw_calls", "video_mem_bytes", "nodes"]))
	for row in rows:
		var fields: PackedStringArray = []
		for value in row: fields.append(str(value))
		file.store_csv_line(fields)
	file.close()
	report.phases.append({"name": label, "frames": rows.size(), "seconds": float(previous - begin) / 1000000.0,
		"logic_ticks": int(app.session.state.clock.logic_tick) - tick, "moves": moves - start_moves,
		"battle_commands": commands, "battle_complete": not app.session.battle_open() and not app.battle_view.playing(),
		"eligible_for_comparison": focus_lost == 0,
		"focus_lost_frames": focus_lost, "map_rebuilds": rebuilds, "node_id": app.session.current_node().id,
		"scene_id": app.session.state.cursor.scene_id, "party_size": app.session.state.active_party.size(),
		"window_size": [root.size.x, root.size.y], "world_viewport_size": [app.viewport.size.x, app.viewport.size.y],
		"max_fps": Engine.max_fps, "vsync_mode": DisplayServer.window_get_vsync_mode()})
	print("PERF ", label, " ", rows.size(), " frames / ", float(previous - begin) / 1000000.0, " sec")
func open(path: String, label: String) -> bool:
	var begin: int = Time.get_ticks_usec()
	var ok: bool = app.open_package(path)
	var loaded: int = Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	report.operations.append({"name": label, "load_call_ms": float(loaded - begin) / 1000.0, "first_frame_ms": float(Time.get_ticks_usec() - begin) / 1000.0})
	return require(ok, "open: " + app.message.text)
func advance() -> bool:
	for i in range(30):
		if not app.session.dialogue_open or app.session.current_node().op != "dialogue": return true
		if not require(app.session.advance_dialogue(), "advance: " + app.session.error): return false
	return require(false, "dialogue bound")
func choose(suffix: String) -> bool:
	for option in app.session.current_node().get("options", []):
		if option.id.ends_with("." + suffix): return require(app.session.advance_dialogue(option.id), "choose: " + app.session.error)
	return require(false, "missing choice " + suffix)
func go(target: Vector2i) -> bool:
	# Retired companions are ordinary obstacles. Use the authored walkable cells,
	# not a straight line that assumes all bounding-box cells are available.
	for step in range(80):
		if position() == target: return true
		var start: Vector2i = position(); var parents: Dictionary = {start: start}; var queue: Array = [start]; var head: int = 0
		var occupied: Dictionary = {}
		for actor in app.session.state.entities:
			if actor.scene_id == app.session.state.cursor.scene_id and actor.instance_id not in app.session.state.active_party:
				occupied[Vector2i(actor.position.x, actor.position.y)] = true
		while head < queue.size() and not parents.has(target):
			var cell: Vector2i = queue[head]; head += 1
			for delta in [Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT, Vector2i.RIGHT]:
				var next: Vector2i = cell + delta
				if next.x < 129 or next.x > 134 or next.y < 68 or next.y > 76 or parents.has(next) or occupied.has(next): continue
				if not app.session.package.can_stand(app.session.state.cursor.scene_id, {"x": next.x, "y": next.y}): continue
				parents[next] = cell; queue.append(next)
		if not require(parents.has(target), "walkable path to " + str(target)): return false
		var next: Vector2i = target
		while parents[next] != start: next = parents[next]
		route = [next]; waypoint = 0; previous_position = start
		var deadline: int = Time.get_ticks_msec() + 3000
		while position() == start and Time.get_ticks_msec() < deadline:
			walk_frame(); await process_frame
		if held != 0: key(held, false); held = 0
		await process_frame
		if not require(position() == next, "movement to " + str(next)): return false
	return require(false, "walk budget to " + str(target))
func interaction(label: String, expected_scene: String) -> bool:
	var before_id: int = app.world_view.tiles.get_instance_id()
	var begin: int = Time.get_ticks_usec()
	if not require(app.session.interact(), "interact " + label + ": " + app.session.error) or not advance(): return false
	var call_end: int = Time.get_ticks_usec()
	await RenderingServer.frame_post_draw
	report.operations.append({"name": label, "call_ms": float(call_end - begin) / 1000.0,
		"first_frame_ms": float(Time.get_ticks_usec() - begin) / 1000.0,
		"map_reused": app.world_view.tiles.get_instance_id() == before_id})
	return require(app.session.state.cursor.scene_id.ends_with("." + expected_scene), "arrive " + expected_scene)
func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() < 6 or DisplayServer.get_name() == "headless": quit(2); return
	output = args[1]; DirAccess.make_dir_recursive_absolute(output)
	root.size = Vector2i(int(args[3]), int(args[4]))
	app = App.instantiate(); root.add_child(app); await process_frame
	Engine.max_fps = int(args[5]); DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	root.grab_focus(); await process_frame
	RenderingServer.viewport_set_measure_render_time(root.get_viewport_rid(), true)
	RenderingServer.viewport_set_measure_render_time(app.viewport.get_viewport_rid(), true)
	report.merge({"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "screen_size": str(DisplayServer.screen_get_size()),
		"screen_refresh_hz": DisplayServer.screen_get_refresh_rate(), "display_server": DisplayServer.get_name(),
		"package_path": args[0], "package_sha256": FileAccess.get_sha256(args[0]),
		"input_kind": "injected movement keys; production session dialogue commands", "physical_input": false,
		"full_playthrough": false, "warmup_seconds": 2.0})
	if not await open(args[0], "initial_open"): finish(); return
	await sample("opening", float(args[2]))
	if not advance() or not choose("skip") or not advance(): finish(); return
	await sample("camp_idle", float(args[2]))
	previous_position = position()
	var walk_seconds: float = maxf(float(args[2]), float(args[6]) if args.size() > 6 else 0.0)
	await sample("camp_walk", walk_seconds, true)
	if args.size() > 7 and args[7] == "sweep":
		for cap in [30, 60, 100, 120, 144, 240]:
			if not await go(Vector2i(130, 74)): finish(); return
			route = [Vector2i(129, 74), Vector2i(129, 75), Vector2i(130, 75), Vector2i(130, 74)]; waypoint = 0
			previous_position = position(); Engine.max_fps = cap
			await sample("camp_walk_fps_" + str(cap), float(args[2]), true)
		Engine.max_fps = int(args[5])
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("camp.png"))
	if not await go(Vector2i(130, 73)) or not await interaction("herald_solo", "camp"): finish(); return
	if not await go(Vector2i(130, 76)) or not await interaction("camp_to_path", "path"): finish(); return
	if not await go(Vector2i(134, 74)) or not await interaction("path_to_stone", "stone"): finish(); return
	if not await go(Vector2i(130, 74)) or not await interaction("stone_to_path", "path"): finish(); return
	if not await go(Vector2i(130, 74)) or not await interaction("path_to_camp", "camp"): finish(); return
	if not await open(args[0], "second_open"): finish(); return
	var begin: int = Time.get_ticks_usec()
	if not advance() or not choose("train") or not advance() or not require(app.session.battle_open(), "five-party battle"): finish(); return
	await RenderingServer.frame_post_draw
	report.operations.append({"name": "enter_battle", "first_frame_ms": float(Time.get_ticks_usec() - begin) / 1000.0})
	await sample("battle_idle", float(args[2]))
	root.get_texture().get_image().save_png(output.path_join("battle.png"))
	await sample("battle_actions", 120.0, false, true)
	# Preserve an interrupted phase but exclude it from performance claims. A
	# foreground change is not a runtime failure and is never hidden from data.
	report.success = not report.has("error") and report.phases.all(func(p): return (not p.name.begins_with("camp_walk") or p.moves >= int(p.seconds * 5.0)) and (p.name != "battle_actions" or p.battle_complete))
	finish()
func finish() -> void:
	var file = FileAccess.open(output.path_join("measurements.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ") + "\n"); file.close()
	if app != null: app.queue_free(); await process_frame
	quit(0 if report.success else 1)
