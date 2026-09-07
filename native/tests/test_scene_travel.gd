# SPDX-License-Identifier: MIT
extends SceneTree
const App = preload("res://scenes/main.tscn")
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const Travel = preload("res://src/native_scene_travel.gd")
const MapProjection = preload("res://src/native_map_projection.gd")
var checks: Array = []
var failed: int = 0
var app

func _initialize() -> void: _run.call_deferred()
func check(ok: bool, name: String) -> void:
	checks.append({"name": name, "passed": ok})
	if not ok:
		failed += 1
		push_error(name)

func _key(key: Key, down: bool, echo: bool = false) -> void:
	var event = InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = down
	event.echo = echo
	Input.parse_input_event(event)

func _run() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 4:
		quit(2)
		return
	var output: String = args[3]
	DirAccess.make_dir_recursive_absolute(output)
	var saved: Array = []
	for package_path in [args[0], args[1], args[2]]:
		var package = Package.new()
		check(package.load_package(package_path), "compiled scene package loads: " + package_path.get_file())
		if not package.error.is_empty():
			push_error(package.error)
			quit(1)
			return
		var s = Session.new()
		check(s.activate(package, 1000), "activate scene fixture")
		var size: int = s.state.active_party.size()
		check(s.advance_dialogue() and s.advance_dialogue(package.world.nodes[1].options[0].id), "%d members complete initial choice" % size)
		check(s.move(Vector2i.DOWN), "%d members walk to portal" % size)
		var before: Dictionary = s.snapshot()
		check(s.interact(), "%d members enter paired destination" % size)
		var arrived: Dictionary = s.snapshot()
		var scene: Dictionary = package.index.scenes[arrived.cursor.scene_id]
		var entrance: Dictionary = scene.entrances[0]
		check(arrived.cursor.scene_id != before.cursor.scene_id and s.movement_rule() == "pal.walk.v1", "%d destination changes scene and movement profile" % size)
		for slot in range(size):
			var actor: Dictionary = s.entity(arrived.active_party[slot])
			check(actor.scene_id == scene.id and actor.position == entrance.positions[slot] and actor.components["pal.native.pose"].moving_until_tick == arrived.clock.logic_tick, "%d party slot %d arrives without stale motion" % [size, slot])
		for actor in before.entities:
			check(s.entity(actor.instance_id).hp == actor.hp and s.entity(actor.instance_id).mp == actor.mp, "%d entity stats preserved %s" % [size, actor.instance_id])
			if actor.instance_id not in before.active_party: check(s.entity(actor.instance_id) == actor, "%d inactive actor remains in source scene" % size)
		check(arrived.scopes == before.scopes and arrived.roster == before.roster and arrived.narrative_cast == before.narrative_cast and arrived.run_id == before.run_id and arrived.clock == before.clock and arrived.timeline_epoch == before.timeline_epoch, "%d identities/scopes/clock survive travel" % size)
		check(arrived.committed_effect_ids.size() == before.committed_effect_ids.size() + 1 and s.can_save(), "%d transfer commits once at destination safe point" % size)
		var saves = Save.new(output.path_join("party-%d" % size))
		check(saves.save(s), "%d actual destination save written" % size)
		var path: String = saves.last_path
		saved.append({"party": size, "package_path": package_path, "save_path": path})
		check(s.dialogue_open and s.advance_dialogue(), "%d arrival dialogue uses existing story executor" % size)
		check(s.interact() and s.state.cursor.scene_id == before.cursor.scene_id, "%d reciprocal portal returns" % size)
		check(saves.load_into(s, path), "%d save restores destination" % size)
		check(s.state.cursor == arrived.cursor and s.state.entities == arrived.entities and s.state.committed_effect_ids == arrived.committed_effect_ids and s.state.timeline_epoch == 1, "%d restore preserves state without reapplying transfer" % size)
		check(s.advance_dialogue() and s.move(Vector2i.DOWN), "%d first post-load PAL movement available after restored dialogue" % size)
		for slot in range(1, size): check(s.entity(s.state.active_party[slot]).position == arrived.entities.filter(func(e): return e.instance_id == arrived.active_party[slot - 1])[0].position, "%d follower %d continues arrival chain" % [size, slot])
		# Failure tests mutate only fresh synthetic model copies, never package bytes.
		for defect in ["capacity", "occupied", "blocked", "sprite_profile", "counter"]:
			var test = Session.new()
			test.activate(package, 1000)
			test.advance_dialogue()
			test.advance_dialogue(package.world.nodes[1].options[0].id)
			test.move(Vector2i.DOWN)
			var original_slots: Array = entrance.positions.duplicate(true)
			var original_actors: Dictionary = package.index.actor_definitions.duplicate(true)
			var original_sprites: Dictionary = package.index.sprite_sets.duplicate(true)
			var target_map: Dictionary = package.index.maps[scene.map_id]
			var blocked_before: Dictionary = package.map_blocked[target_map.id].duplicate()
			var original_rule: String = target_map.get("movement_rule", "native.grid.v1")
			if defect == "capacity": entrance.positions = entrance.positions.slice(0, size - 1)
			if defect == "occupied":
				# A synthetic independent non-party actor can occupy any slot.
				var visitor: Dictionary = test.state.entities[0].duplicate(true)
				visitor.instance_id = "instance.fixture.visitor"
				visitor.scene_id = scene.id
				visitor.position = entrance.positions[size - 1].duplicate()
				test.state.entities.append(visitor)
			if defect == "blocked": package.map_blocked[target_map.id][Vector2i(entrance.positions[-1].x, entrance.positions[-1].y)] = true; entrance.positions = entrance.positions.slice(0, size - 1) + [original_slots[-1]]
			if defect == "sprite_profile":
				package.index.actor_definitions[test.state.entities[0].definition_id].map_sprite_set = "sprite.fixture.profile"
				package.index.sprite_sets["sprite.fixture.profile"] = {"playback": "pal.walk-phase.v1"}
				target_map.movement_rule = "native.grid.v1"
			if defect == "counter": test.state.extensions[Travel.EXTENSION] = {"revision": 2147483647, "scene_id": test.state.cursor.scene_id, "entrance_id": "fixture"}
			var snapshot: Dictionary = test.snapshot()
			check(not test.interact() and test.snapshot() == snapshot and not test.error.is_empty(), "%d %s refuses complete transaction" % [size, defect])
			entrance.positions = original_slots
			package.index.actor_definitions = original_actors
			package.index.sprite_sets = original_sprites
			package.map_blocked[target_map.id] = blocked_before
			target_map.movement_rule = original_rule
		for defect in [true, -1, 2147483648]:
			var bad: Dictionary = arrived.duplicate(true)
			bad.extensions[Travel.EXTENSION].revision = defect
			check(not s.validate_saved(bad).is_empty(), "%d invalid saved scene revision refused" % size)
		if size == 4:
			var transaction = Session.new()
			transaction.activate(package, 1000)
			var greeting: Dictionary = package.index.nodes[package.world.entry_node]
			var old_next: String = greeting.next
			var transfer_id: String = package.index.scenes[package.world.entry_scene].portals[0].transfer_node
			package.index.nodes["node.fixture.assignment"] = {"id": "node.fixture.assignment", "op": "set", "variable": package.world.variables[0].id, "value": true, "next": transfer_id}
			greeting.next = "node.fixture.assignment"
			var before_slots: Array = entrance.positions.duplicate(true)
			entrance.positions = entrance.positions.slice(0, 2)
			var original: Dictionary = transaction.snapshot()
			check(not transaction.advance_dialogue() and transaction.snapshot() == original, "failed transfer rolls back preceding variable/effect/cursor changes")
			entrance.positions = before_slots
			greeting.next = old_next
			package.index.nodes.erase("node.fixture.assignment")
			var source_portal: Dictionary = package.index.scenes[package.world.entry_scene].portals[0]
			var reverse_id: String = source_portal.reverse_portal
			source_portal.reverse_portal = "portal.missing"
			check(not Travel.validate(package).is_empty(), "runtime reference validator rejects missing reciprocal portal")
			source_portal.reverse_portal = reverse_id
	root.size = Vector2i(1280, 800)
	app = App.instantiate()
	root.add_child(app)
	await process_frame
	check(app.open_package(args[0]), "production window loads GUI-authored package")
	await process_frame
	check(app.world_view.portal_markers.size() == 1, "source portal drawn in formal world")
	app.session.advance_dialogue()
	app.session.advance_dialogue(app.session.package.world.nodes[1].options[0].id)
	_key(KEY_S, true)
	await physics_frame
	_key(KEY_S, false)
	await process_frame
	var source_scene: String = app.session.state.cursor.scene_id
	check(app.session.entity(app.session.state.active_party[0]).position == {"x": 1, "y": 3}, "application keyboard walks onto authored door")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await process_frame
	await process_frame
	check(app.session.state.cursor.scene_id != source_scene, "application interaction key enters destination")
	check(app.world_view.actors.size() == 4 and app.roster.get_child_count() == 4 and app.world_view.portal_markers.size() == 1, "destination world/UI rebuild excludes inactive source actor")
	var actor: Dictionary = app.session.entity(app.session.state.active_party[0])
	var target: Vector2 = MapProjection.project(Vector2(actor.position.x, actor.position.y), app.world_view._map.coordinates)
	check(app.world_view.actors[actor.instance_id].position.is_equal_approx(target), "scene history resets at arrival instead of interpolating across maps")
	var revision: int = Travel.revision(app.session.state)
	_key(KEY_SPACE, true, true)
	await process_frame
	check(Travel.revision(app.session.state) == revision, "held interaction echo cannot bounce between scenes")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene-destination.png"))
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await process_frame
	check(app.session.state.cursor.scene_id != source_scene and not app.session.dialogue_open, "confirmation closes arrival dialogue before returning")
	_key(KEY_SPACE, true)
	_key(KEY_SPACE, false)
	await process_frame
	check(app.session.state.cursor.scene_id == source_scene and app.world_view.actors.size() == 5, "keyboard reciprocal return rebuilds source actors")
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("scene-returned.png"))
	# A synthetic same-scene node uses the same production executor/presentation.
	var room: Dictionary = app.session.package.index.scenes[source_scene]
	var local_entrance: Dictionary = room.entrances[0].duplicate(true)
	local_entrance.id = "entrance.fixture.same-scene"
	for point in local_entrance.positions: point.y += 2
	room.entrances.append(local_entrance)
	var local_node: Dictionary = {"id": "node.fixture.same-scene", "op": "scene_transfer", "scene_id": source_scene, "entrance_id": local_entrance.id, "next": app.session.state.cursor.node_id}
	app.session.package.index.nodes[local_node.id] = local_node
	var old_history: String = app.world_view._history_key()
	app.walk_input.key_event(KEY_D, true)
	check(app.session._interact_node(local_node.id), "same-scene transfer commits through production executor")
	actor = app.session.entity(app.session.state.active_party[0])
	target = MapProjection.project(Vector2(actor.position.x, actor.position.y), app.world_view._map.coordinates)
	check(app.world_view._history_key() != old_history and app.world_view.actors[actor.instance_id].position.is_equal_approx(target), "same-scene arrival revision resets render history")
	check(app.walk_input.sample(app.session.movement_rule()) == Vector2i.ZERO, "arrival clears held movement input")
	var report = {"passed": checks.size() - failed, "failed": failed, "checks": checks, "saves": saved, "save_path": saved[0].save_path, "physical_input": false, "real_assets": false, "full_playthrough": false, "renderer": RenderingServer.get_current_rendering_method(), "adapter": RenderingServer.get_video_adapter_name()}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true))
	file.close()
	print(JSON.stringify(report))
	quit(0 if failed == 0 else 1)
