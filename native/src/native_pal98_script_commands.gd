# SPDX-License-Identifier: MIT
extends RefCounted
## T240 ExecuteScriptCommand: a bounded, real consumer for the reviewed
## scene-entry commands.
##
## Only the cases listed in `CASES` change state. Every other T240 command ends
## the invocation with an explicit diagnostic that carries the opcode, the
## instruction receipt and the pinned case range when it is known; nothing is a
## silent no-op. Sub-effects of an implemented case that Native still lacks are
## reported as `unimplemented` entries on that command's receipt, and a command
## that cannot complete its original effects fails the invocation instead of
## publishing a state the original would not produce.
##
## The ranges/hashes are the pinned fixed-source review facts for PAL.EXE
## SHA256 75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450.
## They were re-hashed from the local private copy before this file was written;
## this module only consumes their consequences.
const Events = preload("res://src/native_pal98_scene_events.gd")

const ROLES = 6
const ROLE_FIELDS = 75
# G079C[role,2] holds the role's map sprite id. The product review corrected the
# research summary's ambiguous "field6" name, so only the numeric index is used.
const ROLE_MAP_SPRITE_FIELD = 2
# ffxy viewport bounds recovered from the original 0x0041B120..0x0041B14A.
const FX_MAX_X = 1696
const FX_MAX_Y = 1840
const SCENE_EVENT_MASK = 12 # G0306 bits4|8: event reload and EnterScript

const CASES = {
	0x003B: {"range": ["0x0042322E", "0x00423272"],
		"sha256": "484d663d6609be35e3f751d9ffd339139334eb4d09b80749cfba723871e1f842",
		"effect": "centered dialog globals: mode 0, text origin (80,40)"},
	0x003D: {"range": ["0x0042331A", "0x004233C2"],
		"sha256": "cd726d7203549f9ca44af334f1ee5223228b14719914b049918c133c44c8f6d8",
		"effect": "lower dialog globals: mode 2, title (12,108), body origin (44,126)"},
	0x0015: {"range": ["0x0042149E", "0x004214DC"],
		"sha256": "6ff196f1a2b77487ac2e91af92f7ba0776d28134b53dc528ebd1d11f8344e44b",
		"effect": "G026E = A0; G04AC[A2].field6 = G026E*3 + A1"},
	0x0041: {"range": ["0x004234D6", "0x004234F0"],
		"sha256": "ad650e711580bdfef6846cfb7ad9d5c1ecf6dd18aabc688d2184ef8c7872d60c",
		"effect": "G0302 = 0"},
	0x0046: {"range": ["0x00423834", "0x004239F4"],
		"sha256": "5a4b534c4bc6a24139258fb2cb2f78da745a8640b29e0c8aa57afb937e7572d0",
		"effect": "party world position, party viewport records, trail and map redraw"},
	0x0048: {"range": ["0x00423A16", "0x00423A2C"],
		"sha256": "22117f8fba64e3bbaca08f2fdeece837148928f6f42add0ff40c75fa0cdc225a",
		"effect": "original no-op: dispatch and exit only"},
	0x0059: {"range": ["0x004243B8", "0x00424408"],
		"sha256": "bf234982c4cacef65ce8b3e63e275744d2a0afd8b162b2edd1e6fbb05adce0f6",
		"effect": "valid changed scene: G0306|=12, G026A = A0, G028A = 0"},
	0x0065: {"range": ["0x0042477E", "0x004247CC"],
		"sha256": "8f02d5a65015d7ddff5937ccf88a3484ef2e9e5f1fd73d47787aa8f22558a00c",
		"effect": "G079C[A0,2] = A1; optional outside-battle sprite reload"},
	0x0075: {"range": ["0x004255D8", "0x0042568C"],
		"sha256": "ca7af492236a04d1336ed2e1081028a484fe05e497f91be694423d9703576207",
		"effect": "rebuild up-to-three-member party, then LoadPlayerAndFollowerSprites (T99), InitializePartyBattleAndEquipmentState (T156) and SyncMembersFromTrail (T230)"},
	0x008E: {"range": ["0x004264EE", "0x00426506"],
		"sha256": "282fc769a7cbac2159090b9fc1217aebc4cb32598fcae4b1f15fd51953bc5187",
		"effect": "RestoreDialogBackground (0x0041D2B4) and clear the two capture/restore gates"},
}
# Owner procedures the party rebuild calls, kept by their original entry points
# so the relayed requests name the same identities the review does.
const LOAD_PARTY_SPRITES = "load_party_sprites"          # T99 0x0041C864
const REBUILD_PARTY_EQUIPMENT = "rebuild_party_equipment" # T156 0x0041D374
const SYNC_MEMBERS_FROM_TRAIL = "sync_members_from_trail" # T230 0x0041D2E4
const RESTORE_DIALOG_BACKGROUND = "restore_dialog_background" # 0x0041D2B4
# Named next gaps: not implemented, kept here so the diagnostic and the review
# can name the same case identity.
const NEXT_GAPS = {}

