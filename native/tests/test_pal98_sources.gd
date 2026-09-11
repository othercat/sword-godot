# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Kernel = preload("res://src/native_pal98_equipment_kernel.gd")
const Session = preload("res://src/native_session.gd")
const Schema = preload("res://src/native_schema.gd")
const Reader = preload("res://src/native_json.gd")
const HASH_KEY = "pal.native.component-contracts"
var checks: Array = []
var failed: int = 0
var output: String
var reference: Dictionary = {}

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]
	if DirAccess.dir_exists_absolute(output): push_error("Use a fresh evidence directory"); quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var fixture: Dictionary = Reader.new().decode(FileAccess.get_file_as_bytes(args[0]))
	for path in [fixture.package, fixture.directory]:
		var package = Package.new()
		check(package.load_package(path), "ordinary source package admitted: " + path.get_file())
		if not package.error.is_empty(): push_error(package.error); _finish(); return
		check(package.pal98_sources != null, "source snapshot available")
		var source = package.pal98_sources
		check(source.counts() == fixture.counts, "source counts and message tail match compiler")
		check(source.metadata() == fixture.descriptor, "source identity and encoding match compiler")
		for role in Sources.FILES:
			var bytes: PackedByteArray = source.copy_bytes(role)
			check(Schema.digest(bytes) == fixture.descriptor.files[role].sha256, "source bytes " + role)
			if not bytes.is_empty(): bytes[0] ^= 1
			check(Schema.digest(source.copy_bytes(role)) == fixture.descriptor.files[role].sha256, "source copy isolation " + role)
		var metadata: Dictionary = source.metadata(); metadata.fingerprint = "changed"
		var counts: Dictionary = source.counts(); counts.roles = 0
		check(source.metadata().fingerprint == fixture.fingerprint and source.counts().roles == 6, "metadata and count copies do not mutate stored source")
		var session = Session.new(); check(session.activate(package, 1000), "ordinary authored session still activates")
		check(not JSON.stringify(session.snapshot()).contains(fixture.fingerprint), "source admission adds no interpreter state or role mapping")
		if path == fixture.package:
			_equipment(source)
			reference.package_content_lock = package.content_lock
			reference.package_sha256 = Schema.digest(FileAccess.get_file_as_bytes(path))
			_synthetic(_files(path), package.schema)
	_finish()

func _equipment(source) -> void:
	var kernel = Kernel.new()
	check(kernel.read_tables(source.copy_chunk("data", 3), source.copy_chunk("sss", 2), source.copy_chunk("sss", 4)), "equipment consumer reads admitted package source chunks")
	var rows: Array = []
	var expected: Array = [[35,20,41,31,32],[28,72,41,61,27],[58,22,72,60,37],[268,564,284,141,96],[218,282,176,160,168],[190,650,254,122,49]]
	for role in range(6):
		var initial: Dictionary = kernel.initial_state([role])
		var rebuilt: Dictionary = kernel.rebuild_party_equipment(initial)
		check(rebuilt.has("state"), "admitted source equipment completes for single-role party " + str(role))
		if not rebuilt.has("state"): push_error(str(rebuilt)); continue
		var stats: Array = []
		for field in range(17,31):
			var value: Dictionary = kernel.effective_stat(rebuilt.state, role, field)
			check(value.has("value"), "effective field from source " + str(role) + ":" + str(field))
			stats.append(value.get("value"))
		check(stats.slice(0,5) == expected[role], "five independently established source stats " + str(role))
		rows.append({"role": role, "state": rebuilt.state, "effective": stats})
	reference = {"source_fingerprint": source.metadata().fingerprint, "counts": source.counts(), "equipment": rows}

func _files(path: String) -> Dictionary:
	var zip = ZIPReader.new(); zip.open(path); var files: Dictionary = {}
	for name in zip.get_files(): files[name] = zip.read_file(name)
	zip.close(); return files

func _mkf(chunks: Array) -> PackedByteArray:
	var size: int = (chunks.size() + 1) * 4
	var bytes = PackedByteArray(); bytes.resize(size); bytes.encode_u32(0, size)
	for i in range(chunks.size()):
		size += chunks[i].size(); bytes.encode_u32((i + 1) * 4, size)
	for chunk in chunks: bytes.append_array(chunk)
	return bytes

