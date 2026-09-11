# SPDX-License-Identifier: MIT
extends RefCounted
## Immutable source tables, distinct from an interpreter or authoritative session state.
const KEY = "pal.native.pal98-sources"
const SCHEMA = "pal.native.pal98-sources.v1"
const CAPABILITY = "sources.pal98-win95.v1"
const FILES = {"data": "data.mkf", "sss": "sss.mkf", "words": "word.dat", "messages": "m.msg"}
const MAX_FILE = 8388608
const Schema = preload("res://src/native_schema.gd")
var error: String = ""
var _metadata: Dictionary = {}
var _bytes: Dictionary = {}
var _tables: Dictionary = {}
var _counts: Dictionary = {}

static func used(content: Dictionary) -> bool:
	return content.get("extensions", {}).has(KEY)

static func fingerprint(encoding: String, hashes: Dictionary) -> String:
	var text: String = "pal98-win95-sources-v1\n" + encoding
	for role in FILES: text += "\n" + role + ":" + hashes[role]
	return Schema.digest(text.to_utf8_buffer())

static func validate_content(content: Dictionary, schema) -> String:
	if not used(content): return ""
	var issue: String = schema.validate(SCHEMA, content.extensions[KEY])
	if not issue.is_empty(): return issue
	var component: Dictionary = content.extensions[KEY]
	if component.label.strip_edges().is_empty() or component.license.strip_edges().is_empty(): return "pal98-sources: blank label/license"
	var hashes: Dictionary = {}
	for role in FILES: hashes[role] = component.files[role].sha256
	if component.fingerprint != fingerprint(component.text_encoding, hashes): return "pal98-sources: source fingerprint mismatch"
	for role in FILES:
		if component.files[role].path != "content/pal98-sources/" + component.fingerprint + "/" + FILES[role]: return "pal98-sources: source path/role mismatch"
	return ""

func load_source(component: Dictionary, payloads: Dictionary, schema) -> bool:
	error = validate_content({"extensions": {KEY: component}}, schema)
	if not error.is_empty(): return false
	if payloads.size() != FILES.size(): return _fail("missing or extra source role")
	for role in FILES:
		if not payloads.get(role) is PackedByteArray: return _fail("missing source bytes")
		var bytes: PackedByteArray = payloads[role]; var row: Dictionary = component.files[role]
		if bytes.size() > MAX_FILE or bytes.size() != row.size_bytes or Schema.digest(bytes) != row.sha256: return _fail("source hash/length mismatch: " + role)
	var data: Array = _chunks(payloads.data, "DATA")
	if not error.is_empty(): return false
	var sss: Array = _chunks(payloads.sss, "SSS")
	if not error.is_empty(): return false
	if data.size() < 4 or data[3].size() != 900: return _fail("DATA3 must contain six 75-WORD roles")
	if sss.size() < 5: return _fail("SSS tables missing")
	if sss[2].size() < 14 or sss[2].size() > 65536 * 14 or sss[2].size() % 14 != 0: return _fail("SSS2 object alignment/count")
	if sss[4].size() < 8 or sss[4].size() > 65536 * 8 or sss[4].size() % 8 != 0: return _fail("SSS4 script alignment/count")
	if payloads.words.size() < 10 or payloads.words.size() > 655360 or payloads.words.size() % 10 != 0: return _fail("WORD alignment/count")
	var offsets: PackedByteArray = sss[3]
	if offsets.size() < 4 or offsets.size() % 4 != 0: return _fail("SSS3 message offsets")
	var last: int = 0
	for i in range(0, offsets.size(), 4):
		var offset: int = offsets.decode_u32(i)
		if (i == 0 and offset != 0) or offset < last or offset > payloads.messages.size(): return _fail("M.MSG offset bounds")
		last = offset
	var counts: Dictionary = {"data_chunks": data.size(), "sss_chunks": sss.size(), "roles": 6,
		"objects": int(sss[2].size() / 14), "scripts": int(sss[4].size() / 8), "words": int(payloads.words.size() / 10),
		"messages": int(offsets.size() / 4) - 1, "message_tail_bytes": payloads.messages.size() - last}
	var snapshot: Dictionary = {}
	for role in FILES: snapshot[role] = payloads[role].duplicate()
	_bytes = snapshot; _metadata = component.duplicate(true); _tables = {"data": data, "sss": sss}; _counts = counts
	return true

func metadata() -> Dictionary:
	return _metadata.duplicate(true)

func counts() -> Dictionary:
	return _counts.duplicate(true)

func copy_bytes(role: String) -> PackedByteArray:
	return _bytes.get(role, PackedByteArray()).duplicate()

func copy_chunk(role: String, index: int) -> PackedByteArray:
	var chunks: Array = _tables.get(role, [])
	return chunks[index].duplicate() if index >= 0 and index < chunks.size() else PackedByteArray()

func _chunks(bytes: PackedByteArray, label: String) -> Array:
	if bytes.size() < 4: _fail(label + " length"); return []
	var first: int = bytes.decode_u32(0)
	if first < 8 or first > bytes.size() or first % 4 != 0 or first / 4 - 1 > 4096: _fail(label + " offset table"); return []
	var chunks: Array = []; var previous: int = first
	for i in range(4, first, 4):
		var next: int = bytes.decode_u32(i)
		if next < previous or next > bytes.size(): _fail(label + " chunk bounds"); return []
		chunks.append(bytes.slice(previous, next)); previous = next
	if previous != bytes.size(): _fail(label + " trailing bytes outside MKF"); return []
	return chunks

func _fail(message: String) -> bool:
	error = "pal98-sources: " + message
	return false
