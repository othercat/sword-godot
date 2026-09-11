# SPDX-License-Identifier: MIT
extends SceneTree
const Cache = preload("res://src/native_pal98_sprite_cache.gd")
const Events = preload("res://src/native_pal98_scene_events.gd")
const Requests = preload("res://src/native_pal98_scene_sprite_requests.gd")
const Package = preload("res://src/native_package.gd")
var checks: Array = []
var failed: int = 0
var real_results: Array = []

class FixtureTables extends RefCounted:
	var events: PackedByteArray
	var scenes: PackedByteArray
	func metadata() -> Dictionary: return {"fingerprint":"fixture-tables", "provenance":{"source_revision":"sha256:fixture-origin"}}
	func copy_chunk(_role: String, index: int) -> PackedByteArray: return events.duplicate() if index == 0 else scenes.duplicate()

class FixtureGraphics extends RefCounted:
	var groups: Dictionary = {}
	func metadata() -> Dictionary: return {"fingerprint":"fixture-graphics", "source_fingerprint":"fixture-origin"}
	func open_records():
		var result = FixtureGraphics.new(); result.groups = groups.duplicate(true); return result
	func raw_chunk(_role: String, index: int) -> Dictionary:
		if not groups.has(index): return {"error":"MGO unavailable"}
		var header = PackedByteArray(); header.resize(4); header.encode_u32(0, groups[index].size())
		return {"value":header, "source":{"file_role":"MGO.MKF", "chunk_index":index, "fingerprint":"fixture-graphics"}}
	func decoded_chunk(role: String, index: int) -> Dictionary:
		var raw: Dictionary = raw_chunk(role, index)
		if raw.has("error"): return raw
		raw.value = groups[index].duplicate(); return raw

func check(ok: bool, label: String) -> void:
	checks.append({"name":label, "passed":ok})
	if not ok: failed += 1; push_error(label)

func image_group(colour: int, length: int = 10) -> PackedByteArray:
	var bytes = PackedByteArray([2,0,0,0,1,0,1,0,1,colour]); bytes.resize(length); return bytes

func tables_for(ids: Array):
	var result = FixtureTables.new(); result.events.resize(ids.size() * 32); result.scenes.resize(16)
	result.scenes.encode_u16(14, ids.size())
	for index in range(ids.size()):
		for pair in [[2,160],[4,112],[12,1],[16,ids[index]],[18,3]]: result.events.encode_s16(index * 32 + pair[0], pair[1])
	return result

func state_for(storage, tables) -> Dictionary:
	storage.load_source(tables); return storage.load_scene_events(storage.source_state(), 1).state

func colour(cache, kind: String, offset: int) -> int:
	var result: Dictionary = cache.resolve(kind, offset, 0)
	return -1 if result.has("error") else result.value.indices[0]

