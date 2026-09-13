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
## Trail rotation, member sync, frame processing and rendering require bound
## execution owners. A successful no-op is never supplied for an unbound kind.

var error: String = ""
## Every request kind this owner has answered, in order, for host evidence.
var requests: Array = []
## The dependent kinds executed by this owner, in order, for host evidence.
var executed: Array = []
## Optional owner for forwarded kinds this movement owner does not execute
## (the display family); without it such kinds are refused by name.
var _fallback = null

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
	return _forward(request)

## The recovered ShiftPartyTrailAndStorePreviousPosition: the five trail
## entries shift back and the newest entry carries the team direction plus
## the pre-move world position the caller refreshed.
func _rotate_party_trail(moved: Dictionary) -> Dictionary:
	var trail = moved.get("party_trail", [])
	if not trail is Array or trail.size() != 5:
		return _failure("rotate_party_trail requires the five-entry party trail")
	for entry in trail:
		if not entry is Dictionary: return _failure("party trail entries must be dictionaries")
	for index in range(4, 0, -1):
		trail[index] = trail[index - 1].duplicate(true)
	trail[0] = {"x": moved.globals.get("previous_x", 0), "y": moved.globals.get("previous_y", 0),
		"direction_word": moved.globals.get("direction_word", 0)}
	moved.party_trail = trail
	return {"completed": true, "state": moved}

## The recovered SyncMembersFromTrail position sync. The leader adopts the
## party-in-viewport position; members adopt their trail position relative to
## the viewport through the original's probe-rejected fallback (the
## formation-offset candidate needs the unrecovered G041C/G0434 values, so
## the receipt names that adaptation); followers adopt trail[follower+2]
## directly. Frame indices stay untouched: FramesPerDirection is sprite
## metadata the state does not carry.
func _sync_members_from_trail(moved: Dictionary) -> Dictionary:
	var trail = moved.get("party_trail", [])
	var records = moved.get("party_records", [])
	if not trail is Array or trail.size() < 3:
		return _failure("sync_members_from_trail requires the party trail")
	if not records is Array or records.is_empty():
		return _failure("sync_members_from_trail requires party records")
	for entry in trail:
		if not entry is Dictionary: return _failure("party trail entries must be dictionaries")
	var globals: Dictionary = moved.globals
	var viewport_x = globals.get("viewport_x"); var viewport_y = globals.get("viewport_y")
	if not viewport_x is int or not viewport_y is int:
		return _failure("sync_members_from_trail requires the viewport words")
	var member_last = globals.get("member_last")
	var follower_count = globals.get("follower_count")
	if not member_last is int or member_last < 0 or not follower_count is int or follower_count < 0:
		return _failure("sync_members_from_trail requires the explicit member counters")
	if records[0] is Dictionary:
		records[0]["screen_x"] = globals.get("party_x", 0)
		records[0]["screen_y"] = globals.get("party_y", 0)
	var source: Dictionary = trail[1]
	var adaptations: Array = []
	for member_index in range(1, member_last + 1):
		if member_index >= records.size() or not records[member_index] is Dictionary:
			return _failure("sync_members_from_trail member slot missing: " + str(member_index))
		records[member_index]["screen_x"] = _u2_as_i2(source.get("x", 0) - viewport_x)
		records[member_index]["screen_y"] = _u2_as_i2(source.get("y", 0) - viewport_y)
		adaptations.append("member %d uses the probe-rejected fallback trail position" % member_index)
	for follower in range(1, follower_count + 1):
		var slot: int = member_last + follower
		var trail_index: int = follower + 2
		if slot >= records.size() or not records[slot] is Dictionary:
			return _failure("sync_members_from_trail follower slot missing: " + str(slot))
		if trail_index >= trail.size() or not trail[trail_index] is Dictionary:
			return _failure("sync_members_from_trail follower trail missing: " + str(trail_index))
		records[slot]["screen_x"] = _u2_as_i2(trail[trail_index].get("x", 0) - viewport_x)
		records[slot]["screen_y"] = _u2_as_i2(trail[trail_index].get("y", 0) - viewport_y)
	moved.party_records = records
	moved.party_trail = trail
	var receipt: Dictionary = {"adaptations": adaptations}
	return {"completed": true, "state": moved, "sync": receipt}


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
		if forwarded.get("completed") != true: return _failure("dependent owner did not complete " + request.kind)
		if not forwarded.has("state"): forwarded.state = request.state.duplicate(true)
		if not forwarded.state is Dictionary or not forwarded.state.get("globals") is Dictionary:
			return _failure("dependent owner returned malformed state for " + request.kind)
		return forwarded
	return _failure("no execution owner bound for " + str(request.kind))
