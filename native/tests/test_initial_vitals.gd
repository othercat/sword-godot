# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Session = preload("res://src/native_session.gd")
const Save = preload("res://src/native_save.gd")
const Schema = preload("res://src/native_schema.gd")
const Vitals = preload("res://src/native_initial_vitals.gd")
const Growth = preload("res://src/native_progression.gd")
const Equipment = preload("res://src/native_equipment.gd")
const HASH_KEY = "pal.native.component-contracts"
var checks: Array = []
var failed: int = 0
var output: String

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]
	if FileAccess.file_exists(output.path_join("results.json")): push_error("Use a fresh evidence directory"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	for fixture in fixtures:
		var package = Package.new()
		check(package.load_package(fixture.path), "real Studio package admitted: " + fixture.kind)
		if not package.error.is_empty(): push_error(package.error); _finish(); return
		var hero: String = package.world.entities[0].instance_id
		var session = Session.new(); var published: Array = []
		var observe: Callable = func(): published.append(session.entity(hero).hp)
		session.changed.connect(observe)
		check(session.activate(package, 1000), "new session activates: " + fixture.kind)
		if session.state.is_empty(): push_error(session.error); _finish(); return
		var actor: Dictionary = session.entity(hero); var limits: Dictionary = Growth.stats(package, actor)
		check(actor.hp == fixture.hp and actor.mp == fixture.mp, "starting current values match compiler fixture: " + fixture.kind)
		check(limits.max_hp == fixture.max_hp and limits.max_mp == fixture.max_mp, "effective limits include initial growth and equipment: " + fixture.kind)
		session.changed.disconnect(observe)
		check(not published.is_empty() and published.all(func(hp): return hp == fixture.hp), "every initial publication has configured HP: " + fixture.kind)
		check(session.validate_saved(session.snapshot()).is_empty(), "initial session is a valid checkpoint: " + fixture.kind)
		if fixture.kind == "authored":
			check(session.state.entities[1].hp == 0 and session.state.entities[2].hp == 120 and session.state.entities[4].hp == 7, "same-definition active reserve and default instances stay independent")
			_test_admission(fixture.path, session)
			_test_party(fixture.path)
		var hp: int = mini(7, int(limits.max_hp)); var mp: int = mini(3, int(limits.max_mp))
		actor.hp = hp; actor.mp = mp
		var storage = Save.new(output.path_join(fixture.kind + "-saves")); storage.source_origin = "modified"
		check(storage.save(session), "actual save generation written: " + fixture.kind)
		if storage.last_path.is_empty(): push_error(storage.error); _finish(); return
		var before_bytes: PackedByteArray = FileAccess.get_file_as_bytes(storage.last_path)
		var fresh = Session.new(); check(fresh.activate(package, 2000), "second session starts from configured values: " + fixture.kind)
		check(fresh.entity(hero).hp == fixture.hp and fresh.entity(hero).mp == fixture.mp, "new game reuses configuration: " + fixture.kind)
		check(storage.load_into(fresh, storage.last_path, 3000), "existing save loads into second session: " + fixture.kind)
		check(fresh.entity(hero).hp == hp and fresh.entity(hero).mp == mp, "load preserves saved HP/MP instead of reapplying initial values: " + fixture.kind)
		check(FileAccess.get_file_as_bytes(storage.last_path) == before_bytes, "load leaves immutable save generation intact: " + fixture.kind)
		var before: Dictionary = fresh.snapshot(); var bad: Dictionary = before.duplicate(true)
		bad.entities[0].hp = limits.max_hp + 1
		check(not fresh.restore(bad, 4000) and fresh.state == before, "invalid saved maximum preserves live session: " + fixture.kind)
	_finish()

func _files(path: String) -> Dictionary:
	var zip = ZIPReader.new(); zip.open(path); var files: Dictionary = {}
	for name in zip.get_files(): files[name] = zip.read_file(name)
	zip.close(); return files

func _write(files: Dictionary, world: Dictionary, manifest: Dictionary, name: String) -> String:
	files = files.duplicate(true)
	files["content/world.json"] = JSON.stringify(world).to_utf8_buffer()
	for row in manifest.files:
		row.sha256 = Schema.digest(files[row.path]); row.size_bytes = files[row.path].size()
	files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var path: String = output.path_join(name + ".zip"); var packer = ZIPPacker.new(); packer.open(path)
	for key in files:
		packer.start_file(key); packer.write_file(files[key]); packer.close_file()
	packer.close(); return path

func _test_admission(path: String, session) -> void:
	var files: Dictionary = _files(path)
	for defect in ["capability", "schema-hash", "orphan", "negative", "fraction", "boolean", "over-hp", "over-mp", "duplicate", "unknown", "empty", "null", "extra"]:
		var world: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
		var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
		var row: Dictionary = world.extensions[Vitals.KEY].actors[0]
		match defect:
			"capability": manifest.required_capabilities.erase(Vitals.CAPABILITY)
			"schema-hash": manifest.extensions[HASH_KEY][Vitals.SCHEMA] = "0".repeat(64)
			"orphan": world.extensions.erase(Vitals.KEY)
			"negative": row.hp = -1
			"fraction": row.hp = 1.5
			"boolean": row.mp = true
			"over-hp": row.hp = 241
			"over-mp": row.mp = 241
			"duplicate": world.extensions[Vitals.KEY].actors.append(row.duplicate(true))
			"unknown": row.instance_id = "instance.missing"
			"empty": world.extensions[Vitals.KEY].actors.clear()
			"null": world.extensions[Vitals.KEY] = null
			"extra": row.heal_on_join = true
		var bad = Package.new(); var before: Dictionary = session.snapshot()
		check(not bad.load_package(_write(files, world, manifest, "bad-" + defect)), "package admission rejects " + defect)
		check(not session.activate(bad, 2000) and session.state == before, "rejected candidate retains live session: " + defect)
	var changed = Package.new(); check(changed.load_package(path), "fresh candidate admitted before initialization mutation")
	changed.world.extensions[Vitals.KEY].actors[0].hp = 241
	var before: Dictionary = session.snapshot()
	check(not session.activate(changed, 2000) and session.state == before, "post-admission invalid initial HP rolls back activation")

func _test_party(path: String) -> void:
	var files: Dictionary = _files(path)
	var world: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
	var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
	var prior: Dictionary = world.nodes[2]
	world.nodes[2] = {"id": prior.id, "op": "party", "members": [world.entities[0].instance_id, world.entities[4].instance_id], "next": prior.next, "provenance": prior.provenance.duplicate(true)}
	world.nodes[2].provenance.status = "synthetic"
	var package = Package.new()
	check(package.load_package(_write(files, world, manifest, "party-join")), "synthetic party transition admitted with ordinary loader")
	if not package.error.is_empty(): push_error(package.error); return
	var session = Session.new(); check(session.activate(package, 0), "party transition session activates")
	check(session.advance_dialogue() and session.advance_dialogue(world.nodes[1].options[0].id), "ordinary story party operation admits reserve member")
	check(world.entities[4].instance_id in session.state.active_party and session.state.entities[4].hp == 7 and session.state.entities[0].hp == 28, "joining party preserves reserve and current-party vitals")

func _finish() -> void:
	var report: Dictionary = {"checks": checks, "passed": checks.size() - failed, "failed": failed, "synthetic": true, "full_playthrough": false, "headless": true}
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "  ", true)); file.close()
	print("Initial vitals checks: %d passed, %d failed; %s" % [checks.size() - failed, failed, output])
	quit(0 if failed == 0 else 1)