func _zero(count: int) -> PackedByteArray:
	var bytes = PackedByteArray(); bytes.resize(count); return bytes

func _offsets(values: Array) -> PackedByteArray:
	var bytes = _zero(values.size() * 4)
	for i in range(values.size()): bytes.encode_u32(i * 4, values[i])
	return bytes

func _descriptor(payloads: Dictionary, encoding: String = "gbk") -> Dictionary:
	var hashes: Dictionary = {}
	for role in Sources.FILES: hashes[role] = Schema.digest(payloads[role])
	var identity: String = Sources.fingerprint(encoding, hashes)
	var files: Dictionary = {}
	for role in Sources.FILES:
		files[role] = {"path": "content/pal98-sources/" + identity + "/" + Sources.FILES[role], "sha256": hashes[role], "size_bytes": payloads[role].size()}
	return {"schema": Sources.SCHEMA, "kind": "content", "dialect": "pal98-win95", "text_encoding": encoding, "fingerprint": identity,
		"label": "Synthetic sources", "license": "CC0-1.0", "redistributable": true, "files": files, "provenance": {"status": "synthetic"}}

func _write_package(base: Dictionary, component: Dictionary, payloads: Dictionary, defect: String) -> String:
	var files: Dictionary = base.duplicate(true)
	for name in files.keys():
		if name.begins_with("content/pal98-sources/"): files.erase(name)
	var world: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
	var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
	var kinds: Dictionary = {}
	for row in manifest.files: kinds[row.path] = row.kind
	world.extensions[Sources.KEY] = component
	for role in Sources.FILES: files[component.files[role].path] = payloads[role]
	if defect == "cap": manifest.required_capabilities.erase(Sources.CAPABILITY)
	if defect == "orphan": world.extensions.erase(Sources.KEY)
	if defect == "schema-hash": manifest.extensions[HASH_KEY][Sources.SCHEMA] = "0".repeat(64)
	if defect == "missing": files.erase(component.files.data.path)
	if defect == "extra": files["content/undeclared.bin"] = PackedByteArray([1])
	if defect == "rights":
		component.redistributable = false; manifest.extensions.erase("pal.native.distribution"); manifest.required_capabilities.erase("package.local-preview.v1")
	files["content/world.json"] = JSON.stringify(world).to_utf8_buffer()
	var rows: Array = []
	for path in files:
		if path == "manifest.json": continue
		rows.append({"path": path, "kind": "license" if defect == "file-kind" and path == component.files.data.path else kinds.get(path, "content"), "sha256": Schema.digest(files[path]), "size_bytes": files[path].size()})
	manifest.files = rows; files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var path: String = output.path_join(defect + ".zip"); var zip = ZIPPacker.new(); zip.open(path)
	for name in files: zip.start_file(name); zip.write_file(files[name]); zip.close_file()
	zip.close()
	if defect in ["empty-message", "message-tail"]:
		var root: String = output.path_join(defect)
		for name in files:
			DirAccess.make_dir_recursive_absolute(root.path_join(name).get_base_dir())
			var stream = FileAccess.open(root.path_join(name), FileAccess.WRITE); stream.store_buffer(files[name]); stream.close()
	return path

