# SPDX-License-Identifier: MIT
extends SceneTree
const Events = preload("res://src/native_pal98_scene_events.gd")
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")
var failed: int = 0
var checks: Array = []
class FixtureSource extends RefCounted:
	var events: PackedByteArray
	var scenes: PackedByteArray
	func metadata() -> Dictionary: return {"fingerprint": "sprite-request-fixture"}
	func copy_chunk(_role: String, index: int) -> PackedByteArray: return events.duplicate() if index == 0 else scenes.duplicate()

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func with_words(state: Dictionary, fields: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate(true)
	for offset in fields: result.active_slots[0].encode_s16(offset, fields[offset])
	return result

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]) or DirAccess.dir_exists_absolute(args[0]): quit(2); return
	var fixture = FixtureSource.new(); fixture.events.resize(32); fixture.scenes.resize(16); fixture.scenes.encode_u16(14, 1)
	for pair in [[2,160],[4,112],[6,1],[12,1],[16,56],[18,3],[20,2],[22,2]]: fixture.events.encode_s16(pair[0], pair[1])
	var storage = Events.new(); storage.load_source(fixture)
	var state: Dictionary = storage.load_scene_events(storage.source_state(), 1).state
	var before: Dictionary = state.duplicate(true)
	check(Requests.event_requests(storage, state, 1.5, 0).has("error") and Requests.event_requests(storage, state, 0, 1.0).has("error"), "direct event helper rejects floats before integer conversion")
	check(Requests.party_requests(0.5, 0, [], 0).has("error") and Requests.party_requests(-1, 0.0, [], 0).has("error") and Requests.party_requests(-1, 0, [], 0.5).has("error"), "direct party helper rejects floats before integer conversion")
	var selected: Dictionary = Requests.event_requests(storage, state, 0, 0)
	check(selected.value.size() == 1 and selected.value[0].frame_offset == 6 and selected.value[0].layer_base == 8, "T213 frame2 maps to0 for three-frame directions")
	check(Requests.event_requests(storage, with_words(state, {22:3}), 0, 0).value[0].frame_offset == 8, "T213 frame3 maps to2")
	check(Requests.event_requests(storage, with_words(state, {22:4}), 0, 0).value[0].frame_offset == 10, "other current frames are not normalized")
	check(Requests.event_requests(storage, with_words(state, {18:5,20:-1,22:7}), 0, 0).value[0].frame_offset == 2, "signed direction and other frame group are not clamped")
	check(Requests.event_requests(storage, with_words(state, {2:-32768,12:0}), 1, 0).value.is_empty(), "nonpositive State skips coordinate arithmetic")
	check(Requests.event_requests(storage, with_words(state, {2:-32768,16:0}), 1, 0).get("error", "").contains("screen X"), "screen X overflow occurs before zero SpriteId gate")
	check(Requests.event_requests(storage, with_words(state, {4:-32768,16:0}), 0, 1).get("error", "").contains("screen Y"), "screen Y overflow occurs before zero SpriteId gate")
	check(Requests.event_requests(storage, with_words(state, {2:400,6:4096,16:0}), 0, 0).get("error", "").contains("layer"), "layer multiplication occurs before offscreen and SpriteId gates")
	check(Requests.event_requests(storage, with_words(state, {2:-64,4:328}), 0, 0).value.size() == 1 and Requests.event_requests(storage, with_words(state, {2:384,4:0}), 0, 0).value.size() == 1, "event screen filter includes all four endpoints")
	check(Requests.event_requests(storage, with_words(state, {2:385,20:32767}), 0, 0).value.is_empty(), "screen gate occurs before direction multiplication")
	check(Requests.event_requests(storage, with_words(state, {20:32767,16:0}), 0, 0).get("error", "").contains("multiplication"), "direction multiplication occurs before zero SpriteId gate")
	check(Requests.event_requests(storage, with_words(state, {18:1,20:32767,22:1,16:0}), 0, 0).value.is_empty(), "zero SpriteId prevents only final frame addition")
	check(Requests.event_requests(storage, with_words(state, {18:1,20:32767,22:1}), 0, 0).get("error", "").contains("addition"), "positive SpriteId performs checked final addition")
	check(Requests.event_requests(storage, with_words(state, {16:-1}), 0, 0).value.is_empty(), "SpriteId uses signed-positive test")
	var changed_sprite: Dictionary = Requests.event_requests(storage, with_words(state, {16:193}), 0, 0)
	check(changed_sprite.value[0].slot == 1 and changed_sprite.value[0].observed_sprite_id == 193 and not changed_sprite.value[0].has("mgo_chunk"), "draw request preserves cache-slot identity instead of rebinding a changed SpriteId")
	var party: Array = [{"x": -100, "y": -5, "current_frame": 3}, {"x": 160, "y": 112, "current_frame": 9}]
	var party_result: Dictionary = Requests.party_requests(0, 1, party, 4)
	check(party_result.value.size() == 2 and party_result.value[0].screen_x == -100 and party_result.value[0].frame_offset == 3, "T209 preserves offscreen party state and current frame")
	check(not party_result.value[0].follower and party_result.value[1].follower and party_result.value[1].layer_base == 4, "inclusive member upper bound plus follower count selects contiguous slots")
	check(Requests.party_requests(-1, 0, [], 0).value.is_empty(), "negative loop upper bound produces no requests")
	check(Requests.party_requests(32767, 1, [], 0).get("error", "").contains("overflow"), "member/follower addition is checked")
	check(Requests.party_requests(1, 0, [party[0]], 0).get("error", "").contains("unavailable"), "missing owned party backing is diagnosed")
	check(Requests.party_requests(0, 0, [{"x":160,"y":112,"current_frame":null}], 0).has("error"), "Unknown current frame never becomes frame0")
	var caller: Dictionary = {"viewport_x":0,"viewport_y":0,"member_last":0,"follower_count":1,"team_layer":4,"party_records":party}
	var render: Dictionary = Requests.collect("render_scene_frame", storage, state, caller)
	var main: Dictionary = Requests.collect("submain", storage, state, caller)
	check(render.value.map(func(row): return row.kind) == ["event","party","party"] and main.value.map(func(row): return row.kind) == ["party","party","event"], "two original owners preserve distinct request order")
	var unknown_party: Dictionary = caller.duplicate(true); unknown_party.party_records[0].current_frame = null
	var invalid_event: Dictionary = with_words(state, {6:4096})
	check(Requests.collect("render_scene_frame", storage, invalid_event, unknown_party).sprite_kind == "event" and Requests.collect("submain", storage, invalid_event, unknown_party).sprite_kind == "party", "owner order also preserves the first diagnostic source")
	check(Requests.collect("unknown", storage, state, caller).has("error"), "unknown composition owner is not guessed")
	var many: Array = []; many.resize(255); many.fill(party[0])
	check(Requests.party_requests(254, 0, many, 0).value.size() == 255, "maximum safe original depth request count")
	var crowded: Dictionary = caller.duplicate(true); crowded.member_last = 254; crowded.follower_count = 0; crowded.party_records = many
	check(Requests.collect("submain", storage, state, crowded).get("error", "").contains("combined"), "event plus party total observes original depth count limit")
	check(state == before and fixture.events == before.global_events and party[0].current_frame == 3, "request collection never mutates source or caller state")
	var file = FileAccess.open(args[0], FileAccess.WRITE); file.store_string(JSON.stringify({"success":failed==0,"failed":failed,"checks":checks,"original_gameplay":false,"resource_binding_implemented":false}, "\t")); file.close()
	print("Original sprite requests: ",checks.size()," checks, ",failed," failed"); quit(0 if failed==0 else 1)
