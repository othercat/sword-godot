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
## The per-step host kinds this owner acknowledges with the state round-trip
## while their real owners (frame/viewport/render, member sync) stay unbound.
const ACKED_KINDS = ["sync_members_from_trail", "start_frame_and_process_events",
	"update_viewport_and_party_position", "render_scene_frame"]

var error: String = ""

func _failure(message: String) -> Dictionary:
	error = "pal98-walk-facing: " + message
	return {"error": error}

## The decoded extf core: returns {"direction": word} for a facing change, or
## {"unchanged": true} when both deltas are zero (the original writes nothing).
func face(delta_x: int, delta_y: int) -> Dictionary:
	if delta_x == 0 and delta_y == 0:
		return {"unchanged": true}
	var index: int = 0
	if delta_y == 0: index = 3
	elif delta_y > 0: index = 6
	if delta_x == 0: index += 1
	elif delta_x > 0: index += 2
	return {"direction": DIRECTION_TABLE[index]}

## EntryHost movement-owner entry point. face_party_toward applies the decoded
## extf to the request's deltas; post_move_update applies the reviewed world
## relation (world = viewport + party screen anchor) inherited from the host
## double that preceded this owner. Other forwarded kinds are refused by name.
func answer(request: Dictionary) -> Dictionary:
	if not request is Dictionary or not request.get("kind") is String:
		return _failure("owner request shape")
	var state: Dictionary = request.get("state", {})
	if not state is Dictionary: return _failure("movement request requires the pending state")
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
			var world_x = globals.get("viewport_x"); var party_x = globals.get("party_x")
			var world_y = globals.get("viewport_y"); var party_y = globals.get("party_y")
			if not world_x is int or not party_x is int or not world_y is int or not party_y is int:
				return _failure("post_move_update requires the explicit viewport and party words")
			globals.world_x = world_x + party_x
			globals.world_y = world_y + party_y
			moved.globals = globals
			return {"completed": true, "state": moved}
	if request.kind in ACKED_KINDS:
		return {"completed": true, "state": moved}
	return _failure("not a walk facing request: " + str(request.kind))
