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
# Party formation step tables from the generated initializer (G041C/G0434).
# The original subtracts them from the running member position per direction.
const FORMATION_STEP_X = [-16, -16, 16, 16]
const FORMATION_STEP_Y = [8, -8, -8, 8]
const PARTY_SLOTS = 5
const TRAIL_SLOTS = 5

const CASES = {
	0x003B: {"range": ["0x0042322E", "0x00423272"],
		"sha256": "484d663d6609be35e3f751d9ffd339139334eb4d09b80749cfba723871e1f842",
		"effect": "centered dialog globals: mode 0, text origin (80,40), colour word when A0 is positive"},
	0x003C: {"range": ["0x00423272", "0x0042331A"],
		"sha256": "14e1e16b5fd89ef4b78445898d329e0195fc0e5b269a6500d2665505e7b3b71f",
		"effect": "upper dialog globals: mode 1, title (12,8), origin (44,26); a positive A0 adds the capture path, the 0x41D44C call and the 80/96 anchors, a positive A1 writes the colour word"},
	0x003D: {"range": ["0x0042331A", "0x004233C2"],
		"sha256": "cd726d7203549f9ca44af334f1ee5223228b14719914b049918c133c44c8f6d8",
		"effect": "lower dialog globals: mode 2, title (12,108), body origin (44,126)"},
	0x0015: {"range": ["0x0042149E", "0x004214DC"],
		"sha256": "6ff196f1a2b77487ac2e91af92f7ba0776d28134b53dc528ebd1d11f8344e44b",
		"effect": "G026E = A0; G04AC[A2].field6 = G026E*3 + A1"},
	0x0016: {"range": ["0x004214DC", "0x004215E0"],
		"sha256": "97d5870a01db9368720b7a49812dceec9ffe99cef587f9f2603b623a95cb6a7a",
		"effect": "A0==0 no-op; a negative A0 targets the current event, a positive one resolves against the scene event base; fields +20/+22 are written or the global table falls back to G0138+(A0-1)*32"},
	0x0024: {"range": ["0x00422276", "0x00422336"],
		"sha256": "8a43d83100b9aaa6191cbe5afbdcb54c4e1873620c3030933b1f225fd3366156",
		"effect": "same target resolution as 0x0016, writing the resolved record's +10 word (AutoScript/TriggerScript family)"},
	0x0025: {"range": ["0x00422336", "0x004223F6"],
		"sha256": "fdf265acb90d295e120a24a90b9031f8207e1e027fab632542f2cba4181418e0",
		"effect": "same target resolution, writing the resolved record's +8 word"},
	0x0049: {"range": ["0x00423A2C", "0x00423AEC"],
		"sha256": "e74b03b5e84ab52df630e2933fb93f79a63482d5030a8c738e2daad5a903a1fd",
		"effect": "same target resolution, writing the resolved record's +12 word (event state)"},
	0x0071: {"range": ["0x00425400", "0x00425426"],
		"sha256": "74f0007bd082b1a319179bc64968d2abc6c6ab6c66206d37d31af0b0354d94af",
		"effect": "G0298 = A0, G029A = A1 (screen-wave state)"},
	0x0077: {"range": ["0x004256AC", "0x004256FE"],
		"sha256": "679bb8101add55d44cf71111cb9a0130c1c69ca9ed28b78e10b2e40dd0ff03c2",
		"effect": "A0 defaults to 1; a zero A1 queries the CD track, then the media stop runs and a non-battle context clears G027C"},
	0x0035: {"range": ["0x00422F16", "0x00422F52"],
		"sha256": "873a78738f09dd6511e58f5a57a3bb27ce0b4a26c68a7b39ba9e0cf0a3532144",
		"effect": "screen-shake count = A0 and amplitude = A1 with the original default 4"},
	0x0041: {"range": ["0x004234D6", "0x004234F0"],
		"sha256": "ad650e711580bdfef6846cfb7ad9d5c1ecf6dd18aabc688d2184ef8c7872d60c",
		"effect": "G0302 = 0"},
	0x0043: {"range": ["0x004235C8", "0x00423624"],
		"sha256": "253041177018f3844200f72161b68bcbcc020827886a343452f03cd856f2b3fb",
		"effect": "G027C = A0 and a changed field track is played through PlayMidiTrack (0x0041D26C)"},
	0x0045: {"range": ["0x00423818", "0x00423834"],
		"sha256": "411645d044464b94b4c2f42cee5469383bb23e6aa8126f976b07ec9a891f04f2",
		"effect": "G027E = A0 (battle music track)"},
	0x0046: {"range": ["0x00423834", "0x004239F4"],
		"sha256": "5a4b534c4bc6a24139258fb2cb2f78da745a8640b29e0c8aa57afb937e7572d0",
		"effect": "party world position, party viewport records, trail and map redraw"},
	0x0047: {"range": ["0x004239F4", "0x00423A16"],
		"sha256": "9951cb790ca0ae9cbc252a3a98d97cbdc850552d7312bffd0ea6ac7f65ce7357",
		"effect": "PlaySoundEffectIfEnabled(A0)"},
	0x0048: {"range": ["0x00423A16", "0x00423A2C"],
		"sha256": "22117f8fba64e3bbaca08f2fdeece837148928f6f42add0ff40c75fa0cdc225a",
		"effect": "original no-op: dispatch and exit only"},
	0x004A: {"range": ["0x00423AEC", "0x00423B08"],
		"sha256": "ade90cc13b3ccc4149656913c8d4351ccc36c20e2ed0c188b5a9747a19fca588",
		"effect": "G0280 = A0 (battlefield selector word)"},
	0x0050: {"range": ["0x004240E6", "0x0042411C"],
		"sha256": "6d376704c4f69b7fe918fa9d16bb06f4addfdb821485734e6a4c83bfd3e25710",
		"effect": "A0 defaults to 1, then FadePaletteToBlackOnce (0x0041CDD4) runs"},
	0x0051: {"range": ["0x0042411C", "0x00424152"],
		"sha256": "00e052e759aee099ac5397f956839d68bcc559f54395c6452f23d6b201669fb7",
		"effect": "A0 defaults to 1, then FadePaletteToRepeatedColorBlock (0x0041CDEC) runs"},
	0x0053: {"range": ["0x004241B4", "0x004241CE"],
		"sha256": "391a28859adbc4c28a573632f1903d4f9a5ac7e9635c8795806973c0e7e7c2f3",
		"effect": "G026C = 0 (day palette offset)"},
	0x0054: {"range": ["0x004241CE", "0x004241EA"],
		"sha256": "66593d3969df57bb719347ff08e8cf48591777fb55a54db12509cedac53d35f7",
		"effect": "G026C = 384 (night palette offset)"},
	0x0059: {"range": ["0x004243B8", "0x00424408"],
		"sha256": "bf234982c4cacef65ce8b3e63e275744d2a0afd8b162b2edd1e6fbb05adce0f6",
		"effect": "valid changed scene: G0306|=12, G026A = A0, G028A = 0"},
	0x006D: {"range": ["0x004250D8", "0x00425178"],
		"sha256": "d69bf04eef9fcda8ad8f7a3dd6f9d587d0b9a1e0572e40a7433eff43b6ba2668",
		"effect": "for a positive scene: writes the record's enter (+2) and leave (+4) script words, or clears the pair when both arguments are zero"},
	0x006E: {"range": ["0x00425178", "0x00425206"],
		"sha256": "8b13d7703f032edde9e259c8491c84c6a86c674dc295405f1af189599284a8ea",
		"effect": "copies the world position into the previous-position words and the viewport into its previous copies, adds the A0/A1 deltas to the viewport, stores A2*8 as the party layer word and, when either delta is nonzero, requests PostMoveUpdate (0x0041D2CC) and UpdateViewportAndPartyPosition (0x0041CC3C)"},
	0x009A: {"range": ["0x0042694E", "0x00426A56"],
		"sha256": "2c21b7afb612569200ad2e9991adcb32b92cc0f5736d8c25b469ded47aef59a4",
		"effect": "resolves A0/A1 against the scene event base and writes the state word (+12) for the inclusive range, falling back to the global event record when the start is out of range"},
	0x001F: {"range": ["0x00421EC4", "0x00421F00"],
		"sha256": "79fa119ab6503c8516f2ac38ffe38c581b8630ad9f6072d3a3c1d1903e55d8b0",
		"effect": "compresses the inventory (T152 0x0041C96C), defaults a nonpositive amount to 1 and adds the item through T140 (0x0041CCCC)"},
	0x0065: {"range": ["0x0042477E", "0x004247CC"],
		"sha256": "8f02d5a65015d7ddff5937ccf88a3484ef2e9e5f1fd73d47787aa8f22558a00c",
		"effect": "G079C[A0,2] = A1; optional outside-battle sprite reload"},
	0x0075: {"range": ["0x004255D8", "0x0042568C"],
		"sha256": "ca7af492236a04d1336ed2e1081028a484fe05e497f91be694423d9703576207",
		"effect": "rebuild up-to-three-member party, then LoadPlayerAndFollowerSprites (T99), InitializePartyBattleAndEquipmentState (T156) and SyncMembersFromTrail (T230)"},
	0x0073: {"range": ["0x004254E4", "0x00425516"],
		"sha256": "819a92f1aea937b8536801c0e9b468524e83d90533f81c1079a7194a6cec8b6a",
		"effect": "ClearEffectiveCrossFade (0x0041CEC4) with A0 defaulting to 1 and the two ByRef argument words"},
	0x008E: {"range": ["0x004264EE", "0x00426506"],
		"sha256": "282fc769a7cbac2159090b9fc1217aebc4cb32598fcae4b1f15fd51953bc5187",
		"effect": "RestoreDialogBackground (0x0041D2B4) and clear the two capture/restore gates"},
	0x008B: {"range": ["0x00426338", "0x0042637A"],
		"sha256": "039ec2c5ba429c40b2f89b7b43af4ec48d4b223365afeab6d56182a1fd00165e",
		"effect": "sets the palette through 0x0041D11C and, when the fade gate is zero, applies the palette at the day/night offset through 0x004174D0"},
	0x0093: {"range": ["0x004266E8", "0x00426704"],
		"sha256": "016ec32ec874da9eef00d94ed9340c0d2aaa1d734b72cba175d9fe372e499604",
		"effect": "FadeScenePaletteAndUpdateFrames (0x0041CE04) with the instruction's argument"},
	0x0099: {"range": ["0x004268EC", "0x0042694E"],
		"sha256": "cf2a332b02f7f20c715aed6298f0fb2ff7fd3921c90cd9b13e84fac85405203f",
		"effect": "writes the scene record's map word; a negative A0 means the current scene and additionally requests EnsureMapResourcesLoaded (0x0041C834)"},
}
	# Owner procedures the party rebuild calls, kept by their original entry points
