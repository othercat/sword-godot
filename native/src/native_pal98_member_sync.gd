# SPDX-License-Identifier: MIT
extends RefCounted
## The real member formation/frame executor behind the member half of
## SyncMembersFromTrail (0x0041D2E4): the members walking directly behind the
## leader take their screen position from the probed trail and their sprite
## frame from the walk-phase offset scaled by the sprite's frames per
## direction. This is the owner `bind_member_sync` requires; without it the
## movement owner refuses the whole sync instead of assuming every probe
## rejected.
##
## Named evidence boundaries:
## - Frame selection: DATA3 field64 picks the per-direction frame count — a
##   value of 4 takes `direction*4 + frame_offset`, anything else takes
##   `direction*3 + frame_offset` (the `0x411594` decode in
##   ORIGINAL_ENTRY_CLOSURE). The per-slot count is read from the slot's own
##   sprite source through the bound provider; this owner never guesses one.
## - Member positions: the trail candidate is probed with the same two-level
##   collision probe the party step uses. A rejected probe falls back to the
##   generated formation tables `G041C=[-16,-16,16,16]`/`G0434=[8,-8,-8,8]`
##   (decoded from `0x00418350..0x00418448`, subtracted from the running
##   member screen position in the reviewed walk loop); applying them here as
##   the rejected-probe fallback is a named Native adaptation.
## - The member trail stride `slot+1` (with the reviewed follower stride
##   `follower+2`) is the Native reading that keeps the entries distinct; the
##   0x0041D2E4 byte body is not decoded yet and this owner says so instead
##   of claiming the full original procedure.
const FORMATION_STEP_X = [-16, -16, 16, 16]
const FORMATION_STEP_Y = [8, -8, -8, 8]

var error: String = ""
var _probe = null
var _frame_counts: Callable = Callable()

func _failure(message: String) -> Dictionary:
	error = "pal98-member-sync: " + message
	return {"error": error}

func _u2_as_i2(raw: int) -> int:
	return ((raw + 32768) & 0xFFFF) - 32768

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _word(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 65535

## The probe owner needs the combined two-level `probe(x, y)` the party step
## already consumes (the collision probe owner).
func bind_probe(owner) -> bool:
	if owner == null or not owner.has_method("probe"):
		error = "pal98-member-sync: the collision probe owner is required"
		return false
	_probe = owner; error = ""; return true

## Reads the per-direction frame count for one party slot from that slot's
## own sprite source. `Callable(slot: int) -> int`; only 3 or 4 are the
## decoded field64 outcomes, anything else is refused by name at answer time.
func bind_frame_counts(provider: Callable) -> void:
	_frame_counts = provider

func _trail_issue(trail) -> String:
	if not trail is Array or trail.size() != 5: return "requires the five-entry party trail"
	for entry in trail:
		if not entry is Dictionary: return "party trail entries must be dictionaries"
		for key in ["x", "y", "direction_word"]:
			if not _word(entry.get(key)): return "party trail requires explicit WORD " + key
	return ""

## Answers one `sync_party_formation_and_frames` request. Only the active
## slots' current_frame and the member slots' x/y may change; the movement
## owner verifies exactly that shape and refuses anything wider.
func answer(request: Dictionary) -> Dictionary:
	error = ""
	if not request is Dictionary or request.get("kind") != "sync_party_formation_and_frames":
		return _failure("owner answers sync_party_formation_and_frames only")
	if not request.get("state") is Dictionary or not request.state.get("globals") is Dictionary:
		return _failure("requires the pending state and globals")
	var state: Dictionary = request.state
	var globals: Dictionary = state.globals
	for key in ["viewport_x", "viewport_y", "direction_word",
			"leader_frame_offset_word", "party_frame_offset_word", "member_last", "follower_count"]:
		if not _word(globals.get(key)): return _failure("requires explicit WORD " + key)
	var member_last: int = globals.member_last
	var follower_count: int = globals.follower_count
	if member_last < 0 or member_last > 2 or follower_count < 0 or follower_count > 2:
		return _failure("member counters outside the 0..2 party bounds")
	var trail = state.get("party_trail", [])
	var issue := _trail_issue(trail)
	if not issue.is_empty(): return _failure("trail " + issue)
	var records = state.get("party_records", [])
	if not records is Array or records.size() < member_last + follower_count + 1:
		return _failure("active party records missing")
	if _probe == null:
		return _failure("collision probe owner not bound")
	if not _frame_counts.is_valid():
		return _failure("frames-per-direction provider not bound")
	for slot in range(member_last + follower_count + 1):
		if not records[slot] is Dictionary: return _failure("party record at slot %d is not a record" % slot)
		for key in ["x", "y", "current_frame", "role_id"]:
			if not _i2(records[slot].get(key)): return _failure("party record requires I2 " + key)
	var updated: Array = []
	for row in records: updated.append(row.duplicate(true))
	var viewport_x: int = _u2_as_i2(globals.viewport_x)
	var viewport_y: int = _u2_as_i2(globals.viewport_y)
	for slot in range(member_last + follower_count + 1):
		var direction: int
		var offset: int
		if slot == 0:
			direction = globals.direction_word; offset = globals.leader_frame_offset_word
		elif slot <= member_last:
			direction = trail[slot + 1].direction_word; offset = globals.party_frame_offset_word
		else:
			direction = trail[slot - member_last + 2].direction_word; offset = globals.party_frame_offset_word
		if direction < 0 or direction > 3: return _failure("direction word outside 0..3 at slot %d" % slot)
		var counts: int = _frame_counts.call(slot)
		if counts != 3 and counts != 4:
			return _failure("frames-per-direction unknown at slot %d" % slot)
		var frame: int = direction * counts + offset
		if not _i2(frame): return _failure("frame arithmetic leaves I2 at slot %d" % slot)
		updated[slot].current_frame = frame
		if slot > 0 and slot <= member_last:
			var entry: Dictionary = trail[slot + 1]
			var candidate_x: int = _u2_as_i2(entry.x - viewport_x)
			var candidate_y: int = _u2_as_i2(entry.y - viewport_y)
			var probed: Dictionary = _probe.probe(candidate_x, candidate_y)
			if probed.has("error"): return _failure(str(probed.error))
			if probed.get("accepted", false):
				updated[slot].x = candidate_x; updated[slot].y = candidate_y
			else:
				var step_x: int = updated[slot].x - FORMATION_STEP_X[direction]
				var step_y: int = updated[slot].y - FORMATION_STEP_Y[direction]
				if not _i2(step_x) or not _i2(step_y):
					return _failure("formation fallback leaves I2 at slot %d" % slot)
				updated[slot].x = step_x; updated[slot].y = step_y
	return {"completed": true, "party_records": updated}
