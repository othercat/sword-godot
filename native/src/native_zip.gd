# SPDX-License-Identifier: MIT
extends RefCounted
## Allowlisted standard ZIP. Preflight central AND local records before inflation.
var error: String = ""
var entries: Dictionary = {}
var _directories: Dictionary = {}
var _reader: ZIPReader
var _guard: FileAccess
const MAX_TOTAL = 285212672
const MAX_ENTRY = 16777216

static func portable(path: String) -> bool:
	if path.length() > 240 or RegEx.create_from_string("^[A-Za-z0-9_-][A-Za-z0-9_.-]*(?:/[A-Za-z0-9_-][A-Za-z0-9_.-]*)*$").search(path) == null: return false
	for part in path.split("/"):
		var stem: String = part.split(".")[0].to_upper()
		if part.ends_with(".") or stem in ["CON", "PRN", "AUX", "NUL"] or RegEx.create_from_string("^(COM|LPT)[1-9]$").search(stem) != null: return false
	return true

func open(path: String) -> bool:
	close()
	error = ""
	entries = {}
	_directories = {}
	_guard = FileAccess.open(path, FileAccess.READ)
	if _guard == null: return _fail("cannot open package")
	var length: int = _guard.get_length()
	if length < 22 or length > MAX_TOTAL: return _fail("ZIP file size limit")
	# Current emitter emits no ZIP comment, ZIP64, multi-volume or executable stub.
	_guard.seek(length - 22)
	var end = _guard.get_buffer(22)
	if end.decode_u32(0) != 0x06054b50 or end.decode_u16(4) != 0 or end.decode_u16(6) != 0 or end.decode_u16(20) != 0: return _fail("unsupported ZIP envelope")
	var count: int = end.decode_u16(10)
	var central_size: int = end.decode_u32(12)
	var central_offset: int = end.decode_u32(16)
	if count < 1 or count > 4096 or count != end.decode_u16(8) or central_offset + central_size != length - 22: return _fail("invalid ZIP directory")
	_guard.seek(central_offset)
	var total: int = 0
	var folded: Dictionary = {}
	var ranges: Array = []
	for _i in count:
		if _guard.get_position() + 46 > length - 22: return _fail("truncated ZIP directory")
		var header = _guard.get_buffer(46)
		if header.decode_u32(0) != 0x02014b50: return _fail("invalid ZIP central signature")
		var flags: int = header.decode_u16(8)
		var method: int = header.decode_u16(10)
		var size: int = header.decode_u32(24)
		var compressed: int = header.decode_u32(20)
		var name_size: int = header.decode_u16(28)
		var extra_size: int = header.decode_u16(30)
		var comment_size: int = header.decode_u16(32)
		var offset: int = header.decode_u32(42)
		if flags & ~0x80e or method not in [0, 8] or (method == 0 and flags & 6) or header.decode_u16(34) != 0 or size > MAX_ENTRY or compressed > MAX_ENTRY: return _fail("unsupported ZIP entry/size")
		if name_size < 1 or name_size > 240 or _guard.get_position() + name_size + extra_size + comment_size > length - 22: return _fail("ZIP name bounds")
		var name_bytes = _guard.get_buffer(name_size)
		var name = name_bytes.get_string_from_utf8()
		var directory: bool = name.ends_with("/")
		if name.to_utf8_buffer() != name_bytes or not portable(name.trim_suffix("/") if directory else name) or folded.has(name.to_lower()): return _fail("nonportable or duplicate ZIP path")
		if directory and size != 0: return _fail("ZIP directory/file size mismatch")
		folded[name.to_lower()] = true
		_guard.seek(_guard.get_position() + extra_size + comment_size)
		var next: int = _guard.get_position()
		if offset + 30 > central_offset: return _fail("invalid local ZIP offset")
		_guard.seek(offset)
		var local = _guard.get_buffer(30)
		if local.decode_u32(0) != 0x04034b50 or local.decode_u16(6) != flags or local.decode_u16(8) != method or local.decode_u16(26) != name_size: return _fail("central/local ZIP mismatch")
		if _guard.get_buffer(name_size) != name_bytes: return _fail("central/local name mismatch")
		var data_end: int = offset + 30 + name_size + local.decode_u16(28) + compressed
		if data_end > central_offset: return _fail("ZIP data out of bounds")
		if flags & 8 == 0 and (local.decode_u32(18) != compressed or local.decode_u32(22) != size or local.decode_u32(14) != header.decode_u32(16)): return _fail("central/local size mismatch")
		ranges.append([offset, data_end])
		if directory: _directories[name] = true
		else: entries[name] = {"size": size}
		total += size
		if total > MAX_TOTAL: return _fail("expanded ZIP limit")
		_guard.seek(next)
	if _guard.get_position() != length - 22: return _fail("unconsumed ZIP directory")
	ranges.sort_custom(func(a, b): return a[0] < b[0])
	if ranges[0][0] != 0: return _fail("ZIP prefix forbidden")
	for i in range(1, ranges.size()):
		if ranges[i][0] < ranges[i - 1][1]: return _fail("overlapping ZIP entries")
	_reader = ZIPReader.new()
	if _reader.open(path) != OK: return _fail("ZIP decoder could not open")
	var names = _reader.get_files()
	if names.size() != entries.size() + _directories.size(): return _fail("ZIP decoder directory mismatch")
	for name in names:
		if not entries.has(name) and not _directories.has(name): return _fail("ZIP decoder name mismatch")
	return true

func read(path: String) -> PackedByteArray:
	if _reader == null or not entries.has(path):
		_fail("missing ZIP entry " + path)
		return PackedByteArray()
	var bytes = _reader.read_file(path, true)
	if bytes.size() != entries[path].size:
		_fail("ZIP decoded length mismatch")
		return PackedByteArray()
	return bytes

func _fail(message: String) -> bool:
	error = message
	close()
	return false

func close() -> void:
	if _reader != null: _reader.close()
	_reader = null
	_guard = null
