# SPDX-License-Identifier: MIT
extends RefCounted
## Immutable opaque graphics containers. No frame decoding or gameplay admission.
const KEY = "pal.native.pal98-graphics"
const SCHEMA = "pal.native.pal98-graphics.v1"
const CAPABILITY = "resources.pal98-graphics.v1"
const FILES = ["MAP.MKF", "GOP.MKF", "MGO.MKF", "PAT.MKF"]
const MAX_FILE = 16777216
const Schema = preload("res://src/native_schema.gd")
const Sources = preload("res://src/native_pal98_sources.gd")
var error: String = ""
var _metadata: Dictionary = {}
var _bytes: Dictionary = {}

static func used(content: Dictionary) -> bool:
	return content.get("extensions", {}).has(KEY)

static func fingerprint(hashes: Dictionary) -> String:
	var text: String = "pal98-original-graphics-v1"
	for role in FILES: text += "\n" + role + ":" + hashes[role]
	return Schema.digest(text.to_utf8_buffer())

static func validate_content(content: Dictionary, schema) -> String:
	if not used(content): return ""
	var component = content.extensions[KEY]
	var issue: String = schema.validate(SCHEMA, component)
	if not issue.is_empty(): return issue
	var source: Dictionary = content.extensions.get(Sources.KEY, {})
	if source.get("provenance", {}).get("source_revision") != "sha256:" + component.source_fingerprint: return "pal98-graphics: source origin mismatch"
	if component.label.strip_edges().is_empty() or component.license.strip_edges().is_empty(): return "pal98-graphics: blank label/license"
	var hashes: Dictionary = {}
	for role in FILES: hashes[role] = component.files[role].sha256
	if component.fingerprint != fingerprint(hashes): return "pal98-graphics: fingerprint mismatch"
	for role in FILES:
		if component.files[role].path != "content/pal98-graphics/" + component.fingerprint + "/" + role.to_lower(): return "pal98-graphics: path/role mismatch"
	return ""

func load_source(content: Dictionary, payloads: Dictionary, schema) -> bool:
	error = validate_content(content, schema)
	if not error.is_empty(): return false
	if not used(content) or payloads.size() != FILES.size(): return _fail("missing component or resource role")
	var component: Dictionary = content.extensions[KEY]
	for role in FILES:
		if not payloads.get(role) is PackedByteArray: return _fail("missing resource bytes")
		var bytes: PackedByteArray = payloads[role]; var row: Dictionary = component.files[role]
		if bytes.size() < 8 or bytes.size() > MAX_FILE or bytes.size() != row.size_bytes or Schema.digest(bytes) != row.sha256: return _fail("hash/length mismatch: " + role)
		var first: int = bytes.decode_u32(0)
		if first < 8 or first > bytes.size() or first % 4 != 0 or first / 4 - 1 > 4096: return _fail("MKF offset table: " + role)
		var previous: int = first
		for at in range(4, first, 4):
			var next: int = bytes.decode_u32(at)
			if next < previous or next > bytes.size(): return _fail("MKF chunk bounds: " + role)
			previous = next
		if previous != bytes.size(): return _fail("MKF trailing bytes: " + role)
	var snapshot: Dictionary = {}
	for role in FILES: snapshot[role] = payloads[role].duplicate()
	_metadata = component.duplicate(true); _bytes = snapshot
	return true

func metadata() -> Dictionary:
	return _metadata.duplicate(true)

func copy_bytes(role: String) -> PackedByteArray:
	return _bytes.get(role, PackedByteArray()).duplicate()

func _fail(message: String) -> bool:
	error = "pal98-graphics: " + message
	return false
