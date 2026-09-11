# SPDX-License-Identifier: MIT
extends SceneTree
const Events = preload("res://src/native_pal98_scene_events.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed: int = 0
class FixtureSource extends RefCounted:
	var events: PackedByteArray
	var scenes: PackedByteArray
	func metadata() -> Dictionary: return {"fingerprint": "synthetic-source"}
	func copy_chunk(_name: String, index: int) -> PackedByteArray: return events.duplicate() if index == 0 else scenes.duplicate()

func check(ok: bool, label: String) -> void:
	checks.append({"name": label, "passed": ok})
	if not ok: failed += 1; push_error(label)

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var fixture = FixtureSource.new(); fixture.events.resize(180 * 32); fixture.scenes.resize(5 * 8)
	for at in range(fixture.events.size()): fixture.events[at] = (at * 13 + 7) % 256
	var boundaries: Array = [0, 2, 3, 170, 170]
	for index in range(5): fixture.scenes.encode_u16(index * 8 + 6, boundaries[index])
	var events = Events.new(); check(events.load_source(fixture), "explicit scene/event tables loaded")
	var initial: Dictionary = events.source_state(); var source_bytes: PackedByteArray = initial.global_events.duplicate()
	check(events.validate_state(initial).is_empty() and initial.active_slots.all(func(slot): return slot == null), "unloaded backing is unknown rather than fabricated original zeros")
	check(events.event_record(initial, 1).has("error") and events.commit_current_events(initial).has("error"), "unloaded record reads and writeback diagnose")
	var loaded: Dictionary = events.load_scene_events(initial, 1)
	check(loaded.loaded_count == 2 and loaded.first_global_index == 0 and events.event_record(loaded.state, 1).value == source_bytes.slice(0, 32), "runtime scene1 copies raw scene0 event prefix into one-based slots")
	var edited: PackedByteArray = events.event_record(loaded.state, 1).value; edited[0] ^= 255; edited[31] ^= 85
	var changed: Dictionary = events.replace_event_record(loaded.state, 1, edited).state
	check(events.event_record(loaded.state, 1).value == source_bytes.slice(0, 32) and changed.global_events == source_bytes, "current edits are detached and do not prematurely modify global table")
	var committed: Dictionary = events.commit_current_events(changed)
	check(committed.written_records == 2 and committed.state.global_events.slice(0, 32) == edited and committed.state.global_events.slice(32) == source_bytes.slice(32), "T175 writes exact current prefix including unknown record words")
	var next: Dictionary = events.load_scene_events(committed.state, 2)
	check(next.loaded_count == 1 and events.event_record(next.state, 1).value == source_bytes.slice(64, 96), "next scene loads its own global interval")
	check(events.event_record(next.state, 2).value == source_bytes.slice(32, 64) and not events.event_record(next.state, 2).inside_current_count, "smaller scene preserves known backing beyond current count")
	var empty: Dictionary = events.load_scene_events(next.state, 4)
	check(empty.loaded_count == 0 and empty.state.active_slots == next.state.active_slots and events.commit_current_events(empty.state).state.global_events == next.state.global_events, "zero count preserves backing and commits no bytes")
	var revisit: Dictionary = events.load_scene_events(next.state, 1)
	check(events.event_record(revisit.state, 1).value == edited, "committed event changes survive return to original scene")
	var capped: Dictionary = events.load_scene_events(initial, 3)
	check(capped.raw_count == 167 and capped.loaded_count == 160 and events.event_record(capped.state, 160).value == source_bytes.slice(162 * 32, 163 * 32), "original160-record cap retains exact first160 source records")
	check(events.event_record(capped.state, 161).has("error"), "out-of-owned slot gets diagnostic")
	var clipped_copy: Dictionary = events.commit_current_events(capped.state)
	check(clipped_copy.written_records == 160 and clipped_copy.state.global_events == source_bytes, "capped writeback leaves seven remaining global records and neighbors unchanged")
	var changed_boundary: Dictionary = changed.duplicate(true)
	changed_boundary.scene_records.encode_u16(6, 2); changed_boundary.scene_records.encode_u16(14, 1)
	var count_independent: Dictionary = events.commit_current_events(changed_boundary)
	check(not count_independent.has("error") and count_independent.state.global_events.slice(64, 96) == edited and count_independent.written_records == 2, "T175 ignores even negative next-scene difference and consumes current count/base")
	var negative: Dictionary = initial.duplicate(true); negative.scene_records.encode_u16(6, 3); negative.scene_records.encode_u16(14, 2)
	check(events.load_scene_events(negative, 1).has("error") and negative.global_events == source_bytes, "negative original copy length fails without publishing partial state")
	var overflow: Dictionary = initial.duplicate(true); overflow.scene_records.encode_u16(6, 32768)
	check(events.load_scene_events(overflow, 1).has("error"), "unresolved signed boundary gets explicit diagnostic")
	check(events.load_scene_events(initial, 0).has("error") and events.load_scene_events(initial, 5).has("error"), "zero and terminal-only scene identities rejected")
	var wrong: Dictionary = initial.duplicate(true); wrong.source_fingerprint = "different"
	check(not events.validate_state(wrong).is_empty(), "state from another source cannot be reused")
	var before: Dictionary = events.source_state(); fixture.scenes.resize(7)
	check(not events.load_source(fixture) and events.source_state() == before, "failed source replacement retains previous snapshot")
	var package = Package.new(); check(package.load_package(args[0]), "ordinary authored source package admitted")
	if package.pal98_sources != null: _real_source(package.pal98_sources)
	else: check(false, "ordinary package lacks admitted source tables")
	var file = FileAccess.open(args[1], FileAccess.WRITE)
	file.store_string(JSON.stringify({"success": failed == 0, "failed": failed, "checks": checks, "original_gameplay": false, "original_save_file_written": false}, "\t")); file.close()
	print("Original scene events: ", checks.size(), " checks, ", failed, " failed"); quit(0 if failed == 0 else 1)

func _real_source(source) -> void:
	var owner = Events.new(); check(owner.load_source(source), "real immutable source accepted by runtime event storage")
	var state: Dictionary = owner.source_state(); var original: PackedByteArray = source.copy_chunk("sss", 0)
	var records = source.open_records(); var count: int = records.table_summary().counts.scenes
	var all_equal: bool = true; var total_loaded: int = 0; var last_nonempty: int = 0
	for id in range(1, count + 1):
		var selected: Dictionary = records.scene_for_runtime_id(id).value
		var loaded: Dictionary = owner.load_scene_events(state, id)
		if loaded.has("error"): all_equal = false; break
		state = loaded.state; total_loaded += state.event_count
		if state.event_count > 0: last_nonempty = id
		for slot in range(state.event_count):
			var at: int = (selected.event_start + slot) * 32
			if state.active_slots[slot] != original.slice(at, at + 32): all_equal = false
	check(count == 294 and all_equal and total_loaded > 0, "all294 source scene intervals load exact original record bytes with160 cap")
	state = owner.load_scene_events(state, last_nonempty).state
	var event: PackedByteArray = owner.event_record(state, 1).value; event[31] ^= 128
	state = owner.replace_event_record(state, 1, event).state
	var global_before: PackedByteArray = state.global_events.duplicate(); var committed: Dictionary = owner.commit_current_events(state)
	var selected: Dictionary = records.scene_for_runtime_id(last_nonempty).value; var at: int = selected.event_start * 32
	check(committed.state.global_events.slice(0, at) == global_before.slice(0, at) and committed.state.global_events.slice(at, at + 32) == event and committed.state.global_events.slice(at + 32) == global_before.slice(at + 32), "real current-to-global writeback changes only edited32-byte record")
	var reloaded: Dictionary = owner.load_scene_events(committed.state, last_nonempty)
	check(owner.event_record(reloaded.state, 1).value == event and source.copy_chunk("sss", 0) == original, "real roundtrip retains runtime edit while admitted source is unchanged")
