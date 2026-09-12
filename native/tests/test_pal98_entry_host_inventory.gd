# SPDX-License-Identifier: MIT
extends SceneTree
const Host = preload("res://src/native_pal98_entry_host.gd")
const Equipment = preload("res://src/native_pal98_equipment_kernel.gd")
const Inventory = preload("res://src/native_pal98_inventory.gd")
var results: Array = []
func zeros(n: int) -> PackedByteArray:
	var b = PackedByteArray(); b.resize(n); return b
func check(label: String, ok: bool) -> void:
	results.append({"name":label,"passed":ok})
func _initialize() -> void:
	var args = OS.get_cmdline_user_args()
	if args.size() != 1 or FileAccess.file_exists(args[0]): quit(2); return
	var kernel = Equipment.new()
	if not kernel.read_tables(zeros(900),zeros(28),zeros(16)): quit(2); return
	var seed = zeros(1536); seed.encode_u16(0,196); seed.encode_u16(2,3); seed.encode_u16(4,7)
	seed.encode_u16(255*6,197); seed.encode_u16(255*6+2,9); seed.encode_u16(255*6+4,65535)
	var host = Host.new()
	if not host.bind(RefCounted.new(),kernel,seed,[0,0,0,0,0,0]): quit(2); return
	host.bind_inventory(Inventory.new())
	var state = {"equipment":kernel.initial_state([0]),"inventory_bytes":seed.duplicate()}
	var added = host.answer({"kind":"add_inventory_item","state":state,"item":196,"amount":2})
	check("real inventory add succeeds",added.get("completed",false))
	var rebuilt = host.answer({"kind":"rebuild_party_equipment","state":state})
	check("real equipment rebuild succeeds",rebuilt.get("completed",false))
	check("current quantity survives rebuild",state.inventory_bytes.decode_u16(2)==5)
	check("all usage slots clear",state.inventory_bytes.decode_u16(4)==0 and state.inventory_bytes.decode_u16(255*6+4)==0)
	# Inventory.compress_and_return_last_slot moves live records forward; item
	# identity and quantity are invariant, its original slot is not.
	var other_quantity = 0
	for slot in range(256):
		if state.inventory_bytes.decode_u16(slot*6)==197:
			other_quantity += state.inventory_bytes.decode_u16(slot*6+2)
	check("other item quantity survives compression and rebuild",other_quantity==9)
	check("bind input remains unchanged",seed.decode_u16(2)==3 and seed.decode_u16(4)==7)
	var replacement = seed.duplicate(); replacement.encode_u16(2,99)
	state.inventory_bytes = replacement
	var replaced = host.answer({"kind":"rebuild_party_equipment","state":state})
	check("independent current state replaces prior bag",replaced.get("completed",false) and state.inventory_bytes.decode_u16(2)==99)
	check("current input backing not mutated",replacement.decode_u16(4)==7)
	var before_count = host.answered().size()
	for invalid in [null,"not bytes",[0,1,2],zeros(6),zeros(1535),zeros(1537)]:
		var bad = {"equipment":kernel.initial_state([0]),"inventory_bytes":invalid}
		var before = bad.duplicate(true)
		var response = host.answer({"kind":"rebuild_party_equipment","state":bad})
		check("bad inventory is named failure",response.has("error") and "inventory" in str(response.error) and not response.has("state") and not response.get("completed",false))
		check("bad inventory preserves state",bad==before)
	var missing = {"equipment":kernel.initial_state([0])}
	var missing_before = missing.duplicate(true)
	var refused = host.answer({"kind":"rebuild_party_equipment","state":missing})
	check("missing current bag cannot fall back",refused.has("error") and missing==missing_before)
	check("invalid requests have no success receipts",host.answered().size()==before_count)
	var bad_equipment = {"equipment":{},"inventory_bytes":seed.duplicate()}
	var old_equipment = bad_equipment.duplicate(true)
	var failed = host.answer({"kind":"rebuild_party_equipment","state":bad_equipment})
	check("equipment failure preserves current bag and state",failed.has("error") and not failed.has("state") and bad_equipment==old_equipment)
	var passed = results.filter(func(r):return r.passed).size()
	var file = FileAccess.open(args[0],FileAccess.WRITE)
	if file==null: quit(2); return
	file.store_string(JSON.stringify({"passed":passed,"failed":results.size()-passed,"checks":results},"\t"));file.close()
	print("Astra inventory holdout: ",passed,"/",results.size())
	quit(0 if passed==results.size() else 1)
