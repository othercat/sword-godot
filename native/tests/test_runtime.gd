# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const Reader = preload("res://src/native_json.gd")
const Schema = preload("res://src/native_schema.gd")
var checks: Array = []
var failures: int = 0
var scratch: String
var package_path: String

func check(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition:
		failures += 1
		push_error(name)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2:
		push_error("Provide package and scratch directory")
		quit(2)
		return
	package_path = args[0]
	scratch = args[1].path_join(Session.unique("runtime-test"))
	DirAccess.make_dir_recursive_absolute(scratch)
	var package = Package.new()
	check(package.load_package(package_path), "actual Studio ZIP loads without DOS dependencies")
	if not package.error.is_empty():
		push_error(package.error)
		quit(1)
		return
	check(not DirAccess.dir_exists_absolute("res://Data") and not FileAccess.file_exists("res://objects_dos.bin"), "Native root has no DOS data")
	check(package.world.active_party.size() == 4 and package.world.roster.size() == 5, "four active/five roster preserve identity")
	var session = Session.new()
	check(session.activate(package, 1000), "activate actual world")
	var start: Dictionary = session.snapshot()
	check(package.schema.validate("pal.native.state.v1", start).is_empty(), "live state conforms to shared schema")
	if not package.schema.error.is_empty(): push_error(package.schema.error)
	check(not session.move(Vector2i.DOWN), "dialogue blocks movement")
	check(session.advance_dialogue(), "dialogue advances to choice")
	check(not session.advance_dialogue("choice.unknown"), "unknown choice cannot advance")
	check(session.advance_dialogue(package.world.nodes[1].options[0].id), "actual positive choice executes declared set")
	check(session.state.scopes.run[package.world.variables[0].id] == true and session.state.committed_effect_ids.size() == 1, "effect state committed once")
	check(not session.advance_dialogue(), "completed dialogue cannot repeat effect")
	for _i in range(8): session.tick()
	check(session.move(Vector2i.DOWN), "authoritative tile movement works")
	for i in range(1, 4):
		check(session.entity(session.state.active_party[i]).position == start.entities[i - 1].position, "follower %d uses prior tile" % i)
	check(not session.move(Vector2i.LEFT), "same-tick repeat does not increase speed")
	check(not session.move(Vector2i(1, 1)), "diagonal command rejected")
	var state_before = session.snapshot()
	var invalid = Package.new()
	invalid.error = "fixture rejected"
	check(not session.activate(invalid, 2000) and session.state == state_before, "failed activation preserves live session")
	check(session.restore(start, 2000), "restore checkpoint candidate")
	check(session.state.timeline_epoch == 1 and session.state.session_id == start.session_id, "restore rebinds active epoch/session")
	session.account_time(1001000)
	check(session.state.clock.rta_usec == 1000000 and session.state.clock.active_game_usec == 1000000, "monotonic practice clock")
	session.set_pause(true, 1001000)
	session.account_time(2001000)
	check(session.state.clock.rta_usec == 2000000 and session.state.clock.active_game_usec == 1000000, "RTA includes pause; active clock excludes pause")
	var paused_tick: int = session.state.clock.logic_tick
	session.tick()
	check(session.state.clock.logic_tick == paused_tick, "paused logic does not tick")
	session.set_pause(false, 2001000)
	check(session.restore(start, 2001000) and session.state.clock.rta_usec == 2000000, "old save cannot rewind RTA")
	var bad = start.duplicate(true)
	bad.entities[0].hp = 999999
	state_before = session.snapshot()
	check(not session.restore(bad, 2001000) and session.state == state_before, "invalid save stats leave state unchanged")
	bad = start.duplicate(true)
	bad.entities[0].position.x = -99999
	check(not session.restore(bad, 2001000), "invalid saved position rejected")
	bad = start.duplicate(true)
	bad.active_party = []
	state_before = session.snapshot()
	check(not session.restore(bad, 2001000) and session.state == state_before, "empty active party rejected before restoring state")
	session.set_modal(true, 2001000)
	var modal_tick: int = session.state.clock.logic_tick
	var modal_active: int = session.state.clock.active_game_usec
	session.tick()
	session.account_time(2501000)
	check(session.state.clock.logic_tick == modal_tick and session.state.clock.active_game_usec == modal_active and session.state.clock.logic_paused, "modal pauses logic and active clock consistently")
	session.set_modal(false, 2501000)
	var storage = Save.new(scratch.path_join("saves"))
	session.state.extensions["fixture.unknown"] = {"text": "中文", "values": [7, false]}
	storage.envelope_extensions["fixture.unknown"] = {"opaque": ["keep", 17]}
	storage.source_origin = "modified"
	check(storage.save(session), "real save bundle writes and verifies")
	if not storage.error.is_empty(): push_error(storage.error)
	var saved_path: String = storage.last_path
	var saved_bytes: PackedByteArray = FileAccess.get_file_as_bytes(saved_path) if not saved_path.is_empty() else PackedByteArray()
	check(not storage.save(session, true), "injected interruption before publication")
	check(storage.generations(session).size() == 1, "pending generation excluded from selection")
	check(storage.load_into(session, saved_path, 2001000), "real save bundle loads")
	check(storage.source_origin == "modified", "modified save origin remains modified after load")
	check(session.state.extensions["fixture.unknown"].text == "中文" and storage.envelope_extensions["fixture.unknown"].opaque[1] == 17, "unknown state/envelope extensions preserved")
	check(storage.save(session), "second immutable save generation")
	check(storage.read(session, storage.last_path).envelope.origin == "modified", "ordinary resave never launders modified origin")
	var source_save = ZIPReader.new()
	source_save.open(saved_path)
	var wrong_envelope: Dictionary = JSON.parse_string(source_save.read_file("save.json").get_string_from_utf8())
	wrong_envelope.state_path = "state/other.json"
	var wrong_path_save: Dictionary = {"save.json": JSON.stringify(wrong_envelope).to_utf8_buffer(), "state/current.json": source_save.read_file("state/current.json")}
	source_save.close()
	check(storage.read(session, _write_zip(wrong_path_save, "wrong-state-path")).is_empty(), "save envelope cannot name a different missing state payload")
	check(FileAccess.get_file_as_bytes(saved_path) == saved_bytes and storage.generations(session).size() == 2, "save never overwrites prior generation")
	var corrupt_path = scratch.path_join("corrupt.palsave")
	var corrupt = saved_bytes.duplicate()
	if not corrupt.is_empty(): corrupt[0] = 0
	var output = FileAccess.open(corrupt_path, FileAccess.WRITE)
	output.store_buffer(corrupt)
	output.close()
	state_before = session.snapshot()
	check(not storage.load_into(session, corrupt_path, 2001000) and session.state == state_before, "corrupt save leaves active state and prior save intact")
	for text in ['{"x":1,"x":2}', '{"x":1,}', '[1,]', '{"x":"\\ud800"}', '01', 'true false', '1e999', '"line\nbreak"']:
		var reader = Reader.new()
		reader.decode(text.to_utf8_buffer())
		check(not reader.error.is_empty(), "strict JSON rejects " + text.c_escape())
	var reader = Reader.new()
	check(reader.decode('{"unicode":"\\ud83d\\ude00中文","null":null,"float":1.5}'.to_utf8_buffer()).unicode == "😀中文", "strict Unicode/surrogate decode")
	var original = ZIPReader.new()
	original.open(package_path)
	var files: Dictionary = {}
	for path in original.get_files(): files[path] = original.read_file(path)
	original.close()
	_test_bad_packages(files)
	_test_hd_texture(files)
	_test_display_schedules(package)
	_test_transaction_boundaries(files)
	var transient = Session.new()
	transient.activate(package, 0)
	transient.state.cursor.safe_point_id = null
	check(package.schema.validate("pal.native.state.v1", transient.snapshot()).is_empty(), "live non-save cursor conforms to state schema")
	check(not transient.can_save() and not transient.validate_saved(transient.snapshot()).is_empty(), "live non-save cursor cannot be persisted as a checkpoint")
	var report = {"checks": checks, "passed": checks.size() - failures, "failed": failures, "synthetic": true, "full_playthrough": false, "scratch": scratch, "save_fixture": saved_path}
	output = FileAccess.open(scratch.path_join("results.json"), FileAccess.WRITE)
	output.store_string(JSON.stringify(report, "  ", true))
	output.close()
	print(JSON.stringify(report))
	quit(0 if failures == 0 else 1)

func _write_zip(files: Dictionary, name: String) -> String:
	var path = scratch.path_join(name + ".zip")
	var packer = ZIPPacker.new()
	packer.open(path)
	for key in files:
		packer.start_file(key)
		packer.write_file(files[key])
		packer.close_file()
	packer.close()
	return path

func _test_bad_packages(files: Dictionary) -> void:
	var variants: Dictionary = {}
	var bad = files.duplicate(true)
	bad["content/world.json"] = "{}".to_utf8_buffer()
	variants["corrupt-payload"] = bad
	bad = files.duplicate(true)
	bad["run.gd"] = "extends Node".to_utf8_buffer()
	variants["undeclared-code"] = bad
	bad = files.duplicate(true)
	bad["../escape.json"] = "{}".to_utf8_buffer()
	variants["path-traversal"] = bad
	bad = files.duplicate(true)
	bad["Manifest.json"] = bad["manifest.json"]
	variants["case-collision"] = bad
	for variant in ["contract-hash", "capability", "dependency"]:
		bad = files.duplicate(true)
		var manifest: Dictionary = JSON.parse_string(bad["manifest.json"].get_string_from_utf8())
		if variant == "contract-hash": manifest.contract_hashes["pal.native.content.v1"] = "0".repeat(64)
		elif variant == "capability": manifest.required_capabilities.append("unknown.execute.v1")
		else: manifest.dependencies.append({"package_id": "fixture.other", "version": "0.1.0", "content_hash": "0".repeat(64)})
		bad["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
		variants[variant] = bad
	for name in variants:
		var package = Package.new()
		check(not package.load_package(_write_zip(variants[name], name)), "reject package " + name)

func _test_hd_texture(files: Dictionary) -> void:
	var changed_files = files.duplicate(true)
	var world: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
	var hd = Image.create(2048, 2048, false, Image.FORMAT_RGBA8)
	hd.fill(Color(0.3, 0.2, 0.7, 0.5))
	var png = hd.save_png_to_buffer()
	var asset = {"id": "asset.fixture.hd", "path": "assets/hd.png", "kind": "texture", "sha256": Schema.digest(png), "size_bytes": png.size(), "license": "CC0-1.0", "redistributable": true, "provenance": {"source_id": "fixture.generated", "status": "synthetic", "source_beat_ids": []}}
	world.assets.append(asset)
	world.actor_definitions[0].sprite_asset = asset.id
	changed_files[asset.path] = png
	changed_files["content/world.json"] = JSON.stringify(world).to_utf8_buffer()
	var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
	manifest.files = []
	for path in changed_files:
		if path == "manifest.json": continue
		manifest.files.append({"path": path, "sha256": Schema.digest(changed_files[path]), "size_bytes": changed_files[path].size(), "kind": "texture" if path == asset.path else "content"})
	changed_files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var package = Package.new()
	check(package.load_package(_write_zip(changed_files, "hd-texture")), "actual bounded HD PNG decode")
	if not package.error.is_empty(): push_error(package.error)
	check(package.textures.has(asset.id) and package.textures[asset.id].get_width() == 2048, "HD texture retains 2048px resolution")

func _test_display_schedules(package) -> void:
	var baseline: Dictionary = {}
	for rate in [30, 60, 100, 120, 144, 240]:
		var session = Session.new()
		session.activate(package, 0)
		session.advance_dialogue()
		session.advance_dialogue(package.world.nodes[1].options[0].id)
		var ticks: int = 0
		for frame in range(1, rate * 2 + 1):
			var until: int = int(frame * 60.0 / rate)
			while ticks < until:
				session.tick()
				session.move(Vector2i.DOWN if ticks < 60 else Vector2i.UP)
				ticks += 1
			session.account_time(int(frame * 1000000.0 / rate))
		var projection: Dictionary = {"tick": session.state.clock.logic_tick, "rta": session.state.clock.rta_usec, "active": session.state.clock.active_game_usec, "entities": session.state.entities, "scopes": session.state.scopes}
		if baseline.is_empty(): baseline = projection
		check(projection == baseline, "synthetic %d FPS schedule retains same 60Hz authority" % rate)

func _test_transaction_boundaries(files: Dictionary) -> void:
	for kind in ["automatic-loop", "remote-party"]:
		var changed_files = files.duplicate(true)
		var world: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
		var old_set: Dictionary = world.nodes[2]
		if kind == "automatic-loop":
			old_set.next = old_set.id
		else:
			var remote_scene = world.scenes[0].duplicate(true)
			remote_scene.id = "scene.fixture.remote"
			world.scenes.append(remote_scene)
			world.entities[4].scene_id = remote_scene.id
			world.nodes[2] = {"id": old_set.id, "op": "party", "members": [world.entities[4].instance_id], "next": old_set.next, "provenance": old_set.provenance}
		changed_files["content/world.json"] = JSON.stringify(world).to_utf8_buffer()
		var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
		for file in manifest.files:
			file.size_bytes = changed_files[file.path].size()
			file.sha256 = Schema.digest(changed_files[file.path])
		changed_files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
		var package = Package.new()
		check(package.load_package(_write_zip(changed_files, kind)), "valid references in " + kind + " fixture")
		var session = Session.new()
		session.activate(package, 0)
		session.advance_dialogue()
		var before = session.snapshot()
		check(not session.advance_dialogue(world.nodes[1].options[0].id) and session.state == before, kind + " rejects entire transition and retains prior state")