# so the relayed requests name the same identities the review does.
const LOAD_PARTY_SPRITES = "load_party_sprites"          # T99 0x0041C864
const REBUILD_PARTY_EQUIPMENT = "rebuild_party_equipment" # T156 0x0041D374
const SYNC_MEMBERS_FROM_TRAIL = "sync_members_from_trail" # T230 0x0041D2E4
const RESTORE_DIALOG_BACKGROUND = "restore_dialog_background" # 0x0041D2B4
const RENDER_CURRENT_MAP_BACKGROUND = "render_current_map_background" # 0x0041CB34
const PLAY_MIDI_TRACK = "play_midi" # PlayMidiTrack 0x0041D26C
const CLEAR_EFFECTIVE_CROSS_FADE = "clear_effective_cross_fade" # 0x0041CEC4
const PLAY_SOUND_EFFECT = "play_sound_effect" # PlaySoundEffectIfEnabled 0x0041D284
const CAPTURE_DIALOG_BACKGROUND = "capture_dialog_background" # 0x0041D29C
const UPPER_DIALOG_LAYOUT = "upper_dialog_layout" # 0x0041D44C, identity not established
const STOP_CD_OR_MUSIC = "stop_cd_or_music" # 0x0041D254, identity inferred from its call site
const QUERY_CD_TRACK_PLAYING = "query_cd_track_playing" # 0x0041D224, identity inferred from its call site
const FADE_TO_BLACK = "fade_palette_to_black" # 0x0041CDD4
const FADE_TO_REPEATED_BLOCK = "fade_palette_to_repeated_color_block" # 0x0041CDEC
const SET_PALETTE = "set_palette" # 0x0041D11C
const APPLY_PALETTE = "apply_palette" # 0x004174D0
const FADE_SCENE_PALETTE = "fade_scene_palette_and_update_frames" # 0x0041CE04
const ENSURE_MAP_RESOURCES = "ensure_map_resources_loaded" # 0x0041C834
const ADD_INVENTORY_ITEM = "add_inventory_item" # T152 0x0041C96C then T140 0x0041CCCC
const POST_MOVE_UPDATE = "post_move_update" # 0x0041D2CC
const UPDATE_VIEWPORT_AND_PARTY = "update_viewport_and_party_position" # 0x0041CC3C
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
		0x003C: return _command_003C(state, request, source)
		0x0035: return _command_0035(state, request, source)
		0x001F: return _command_001F(state, request, source)
		0x003D: return _command_003D(state, request, source)
		0x0016: return _command_0016(state, request, source)
		0x0024: return _command_0024(state, request, source)
		0x0025: return _command_0025(state, request, source)
		0x0015: return _command_0015(state, request, source)
		0x0041: return _command_0041(state, request, source)
		0x0043: return _command_0043(state, request, source)
		0x0045: return _command_0045(state, request, source)
		0x0046: return _command_0046(state, request, source)
		0x0047: return _command_0047(state, request, source)
		0x0048: return _result(state, request, [{"kind": "original_no_op", "source": source}])
		0x004A: return _command_004A(state, request, source)
		0x0049: return _command_0049(state, request, source)
		0x0053: return _command_0053(state, request, source)
		0x0054: return _command_0054(state, request, source)
		0x0050: return _command_0050(state, request, source)
		0x0051: return _command_0051(state, request, source)
		0x0059: return _command_0059(state, request, source)
		0x0065: return _command_0065(state, request, source)
		0x006D: return _command_006D(state, request, source)
		0x006E: return _command_006E(state, request, source)
		0x0073: return _command_0073(state, request, source)
		0x0071: return _command_0071(state, request, source)
		0x0075: return _command_0075(state, request, source)
		0x0077: return _command_0077(state, request, source)
		0x008E: return _command_008E(state, request, source)
		0x008B: return _command_008B(state, request, source)
		0x0093: return _command_0093(state, request, source)
		0x0099: return _command_0099(state, request, source)
		0x009A: return _command_009A(state, request, source)
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
	var result: Dictionary = _result(state, request, [{"kind": "dialog_globals", "mode": 0, "origin_x": 80,
		"origin_y": 40, "colour_word": state.globals.get("dialog_colour_word"), "source": source}])
	return _write_positive_colour(result, state, request, source)