func _synthetic(base: Dictionary, schema) -> void:
	check(Schema.digest(PackedByteArray()) == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "standard SHA256 of empty source file")
	var scripts = _zero(24); scripts.encode_u16(8, 0xeeee); scripts.encode_u16(16, 0xffff); scripts.encode_u16(18, 65000)
	var data: Array = [_zero(0), PackedByteArray([3,2,1]), _zero(0), _zero(900)]
	var sss: Array = [_zero(32), _zero(16), _zero(28), _offsets([0,3,3,6]), scripts]
	var original: Dictionary = {"data": _mkf(data), "sss": _mkf(sss), "words": _zero(20), "messages": "abcdef".to_utf8_buffer()}
	var valid = Sources.new(); var descriptor: Dictionary = _descriptor(original)
	check(valid.load_source(descriptor, original, schema), "opaque unknown opcode and out-of-range unexecuted message reference admitted")
	var before: PackedByteArray = valid.copy_bytes("sss")
	var candidate: Dictionary = original.duplicate(true); candidate.data = PackedByteArray([0])
	check(not valid.load_source(_descriptor(candidate), candidate, schema) and valid.copy_bytes("sss") == before, "failed source replacement preserves previous immutable snapshot")
	for defect in ["empty-message", "message-tail", "full-u16", "bad-data", "bad-objects", "bad-scripts", "bad-words", "offset-first", "offset-backward", "offset-end", "chunk-budget", "message-first", "message-range", "message-backward", "fingerprint", "encoding", "path", "size", "hash", "cap", "orphan", "schema-hash", "missing", "extra", "rights", "file-kind"]:
		var payloads: Dictionary = original.duplicate(true); var chunks: Array = sss.duplicate(true)
		match defect:
			"empty-message": chunks[3] = _offsets([0,0]); payloads.sss = _mkf(chunks); payloads.messages = _zero(0)
			"message-tail": payloads.messages.append_array(_zero(20))
			"full-u16": chunks[4] = _zero(65536 * 8); payloads.sss = _mkf(chunks)
			"bad-data": var bad: Array = data.duplicate(true); bad[3] = _zero(898); payloads.data = _mkf(bad)
			"bad-objects": chunks[2] = _zero(13); payloads.sss = _mkf(chunks)
			"bad-scripts": chunks[4] = _zero(65537 * 8); payloads.sss = _mkf(chunks)
			"bad-words": payloads.words = _zero(21)
			"offset-first": payloads.data.encode_u32(0, 0)
			"offset-backward": payloads.data.encode_u32(4, 0)
			"offset-end": payloads.data.append(1)
			"chunk-budget": payloads.data = _zero(17000); payloads.data.encode_u32(0, 4098 * 4)
			"message-first": chunks[3] = _offsets([1,6]); payloads.sss = _mkf(chunks)
			"message-range": chunks[3] = _offsets([0,7]); payloads.sss = _mkf(chunks)
			"message-backward": chunks[3] = _offsets([0,6,3]); payloads.sss = _mkf(chunks)
		var component: Dictionary = _descriptor(payloads)
		match defect:
			"fingerprint": component.fingerprint = "0".repeat(64)
			"encoding": component.text_encoding = "auto"
			"path": component.files.data.path = "content/source.bin"
			"size": component.files.data.size_bytes += 1
			"hash": payloads.data[0] ^= 1
		var path: String = _write_package(base, component, payloads, defect)
		var package = Package.new(); var expected: bool = defect in ["empty-message", "message-tail", "full-u16"]
		check(package.load_package(path) == expected, "package source admission " + defect + ": " + package.error)
		if expected:
			if package.pal98_sources == null: continue
			check(package.pal98_sources.copy_bytes("messages") == payloads.messages, "complete message bytes " + defect)
			if defect != "full-u16":
				var directory = Package.new(); check(directory.load_package(output.path_join(defect)), "directory source admission " + defect)
				check(directory.content_lock == package.content_lock, "ZIP/directory content lock " + defect)
		else: check(package.pal98_sources == null, "rejected package exposes no source " + defect)
	# Removing this optional component preserves the ordinary package format.
	var clean: Dictionary = base.duplicate(true)
	for name in clean.keys():
		if name.begins_with("content/pal98-sources/"): clean.erase(name)
	var world: Dictionary = JSON.parse_string(clean["content/world.json"].get_string_from_utf8())
	var manifest: Dictionary = JSON.parse_string(clean["manifest.json"].get_string_from_utf8())
	world.extensions.erase(Sources.KEY); manifest.required_capabilities.erase(Sources.CAPABILITY)
	manifest.extensions[HASH_KEY].erase(Sources.SCHEMA)
	if manifest.extensions[HASH_KEY].is_empty(): manifest.extensions.erase(HASH_KEY)
	clean["content/world.json"] = JSON.stringify(world).to_utf8_buffer()
	manifest.files = manifest.files.filter(func(row): return clean.has(row.path))
	for row in manifest.files: row.sha256 = Schema.digest(clean[row.path]); row.size_bytes = clean[row.path].size()
	clean["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var path: String = output.path_join("without-source.zip"); var zip = ZIPPacker.new(); zip.open(path)
	for name in clean: zip.start_file(name); zip.write_file(clean[name]); zip.close_file()
	zip.close(); var old = Package.new()
	check(old.load_package(path) and old.pal98_sources == null, "ordinary package without source keeps previous behavior")

func _finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "reference": reference,
		"original_gameplay": false, "human_acceptance": false}, "\t")); file.close()
	print("PAL98 source admission: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