func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 2 or FileAccess.file_exists(args[1]) or DirAccess.dir_exists_absolute(args[1]): quit(2); return
	var tables = tables_for([1,2,1]); var storage = Events.new(); var state: Dictionary = state_for(storage, tables)
	var graphics = FixtureGraphics.new(); graphics.groups = {1:image_group(41),2:image_group(92),3:PackedByteArray()}
	var cache = Cache.new(); check(cache.load_source(graphics, tables), "source origin and owned snapshots admitted")
	check(cache.resolve("event", 0, 0).get("error", "").contains("Unknown"), "unloaded cache is Unknown, not a zero frame")
	var before: Dictionary = state.duplicate(true)
	var loaded: Dictionary = cache.load_events(storage, state)
	check(not loaded.has("error") and loaded.loaded_mgo_chunks == [1,2] and loaded.used_words == 10, "T98 positive groups load once and accumulate WORD counts")
	if loaded.has("error"): finish(args[1]); return
	check(loaded.state.active_slots[0].decode_s16(26) == 0 and loaded.state.active_slots[1].decode_s16(26) == 5 and loaded.state.active_slots[2].decode_s16(26) == 0, "event offsets use WORD units and duplicate binding")
	check(loaded.state.active_slots.slice(0,3).all(func(row): return row.decode_s16(28) == 1), "T98 stores positive directory prefix without subtracting one")
	check(colour(cache, "event", 0) == 41 and colour(cache, "event", 5) == 92 and state == before, "T163 resolves event cache bytes while caller state remains detached")
	var changed: Dictionary = loaded.state.duplicate(true); changed.active_slots[0].encode_s16(16, 2)
	var requests: Dictionary = Requests.event_requests(storage, changed, 0, 0)
	var resolved: Dictionary = cache.resolve_requests(storage, changed, [], requests.value)
	check(resolved.value[0].frame.indices[0] == 41 and resolved.value[0].request.observed_sprite_id == 2, "changing current SpriteId does not rebind loaded event graphics")
	var reloaded: Dictionary = cache.load_events(storage, changed)
	check(not reloaded.has("error") and colour(cache, "event", reloaded.state.active_slots[0].decode_s16(26)) == 92, "explicit reload adopts changed SpriteId")
	var snapshot: Dictionary = cache.snapshot("event"); snapshot.cache.bytes[0] = 255
	check(cache.snapshot("event").cache.bytes[0] == 2, "cache snapshots are detached")
	var no_sprite: Dictionary = loaded.state.duplicate(true); no_sprite.event_count = 1; no_sprite.active_slots[0].encode_s16(16, 0)
	var retained: Dictionary = cache.load_events(storage, no_sprite)
	check(not retained.has("error") and retained.used_words == 0 and retained.state.active_slots[0].decode_s16(28) == 1 and retained.state.active_slots[0].decode_s16(16) == 0, "nonpositive SpriteId still scans old known cache offset")
	var cold = Cache.new(); cold.load_source(graphics, tables)
	check(cold.load_events(storage, no_sprite).get("error", "").contains("Unknown"), "nonpositive SpriteId cannot invent cold cache tail")
	var zero_size: Dictionary = loaded.state.duplicate(true); zero_size.event_count = 2; zero_size.active_slots[1].encode_s16(16, 3)
	var prior_tail: PackedByteArray = cache.snapshot("event").cache.bytes.slice(10)
	var accumulated_gate: Dictionary = cache.load_events(storage, zero_size)
	check(not accumulated_gate.has("error") and accumulated_gate.loaded_mgo_chunks == [1,3] and accumulated_gate.state.active_slots[1].decode_s16(16) == 3 and accumulated_gate.state.active_slots[1].decode_s16(26) == 5, "T98 gate uses accumulated+size, allowing zero-size append with old known tail")
	check(cache.snapshot("event").cache.bytes.slice(10) == prior_tail, "smaller reload preserves older cache bytes instead of clearing tail")
	var zero_first: Dictionary = loaded.state.duplicate(true); zero_first.event_count = 1; zero_first.active_slots[0].encode_s16(16, 3)
	var cleared: Dictionary = cache.load_events(storage, zero_first)
	check(not cleared.has("error") and cleared.loaded_mgo_chunks.is_empty() and cleared.state.active_slots[0].decode_s16(16) == 0 and cleared.state.active_slots[0].decode_s16(28) == 1, "nonpositive first total clears SpriteId then scans unchanged offset")
	var party: Array = [{"role_id":0,"x":160,"y":112,"current_frame":0},{"role_id":1,"x":160,"y":112,"current_frame":0},{"role_id":1,"x":160,"y":112,"current_frame":0}]
	var roles: Array = [1,1]
	var party_load: Dictionary = cache.load_party(1, 1, party, roles)
	check(not party_load.has("error") and party_load.loaded_mgo_chunks == [1,1] and party_load.used_words == 10, "T99 ordinary role-field2 deduplication and direct follower MGO without deduplication")
	check(party_load.party_records.map(func(row): return row.cache_word_offset) == [0,0,5] and not party[0].has("cache_word_offset"), "T99 offsets preserved with detached original party records")
	roles[0] = 2; party_load.party_records[0].role_id = 1
	var party_selected: Dictionary = cache.resolve_requests(storage, loaded.state, party_load.party_records, Requests.party_requests(1,1,party_load.party_records,0).value)
	check(party_selected.value[0].frame.indices[0] == 41, "role field change does not rebind previously loaded party cache")
	check(cache.load_party(-1,0,[],[]).party_records.is_empty(), "negative ordinary upper bound with no follower performs no load")
	check(cache.load_party(-2,1,party,roles).get("runtime_slot") == -1 and cache.load_party(0.0,0,party,roles).has("error"), "negative follower address and float counters diagnose")
	check(cache.load_party(0,0,[{"role_id":null}],roles).has("error") and cache.load_party(0,0,party,[null]).has("error"), "Unknown RoleId or role field2 never defaults to zero")
	check(cache.resolve("event",0.0,0).has("error") and cache.resolve("event",0,null).has("error"), "T163 requires actual known integer cache/frame inputs")
	check(cache.resolve("event",32767,1).get("error", "").contains("table address") and cache.resolve("event",-1,0).has("error"), "T163 checked table address and negative owned-address boundary")
	var event_before: Dictionary = cache.snapshot("event"); var party_before: Dictionary = cache.snapshot("party")
	check(not cache.load_source(null,tables) and cache.snapshot("event") == event_before and cache.snapshot("party") == party_before, "failed source replacement preserves both caches")
	var bad_state: Dictionary = state.duplicate(true); bad_state.source_fingerprint = "different"
	check(cache.load_events(storage,bad_state).has("error") and cache.snapshot("event") == event_before, "cross-source event state is rejected atomically")
	_edge_cases()
	var package = Package.new(); check(package.load_package(args[0]), "ordinary authored source package admitted")
	if package.pal98_sources != null and package.pal98_graphics != null: _real_source(package)
	else: check(false, "ordinary package requires table and graphics snapshots")
	finish(args[1])