## The G022A write only happens when the instruction's argument is positive. Its
## consumer mapping (the dialogue caller's primary colour) is not established, so
## the value is kept as an explicit global projection and reported as a named gap.
## It stays outside the caller's strict dialogue context on purpose.
func _write_positive_colour(result: Dictionary, state: Dictionary, request: Dictionary,
		source: Dictionary) -> Dictionary:
	var argument: int = _signed(request.words[1])
	if argument <= 0: return result
	state.globals.dialog_colour_word = argument & 65535
	result.effects[0].colour_word = argument & 65535
	result.unimplemented.append({"sub_effect": "G022A colour word consumer mapping (value "
		+ str(argument) + " recorded as globals.dialog_colour_word)", "status": "not_implemented"})
	return result

func _command_003C(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var context: Dictionary = _dialog_context(state, request, source)
	if context.has("error"): return context
	var dialogue: Dictionary = context.dialogue
	dialogue.mode = 1
	dialogue.title_x = 12
	dialogue.title_y = 8
	dialogue.origin_x = 44
	dialogue.origin_y = 26
	var effect: Dictionary = {"kind": "dialog_globals", "mode": 1, "title_x": 12, "title_y": 8,
		"origin_x": 44, "origin_y": 26, "source": source}
	var result: Dictionary = _result(state, request, [effect])
	var first: int = _signed(request.words[1])
	var third: int = _signed(request.words[3])
	if first > 0:
		var requests: Array = []
		if third != 0:
			if not _u2(dialogue.get("capture_gate")):
				return _failure("dialogue_backing", "0x003C requires the explicit capture gate", request, source)
			dialogue.capture_gate = third & 65535
			requests.append({"kind": CAPTURE_DIALOG_BACKGROUND, "original_entry": "0x0041D29C",
				"procedure": "0x0041D29C", "argument": third})
		requests.append({"kind": UPPER_DIALOG_LAYOUT, "original_entry": "0x0041D44C",
			"procedure": "0x0041D44C", "argument_words": request.words.duplicate(),
			"decoded_immediates": [0x37, 0x30]})
		dialogue.title_x = 80
		dialogue.origin_x = 96
		effect.title_x = 80; effect.origin_x = 96
		effect.capture_gate = dialogue.capture_gate
		result.requests = requests
		result.unimplemented.append({"sub_effect": "0x0041D44C upper-dialog call identity",
			"status": "not_implemented"})
	result.effects[0].colour_word = state.globals.get("dialog_colour_word")
	return _write_positive_colour(result, state, request, source)

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

## 0x0043 sets the field music track and plays it through PlayMidiTrack when the
## track actually changes. The original's loop-flag transform is not pinned, so
## the raw argument word travels with the request and is reported as a gap.
func _command_0043(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	if not _u2(globals.get("midi_track")):
		return _failure("music_state", "0x0043 requires the explicit G027C track word", request, source)
	var track: int = request.words[1]
	var effect: Dictionary = {"kind": "field_music", "track": track, "previous_track": globals.midi_track,
		"argument_word": request.words[2], "source": source}
	if track == globals.midi_track:
		effect.played = false
		return _result(state, request, [effect])
	globals.midi_track = track
	effect.played = true
	var missing: Array = [{"sub_effect": "PlayMidiTrack loop-flag transform of argument word "
		+ str(request.words[2]), "status": "not_implemented"}]
	var result: Dictionary = _result(state, request, [effect], missing)
	result.requests = [{"kind": PLAY_MIDI_TRACK, "original_entry": "0x0041D26C",
		"procedure": "PlayMidiTrack", "track": track, "argument_word": request.words[2]}]
	return result

## 0x0045 stores the battle music track (G027E).
func _command_0045(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	state.globals.battle_music_track = request.words[1]
	return _result(state, request, [{"kind": "battle_music", "track": request.words[1], "source": source}])

## 0x0073 calls ClearEffectiveCrossFade with the original default and ByRef args.
func _command_0073(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var first: int = _signed(request.words[1])
	var second: int = _signed(request.words[2])
	if first == 0: first = 1
	var missing: Array = [{"sub_effect": "ByRef writeback of the cross-fade argument words", "status": "not_implemented"}]
	var result: Dictionary = _result(state, request, [{"kind": "cross_fade", "first": first,
		"second": second, "source": source}], missing)
	result.requests = [{"kind": CLEAR_EFFECTIVE_CROSS_FADE, "original_entry": "0x0041CEC4",
		"procedure": "ClearEffectiveCrossFade", "first": first, "second": second}]
	return result

## 0x0035 stores the screen-shake count and amplitude (G0308/G030A consumers).
func _command_0035(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var count: int = _signed(request.words[1])
	var amplitude: int = _signed(request.words[2])
	if amplitude == 0: amplitude = 4
	state.globals.shake_count_word = count
	state.globals.shake_amplitude_word = amplitude
	return _result(state, request, [{"kind": "screen_shake", "count": count,
		"amplitude": amplitude, "source": source}])

## 0x001F compresses the inventory, defaults a nonpositive amount to 1 and adds
## the item through the reviewed T140 procedure. The work is owner-requested so
## the inventory owner performs the original arithmetic.
func _command_001F(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	if not state.get("inventory_bytes") is PackedByteArray or state.inventory_bytes.size() != 256 * 6:
		return _failure("inventory_backing", "0x001F requires the explicit 256-record inventory", request, source)
	var item: int = _signed(request.words[1])
	var amount: int = _signed(request.words[2])
	if amount <= 0: amount = 1
	var effect: Dictionary = {"kind": "inventory_add", "item": item, "amount": amount,
		"amount_defaulted": amount != _signed(request.words[2]), "source": source}
	var result: Dictionary = _result(state, request, [effect])
	result.requests = [{"kind": ADD_INVENTORY_ITEM, "original_entry": "0x0041C96C",
		"procedure": "CompressInventoryAndReturnLastSlot", "add_entry": "0x0041CCCC",
		"add_procedure": "AddInventoryItemAmount", "item": item, "amount": amount}]
	return result

## 0x0047 plays a sound effect through the audio owner when sound is enabled.
func _command_0047(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var result: Dictionary = _result(state, request, [{"kind": "sound_effect",
		"index": request.words[1], "source": source}])
	result.requests = [{"kind": PLAY_SOUND_EFFECT, "original_entry": "0x0041D284",
		"procedure": "PlaySoundEffectIfEnabled", "index": request.words[1]}]
	return result

## 0x004A stores the battlefield selector word (G0280).
func _command_004A(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	state.globals.battlefield_word = request.words[1]
	return _result(state, request, [{"kind": "battlefield", "word": request.words[1], "source": source}])

func _day_night(state: Dictionary, request: Dictionary, source: Dictionary, value: int) -> Dictionary:
	state.globals.day_night_word = value
	return _result(state, request, [{"kind": "day_night_palette", "offset": value, "source": source}])

## 0x0016 writes the resolved event record's +20/+22 words. A zero argument is a
## no-op, a negative one targets the current event, a positive one resolves
## against the current scene's event base, and anything outside that range falls
## back to the global event table record (A0-1).
func _command_0016(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var target: int = _signed(request.words[1])
	if target == 0:
		return _result(state, request, [{"kind": "event_fields_skipped",
			"detail": "zero target is the original no-op", "source": source}])
	return _event_field_write(state, request, source, 20, [request.words[2], request.words[3]])

## 0x0024 and 0x0049 share 0x0016's target resolution but write one word.
func _command_0024(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _event_field_write(state, request, source, 10, [request.words[2]])

func _command_0025(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _event_field_write(state, request, source, 8, [request.words[2]])

## 0x0093 runs the scene palette fade owner with the instruction's argument.
func _command_0093(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var result: Dictionary = _result(state, request, [{"kind": "scene_palette_fade",
		"argument": request.words[1], "source": source}])
	result.requests = [{"kind": FADE_SCENE_PALETTE, "original_entry": "0x0041CE04",
		"procedure": "FadeScenePaletteAndUpdateFrames", "argument": request.words[1]}]
	return result

## 0x0099 writes a scene record's map word: a negative A0 means the current scene
## and additionally asks the resource owner to reload the map.
## 0x009A writes the event state word (+12) for an inclusive scene-relative range.
func _command_009A(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	if not state.get("events") is Dictionary:
		return _failure("event_backing", "0x009A requires the explicit event state", request, source)
	if not _u2(request.words[3]):
		return _failure("event_backing", "0x009A requires a U2 state word", request, source)
	var base: int = state.events.scene_records.decode_u16((state.globals.current_scene - 1) * 8 + 6)
	var start: int = _signed(request.words[1]) - base
	var finish: int = _signed(request.words[2]) - base
	var value: int = request.words[3]
	if start > 0 and start <= state.events.event_count:
		if finish < start or finish > state.events.event_count:
			return _failure("event_backing", "0x009A range leaves the current event table", request, source)
		var written: Array = []
		for index in range(start, finish + 1):
			var row: Dictionary = _events.event_record(state.events, index)
			if row.has("error"): return _failure("event_record", str(row.error), request, source)
			var bytes: PackedByteArray = row.value
			bytes.encode_u16(12, value)
			var replaced: Dictionary = _events.replace_event_record(state.events, index, bytes)
			if replaced.has("error"): return _failure("event_writeback", str(replaced.error), request, source)
			state.events = replaced.state
			written.append(index)
		return _result(state, request, [{"kind": "event_state_range", "scope": "current_scene",
			"from": start, "to": finish, "value": value, "written": written, "source": source}])
	var at: int = (_signed(request.words[1]) - 1) * 32 + 12
	var global_bytes: PackedByteArray = state.events.global_events
	if at < 0 or at + 2 > global_bytes.size():
		return _failure("event_backing", "0x009A global fallback target is outside the event table", request, source)
	state.events.global_events = global_bytes
	state.events.global_events.encode_u16(at, value)
	return _result(state, request, [{"kind": "event_state_range", "scope": "global_table",
		"from": _signed(request.words[1]), "to": finish, "value": value, "offset": at, "source": source}])

func _command_0099(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var argument: int = _signed(request.words[1])
	var scene: int = state.globals.get("current_scene", 0) if argument < 0 else argument
	if not state.get("events") is Dictionary or not _u2(scene) or scene < 1 or scene > _scene_count:
		return _failure("scene_backing", "0x0099 requires a playable runtime scene", request, source)
	if not _u2(request.words[2]):
		return _failure("scene_backing", "0x0099 requires a U2 map word", request, source)
	var records: PackedByteArray = state.events.scene_records
	if (scene - 1) * 8 + 2 > records.size():
		return _failure("scene_backing", "0x0099 scene record is outside the loaded table", request, source)
	state.events.scene_records = records
	state.events.scene_records.encode_u16((scene - 1) * 8, request.words[2])
	var effect: Dictionary = {"kind": "scene_map_word", "scene": scene, "map_word": request.words[2],
		"current_scene": argument < 0, "source": source}
	var result: Dictionary = _result(state, request, [effect])
	if argument < 0:
		result.requests = [{"kind": ENSURE_MAP_RESOURCES, "original_entry": "0x0041C834",
			"procedure": "EnsureMapResourcesLoaded", "scene": scene, "map_word": request.words[2]}]
	return result

## 0x008B selects a palette and, when the fade gate is zero, applies the palette
## at the current day/night offset.
func _command_008B(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	if not _u2(globals.get("day_night_word")):
		return _failure("palette_state", "0x008B requires the explicit G026C day/night offset", request, source)
	var fade_gate = globals.get("fade_gate_word")
	if not _i2(fade_gate):
		return _failure("palette_state", "0x008B requires the explicit G0250 fade gate", request, source)
	var requests: Array = [{"kind": SET_PALETTE, "original_entry": "0x0041D11C",
		"procedure": "0x0041D11C", "argument": request.words[1]}]
	var effect: Dictionary = {"kind": "palette_select", "argument": request.words[1],
		"offset": globals.day_night_word, "applied": false, "source": source}
	if fade_gate == 0:
		requests.append({"kind": APPLY_PALETTE, "original_entry": "0x004174D0",
			"procedure": "0x004174D0", "offset": globals.day_night_word})
		effect.applied = true
	var result: Dictionary = _result(state, request, [effect])
	result.requests = requests
	return result

func _command_0049(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _event_field_write(state, request, source, 12, [request.words[2]])

## Shared resolution for the script-field commands: zero is a no-op, negative
## targets the current runtime event slot, positive resolves against the current
## scene's event base, and anything else falls back to the global table record.
func _event_field_write(state: Dictionary, request: Dictionary, source: Dictionary,
		field_offset: int, values: Array) -> Dictionary:
	var target: int = _signed(request.words[1])
	if target == 0:
		return _result(state, request, [{"kind": "event_fields_skipped",
			"detail": "zero target is the original no-op", "source": source}])
	if not state.get("events") is Dictionary:
		return _failure("event_backing", "script field command requires the explicit event state", request, source)
	for value in values:
		if not _u2(value):
			return _failure("event_backing", "script field command requires U2 field words", request, source)
	if target < 0:
		var event_id: int = request.event_id
		if event_id < 1:
			return _failure("event_context",
				"current-event target needs a runtime event slot; the scene-entry context 0 has no owned Native slot",
				request, source)
		var row: Dictionary = _events.event_record(state.events, event_id)
		if row.has("error"): return _failure("event_record", str(row.error), request, source)
		var bytes: PackedByteArray = row.value
		for index in range(values.size()):
			bytes.encode_u16(field_offset + index * 2, values[index])
		var replaced: Dictionary = _events.replace_event_record(state.events, event_id, bytes)
		if replaced.has("error"): return _failure("event_writeback", str(replaced.error), request, source)
		state.events = replaced.state
		return _result(state, request, [{"kind": "event_fields", "scope": "current_event",
			"event_id": event_id, "offset": field_offset, "values": values.duplicate(), "source": source}])
	var base: int = state.events.scene_records.decode_u16((state.globals.current_scene - 1) * 8 + 6)
	var index: int = target - base
	var count: int = state.events.event_count
	if index > 0 and index <= count:
		var active: Dictionary = _events.event_record(state.events, index)
		if active.has("error"): return _failure("event_record", str(active.error), request, source)
		var active_bytes: PackedByteArray = active.value
		for value_index in range(values.size()):
			active_bytes.encode_u16(field_offset + value_index * 2, values[value_index])
		var written: Dictionary = _events.replace_event_record(state.events, index, active_bytes)
		if written.has("error"): return _failure("event_writeback", str(written.error), request, source)
		state.events = written.state
		return _result(state, request, [{"kind": "event_fields", "scope": "current_scene",
			"event_id": index, "offset": field_offset, "values": values.duplicate(), "source": source}])
	var global_bytes: PackedByteArray = state.events.global_events
	var at: int = (target - 1) * 32 + field_offset
	if at < 0 or at + values.size() * 2 > global_bytes.size():
		return _failure("event_backing", "global event fallback target is outside the event table", request, source)
	state.events.global_events = global_bytes
	for global_index in range(values.size()):
		state.events.global_events.encode_u16(at + global_index * 2, values[global_index])
	return _result(state, request, [{"kind": "event_fields", "scope": "global_table",
		"event_id": target, "offset": at, "values": values.duplicate(), "source": source}])

## 0x0071 stores the screen-wave phase and amplitude (G0298/G029A).
func _command_0071(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	state.globals.wave_phase = request.words[1]
	state.globals.wave_amplitude = request.words[2]
	return _result(state, request, [{"kind": "screen_wave", "phase": request.words[1],
		"amplitude": request.words[2], "source": source}])

## 0x0050/0x0051 request the palette fade owners with the original default 1.
func _command_0050(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _fade_request(state, request, source, FADE_TO_BLACK, "0x0041CDD4",
		"FadePaletteToBlackOnce", "fade_to_black")

func _command_0051(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _fade_request(state, request, source, FADE_TO_REPEATED_BLOCK, "0x0041CDEC",
		"FadePaletteToRepeatedColorBlock", "fade_to_repeated_block")

func _fade_request(state: Dictionary, request: Dictionary, source: Dictionary, kind: String,
		entry: String, procedure: String, effect_kind: String) -> Dictionary:
	var argument: int = request.words[1]
	if argument == 0: argument = 1
	var result: Dictionary = _result(state, request, [{"kind": effect_kind, "argument": argument,
		"procedure": procedure, "source": source}])
	result.requests = [{"kind": kind, "original_entry": entry, "procedure": procedure,
		"argument": argument}]
	return result

## 0x0077 stops the media owner's music; the field track clears outside battle.
## 0x006D writes a scene record's enter/leave script words, or clears the pair.
## 0x006E steps the party: position copies, viewport deltas, the party layer word
## and, when the party actually moves, the two movement owners.
func _command_006E(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	for key in ["world_x", "world_y", "viewport_x", "viewport_y"]:
		if not _i2(globals.get(key)):
			return _failure("party_position", "0x006E requires the explicit world/viewport words", request, source)
	var delta_x: int = _signed(request.words[1])
	var delta_y: int = _signed(request.words[2])
	var layer: int = _signed(request.words[3])
	var viewport_x: int = globals.viewport_x + delta_x
	var viewport_y: int = globals.viewport_y + delta_y
	if not _i2(viewport_x) or not _i2(viewport_y):
		return _failure("checked_i2", "0x006E viewport delta leaves I2 range", request, source)
	var layer_word: int = layer * 8
	if not _i2(layer_word):
		return _failure("checked_i2", "0x006E layer word leaves I2 range", request, source)
	globals.previous_x = globals.world_x; globals.previous_y = globals.world_y
	globals.previous_viewport_x = globals.viewport_x; globals.previous_viewport_y = globals.viewport_y
	globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
	globals.party_layer_word = layer_word
	var moved: bool = delta_x != 0 or delta_y != 0
	var effect: Dictionary = {"kind": "party_step", "delta_x": delta_x, "delta_y": delta_y,
		"viewport_x": viewport_x, "viewport_y": viewport_y, "layer_word": layer_word,
		"moved": moved, "source": source}
	var result: Dictionary = _result(state, request, [effect])
	if moved:
		result.requests = [
			{"kind": POST_MOVE_UPDATE, "original_entry": "0x0041D2CC", "procedure": "PostMoveUpdate"},
			{"kind": UPDATE_VIEWPORT_AND_PARTY, "original_entry": "0x0041CC3C",
				"procedure": "UpdateViewportAndPartyPosition"},
		]
	return result

func _command_006D(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var scene: int = _signed(request.words[1])
	if scene <= 0 or scene > _scene_count:
		return _failure("scene_backing", "0x006D requires a positive runtime scene", request, source)
	if not state.get("events") is Dictionary:
		return _failure("scene_backing", "0x006D requires the loaded scene table", request, source)
	var at: int = (scene - 1) * 8
	var records: PackedByteArray = state.events.scene_records
	if at + 8 > records.size():
		return _failure("scene_backing", "0x006D scene record is outside the loaded table", request, source)
	var enter_word: int = request.words[2]
	var leave_word: int = request.words[3]
	state.events.scene_records = records
	var cleared: bool = enter_word == 0 and leave_word == 0
	if cleared:
		records.encode_u16(at + 2, 0); records.encode_u16(at + 4, 0)
	else:
		if enter_word != 0: records.encode_u16(at + 2, enter_word)
		if leave_word != 0: records.encode_u16(at + 4, leave_word)
	return _result(state, request, [{"kind": "scene_script_words", "scene": scene,
		"enter_word": records.decode_u16(at + 2), "leave_word": records.decode_u16(at + 4),
		"pair_cleared": cleared, "source": source}])

func _command_0077(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var first: int = request.words[1]
	var second: int = request.words[2]
	if first == 0: first = 1
	var requests: Array = []
	if second == 0:
		requests.append({"kind": QUERY_CD_TRACK_PLAYING, "original_entry": "0x0041D224",
			"procedure": "0x0041D224"})
	requests.append({"kind": STOP_CD_OR_MUSIC, "original_entry": "0x0041D254", "procedure": "0x0041D254"})
	var effect: Dictionary = {"kind": "stop_music", "first": first, "second": second,
		"cleared_field_track": false, "source": source}
	var result: Dictionary = _result(state, request, [effect])
	result.requests = requests
	if _signed(state.globals.get("battle_mode", -1)) == 0:
		state.globals.midi_track = 0
		effect.cleared_field_track = true
	return result

## 0x0053/0x0054 select the day (0) and night (384) palette offsets in G026C.
func _command_0053(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _day_night(state, request, source, 0)

func _command_0054(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	return _day_night(state, request, source, 384)

func _command_0046(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var globals: Dictionary = state.globals
	for key in ["party_x", "party_y"]:
		if not _i2(globals.get(key)):
			return _failure("party_anchor", "0x0046 requires the explicit party screen anchor", request, source)
	if not _i2(globals.get("direction_word")):
		return _failure("party_direction", "0x0046 requires the explicit G026E direction word", request, source)
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
			"0x0046 viewport outside the original ffxy bounds; the 0x0041739C clamp is not implemented",
			request, source)
	# G0274/G0276 copy the new world position, so the next frame does not
	# interpolate from the position before this teleport.
	var direction: int = _signed(globals.direction_word)
	if direction < 0 or direction >= FORMATION_STEP_X.size():
		return _failure("party_direction", "0x0046 direction outside the reviewed formation tables", request, source)
	if not state.get("party_records") is Array or state.party_records.size() < 1:
		return _failure("party_backing", "0x0046 requires explicit party records", request, source)
	if not state.get("party_trail") is Array or state.party_trail.size() != TRAIL_SLOTS:
		return _failure("party_trail", "0x0046 requires the explicit five-entry trail array", request, source)
	var leader = state.party_records[0]
	if not leader is Dictionary or not leader.get("current_frame") is int:
		return _failure("party_backing", "0x0046 requires the leader's explicit frame word", request, source)
	globals.world_x = world_x; globals.world_y = world_y
	globals.previous_x = world_x; globals.previous_y = world_y
	globals.viewport_x = viewport_x; globals.viewport_y = viewport_y
	var effect: Dictionary = {"kind": "party_map_position", "world_x": world_x, "world_y": world_y,
		"viewport_x": viewport_x, "viewport_y": viewport_y,
		"previous_x": world_x, "previous_y": world_y, "source": source}
	# Fixed G04AC/G04C4 writes for indices 0..4. Slots without explicit Native
	# backing are reported instead of being invented.
	var member_x: int = globals.party_x; var member_y: int = globals.party_y
	var written: int = 0
	var unbacked: Array = []
	for slot in range(TRAIL_SLOTS):
		if slot < state.party_records.size():
			var record = state.party_records[slot]
			if not record is Dictionary or not record.get("screen_x") is int or not record.get("screen_y") is int:
				return _failure("party_backing", "0x0046 requires explicit member screen positions", request, source)
			record.screen_x = member_x
			record.screen_y = member_y
			record.current_frame = leader.current_frame
			written += 1
		else:
			unbacked.append(slot)
		var trail = state.party_trail[slot]
		if not trail is Dictionary:
			return _failure("party_trail", "0x0046 requires explicit trail entries", request, source)
		trail.x = member_x + viewport_x
		trail.y = member_y + viewport_y
		trail.direction_word = direction
		member_x -= FORMATION_STEP_X[direction]
		member_y -= FORMATION_STEP_Y[direction]
	effect.party_slots = written
	effect.trail_slots = TRAIL_SLOTS
	var missing: Array = []
	if not unbacked.is_empty():
		missing.append({"sub_effect": "G04AC party slots without explicit backing: " + str(unbacked),
			"status": "not_implemented"})
	var result: Dictionary = _result(state, request, [effect], missing)
	if _signed(globals.get("battle_mode", -1)) == 0:
		# The original re-renders the map background after a non-battle teleport.
		result.requests = [{"kind": RENDER_CURRENT_MAP_BACKGROUND, "original_entry": "0x0041CB34",
			"procedure": "RenderCurrentMapBackground", "viewport_x": viewport_x, "viewport_y": viewport_y}]
	return result

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
	# G028A is the party layer word that 0x006E sets to A2*8; this case clears it.
	globals.party_layer_word = 0
	return _result(state, request, [{"kind": "scene_request", "scene": requested,
		"resource_flags": globals.resource_flags, "layer_word": 0, "source": source}])

func _command_0065(state: Dictionary, request: Dictionary, source: Dictionary) -> Dictionary:
	var role: int = request.words[1]
	var sprite: int = request.words[2]
	var reload: int = request.words[3]
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
	var effect: Dictionary = {"kind": "role_map_sprite", "role": role,
		"field_index": ROLE_MAP_SPRITE_FIELD, "sprite_word": sprite, "reload": reload != 0, "source": source}
	var result: Dictionary = _result(state, request, [effect])
	if reload != 0:
		# The original reloads the field sprites outside battle through T99.
		if _signed(state.globals.get("battle_mode", -1)) != 0:
			effect.reloaded = false
			result.unimplemented.append({"sub_effect": "0x0065 reload request suppressed in battle mode",
				"status": "not_implemented"})
			return result
		result.requests = [{"kind": LOAD_PARTY_SPRITES, "original_entry": "0x0041C864",
			"procedure": "LoadPlayerAndFollowerSprites", "roles": _active_roles(state)}]
		effect.reloaded = true
	return result

func _active_roles(state: Dictionary) -> Array:
	if not state.get("equipment") is Dictionary or not state.equipment.get("party_roles") is Array:
		return []
	return state.equipment.party_roles.duplicate()

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
	if not equipment.get("party_roles") is Array:
		return _failure("party_backing", "0x0075 requires the explicit active role projection", request, source)
	for role in roles:
		if role < 0 or role >= ROLES:
			return _failure("party_backing", "0x0075 role argument is outside the source role table", request, source)
	# G04AC is a fixed array: the command writes the active slots and leaves the
	# inactive ones untouched, while the equipment projections follow the active
	# member set that the original T156 call rebuilds.
	if state.party_records.size() < roles.size():
		return _failure("party_backing", "0x0075 needs explicit records for every requested member", request, source)
	for slot in range(roles.size()):
		var existing = state.party_records[slot]
		if not existing is Dictionary or not existing.get("current_frame") is int:
			return _failure("party_backing", "0x0075 needs the slot's explicit frame word", request, source)
		existing.role_id = roles[slot]
	for key in ["party_fields", "party_statuses"]:
		if not equipment.get(key) is Array or equipment[key].size() < roles.size():
			return _failure("party_backing", "0x0075 needs the equipment projection for every member", request, source)
		equipment[key] = equipment[key].slice(0, roles.size())
	equipment.party_roles = roles.duplicate()
	state.globals.member_last = roles.size() - 1
	var effect: Dictionary = {"kind": "party_composition", "roles": roles.duplicate(),
		"member_last": state.globals.member_last,
		"inactive_slots": state.party_records.size() - roles.size(), "source": source}
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
