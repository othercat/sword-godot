# SPDX-License-Identifier: MIT
extends SceneTree
const Package = preload("res://src/native_package.gd")
const Graphics = preload("res://src/native_pal98_graphics.gd")
const Schema = preload("res://src/native_schema.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
const Session = preload("res://src/native_session.gd")
const HASH_KEY = "pal.native.component-contracts"
var checks: Array = []
var cases: Array = []
var failed: int = 0
var output: String

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2: quit(2); return
	output = args[1]
	if DirAccess.dir_exists_absolute(output) or FileAccess.file_exists(output): quit(2); return
	DirAccess.make_dir_recursive_absolute(output)
	var path: String = args[0]
	for package_path in [path, path.trim_suffix(".zip")]:
		var package = Package.new()
		check(package.load_package(package_path), "ordinary graphics transport: " + package_path.get_file())
		if not package.error.is_empty(): push_error(package.error); _finish(); return
		check(package.pal98_graphics != null and package.pal98_sources != null, "both immutable resource domains are available")
		var graphics = package.pal98_graphics
		var component: Dictionary = graphics.metadata()
		check(package.pal98_sources.metadata().provenance.source_revision == "sha256:" + component.source_fingerprint, "graphics retain original table origin after author edits")
		for role in Graphics.FILES:
			var bytes: PackedByteArray = graphics.copy_bytes(role)
			check(bytes.size() == component.files[role].size_bytes and Schema.digest(bytes) == component.files[role].sha256, "compiler/Native bytes agree: " + role)
			bytes[0] ^= 1
			check(Schema.digest(graphics.copy_bytes(role)) == component.files[role].sha256, "immutable graphics copy: " + role)
		component.label = "changed copy"
		check(graphics.metadata().label != component.label, "metadata is a detached copy")
		var session = Session.new()
		check(not session.activate(package, 1000) and session.state.is_empty(), "resource admission does not activate a fake original session")
	var base: Dictionary = _read_zip(path)
	for defect in ["opaque", "no-graphics", "source", "no-sources", "fingerprint", "path", "missing-role", "missing-file", "extra", "kind", "capability", "schema-hash", "rights", "length", "bad-offset", "tail", "budget"]:
		var candidate: String = _write_case(base, defect)
		var package = Package.new(); var expected: bool = defect in ["opaque", "no-graphics"]
		var accepted: bool = package.load_package(candidate)
		cases.append({"path": candidate, "expected": expected, "accepted": accepted, "error": package.error})
		check(accepted == expected, "graphics package " + defect + ": " + package.error)
		if not expected: check(package.pal98_graphics == null, "rejected package exposes no graphics: " + defect)
		if defect == "no-graphics": check(package.pal98_graphics == null and package.pal98_sources != null, "old four-table package remains supported")
		if defect == "opaque" and accepted:
			var snapshot = package.pal98_graphics; var before: PackedByteArray = snapshot.copy_bytes("MAP.MKF")
			var broken: Dictionary = {}; for role in Graphics.FILES: broken[role] = snapshot.copy_bytes(role)
			broken["MAP.MKF"][0] ^= 1
			check(not snapshot.load_source(package.world, broken, package.schema) and snapshot.copy_bytes("MAP.MKF") == before, "failed snapshot replacement keeps previous bytes")
	_finish()

func _read_zip(path: String) -> Dictionary:
	var zip = ZIPReader.new(); zip.open(path); var files: Dictionary = {}
	for name in zip.get_files(): files[name] = zip.read_file(name)
	zip.close(); return files

func _write_case(base: Dictionary, defect: String) -> String:
	var files: Dictionary = base.duplicate(true)
	for name in files.keys():
		if name.begins_with("content/pal98-graphics/"): files.erase(name)
	var world: Dictionary = JSON.parse_string(files["content/world.json"].get_string_from_utf8())
	var manifest: Dictionary = JSON.parse_string(files["manifest.json"].get_string_from_utf8())
	var graph: Dictionary = world.extensions[Graphics.KEY]; var payloads: Dictionary = {}; var hashes: Dictionary = {}
	for role in Graphics.FILES:
		var bytes = PackedByteArray([12,0,0,0,12,0,0,0,16,0,0,0,255,7,0,1])
		if role == "MAP.MKF":
			if defect == "bad-offset": bytes.encode_u32(4, 0)
			if defect == "tail": bytes.append(7)
		payloads[role] = bytes; hashes[role] = Schema.digest(bytes)
	graph.fingerprint = Graphics.fingerprint(hashes)
	for role in Graphics.FILES:
		graph.files[role] = {"path": "content/pal98-graphics/" + graph.fingerprint + "/" + role.to_lower(), "sha256": hashes[role], "size_bytes": payloads[role].size()}
		files[graph.files[role].path] = payloads[role]
	var map_path: String = graph.files["MAP.MKF"].path
	match defect:
		"source": graph.source_fingerprint = "0".repeat(64)
		"no-sources": world.extensions.erase(Sources.KEY)
		"fingerprint": graph.fingerprint = "0".repeat(64)
		"path": graph.files["MAP.MKF"].path = graph.files["GOP.MKF"].path
		"missing-role": graph.files.erase("MAP.MKF")
		"missing-file": files.erase(map_path)
		"extra": files["content/extra.bin"] = PackedByteArray([1])
		"capability": manifest.required_capabilities.erase(Graphics.CAPABILITY)
		"schema-hash": manifest.extensions[HASH_KEY][Graphics.SCHEMA] = "0".repeat(64)
		"length": graph.files["MAP.MKF"].size_bytes += 1
		"budget": graph.files["MAP.MKF"].size_bytes = Graphics.MAX_FILE + 1
		"rights":
			world.extensions[Sources.KEY].redistributable = true; graph.redistributable = false
			manifest.extensions.erase("pal.native.distribution"); manifest.required_capabilities.erase("package.local-preview.v1")
		"no-graphics":
			world.extensions.erase(Graphics.KEY); manifest.required_capabilities.erase(Graphics.CAPABILITY); manifest.extensions[HASH_KEY].erase(Graphics.SCHEMA)
			for name in files.keys():
				if name.begins_with("content/pal98-graphics/"): files.erase(name)
	files["content/world.json"] = JSON.stringify(world).to_utf8_buffer()
	var kinds: Dictionary = {}; for row in manifest.files: kinds[row.path] = row.kind
	manifest.files = []
	for name in files:
		if name == "manifest.json": continue
		manifest.files.append({"path": name, "sha256": Schema.digest(files[name]), "size_bytes": files[name].size(), "kind": "license" if defect == "kind" and name == map_path else kinds.get(name, "content")})
	files["manifest.json"] = JSON.stringify(manifest).to_utf8_buffer()
	var path: String = output.path_join(defect + ".zip"); var zip = ZIPPacker.new(); zip.open(path)
	for name in files: zip.start_file(name); zip.write_file(files[name]); zip.close_file()
	zip.close(); return path

func _finish() -> void:
	var file = FileAccess.open(output.path_join("results.json"), FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "cases": cases, "original_gameplay": false}, "\t")); file.close()
	print("PAL98 graphics admission: ", checks.size(), " checks, ", failed, " failed")
	quit(0 if failed == 0 else 1)