var error: String = ""
var _events
var _identity: String = ""
var _scene_count: int = 0

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _u2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 65535

static func _signed(value: int) -> int:
	return value if value < 32768 else value - 65536

func load_source(source) -> bool:
	if source == null or source.metadata().is_empty():
		error = "pal98-command: admitted source snapshot required"; return false
	var records = source.open_records()
	var storage = Events.new()
	if records == null or not storage.load_source(source):
		error = "pal98-command: source tables/graphics unavailable"; return false
	var summary: Dictionary = records.table_summary()
	if not summary.get("issues", []).is_empty() or not summary.get("counts", {}).has("scenes"):
		error = "pal98-command: source scene table is malformed"; return false
	_events = storage; _identity = source.metadata().fingerprint
	_scene_count = int(summary.counts.scenes); error = ""
	return true

func source_identity() -> String:
	return _identity

func scene_count() -> int:
	return _scene_count

func case_facts(opcode: int) -> Dictionary:
	if CASES.has(opcode): return CASES[opcode].duplicate(true)
	if NEXT_GAPS.has(opcode): return NEXT_GAPS[opcode].duplicate(true)
	return {}

func implemented(opcode: int) -> bool:
	return CASES.has(opcode)

func _failure(code: String, message: String, request: Dictionary, details: Dictionary = {}) -> Dictionary:
	var diagnostic: Dictionary = {"code": code, "source_fingerprint": _identity,
		"words": request.get("words", []), "entry": request.get("entry"),
		"event_id": request.get("event_id"), "instruction_source": request.get("instruction_source", {})}
	diagnostic.merge(details, true)
	error = "pal98-command: " + message
	return {"error": error, "diagnostic": diagnostic, "opcode": request.get("words", [0])[0] if request.get("words") is Array and not request.get("words", []).is_empty() else -1}

func _result(state: Dictionary, request: Dictionary, effects: Array, unimplemented: Array = []) -> Dictionary:
	return {"state": state, "entry": request.entry, "event_id": request.event_id,
		"effects": effects, "unimplemented": unimplemented, "opcode": request.words[0]}

