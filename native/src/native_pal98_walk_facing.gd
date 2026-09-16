# SPDX-License-Identifier: MIT
extends RefCounted
## The real party-walk facing owner, recovered from PALOLD.dll export ordinal 44
## (`extf`, stdcall, three arguments): the body at RVA 0x37E0 combines the
## argument signs into an index (third argument: <0→+0, ==0→+3, >0→+6; second
## argument: <0→+0, ==0→+1, >0→+2), and index 4 — both deltas zero, the party
## already stands at the target — writes nothing. Every other index reads one
## byte of the direction table at RVA 0x1000E890 and stores it as the direction
## word. Together with the decoded walk loop (2:1 steps on the isometric
## lattice) this facing rule converges on every lattice-reachable target.
const DIRECTION_TABLE = [1, 2, 2, 1, 0, 3, 0, 0, 3]
const EXTF_BODY_SHA256 = "16be3762663cec8c24ad757b6eafdb5796b6de4cf172f039ca271faecc4e702c"
const DIRECTION_TABLE_SHA256 = "5418a11928803f449f1bb4b4ca3fe8865c1ebf6c3c30a06d1b81ae9d1d26fdb8"
## This owner implements facing and the position/phase portion of post-move.
## Trail rotation is owned here. Formation probes and frame selection require
## a separate member owner; frame processing and rendering also stay explicit.

var error: String = ""
## Every request kind this owner has answered, in order, for host evidence.
var requests: Array = []
## The dependent kinds executed by this owner, in order, for host evidence.
var executed: Array = []
## Optional owner for forwarded kinds this movement owner does not execute
## (the display family); without it such kinds are refused by name.
var _fallback = null
var _member_sync = null

## Internal dependency, separate from the display fallback. It must execute
## formation/probes and frame selection and return completed + party_records.
func bind_member_sync(owner) -> void:
	_member_sync = owner

func bind_fallback(owner) -> void:
	_fallback = owner

func _failure(message: String) -> Dictionary:
	error = "pal98-walk-facing: " + message
	return {"error": error}

func _u2(value) -> int:
	if value is bool or not value is int or value < 0 or value > 65535: return 0
	return value

## The original stores the wrapped sum into a 16-bit field and reads it back
## as a signed Integer: U2 storage with an I2 read-back.
func _u2_as_i2(raw: int) -> int:
	return ((raw + 32768) & 0xFFFF) - 32768

