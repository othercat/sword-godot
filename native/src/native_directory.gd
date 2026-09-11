# SPDX-License-Identifier: MIT
extends RefCounted
## A local directory carries the exact same manifest and payload bytes as a ZIP.
const Zip = preload("res://src/native_zip.gd")
var error: String = ""
var entries: Dictionary = {}
var _root: String = ""

func open(path: String) -> bool:
	close()
	error = ""
	entries = {}
	var local_path = path.replace("\\", "/")
	if local_path.get_file() == "manifest.json": local_path = local_path.get_base_dir()
	_root = local_path.trim_suffix("/")
	if not _ordinary_path(_root) or not _unlinked(_root): return _fail("package directory must be an ordinary local path without links")
	var pending: Array[String] = [""]
	var folded: Dictionary = {}
	var total: int = 0
	while not pending.is_empty():
		var relative: String = pending.pop_back()
		var directory = DirAccess.open(_root.path_join(relative))
		if directory == null: return _fail("cannot open package directory: " + relative + " (" + str(DirAccess.get_open_error()) + "). Check permissions; use a shorter local path or select the matching ZIP.")
		directory.include_hidden = true
		directory.include_navigational = false
		if directory.list_dir_begin() != OK: return _fail("cannot enumerate package directory")
		var name = directory.get_next()
		while not name.is_empty():
			var child = relative.path_join(name) if not relative.is_empty() else name
			if not Zip.portable(child) or folded.has(child.to_lower()) or folded.size() >= 4096:
				return _fail("nonportable, duplicate or excessive directory entries")
			folded[child.to_lower()] = true
			if directory.is_link(name): return _fail("package directory contains a link or reparse point")
			if directory.current_is_dir():
				pending.append(child)
			else:
				var stream = FileAccess.open(_root.path_join(child), FileAccess.READ)
				if stream == null: return _fail("cannot read package file: " + child)
				var length: int = stream.get_length()
				stream.close()
				if length > Zip.MAX_ENTRY: return _fail("directory file size limit")
				total += length
				if total > Zip.MAX_TOTAL: return _fail("directory package size limit")
				entries[child] = {"size": length}
			name = directory.get_next()
		directory.list_dir_end()
	if not entries.has("manifest.json"): return _fail("missing package manifest.json")
	return true

func read(path: String) -> PackedByteArray:
	if _root.is_empty() or not entries.has(path) or not _unlinked(_root.path_join(path)):
		_fail("missing or linked directory payload: " + path)
		return PackedByteArray()
	var stream = FileAccess.open(_root.path_join(path), FileAccess.READ)
	if stream == null:
		_fail("cannot open directory payload: " + path)
		return PackedByteArray()
	var length: int = entries[path].size
	if stream.get_length() != length:
		_fail("directory payload length changed: " + path)
		return PackedByteArray()
	var bytes = stream.get_buffer(length)
	var final_length = stream.get_length()
	stream.close()
	if bytes.size() != length or final_length != length:
		_fail("directory payload changed while reading: " + path)
		return PackedByteArray()
	return bytes

static func _ordinary_path(path: String) -> bool:
	if not path.is_absolute_path() or path.begins_with("//") or path.contains("://"): return false
	var tail = path.substr(3) if OS.get_name() == "Windows" and path.length() >= 3 and path.substr(1,2) == ":/" else path.trim_prefix("/")
	if tail.contains(":") or tail.contains("~"): return false
	for part in tail.split("/"):
		if part in ["", ".", ".."] or part.ends_with(".") or part.ends_with(" "): return false
	return true

static func _unlinked(path: String) -> bool:
	var current = path
	while not current.is_empty():
		var parent = current.get_base_dir()
		if parent == current: break
		var access = DirAccess.open(parent)
		if access == null or access.is_link(current.get_file()): return false
		current = parent
	return true

func close() -> void:
	_root = ""

func _fail(message: String) -> bool:
	error = message
	close()
	return false
