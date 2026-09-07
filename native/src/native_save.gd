# SPDX-License-Identifier: MIT
extends RefCounted
## Immutable generations. No original game path, named legacy slot or overwrite.
const Zip = preload("res://src/native_zip.gd")
const Reader = preload("res://src/native_json.gd")
const Schema = preload("res://src/native_schema.gd")
const Session = preload("res://src/native_session.gd")
var root: String
var error: String = ""
var last_path: String = ""
var envelope_extensions: Dictionary = {}
var source_origin: String = "normal"
var migrations: Array = []

func _init(directory: String = "user://saves") -> void:
	root = ProjectSettings.globalize_path(directory)

func directory(session) -> String:
	# Manifest IDs are storage-independent; hashed directory names avoid platform
	# filename restrictions without changing the saved identity or namespace.
	return root.path_join(Schema.digest((session.package.manifest.save_namespace + "\n" + session.state.profile_id).to_utf8_buffer()))

func save(session, fault_before_publish: bool = false) -> bool:
	error = ""
	if not session.can_save(): return _fail("当前节点尚未到达可保存点。")
	var state: Dictionary = session.snapshot()
	var issue: String = session.validate_saved(state)
	if not issue.is_empty(): return _fail(issue)
	var state_bytes: PackedByteArray = JSON.stringify(state, "", true, true).to_utf8_buffer()
	var transaction: String = Session.unique("transaction")
	var envelope: Dictionary = {"schema": "pal.native.save.v1", "save_id": Session.unique("save"), "save_revision": 1, "runtime_id": state.runtime_id, "package_id": state.package_id, "save_namespace": session.package.manifest.save_namespace, "profile_id": state.profile_id, "run_id": state.run_id, "content_lock": state.content_lock, "ruleset_hash": state.ruleset_hash, "commit_id": transaction, "payload_sha256": Schema.digest(state_bytes), "state_path": "state/current.json", "origin": "normal", "migration": [], "extensions": envelope_extensions.duplicate(true)}
	envelope.extensions["pal.native.save.preview"] = {"created_utc": Time.get_datetime_string_from_system(true), "eligibility": "practice"}
	envelope.origin = source_origin
	envelope.migration = migrations.duplicate(true)
	issue = session.package.schema.validate("pal.native.save.v1", envelope)
	if not issue.is_empty(): return _fail(issue)
	var folder: String = directory(session)
	if DirAccess.make_dir_recursive_absolute(folder) != OK: return _fail("无法建立独立存档目录。")
	var final_path: String = folder.path_join(transaction + ".palsave")
	var pending: String = final_path + ".partial"
	if FileAccess.file_exists(pending) or FileAccess.file_exists(final_path): return _fail("存档名称冲突；原文件保留。")
	var packer = ZIPPacker.new()
	if packer.open(pending) != OK: return _fail("无法写入待完成存档。")
	var failed: bool = false
	for item in [["save.json", JSON.stringify(envelope, "", true, true).to_utf8_buffer()], ["state/current.json", state_bytes]]:
		if packer.start_file(item[0]) != OK or packer.write_file(item[1]) != OK or packer.close_file() != OK:
			failed = true
			break
	if packer.close() != OK or failed: return _fail("存档写入失败；原有存档保留。")
	# Verify the complete unpublished bytes through the same loader. No latest
	# pointer is written yet; discovery only considers final *.palsave generations.
	var decoded: Dictionary = read(session, pending)
	if decoded.is_empty(): return false
	if fault_before_publish: return _fail("injected pre-publication interruption")
	if FileAccess.file_exists(final_path) or DirAccess.rename_absolute(pending, final_path) != OK: return _fail("存档发布失败；原有存档保留。")
	last_path = final_path
	return true

func read(session, path: String) -> Dictionary:
	error = ""
	var zip = Zip.new()
	if not zip.open(path):
		_fail(zip.error)
		return {}
	if zip.entries.size() != 2 or not zip.entries.has("save.json") or not zip.entries.has("state/current.json"):
		zip.close()
		_fail("存档文件集合不完整。")
		return {}
	var reader = Reader.new()
	var envelope = reader.decode(zip.read("save.json"))
	if not reader.error.is_empty() or not envelope is Dictionary:
		zip.close()
		_fail("存档说明损坏。")
		return {}
	var issue: String = session.package.schema.validate("pal.native.save.v1", envelope)
	if not issue.is_empty() or envelope.get("save_namespace") != session.package.manifest.save_namespace or envelope.get("state_path") != "state/current.json":
		zip.close()
		_fail("存档版本或命名空间不匹配。 " + issue)
		return {}
	var bytes = zip.read("state/current.json")
	zip.close()
	if Schema.digest(bytes) != envelope.payload_sha256:
		_fail("存档状态哈希不匹配。")
		return {}
	var state = reader.decode(bytes)
	if not reader.error.is_empty() or not state is Dictionary:
		_fail("存档状态损坏。")
		return {}
	issue = session.validate_saved(state)
	if not issue.is_empty():
		_fail(issue)
		return {}
	for key in ["runtime_id", "package_id", "profile_id", "run_id", "content_lock", "ruleset_hash"]:
		if envelope[key] != state[key]:
			_fail("存档成套身份不匹配。")
			return {}
	return {"envelope": envelope, "state": state}

func load_into(session, path: String, now_usec: int = -1) -> bool:
	var decoded: Dictionary = read(session, path)
	if decoded.is_empty(): return false
	if not session.restore(decoded.state, now_usec): return _fail(session.error)
	envelope_extensions = decoded.envelope.extensions.duplicate(true)
	source_origin = decoded.envelope.origin
	migrations = decoded.envelope.migration.duplicate(true)
	last_path = path
	return true

func generations(session) -> Array:
	var out: Array = []
	var folder: String = directory(session)
	if not DirAccess.dir_exists_absolute(folder): return out
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".palsave"):
			var path: String = folder.path_join(file)
			out.append({"path": path, "modified": FileAccess.get_modified_time(path)})
	out.sort_custom(func(a, b): return a.modified > b.modified if a.modified != b.modified else a.path > b.path)
	return out

func _fail(message: String) -> bool:
	error = message
	return false