static func _word(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 65535

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

func _trail_issue(trail) -> String:
	if not trail is Array or trail.size() != 5: return "requires the five-entry party trail"
	for entry in trail:
		if not entry is Dictionary: return "party trail entries must be dictionaries"
		for key in ["x", "y", "direction_word"]:
			if not _word(entry.get(key)): return "party trail requires explicit WORD " + key
	return ""

func _records_issue(records, member_last: int, follower_count: int) -> String:
	if not records is Array or records.size() <= member_last + follower_count:
		return "active party records missing"
	for slot in range(member_last + follower_count + 1):
		var row = records[slot]
		if not row is Dictionary: return "invalid party record at slot " + str(slot)
		for key in ["x", "y", "current_frame", "role_id"]:
			if not _i2(row.get(key)): return "party record requires explicit I2 " + key + " at slot " + str(slot)
		# Ordinary RoleId selects the six-role table; followers carry an MGO id.
		if row.role_id < 0 or (slot <= member_last and row.role_id >= 6):
			return "party role identity outside its source domain at slot " + str(slot)
	return ""

## The decoded extf core: returns {"direction": word} for a facing change, or
## {"unchanged": true} when both deltas are zero (the original writes nothing).
func face(delta_x: int, delta_y: int) -> Dictionary:
	if delta_x < -32768 or delta_x > 32767 or delta_y < -32768 or delta_y > 32767:
		return _failure("extf requires signed delta words")
	if delta_x == 0 and delta_y == 0:
		return {"unchanged": true}
	var index: int = 0
	if delta_y == 0: index = 3
	elif delta_y > 0: index = 6
	if delta_x == 0: index += 1
	elif delta_x > 0: index += 2
	return {"direction": DIRECTION_TABLE[index]}

## face_party_toward applies extf. Post-move updates position/phase, then
## requires trail rotation and member sync from an explicit execution owner.
func answer(request: Dictionary) -> Dictionary:
	if not request is Dictionary or not request.get("kind") is String:
		return _failure("owner request shape")
	requests.append(request.kind)
	if not request.get("state") is Dictionary or not request.state.get("globals") is Dictionary:
		return _failure("movement request requires the pending state and globals")
	var state: Dictionary = request.state
	var moved: Dictionary = state.duplicate(true)
	var globals: Dictionary = moved.get("globals", {})
	match request.kind:
		"face_party_toward":
			var delta_x = request.get("delta_x"); var delta_y = request.get("delta_y")
			if delta_x is bool or delta_y is bool or not delta_x is int or not delta_y is int:
				return _failure("face_party_toward requires signed delta words")
			var faced: Dictionary = face(delta_x, delta_y)
			if faced.has("error"): return _failure(str(faced.error))
			if faced.has("direction"):
				globals.direction_word = faced.direction
				moved.globals = globals
			return {"completed": true, "state": moved}
		"post_move_update":
			# The recovered PostMoveUpdate body: world = U2(party-in-viewport +
			# viewport) per axis, then movement detection against the previous
			# world words drives the WalkPhase/frame-offset pair. Bound trail
			# and member owners must execute the remaining original effects.
			var world_x = globals.get("viewport_x"); var party_x = globals.get("party_x")
			var world_y = globals.get("viewport_y"); var party_y = globals.get("party_y")
			if not world_x is int or not party_x is int or not world_y is int or not party_y is int:
				return _failure("post_move_update requires the explicit viewport and party words")
			var new_x: int = _u2_as_i2(world_x + party_x)
			var new_y: int = _u2_as_i2(world_y + party_y)
			var previous_x = globals.get("previous_x")
			var previous_y = globals.get("previous_y")
			if not previous_x is int or not previous_y is int:
				return _failure("post_move_update requires the explicit previous world words")
			for word in [world_x, party_x, world_y, party_y, previous_x, previous_y]:
				if word < -32768 or word > 65535: return _failure("post_move_update coordinate leaves WORD")
			previous_x = _u2_as_i2(previous_x); previous_y = _u2_as_i2(previous_y)
			for key in ["walk_phase_word", "leader_frame_offset_word", "party_frame_offset_word"]:
				var word = globals.get(key, 0)
				if typeof(word) != TYPE_INT or word < 0 or word > 65535:
					return _failure("invalid phase/frame WORD: " + key)
			var phase: int = _u2(globals.get("walk_phase_word", 0))
			var leader_offset: int = _u2(globals.get("leader_frame_offset_word", 0))
			var party_offset: int = _u2(globals.get("party_frame_offset_word", 0))
			if new_x != previous_x or new_y != previous_y:
				phase = (phase + 1) & 3
				if (phase & 1) == 0:
					leader_offset = 0; party_offset = 0
				else:
					leader_offset = (phase + 1) / 2
					party_offset = 3 - leader_offset
			else:
				leader_offset = 0; party_offset = 0
				phase = (phase & 2) ^ 2
			globals.world_x = new_x
			globals.world_y = new_y
			globals.walk_phase_word = phase
			globals.leader_frame_offset_word = leader_offset
			globals.party_frame_offset_word = party_offset
			moved.globals = globals
			# Previous world belongs to the caller. AdvanceMovementPhase rotates
			# trail only on displacement; SyncMembersFromTrail always follows.
			# Do not replace either procedure with a fabricated trail[0] write.
			var dependencies: Array = []
			if new_x != previous_x or new_y != previous_y: dependencies.append("rotate_party_trail")
			dependencies.append("sync_members_from_trail")
			for kind in dependencies:
				var child = request.duplicate(true); child.kind = kind; child.state = moved
				var answer = _execute_dependent(child)
				if answer.has("error"): return answer
				moved = answer.state
			return {"completed": true, "state": moved}
		"rotate_party_trail":
			return _rotate_party_trail(moved)
		"sync_members_from_trail":
			return _sync_members_from_trail(moved)
		"rebuild_no_move_frames":
			if _member_sync == null: return _failure("standing frame owner not bound")
			var answer: Dictionary = _member_sync.answer({"kind": request.kind, "state": moved})
			if answer.has("error"): return _failure(str(answer.error))
			if answer.get("completed") != true: return _failure("standing frames not completed")
			var rows = answer.get("party_records")
			if not rows is Array or rows.size() != moved.party_records.size(): return _failure("standing frame backing changed")
			for slot in range(rows.size()):
				var expected: Dictionary = moved.party_records[slot].duplicate(true)
				if slot <= globals.member_last + globals.follower_count:
					if not _i2(rows[slot].get("current_frame")): return _failure("standing frame leaves I2")
					expected.current_frame = rows[slot].current_frame
				if expected != rows[slot]: return _failure("standing frame owner changed unrelated state")
			moved.party_records = rows.duplicate(true)
			globals.walk_phase_word = (globals.walk_phase_word & 2) ^ 2
			return {"completed": true, "state": moved}
	return _forward(request)

## The recovered ShiftPartyTrailAndStorePreviousPosition: the five trail
## entries shift back and the newest entry carries the team direction plus
## the pre-move world position the caller refreshed.
func _rotate_party_trail(moved: Dictionary) -> Dictionary:
	var trail = moved.get("party_trail", [])
	var issue = _trail_issue(trail)
	if not issue.is_empty(): return _failure("rotate_party_trail " + issue)
	for key in ["previous_x", "previous_y", "direction_word"]:
		if not _word(moved.globals.get(key)): return _failure("rotate_party_trail requires explicit WORD " + key)
	for index in range(4, 0, -1):
		trail[index] = trail[index - 1].duplicate(true)
	trail[0] = {"x": moved.globals.previous_x, "y": moved.globals.previous_y,
		"direction_word": moved.globals.direction_word}
	moved.party_trail = trail
	return {"completed": true, "state": moved}

## Known leader/follower position projection, followed by the required member
## formation/probe/frame dependency. Never assume every probe rejected or keep
## stale frames while acknowledging the whole original procedure. x/y are the
## same internal fields T209 consumes; screen_x/y exist only on draw requests.
func _sync_members_from_trail(moved: Dictionary) -> Dictionary:
	var trail = moved.get("party_trail", [])
	var records = moved.get("party_records", [])
	var issue = _trail_issue(trail)
	if not issue.is_empty(): return _failure("sync_members_from_trail " + issue)
	var globals: Dictionary = moved.globals
	var viewport_x = globals.get("viewport_x"); var viewport_y = globals.get("viewport_y")
	for key in ["viewport_x", "viewport_y", "party_x", "party_y", "direction_word"]:
		if not _word(globals.get(key)): return _failure("sync_members_from_trail requires explicit WORD " + key)
	var member_last = globals.get("member_last")
	var follower_count = globals.get("follower_count")
	if not _i2(member_last) or member_last < 0 or member_last > 2 \
		or not _i2(follower_count) or follower_count < 0 or follower_count > 2:
		return _failure("sync_members_from_trail requires the explicit member counters")
	issue = _records_issue(records, member_last, follower_count)
	if not issue.is_empty(): return _failure("sync_members_from_trail " + issue)
	if _member_sync == null or not _member_sync.has_method("answer"):
		return _failure("sync_members_from_trail formation probes/frame selection owner not bound")
	records[0].x = _u2_as_i2(globals.party_x)
	records[0].y = _u2_as_i2(globals.party_y)
	for follower in range(1, follower_count + 1):
		var slot: int = member_last + follower
		var trail_index: int = follower + 2
		var relative_x: int = _u2_as_i2(trail[trail_index].x) - _u2_as_i2(viewport_x)
		var relative_y: int = _u2_as_i2(trail[trail_index].y) - _u2_as_i2(viewport_y)
		if not _i2(relative_x) or not _i2(relative_y): return _failure("follower position leaves I2")
		records[slot].x = relative_x
		records[slot].y = relative_y
	moved.party_records = records
	var answer: Dictionary = _member_sync.answer({"kind": "sync_party_formation_and_frames", "state": moved.duplicate(true)})
	if answer.has("error"): return _failure(str(answer.error))
	if answer.get("completed") != true: return _failure("member formation/frame owner did not complete")
	var updated = answer.get("party_records")
	issue = _records_issue(updated, member_last, follower_count)
	if not issue.is_empty(): return _failure("member owner returned " + issue)
	if updated.size() != records.size(): return _failure("member owner changed party backing size")
	for slot in range(records.size()):
		if slot > member_last + follower_count:
			if records[slot] != updated[slot]: return _failure("member owner changed inactive party backing")
			continue
		var expected = records[slot].duplicate(true)
		if slot <= member_last + follower_count:
			expected.current_frame = updated[slot].current_frame
			if slot > 0 and slot <= member_last:
				expected.x = updated[slot].x; expected.y = updated[slot].y
		if expected != updated[slot]: return _failure("member owner changed unrelated party fields at slot " + str(slot))
	moved.party_records = updated.duplicate(true)
	for key in ["previous_x", "previous_y"]:
		if not _word(globals.get(key)): return _failure("sync requires " + key)
	moved.party_trail[0] = {"x": globals.previous_x, "y": globals.previous_y, "direction_word": globals.direction_word}
	return {"completed": true, "state": moved}


## Dependent kinds execute here for real; only kinds this owner does not
## implement fall through to the display fallback.
func _execute_dependent(request: Dictionary) -> Dictionary:
	executed.append(request.kind)
	match request.kind:
		"rotate_party_trail":
			return _rotate_party_trail(request.state)
		"sync_members_from_trail":
			return _sync_members_from_trail(request.state)
	return _forward(request)

func _forward(request: Dictionary) -> Dictionary:
	if _fallback != null and _fallback.has_method("answer"):
		var forwarded: Dictionary = _fallback.answer(request)
		if forwarded.has("error"): return forwarded
		# The parked cross-fade marker travels untouched: only the display
		# owner's finish_transition may complete this command later.
		if forwarded.get("parked_transition", false): return forwarded
		if forwarded.get("completed") != true: return _failure("dependent owner did not complete " + request.kind)
		if not forwarded.has("state"): forwarded.state = request.state.duplicate(true)
		if not forwarded.state is Dictionary or not forwarded.state.get("globals") is Dictionary:
			return _failure("dependent owner returned malformed state for " + request.kind)
		return forwarded
	return _failure("no execution owner bound for " + str(request.kind))