## Consume one T240 request. `state` keeps the T258 state shape plus the explicit
## `party_records` and `equipment` blocks this consumer writes.
func consume(state: Dictionary, request: Dictionary) -> Dictionary:
	if _identity.is_empty(): return {"error": "pal98-command: source not loaded"}
	if not state.get("globals") is Dictionary:
		return {"error": "pal98-command: explicit globals required"}
	if not request.get("words") is Array or request.words.size() != 4:
		return {"error": "pal98-command: four instruction words required"}
	for word in request.words:
		if not _u2(word): return {"error": "pal98-command: instruction word outside U2"}
	if not _u2(request.get("entry")) or not _i2(request.get("event_id")):
		return {"error": "pal98-command: ByRef entry/event context required"}
	var opcode: int = request.words[0]
	var source: Dictionary = {"opcode": opcode, "words": request.words.duplicate(),
		"entry": request.entry, "event_id": request.event_id,
		"instruction_source": request.get("instruction_source", {})}
	# The signed <= 10 tail and FFFF messages run no case body; the T258 driver
	# already applied their local effect before requesting the shared T240 gate.
	if _signed(opcode) <= 10:
		return _result(state, request, [{"kind": "dispatch_tail", "detail": "signed opcode <= 10: no case body"}])
	match opcode:
		0x003B: return _command_003B(state, request, source)
		0x003D: return _command_003D(state, request, source)
		0x0015: return _command_0015(state, request, source)
		0x0041: return _command_0041(state, request, source)
		0x0046: return _command_0046(state, request, source)
		0x0048: return _result(state, request, [{"kind": "original_no_op", "source": source}])
		0x0059: return _command_0059(state, request, source)
		0x0065: return _command_0065(state, request, source)
		0x0075: return _command_0075(state, request, source)
		0x008E: return _command_008E(state, request, source)
	var facts: Dictionary = case_facts(opcode)
	var details: Dictionary = {"effect": facts.get("effect"), "case_range": facts.get("range"),
		"case_sha256": facts.get("sha256")}
	return _failure("unimplemented_command",
		"ExecuteScriptCommand 0x%04X is not implemented in the entry consumer" % opcode, request, details)

