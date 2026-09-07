# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Regions = preload("res://src/native_regions.gd")
const Save = preload("res://src/native_save.gd")
var checks: Array = []
var failed: int = 0
func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok:
		failed += 1
		push_error(label)
func walk(session, direction: Vector2i) -> bool:
	for _i in range(8): session.tick()
	return session.move(direction)
func finish_dialogue(session) -> void:
	check(session.advance_dialogue() and session.advance_dialogue(session.current_node().options[1].id), "finish initial conversation without reward")
func _initialize() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2:
		quit(2)
		return
	DirAccess.make_dir_recursive_absolute(args[1])
	var package = Package.new()
	check(package.load_package(args[0]), "load actual authored region package: " + package.error)
	if not package.error.is_empty():
		quit(1)
		return
	var triggers: Array = package.world.scenes[0].triggers
	var session = Session.new()
	check(session.activate(package, 0), "activate region package")
	check(session.state.extensions[Regions.KEY].sequence == 0, "spawn does not trigger region")
	finish_dialogue(session)
	check(walk(session, Vector2i.UP), "actual leader enters authored rectangle")
	check(session.dialogue_open and session.current_node().id == triggers[0].node_id, "higher priority dialogue owns input")
	var ext: Dictionary = session.state.extensions[Regions.KEY]
	check(ext.pending.size() == 1 and ext.fired.size() == 1, "second region queued without firing")
	check(session.validate_saved(session.state).is_empty(), "waiting queue is a valid save state: " + session.validate_saved(session.state))
	var snapshot: Dictionary = session.snapshot()
	var storage = Save.new(args[1].path_join("saves"))
	check(storage.save(session), "write actual queued-region generation: " + storage.error)
	if not storage.error.is_empty():
		quit(1)
		return
	var read: Dictionary = storage.read(session, storage.last_path)
	check(read.has("state") and read.state.extensions[Regions.KEY] == snapshot.extensions[Regions.KEY], "read exact pending queue from save bytes")
	check(session.restore(read.state), "restore queue without reexecuting trigger")
	check(session.state.extensions[Regions.KEY] == snapshot.extensions[Regions.KEY], "restore does not create crossing")
	finish_dialogue(session)
	check(not session.dialogue_open and session.state.scopes.run.values()[0] == true, "queued condition then reward drains after dialogue")
	check(session.state.extensions[Regions.KEY].pending.is_empty() and session.state.extensions[Regions.KEY].fired.size() == 2, "both once records committed")
	check(walk(session, Vector2i.DOWN) and walk(session, Vector2i.UP) and not session.dialogue_open, "once regions do not repeat on new crossing")
	check(session.state.extensions[Regions.KEY].fired[triggers[0].id].count == 1, "once count remains one")
	# All subsequent cases are synthetic mutations of the already loaded fixture,
	# not claims that the author window produced these combinations.
	var original: Array = triggers.duplicate(true)
	triggers[0].node_id = package.world.nodes[2].id
	triggers[0].policy = "repeat"
	triggers[1].condition = null
	triggers[1].policy = "repeat"
	triggers[0].mutex_group = "camp"
	triggers[1].mutex_group = "camp"
	check(Regions.validate(package).is_empty(), "validate synthetic persistent mutex")
	check(session.activate(package, 0), "restart mutex fixture"); finish_dialogue(session)
	check(walk(session, Vector2i.UP), "mutex entry")
	ext = session.state.extensions[Regions.KEY]
	check(ext.fired.size() == 1 and ext.mutex.camp == triggers[0].id, "highest priority eligible member owns mutex")
	check(walk(session, Vector2i.DOWN) and walk(session, Vector2i.UP), "repeat owner reenters")
	check(session.state.extensions[Regions.KEY].fired[triggers[0].id].count == 2, "winning repeat owner can fire again")
	triggers[0].policy = "cooldown"; triggers[0].cooldown_ticks = 60
	check(session.activate(package, 0), "restart cooldown fixture"); finish_dialogue(session)
	check(walk(session, Vector2i.UP) and walk(session, Vector2i.DOWN) and walk(session, Vector2i.UP), "cross twice before cooldown")
	check(session.state.extensions[Regions.KEY].fired[triggers[0].id].count == 1, "cooldown suppresses early crossing")
	for _i in range(60): session.tick()
	check(session.state.extensions[Regions.KEY].fired[triggers[0].id].count == 1, "standing after cooldown does not synthesize entry")
	check(walk(session, Vector2i.DOWN) and walk(session, Vector2i.UP), "cross after cooldown")
	check(session.state.extensions[Regions.KEY].fired[triggers[0].id].count == 2, "cooldown admits later crossing")
	triggers[0].policy = "repeat"; triggers[0].cooldown_ticks = 0; triggers[0].event = "exit"
	check(session.activate(package, 0), "restart exit fixture"); finish_dialogue(session)
	check(walk(session, Vector2i.UP), "enter exit region")
	check(not session.state.extensions[Regions.KEY].fired.has(triggers[0].id), "exit does not fire on enter")
	# Remove competing winner for the isolated exit case.
	session.state.extensions[Regions.KEY].mutex.clear(); session.state.extensions[Regions.KEY].fired.clear()
	check(walk(session, Vector2i.DOWN) and session.state.extensions[Regions.KEY].fired.has(triggers[0].id), "exit fires on actual boundary departure")
	triggers[0].event = "enter"; triggers[0].mutex_group = null; triggers[1].mutex_group = null
	triggers[1].condition = {"op": "var_eq", "variable": "missing", "value": true}
	check(session.activate(package, 0), "restart rollback fixture"); finish_dialogue(session)
	for _i in range(8): session.tick()
	var before: Dictionary = session.snapshot()
	check(not session.move(Vector2i.UP), "invalid later condition rejects entire crossing")
	check(session.state == before, "movement, earlier reward, cursor and policy claims all roll back")
	triggers[1].condition = null
	check(session.move(Vector2i.UP), "same movement tick retries after repair")
	# Known scheduler extension rejects impossible claims and stale pending state.
	for kind in ["sequence", "tick", "crossing", "scene", "unknown", "duplicate", "mutex", "count"]:
		var bad: Dictionary = snapshot.duplicate(true)
		var scheduler: Dictionary = bad.extensions[Regions.KEY]
		match kind:
			"sequence": scheduler.pending[0].sequence = scheduler.sequence + 1
			"tick": scheduler.pending[0].tick = bad.clock.logic_tick + 1
			"crossing": scheduler.pending[0].from = scheduler.pending[0].to.duplicate()
			"scene": scheduler.pending[0].scene_id = "missing"
			"unknown": scheduler.pending[0].trigger_id = "missing"
			"duplicate": scheduler.pending.append(scheduler.pending[0].duplicate(true))
			"mutex": scheduler.mutex.bad = triggers[0].id
			"count": scheduler.fired[triggers[0].id].count = scheduler.sequence + 1
		check(not session.validate_saved(bad).is_empty(), "reject corrupted region " + kind)
	# Restore exact source definitions before interpreting the saved fixture again.
	package.world.scenes[0].triggers = original
	check(Regions.validate(package).is_empty(), "restore actual fixture definitions")
	check(session.restore(read.state), "restore real saved queue after synthetic trials")
	var no_move: Dictionary = session.snapshot()
	check(not session.move(Vector2i.ZERO) and session.state == no_move, "waiting owner blocks follower-only movement")
	# Same-scene transfer runs through the production story executor and must
	# discard the old crossing tail, retaining the committed once record.
	var scene: Dictionary = package.world.scenes[0]
	scene.entrances = [{"id": "entrance.region.test", "display_name": "Test", "facing": "down", "positions": [{"x": 1, "y": 1}, {"x": 2, "y": 1}, {"x": 3, "y": 1}, {"x": 4, "y": 1}]}]
	var transfer: Dictionary = {"id": "node.region.transfer", "op": "scene_transfer", "scene_id": scene.id, "entrance_id": "entrance.region.test", "next": package.world.nodes[3].id}
	package.index.nodes[transfer.id] = transfer
	check(session._advance(transfer.id), "production same-scene transfer with pending region tail")
	check(session.state.extensions[Regions.KEY].pending.is_empty() and session.state.extensions[Regions.KEY].fired.size() == 1, "transfer clears queue but preserves once claim")
	check(session.state.extensions[Regions.KEY].sequence == snapshot.extensions[Regions.KEY].sequence, "transfer arrival inside region does not synthesize crossing")
	var party: Dictionary = {"id": "node.region.party", "op": "party", "members": session.state.active_party.duplicate(), "next": package.world.nodes[3].id}
	party.members.reverse(); package.index.nodes[party.id] = party
	check(session._advance(party.id), "change leader via production story transaction")
	check(session.state.extensions[Regions.KEY].sequence == snapshot.extensions[Regions.KEY].sequence, "leader change does not synthesize entry/exit")
	var seq: int = session.state.extensions[Regions.KEY].sequence
	for _i in range(8): session.tick()
	session.move(Vector2i.ZERO)
	check(session.state.extensions[Regions.KEY].sequence == seq, "follower-only catch-up does not synthesize region event")
	var report: Dictionary = {"checks": checks, "failed": failed, "save_path": storage.last_path, "actual_author_package": args[0], "synthetic_mutations": true, "ui_input": false, "full_playthrough": false}
	FileAccess.open(args[1].path_join("results.json"), FileAccess.WRITE).store_string(JSON.stringify(report, "\t", false, true))
	print(JSON.stringify(report))
	quit(0 if failed == 0 else 1)
