# SPDX-License-Identifier: MIT
extends RefCounted
## Answers the EnterScript owner's command-owner requests with the real Native
## owners: `load_party_sprites` goes to the T98/T99 sprite cache and
## `rebuild_party_equipment` to the T156 equipment kernel. Requests that belong
## to a display, audio or save owner are forwarded to an explicitly bound owner
## or refused by name; this module never acknowledges work it did not do.
##
## It binds already-loaded owners, so the caller keeps ownership of the source
## snapshot, the cache fork and the inventory backing.
const ROLE_FIELDS = 75
const ROLE_SPRITE_FIELD = 2
const Inventory = preload("res://src/native_pal98_inventory.gd")

var error: String = ""
var _cache
var _equipment
var _inventory: PackedByteArray = PackedByteArray()
var _role_sprite_ids: Array = []
var _display_owner
var _inventory_owner
var _answered: Array = []

## `role_sprite_ids` is the per-role map sprite projection (G079C[role,2]).
func bind(cache, equipment, inventory_bytes: PackedByteArray, role_sprite_ids: Array) -> bool:
	if cache == null or equipment == null:
		error = "pal98-entry-host: sprite cache and equipment kernel required"; return false
	if inventory_bytes.size() != 1536:
		error = "pal98-entry-host: inventory requires 256 six-byte records"; return false
	if role_sprite_ids.size() < 6:
		error = "pal98-entry-host: six role sprite words required"; return false
	for sprite in role_sprite_ids:
		if typeof(sprite) != TYPE_INT or sprite < 0 or sprite > 65535:
			error = "pal98-entry-host: role sprite word outside U2"; return false
	_cache = cache; _equipment = equipment; _inventory = inventory_bytes.duplicate()
	_role_sprite_ids = role_sprite_ids.duplicate(); _answered = []; error = ""
	return true

## Optional explicit owner for the render/restore/audio requests. A caller that
## binds a test double must say so; the adapter does not create one itself.
func bind_display(owner) -> void:
	_display_owner = owner

## Optional real inventory owner for the 0x001F chain. Without it those requests
## are refused by name instead of being acknowledged.
func bind_inventory(owner) -> void:
	_inventory_owner = owner

func answered() -> Array:
	return _answered.duplicate(true)

func _failure(message: String) -> Dictionary:
	error = "pal98-entry-host: " + message
	return {"error": error}

func _state_of(request: Dictionary) -> Dictionary:
	if not request.get("state") is Dictionary: return _failure("owner request requires the pending state")
	return request.state

func _role_map_sprites(equipment: Dictionary) -> Dictionary:
	if not equipment.get("role_words") is Array or equipment.role_words.size() != 6 * ROLE_FIELDS:
		return _failure("role word table shape")
	var ids: Array = []
	for role in range(6):
		var word = equipment.role_words[role * ROLE_FIELDS + ROLE_SPRITE_FIELD]
		if typeof(word) != TYPE_INT or word < 0 or word > 65535:
			return _failure("role sprite word is not a WORD")
		ids.append(word)
	return {"ids": ids}

## Returns the response dictionary for `native_pal98_enter_script.gd.resume`.
func answer(request: Dictionary) -> Dictionary:
	if not request is Dictionary or not request.get("kind") is String:
		return _failure("owner request shape")
	var state: Dictionary = _state_of(request)
	if state.has("error"): return state
	match request.kind:
		"load_party_sprites":
			var globals: Dictionary = state.get("globals", {})
			if not globals.get("member_last") is int or not globals.get("follower_count") is int:
				return _failure("party counters are not explicit")
			var sprites: Dictionary = _role_map_sprites(state.get("equipment", {}))
			if sprites.has("error"): return sprites
			var loaded: Dictionary = _cache.load_party(globals.member_last, globals.follower_count,
				state.party_records, sprites.ids)
			if loaded.has("error"): return _failure(str(loaded.error))
			state.party_records = loaded.party_records
			_answered.append({"kind": request.kind, "loaded_mgo_chunks": loaded.loaded_mgo_chunks,
				"used_words": loaded.used_words, "role_sprite_ids": sprites.ids})
			return {"completed": true, "state": state}
		"rebuild_party_equipment":
			var prepared: Dictionary = _equipment.prepare_party_equipment(state.get("equipment", {}), _inventory)
			if prepared.has("error"): return _failure(str(prepared.error))
			state.equipment = prepared.state
			state.inventory_bytes = prepared.inventory_bytes
			_answered.append({"kind": request.kind, "party_roles": prepared.state.party_roles.duplicate()})
			return {"completed": true, "state": state}
		"add_inventory_item":
			if _inventory_owner == null:
				return _failure("no inventory owner bound for " + request.kind)
			var compressed: Dictionary = _inventory_owner.compress_and_return_last_slot(state.inventory_bytes)
			if compressed.has("error"): return _failure(str(compressed.error))
			var added: Dictionary = _inventory_owner.add_item_amount(compressed.inventory_bytes,
				request.get("item", 0), request.get("amount", 1))
			if added.has("error"): return _failure(str(added.error))
			state.inventory_bytes = added.inventory_bytes
			_answered.append({"kind": request.kind, "mode": added.mode, "slot": added.slot,
				"amount": added.amount, "last_slot": compressed.last_slot})
			return {"completed": true, "state": state}
	if _display_owner != null and _display_owner.has_method("answer"):
		var forwarded: Dictionary = _display_owner.answer(request)
		_answered.append({"kind": request.kind, "forwarded": true})
		return forwarded
	return _failure("no owner bound for " + request.kind)
