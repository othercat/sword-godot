# SPDX-License-Identifier: MIT
extends RefCounted
## Recovered 0x411580..0x41196E: trail[1] positions, trail[2] directions,
## world-space collision, and the current request's field*6+role backing.
const FORMATION_STEP_X = [-16, -16, 16, 16]
const FORMATION_STEP_Y = [8, -8, -8, 8]
var error: String = ""
var _probe = null

func _failure(message: String) -> Dictionary:
	error = "pal98-member-sync: " + message
	return {"error": error}

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _word(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 65535

static func _signed(value: int) -> int:
	return ((value + 32768) & 65535) - 32768

func bind_probe(owner) -> bool:
	if owner == null or not owner.has_method("probe"):
		error = "pal98-member-sync: the collision probe owner is required"; return false
	_probe = owner; error = ""; return true

func answer(request: Dictionary) -> Dictionary:
	error = ""
	var standing: bool = request.get("kind") == "rebuild_no_move_frames"
	if not standing and request.get("kind") != "sync_party_formation_and_frames":
		return _failure("unsupported member request")
	var state = request.get("state")
	if not state is Dictionary or not state.get("globals") is Dictionary:
		return _failure("requires pending state and globals")
	var g: Dictionary = state.globals
	for key in ["viewport_x", "viewport_y", "direction_word", "walk_phase_word",
			"leader_frame_offset_word", "party_frame_offset_word", "member_last", "follower_count"]:
		if not _word(g.get(key)): return _failure("requires explicit WORD " + key)
	var last: int = g.member_last; var followers: int = g.follower_count
	if last < 0 or last > 2 or followers < 0 or followers > 2:
		return _failure("member counters outside 0..2")
	var trail = state.get("party_trail")
	if not trail is Array or trail.size() != 5: return _failure("requires five trail entries")
	for row in trail:
		if not row is Dictionary: return _failure("invalid trail record")
		for key in ["x", "y", "direction_word"]:
			if not _word(row.get(key)): return _failure("trail requires WORD " + key)
		if row.direction_word < 0 or row.direction_word > 3: return _failure("trail direction outside 0..3")
	if g.direction_word < 0 or g.direction_word > 3: return _failure("team direction outside 0..3")
	var records = state.get("party_records")
	if not records is Array or records.size() <= last + followers:
		return _failure("active party records missing")
	var words = state.get("equipment", {}).get("role_words")
	if not words is Array or words.size() != 450: return _failure("requires current 450 role WORDs")
	for word in words:
		if typeof(word) != TYPE_INT or word < 0 or word > 65535: return _failure("invalid role U2")
	var identities: Array = []
	for slot in range(last + followers + 1):
		var row = records[slot]
		if not row is Dictionary: return _failure("invalid active party record")
		for key in ["x", "y", "current_frame", "role_id"]:
			if not _i2(row.get(key)): return _failure("party requires I2 " + key)
		if row.role_id < 0 or (slot <= last and (row.role_id >= 6 or row.role_id in identities)):
			return _failure("invalid or duplicate ordinary role identity")
		if slot <= last: identities.append(row.role_id)
	if not standing and _probe == null: return _failure("collision probe owner not bound")
	var updated: Array = records.duplicate(true)
	var vx: int = _signed(g.viewport_x); var vy: int = _signed(g.viewport_y)
	for slot in range(last + followers + 1):
		var follower: bool = slot > last
		var direction: int = g.direction_word if slot == 0 else trail[slot - last + 2 if follower else 2].direction_word
		var count := 3
		if not follower:
			var source_count: int = _signed(words[64 * 6 + records[slot].role_id])
			count = (source_count if source_count != 0 else 3) if standing else (4 if source_count == 4 else 3)
		var offset: int = 0 if standing else _signed(g.leader_frame_offset_word if slot == 0 else g.party_frame_offset_word)
		if not standing and not follower and count == 4: offset = _signed(g.walk_phase_word)
		var frame: int = direction * count
		if not _i2(frame) or not _i2(frame + offset): return _failure("frame arithmetic leaves I2")
		updated[slot].current_frame = frame + offset
		if standing or slot == 0 or follower: continue
		var bx: int = _signed(trail[1].x) - vx; var by: int = _signed(trail[1].y) - vy
		if not _i2(bx) or not _i2(by): return _failure("trail relative position leaves I2")
		var cx: int = bx; var cy: int = by; var d: int = trail[1].direction_word
		if slot == 1:
			cx -= FORMATION_STEP_X[d]; cy -= FORMATION_STEP_Y[d]
		else:
			cy += 8; cx += 16 if (d & 1) == 0 else -16
		if not _i2(cx) or not _i2(cy) or not _i2(vx + cx) or not _i2(vy + cy):
			return _failure("formation world arithmetic leaves I2")
		var probed: Dictionary = _probe.probe(vx + cx, vy + cy)
		if probed.has("error"): return _failure(str(probed.error))
		if typeof(probed.get("accepted")) != TYPE_BOOL: return _failure("probe requires accepted boolean")
		updated[slot].x = cx if probed.accepted else bx
		updated[slot].y = cy if probed.accepted else by
	return {"completed": true, "party_records": updated}