func _edge_cases() -> void:
	var tables = tables_for([1,2]); var storage = Events.new(); var state: Dictionary = state_for(storage, tables)
	var graphics = FixtureGraphics.new(); graphics.groups = {1:image_group(13,11),2:image_group(27)}; graphics.groups[1][10] = 77
	var cache = Cache.new(); cache.load_source(graphics,tables)
	var result: Dictionary = cache.load_events(storage,state)
	check(not result.has("error") and result.used_words == 10 and result.state.active_slots[1].decode_s16(26) == 5 and cache.snapshot("event").cache.bytes[10] == 2, "odd decoded length writes terminal byte then next floor-WORD append overwrites it")
	graphics.groups = {1:PackedByteArray([2,0,6,0,7,0,0,0]),2:PackedByteArray([3,0,34,194,0,0])}
	cache.load_source(graphics,tables); result = cache.load_events(storage,state)
	check(not result.has("error") and result.state.active_slots[0].decode_s16(28) == 3 and result.state.active_slots[1].decode_s16(28) == 1, "positive-prefix scanning is neither generic first-word-minus-one nor unsigned-pointer counting")
	graphics.groups = {1:PackedByteArray([1,0,1,0]),2:image_group(27)}
	cache.load_source(graphics,tables); var before: Dictionary = cache.snapshot("event")
	result = cache.load_events(storage,state)
	check(result.get("error", "").contains("Unknown") and cache.snapshot("event") == before, "directory scan past known bytes rejects instead of inventing a zero terminator")
	graphics.groups = {1:PackedByteArray([0,0,0,0]),2:image_group(27)}
	cache.load_source(graphics,tables); result = cache.load_events(storage,state)
	check(not result.has("error") and result.state.active_slots[0].decode_s16(28) == 0 and result.state.active_slots[0].decode_s16(16) == 0, "zero positive-prefix count clears SpriteId")
	graphics.groups = {1:image_group(13,32768),2:image_group(27,32768)}
	cache.load_source(graphics,tables); before = cache.snapshot("event"); result = cache.load_events(storage,state)
	check(result.get("error", "").contains("before unpak") and cache.snapshot("event") == before, "T98 positive accumulation overflow diagnoses before second write and retains published cache")
	var party: Array = [{"role_id":0},{"role_id":1}]; before = cache.snapshot("party")
	result = cache.load_party(1,0,party,[1,2])
	check(result.get("error", "").contains("after unpak") and cache.snapshot("party") == before and not party[0].has("cache_word_offset"), "T99 post-unpak accumulation overflow returns atomic failure instead of original partial effects")
	graphics.groups = {1:image_group(13,65536)}; cache.load_source(graphics,tables)
	result = cache.load_party(0,0,[{"role_id":0}],[1])
	check(not result.has("error") and result.used_words == -32768 and colour(cache,"party",0) == 13, "paksize65536 truncates WORD count to signed-32768 without checked conversion")
	var single: Dictionary = state.duplicate(true); single.event_count = 1; before = cache.snapshot("event")
	result = cache.load_events(storage,single)
	check(result.get("error", "").contains("Unknown") and cache.snapshot("event") == before, "T98 negative truncated total bypasses unpak then diagnoses Unknown old directory")
	graphics.groups[1].encode_s16(0,32767); graphics.groups[1].encode_s16(65534,1); cache.load_source(graphics,tables)
	cache.load_party(0,0,[{"role_id":0}],[1])
	check(cache.resolve("party",0,0).get("error", "").contains("height address"), "T163 reads width then checks frame address plus one before height")
	graphics.groups[1].encode_s16(200,32767); cache.load_source(graphics,tables); cache.load_party(0,0,[{"role_id":0}],[1])
	check(cache.resolve("party",100,0).get("error", "").contains("pointer addition"), "T163 relative pointer plus base uses checked signed16 addition")
	graphics.groups = {1:image_group(13),2:PackedByteArray([253,255,0,0])}; cache.load_source(graphics,tables)
	result = cache.load_party(1,0,party,[1,2])
	check(not result.has("error") and colour(cache,"party",5) == 13, "negative signed relative pointer can select earlier known bytes with a positive base")
	graphics.groups = {1:image_group(13)}; graphics.groups[1].encode_u16(4,32768)
	cache.load_source(graphics,tables); cache.load_party(0,0,[{"role_id":0}],[1])
	check(cache.resolve("party",0,0).get("error", "").contains("pixel budget"), "high-bit original signed dimensions are rejected by bounded RLE admission")
	graphics.groups = {1:PackedByteArray([255,127,0,0])}; cache.load_source(graphics,tables)
	result = cache.load_party(0,0,[{"role_id":0}],[1])
	check(not result.has("error") and cache.resolve("party",0,0).has("error"), "known directory pointer into Unknown cache is not a usable frame")
	var detached = FixtureGraphics.new(); detached.groups = {1:image_group(66)}; cache.load_source(detached,tables)
	detached.groups[1][9] = 99; result = cache.load_party(0,0,[{"role_id":0}],[1])
	check(not result.has("error") and colour(cache,"party",0) == 66, "cache reader owns source snapshot independently of later provider changes")

