# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const Trail = preload("res://src/native_party_trail.gd")
const WalkInput = preload("res://src/native_walk_input.gd")
var checks: Array = []
var failed: int = 0

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok:
		failed += 1
		push_error(name)

func advance(s, direction: Vector2i) -> bool:
	for _i in range(s.movement_ticks()): s.tick()
	return s.move(direction)

func positions(s) -> Array:
	return s.state.entities.map(func(e): return e.position.duplicate())

func settle(s, count: int = 64) -> void:
	for _i in range(count): advance(s, Vector2i.ZERO)

func start(package):
	var s = Session.new()
	check(s.activate(package, 1000), "activate authored party")
	check(s.advance_dialogue() and s.advance_dialogue(package.world.nodes[1].options[0].id), "complete existing positive story route")
	return s

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(2)
		return
	var output: String = args[3]
	DirAccess.make_dir_recursive_absolute(output)
	var saved: Array = []
	for path in [args[0], args[1], args[2]]:
		var package = Package.new()
		check(package.load_package(path), "actual compiler package loads")
		if not package.error.is_empty():
			push_error(package.error)
			quit(1)
			return
		var s = start(package)
		var size: int = s.state.active_party.size()
		var initial: Dictionary = s.snapshot()
		check(Trail.used(package.world) and s.validate_saved(initial).is_empty(), "%d initial plan matches owner contract" % size)
		var same: Dictionary = s.snapshot()
		check(Trail.reseed(package, same, same.active_party).is_empty() and same == s.state, "%d identical order retains exact cadence and queues" % size)
		# Synthetic placement over this package's real logical map. The ZIP is unchanged.
		var locations: Array = [Vector2i(2, 3), Vector2i(8, 3), Vector2i(10, 4), Vector2i(12, 5), Vector2i(14, 6)]
		for i in range(s.state.entities.size()): s.state.entities[i].position = Trail.point(locations[i])
		var map_id: String = package.index.scenes[s.state.cursor.scene_id].map_id
		var blocked: Dictionary = package.map_blocked[map_id].duplicate()
		for y in range(1, 6): package.map_blocked[map_id][Vector2i(5, y)] = true
		check(Trail.reseed(package, s.state, s.state.active_party, true).is_empty(), "%d bounded planner finds path around wall" % size)
		var pending: Dictionary = s.snapshot()
		check(s.validate_saved(pending).is_empty(), "%d long pending path is saveable" % size)
		var store = Save.new(output.path_join("party-%d" % size))
		check(store.save(s), "%d write actual pending-path save" % size)
		saved.append({"party": size, "package_path": path, "save_path": store.last_path})
		var trace: Array = []
		for step in range(32):
			var previous: Array = positions(s)
			advance(s, Vector2i.ZERO)
			trace.append(positions(s))
			var legal: bool = true
			for i in range(previous.size()):
				var distance: Vector2i = Trail.cell(s.state.entities[i].position) - Trail.cell(previous[i])
				legal = legal and absi(distance.x) + absi(distance.y) <= 1 and package.can_stand(s.state.entities[i].scene_id, s.state.entities[i].position)
			check(legal and s.validate_saved(s.snapshot()).is_empty(), "%d idle catchup step %d remains contiguous and walkable" % [size, step])
		check(s.entity(s.state.active_party[0]).position == pending.entities.filter(func(e): return e.instance_id == s.state.active_party[0])[0].position, "%d idle catchup never moves leader" % size)
		check(store.load_into(s, store.last_path) and s.state.extensions[Trail.EXTENSION] == pending.extensions[Trail.EXTENSION], "%d restore retains exact pending queue" % size)
		for step in range(32):
			advance(s, Vector2i.ZERO)
			check(positions(s) == trace[step], "%d saved continuation matches original path %d" % [size, step])
		# Turning and reversing append history; never replan a shortcut.
		for direction in [Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.LEFT]:
			advance(s, direction)
			check(s.validate_saved(s.snapshot()).is_empty(), "%d corner/reverse preserves trail contract %s" % [size, direction])
		var candidate: Dictionary = pending.duplicate(true)
		var original_positions: Array = candidate.entities.map(func(e): return e.position.duplicate())
		var order: Array = candidate.active_party.duplicate(); order.reverse()
		check(Trail.reseed(package, candidate, order).is_empty() and candidate.entities.map(func(e): return e.position) == original_positions, "%d leader reorder plans without teleport" % size)
		var reduced: Array = candidate.active_party.slice(0, size - 1)
		check(Trail.reseed(package, candidate, reduced).is_empty(), "%d leave preserves separate inactive position" % size)
		check(Trail.reseed(package, candidate, order).is_empty() and candidate.entities.map(func(e): return e.position) == original_positions, "%d rejoin preserves all positions" % size)
		for i in range(candidate.entities.size()):
			check(candidate.entities[i].hp == pending.entities[i].hp and candidate.entities[i].mp == pending.entities[i].mp, "%d membership keeps stats %d" % [size, i])
		check(candidate.scopes == pending.scopes and candidate.narrative_cast == pending.narrative_cast and candidate.roster == pending.roster, "%d membership retains scopes/cast/roster" % size)
		# Explicit injected bad save states. Restore is all-or-nothing.
		for defect in ["missing", "revision", "scene", "count", "predecessor", "gap", "blocked", "tail", "cadence", "extra", "fraction"]:
			var bad: Dictionary = pending.duplicate(true)
			var trail: Dictionary = bad.extensions[Trail.EXTENSION]
			match defect:
				"missing": bad.extensions.erase(Trail.EXTENSION)
				"revision": trail.revision = 0
				"scene": trail.scene_id = "scene.missing"
				"count": trail.followers.pop_back()
				"predecessor": trail.followers[0].predecessor_id = bad.active_party[1]
				"gap": trail.followers[0].steps[0] = {"x": 19, "y": 14}
				"blocked": trail.followers[0].steps[0] = {"x": 5, "y": 3}
				"tail": trail.followers[0].steps = []
				"cadence": trail.next_tick = bad.clock.logic_tick + 9
				"extra": trail.surprise = true
				"fraction": trail.followers[0].steps[0].x = 1.5
			var before: Dictionary = s.snapshot()
			check(not s.restore(bad, 1000) and s.snapshot() == before, "%d corrupt %s save preserves live state" % [size, defect])
		# Move rejection must retain leader and all earlier follower proposals.
		candidate = pending.duplicate(true)
		var first_step: Vector2i = Trail.cell(candidate.extensions[Trail.EXTENSION].followers.back().steps[0])
		package.map_blocked[map_id][first_step] = true
		var untouched: Dictionary = candidate.duplicate(true)
		check(Trail.step(package, candidate, Vector2i.DOWN).has("error") and candidate == untouched, "%d obstruction rolls back whole proposed movement" % size)
		package.map_blocked[map_id].erase(first_step)
		candidate = pending.duplicate(true); untouched = candidate.duplicate(true)
		check(not Trail.reseed(package, candidate, order, true, {"remaining": 0}).is_empty() and candidate == untouched, "%d planning budget refuses without partial writes" % size)
		if size == 4:
			# Alternating plans share one executor budget. An earlier set must also roll back.
			var loop_a: Dictionary = {"id": "node.test.party-a", "op": "party", "members": pending.active_party.duplicate(), "next": "node.test.party-b"}
			var loop_b: Dictionary = {"id": "node.test.party-b", "op": "party", "members": order, "next": "node.test.party-a"}
			package.index.nodes[loop_a.id] = loop_a; package.index.nodes[loop_b.id] = loop_b
			var set_node: Dictionary = package.world.nodes[2].duplicate(true); set_node.id = "node.test.before-party"; set_node.next = loop_a.id
			package.index.nodes[set_node.id] = set_node
			s.state = pending.duplicate(true); var before_transaction: Dictionary = s.snapshot()
			check(not s._interact_node(set_node.id) and s.snapshot() == before_transaction and s.error.contains("规划预算"), "whole story shares planner budget and rolls back prior set/effect/order")
		package.map_blocked[map_id] = blocked
		# Actual compiled choice invokes the author-created ordered party node.
		s = Session.new(); s.activate(package, 1000); s.advance_dialogue()
		var before_join: Dictionary = s.snapshot()
		check(s.advance_dialogue(package.world.nodes[1].options[1].id), "%d authored choice executes party node" % size)
		check(s.state.active_party == package.world.nodes[-1].members and positions(s) == before_join.entities.map(func(e): return e.position), "%d authored join updates all members without teleport" % size)
		var held = WalkInput.new()
		for gate in ["dialogue", "pause", "focus", "modal"]:
			var snapshot: Array = positions(s)
			if gate == "dialogue": s.dialogue_open = true
			if gate == "pause": s.paused = true
			if gate == "focus": s.focused = false
			if gate == "modal": s.modal = true
			for _i in range(20): s.tick(); s.sample_movement(held)
			check(positions(s) == snapshot, "%d %s suspends follower execution" % [size, gate])
			s.dialogue_open = false; s.paused = false; s.focused = true; s.modal = false
	# Actual application loop must advance idle followers with no direction input.
	root.size = Vector2i(1280, 800)
	var app = App.instantiate(); root.add_child(app); await process_frame
	check(app.open_package(args[0]), "window opens authored package")
	app.session.advance_dialogue()
	app.session.advance_dialogue(app.session.package.world.nodes[1].options[1].id)
	var before_idle: Array = positions(app.session)
	var idle_leader: Dictionary = app.session.entity(app.session.state.active_party[0]).position.duplicate()
	for _i in range(100): await physics_frame
	check(positions(app.session) != before_idle and app.session.entity(app.session.state.active_party[0]).position == idle_leader, "application zero-input loop advances only pending followers")
	check(app.world_view.tiles is TileMapLayer and app.roster.get_child_count() == 5, "formal TileMap and roster show all five authored members")
	check(app.session.validate_saved(app.session.snapshot()).is_empty(), "window produces valid continuous party state")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("party-runtime.png"))
	var report: Dictionary = {"passed": checks.size() - failed, "failed": failed, "checks": checks, "saves": saved, "physical_input": false, "real_assets": false, "full_playthrough": false, "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name()}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE); file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print(JSON.stringify(report))
	quit(0 if failed == 0 else 1)