## Shared guard for the dialog-global commands: the caller must supply the
## explicit context the reviewed fields live in.
func _dialog_context(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var dialogue = state.get("dialogue")
	if not dialogue is Dictionary or not dialogue.get("mode") is int:
		return _failure("dialogue_backing", "dialog-global command requires the explicit dialogue context", request, source)
	return {"dialogue": dialogue}

func _command_003B(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var context: Dictionary = _dialog_context(state, request, source)
	if context.has("error"): return context
	var dialogue: Dictionary = context.dialogue
	dialogue.mode = 0
	dialogue.origin_x = 80
	dialogue.origin_y = 40
	var missing: Array = [{"sub_effect": "G022A dialog colour word", "status": "not_implemented"}]
	return _result(state, request, [{"kind": "dialog_globals", "mode": 0, "origin_x": 80,
		"origin_y": 40, "source": source}], missing)

func _command_003D(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var context: Dictionary = _dialog_context(state, request, source)
	if context.has("error"): return context
	var dialogue: Dictionary = context.dialogue
	dialogue.mode = 2
	dialogue.title_x = 12
	dialogue.title_y = 108
	dialogue.origin_x = 44
	dialogue.origin_y = 126
	var missing: Array = [
		{"sub_effect": "0x0041D29C background capture call", "status": "not_implemented"},
		{"sub_effect": "0x0041D44C lower-dialog layout call", "status": "not_implemented"},
	]
	return _result(state, request, [{"kind": "dialog_globals", "mode": 2, "title_x": 12,
		"title_y": 108, "origin_x": 44, "origin_y": 126, "source": source}], missing)

func _command_008E(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var context: Dictionary = _dialog_context(state, request, source)
	if context.has("error"): return context
	var dialogue: Dictionary = context.dialogue
	for key in ["capture_gate", "restore_gate"]:
		if not _u2(dialogue.get(key)):
			return _failure("dialogue_backing", "0x008E requires the explicit capture/restore gates", request, source)
	dialogue.capture_gate = 0
	dialogue.restore_gate = 0
	var result: Dictionary = _result(state, request, [{"kind": "restore_dialog_background",
		"capture_gate": 0, "restore_gate": 0, "source": source}])
	result.requests = [{"kind": RESTORE_DIALOG_BACKGROUND, "original_entry": "0x0041D2B4",
		"procedure": "RestoreDialogBackground"}]
	return result

func _command_0015(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var direction: int = request.words[1]
	var frame_word: int = request.words[2]
	var slot: int = request.words[3]
	if not state.get("party_records") is Array or slot >= state.party_records.size():
		return _failure("party_backing", "0x0015 requires a known party record for slot " + str(slot), request, source)
	var record = state.party_records[slot]
	if not record is Dictionary or not record.get("current_frame") is int:
		return _failure("party_backing", "0x0015 requires the slot's explicit frame word", request, source)
	# G026E = A0; G04AC[A2].field6 = G026E*3 + A1 with checked I2 arithmetic.
	var computed: int = _signed(direction) * 3 + _signed(frame_word)
	if not _i2(computed):
		return _failure("checked_i2", "0x0015 frame arithmetic leaves I2 range", request, source)
	state.globals.direction_word = direction
	record.current_frame = computed & 65535
	return _result(state, request, [{"kind": "party_direction_frame", "direction_word": direction,
		"frame_word": computed & 65535, "party_slot": slot, "source": source}])

func _command_0041(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	state.globals.trigger_success_word = 0
	return _result(state, request, [{"kind": "script_failure_word", "success_word": 0, "source": source}])

func _command_0046(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	for key in ["party_x", "party_y"]:
		if not _i2(globals.get(key)):
			return _failure("party_anchor", "0x0046 requires the explicit party screen anchor", request, source)
	var arg0: int = _signed(request.words[1])
	var arg1: int = _signed(request.words[2])
	var arg2: int = _signed(request.words[3])
	# (worldX, worldY) = ((2*A0+A2)*16, (2*A1+A2)*8) from the original body.
	var world_x: int = (arg0 * 2 + arg2) * 16
	var world_y: int = (arg1 * 2 + arg2) * 8
	if not _u2(world_x) or not _u2(world_y):
		return _failure("checked_i2", "0x0046 world position leaves WORD range", request, source)
	var viewport_x: int = world_x - globals.party_x
	var viewport_y: int = world_y - globals.party_y
	if viewport_x < 0 or viewport_x > FX_MAX_X or viewport_y < 0 or viewport_y > FX_MAX_Y:
		return _failure("ffxy_clamp_unimplemented",
			"0x0046 viewport outside the original ffxy bounds; Native does not implement the clamp",
			request, source)
	var previous = [globals.get("world_x"), globals.get("world_y")]
	globals.world_x = world_x; globals.world_y = world_y
	globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
	var effect: Dictionary = {"kind": "party_map_position", "world_x": world_x, "world_y": world_y,
		"viewport_x": viewport_x, "viewport_y": viewport_y, "previous_world": previous, "source": source}
	var missing: Array = [
		{"sub_effect": "G04AC party viewport records", "status": "not_implemented"},
		{"sub_effect": "G04C4 five-entry trail", "status": "not_implemented"},
		{"sub_effect": "non-battle map background redraw", "status": "not_implemented"},
	]
	return _result(state, request, [effect], missing)

func _command_0059(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	if not _u2(request.words[1]):
		return _failure("scene_request", "0x0059 requires a U2 scene word", request, source)
	var requested: int = request.words[1]
	var changed: bool = requested != 0 and requested <= _scene_count and requested != globals.get("current_scene")
	if not changed:
		return _result(state, request, [{"kind": "scene_request_skipped",
			"detail": "scene is unchanged or outside the playable table", "scene": requested, "source": source}])
	if not _u2(globals.get("resource_flags")):
		return _failure("resource_flags", "0x0059 requires the explicit G0306 mask", request, source)
	globals.resource_flags = globals.resource_flags | SCENE_EVENT_MASK
	globals.requested_scene = requested
	var missing: Array = [{"sub_effect": "G028A = 0 (no reviewed Native field)", "status": "not_implemented"}]
	return _result(state, request, [{"kind": "scene_request", "scene": requested,
		"resource_flags": globals.resource_flags, "source": source}], missing)

func _command_0065(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var role: int = request.words[1]
	var sprite: int = request.words[2]
	var reload: int = request.words[3]
	if reload != 0:
		return _failure("sprite_reload_unimplemented",
			"0x0065 outside-battle sprite reload is not implemented", request, source)
	var equipment = state.get("equipment")
	if not equipment is Dictionary or not equipment.get("role_words") is Array:
		return _failure("equipment_backing", "0x0065 requires the explicit role word table", request, source)
	var words: Array = equipment.role_words
	if words.size() != ROLES * ROLE_FIELDS or role >= ROLES:
		return _failure("equipment_backing", "0x0065 role index or table shape outside the source table", request, source)
	var index: int = role * ROLE_FIELDS + ROLE_MAP_SPRITE_FIELD
	if not _u2(words[index]):
		return _failure("equipment_backing", "0x0065 role word is not a WORD", request, source)
	words[index] = sprite
	return _result(state, request, [{"kind": "role_map_sprite", "role": role,
		"field_index": ROLE_MAP_SPRITE_FIELD, "sprite_word": sprite, "source": source}])

## 0x0075 rebuilds the active party from up to three role arguments, then runs
## the sprite, equipment and member-sync owners. The composition is applied here;
## the owner work is returned as explicit requests so the caller can fulfil it
## with the real sprite and equipment owners.
func _command_0075(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	if not state.get("party_records") is Array or not state.get("equipment") is Dictionary:
		return _failure("party_backing", "0x0075 requires explicit party records and equipment state", request, source)
	var roles: Array = []
	for slot in range(3):
		var argument: int = _signed(request.words[1 + slot])
		if slot == 0:
			# A nonpositive first argument selects role 0, not "no member".
			roles.append((argument if argument > 0 else 1) - 1)
		elif argument > 0:
			roles.append(argument - 1)
		else:
			break
	if not state.get("globals") is Dictionary:
		return _failure("party_backing", "0x0075 requires explicit globals", request, source)
	var equipment: Dictionary = state.equipment
	if not equipment.get("party_roles") is Array or equipment.party_roles.size() != state.party_records.size():
		return _failure("party_backing", "0x0075 requires party roles matching the party records", request, source)
	for role in roles:
		if role < 0 or role >= ROLES:
			return _failure("party_backing", "0x0075 role argument is outside the source role table", request, source)
	var records: Array = []
	for slot in range(roles.size()):
		var existing = state.party_records[slot] if slot < state.party_records.size() else {}
		if not existing is Dictionary or not existing.get("current_frame") is int:
			return _failure("party_backing", "0x0075 needs the slot's explicit frame word", request, source)
		var record: Dictionary = existing.duplicate(true)
		record.role_id = roles[slot]
		records.append(record)
	var dropped: Array = state.party_records.slice(roles.size())
	state.party_records = records
	equipment.party_roles = roles.duplicate()
	state.globals.member_last = roles.size() - 1
	var effect: Dictionary = {"kind": "party_composition", "roles": roles.duplicate(),
		"member_last": state.globals.member_last, "dropped_slots": dropped.size(), "source": source}
	var requests: Array = [
		{"kind": LOAD_PARTY_SPRITES, "original_entry": "0x0041C864", "procedure": "LoadPlayerAndFollowerSprites",
			"roles": roles.duplicate(), "follower_count": state.globals.get("follower_count", 0)},
		{"kind": REBUILD_PARTY_EQUIPMENT, "original_entry": "0x0041D374", "procedure": "InitializePartyBattleAndEquipmentState",
			"roles": roles.duplicate()},
	]
	# T230 member/trail sync has no Native owner yet; the command still applies its
	# composition and reports the gap instead of pretending the members are synced.
	var missing: Array = [{"sub_effect": "T230 SyncMembersFromTrail (0x0041D2E4)", "status": "not_implemented"}]
	var result: Dictionary = _result(state, request, [effect], missing)
	result.requests = requests
	return result