func _real_source(package) -> void:
	var storage = Events.new(); storage.load_source(package.pal98_sources)
	var initial: Dictionary = storage.load_scene_events(storage.source_state(),1).state
	var reader = package.pal98_graphics.open_records()
	for id in [2,56,193,571]:
		var cache = Cache.new(); check(cache.load_source(package.pal98_graphics,package.pal98_sources), "real source-bound cache: MGO" + str(id))
		# Explicit resource-consumer fixture, not original new-game state.
		var state: Dictionary = initial.duplicate(true); state.event_count = 1
		var fixture_row = PackedByteArray(); fixture_row.resize(32); state.active_slots[0] = fixture_row
		state.active_slots[0].encode_s16(16,id); state.active_slots[0].encode_s16(26,0)
		var loaded: Dictionary = cache.load_events(storage,state)
		check(not loaded.has("error"), "real T98 resource load: MGO" + str(id))
		if loaded.has("error"): continue
		var selected: Dictionary = cache.resolve("event",0,0); var direct: Dictionary = reader.frame("MGO.MKF",id,0)
		check(not selected.has("error") and not direct.has("error") and selected.value.indices == direct.value.indices and selected.value.coverage == direct.value.coverage and selected.value.width == direct.value.width and selected.value.height == direct.value.height, "real cached frame matches independently addressed frame reader: MGO" + str(id))
		var raw: Dictionary = reader.raw_chunk("MGO.MKF",id)
		check(loaded.used_words == (raw.value.decode_u32(0) >> 1) and not selected.value.has("tail"), "real resource WORD count and bounded render payload: MGO" + str(id))
		real_results.append({"mgo_chunk":id,"used_words":loaded.used_words,"event_positive_prefix":loaded.state.active_slots[0].decode_s16(28),"source":raw.source})
		if id == 571:
			check(loaded.state.active_slots[0].decode_s16(28) == 1 and cache.resolve("event",0,1).has("error"), "real MGO571 signed prefix is1 and invalid second pointer stays diagnostic")
	check(package.pal98_sources.metadata().fingerprint == initial.source_fingerprint, "real source table identity remains unchanged")

func finish(path: String) -> void:
	var file = FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"success":failed==0,"failed":failed,"checks":checks,"real_resources":real_results,"explicit_resource_fixture":true,"original_gameplay":false,"mac_amd_acceptance":false},"\t")); file.close()
	print("Original sprite cache: ",checks.size()," checks, ",failed," failed"); quit(0 if failed==0 else 1)
