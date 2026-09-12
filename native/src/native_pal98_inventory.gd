# SPDX-License-Identifier: MIT
extends RefCounted
## T140/T144/T152 inventory arithmetic over the explicit 256-slot 6-byte backing
## (ItemId +0, Amount +2, AmountInUse +4).
##
## `add_item_amount` follows the reviewed AddInventoryItemAmount procedure: a
## nonpositive item id returns immediately, the first living record with the same
## item takes a checked I2 delta, otherwise the first slot with `Amount <= 0`
## receives `Amount = delta`, `ItemId = item` and cleared usage, and a full
## inventory ends silently. The original has no delta default, no 99 cap in the
## add path and no success value; the 99 cap belongs to `compress`.
const SLOTS = 256
const RECORD_BYTES = 6
const AMOUNT_CAP = 99
const ROLES = 6
const ROLE_FIELDS = 75
const SOURCE_PARTY_SLOTS = 3

var error: String = ""

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

static func _u2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= 0 and value <= 65535

func _shape_issue(inventory_bytes) -> String:
	if not inventory_bytes is PackedByteArray or inventory_bytes.size() != SLOTS * RECORD_BYTES:
		return "inventory requires 256 six-byte records"
	return ""

func _failure(message: String) -> Dictionary:
	error = "pal98-inventory: " + message
	return {"error": error}

static func _signed(value: int) -> int:
	return value - 65536 if value > 32767 else value

func _amount(inventory: PackedByteArray, slot: int) -> int:
	return inventory.decode_s16(slot * RECORD_BYTES + 2)

func _item(inventory: PackedByteArray, slot: int) -> int:
	return inventory.decode_s16(slot * RECORD_BYTES)

## T144: the highest matching living slot, or -1. The original keeps scanning
## after a match, so later duplicates win.
func find_last_active_slot(inventory_bytes: PackedByteArray, item_id: int) -> Dictionary:
	var issue: String = _shape_issue(inventory_bytes)
	if not issue.is_empty(): return _failure(issue)
	var result: int = -1
	for slot in range(SLOTS):
		if _amount(inventory_bytes, slot) > 0 and _item(inventory_bytes, slot) == item_id:
			result = slot
	return {"value": result}

## T140: add a signed amount to the first living match or the first free slot.
func add_item_amount(inventory_bytes: PackedByteArray, item_id: int, delta: int) -> Dictionary:
	var issue: String = _shape_issue(inventory_bytes)
	if not issue.is_empty(): return _failure(issue)
	if not _i2(item_id) or not _i2(delta): return _failure("inventory add requires signed I2 arguments")
	if item_id <= 0:
		return {"inventory_bytes": inventory_bytes.duplicate(), "mode": "ignored", "slot": -1, "amount": 0}
	var candidate: PackedByteArray = inventory_bytes.duplicate()
	for slot in range(SLOTS):
		if _amount(candidate, slot) > 0 and _item(candidate, slot) == item_id:
			var total: int = _amount(candidate, slot) + delta
			if not _i2(total):
				return _failure("checked I2 inventory amount overflow at slot " + str(slot))
			candidate.encode_s16(slot * RECORD_BYTES + 2, total)
			return {"inventory_bytes": candidate, "mode": "merged", "slot": slot, "amount": total}
	for slot in range(SLOTS):
		if _amount(candidate, slot) <= 0:
			candidate.encode_s16(slot * RECORD_BYTES, item_id)
			candidate.encode_s16(slot * RECORD_BYTES + 2, delta)
			candidate.encode_s16(slot * RECORD_BYTES + 4, 0)
			return {"inventory_bytes": candidate, "mode": "created", "slot": slot, "amount": delta}
	return {"inventory_bytes": candidate, "mode": "no_space", "slot": -1, "amount": 0}

## T152: clamp amounts above 99, move living records to the front with the
## original swap sequence and return the last living slot (-1 when empty).
func compress_and_return_last_slot(inventory_bytes: PackedByteArray) -> Dictionary:
	var issue: String = _shape_issue(inventory_bytes)
	if not issue.is_empty(): return _failure(issue)
	var candidate: PackedByteArray = inventory_bytes.duplicate()
	var selectable: Array = []
	for source in range(SLOTS):
		var amount: int = _amount(candidate, source)
		if amount > AMOUNT_CAP:
			candidate.encode_s16(source * RECORD_BYTES + 2, AMOUNT_CAP)
			amount = AMOUNT_CAP
		if amount <= 0: continue
		selectable.append(source)
	var last: int = selectable.size() - 1
	for target in range(selectable.size()):
		var source_slot: int = selectable[target]
		if source_slot == target: continue
		for byte in range(RECORD_BYTES):
			var temporary: int = candidate[target * RECORD_BYTES + byte]
			candidate[target * RECORD_BYTES + byte] = candidate[source_slot * RECORD_BYTES + byte]
			candidate[source_slot * RECORD_BYTES + byte] = temporary
	return {"inventory_bytes": candidate, "last_slot": last, "moved": selectable.size()}

## Validate the Native backing before counting or preparing a removal. The
## original loops through every member 0..member_last; a missing projection
## cannot be replaced with a shorter loop or a partially applied inventory.
func _role_words_issue(role_words: Array) -> String:
	if role_words.size() != ROLES * ROLE_FIELDS:
		return "equipment requires the complete 450-WORD role table"
	for word in role_words:
		if not _u2(word): return "equipment role word is outside U2"
	return ""

func _equipment_issue(role_words: Array, party_roles: Array, member_last: int) -> String:
	var issue: String = _role_words_issue(role_words)
	if not issue.is_empty(): return issue
	if party_roles.is_empty() or party_roles.size() > SOURCE_PARTY_SLOTS:
		return "equipment requires a legacy 1..3-member role projection"
	if member_last < 0 or member_last >= SOURCE_PARTY_SLOTS or member_last >= party_roles.size():
		return "equipment role projection does not cover the active member range"
	var seen: Array = []
	for slot in range(member_last + 1):
		var role = party_roles[slot]
		if not _i2(role) or role < 0 or role >= ROLES or role in seen:
			return "equipment active role identity is invalid or repeated"
		seen.append(role)
	return ""

## T153: the copies of the item across the active members' six equipment fields
## (11..16), addressed field*6+role through the party projection over the
## members 0..member_last.
func count_equipped_copies(item_id: int, role_words: Array, party_roles: Array, member_last: int) -> Dictionary:
	if not _i2(item_id): return _failure("equipment count requires a signed I2 item")
	var issue: String = _equipment_issue(role_words, party_roles, member_last)
	if not issue.is_empty(): return _failure(issue)
	var total: int = 0
	for slot in range(member_last + 1):
		var role = party_roles[slot]
		for field in range(11, 17):
			var word: int = field * ROLES + role
			if _signed(role_words[word]) == item_id: total += 1
	return {"value": total}

## T173: the amount of the last active inventory slot for the item (duplicates
## never sum) plus the equipped copies, combined with a checked I2 add.
func count_item_inventory_and_equipment(inventory_bytes: PackedByteArray, item_id: int,
		role_words: Array, party_roles: Array, member_last: int) -> Dictionary:
	var issue: String = _shape_issue(inventory_bytes)
	if not issue.is_empty(): return _failure(issue)
	var last = find_last_active_slot(inventory_bytes, item_id)
	if last.has("error"): return last
	var total: int = _amount(inventory_bytes, last.value) if last.value >= 0 else 0
	var equipped: Dictionary = count_equipped_copies(item_id, role_words, party_roles, member_last)
	if equipped.has("error"): return equipped
	var combined: int = total + equipped.value
	if not _i2(combined): return _failure("checked I2 combined count overflow")
	return {"value": combined}

## T135: remove up to `remove_count` copies. While remaining, each matching
## record decrements its in-use field by the current remaining with a checked
## I2 subtract clamped below zero, then either reduces the amount (enough
## stock) or clears the exhausted record. Each shortage copy clears the first
## matching field 11..16 equipped copy over the active members. A failure
## applies nothing.
func remove_inventory_item_and_unequip_shortfall(inventory_bytes: PackedByteArray, item_id: int,
		remove_count: int, role_words: Array, party_roles: Array, member_last: int) -> Dictionary:
	var issue: String = _shape_issue(inventory_bytes)
	if not issue.is_empty(): return _failure(issue)
	if not _i2(item_id) or not _i2(remove_count): return _failure("inventory remove requires signed I2 arguments")
	issue = _equipment_issue(role_words, party_roles, member_last)
	if not issue.is_empty(): return _failure(issue)
	var candidate: PackedByteArray = inventory_bytes.duplicate()
	var words: Array = role_words.duplicate()
	var remaining: int = remove_count
	var consumed: int = 0
	for record in range(SLOTS):
		if remaining <= 0: break
		if _item(candidate, record) != item_id or _amount(candidate, record) <= 0: continue
		var left: int = candidate.decode_s16(record * RECORD_BYTES + 4) - remaining
		if not _i2(left): return _failure("checked I2 in-use decrement overflow at slot " + str(record))
		candidate.encode_s16(record * RECORD_BYTES + 4, maxi(left, 0))
		var amount: int = _amount(candidate, record)
		if amount >= remaining:
			candidate.encode_s16(record * RECORD_BYTES + 2, amount - remaining)
			consumed += remaining
			remaining = 0
		else:
			remaining -= amount
			consumed += amount
			candidate.encode_s16(record * RECORD_BYTES, 0)
			candidate.encode_s16(record * RECORD_BYTES + 2, 0)
	var unequipped: int = 0
	for copy in range(maxi(remaining, 0)):
		var cleared: bool = false
		for slot in range(member_last + 1):
			var role = party_roles[slot]
			for field in range(11, 17):
				var word: int = field * ROLES + role
				if _signed(words[word]) == item_id:
					words[word] = 0
					unequipped += 1
					cleared = true
					break
			if cleared: break
	return {"inventory_bytes": candidate, "role_words": words, "consumed": consumed,
		"unequipped": unequipped, "shortage_left": maxi(remaining, 0)}

## 0x0023 unequip: for each field in first_field..last_field the absolute
## role's word field*ROLES+role holds a signed item id. A word above zero is
## returned through T140 add (+1: merge into the first living match, else the
## first free slot, silently full) and the field is cleared; words at or below
## zero stay untouched. The candidate publishes only after the whole sweep, so
## a checked overflow on any add applies nothing.
func unequip_fields_to_inventory(inventory_bytes: PackedByteArray, role: int,
		first_field: int, last_field: int, role_words: Array) -> Dictionary:
	var issue: String = _shape_issue(inventory_bytes)
	if not issue.is_empty(): return _failure(issue)
	issue = _role_words_issue(role_words)
	if not issue.is_empty(): return _failure(issue)
	if role < 0 or role >= ROLES or first_field < 0 or last_field >= ROLE_FIELDS or first_field > last_field:
		return _failure("equipment role or field range is outside the word table")
	var candidate: PackedByteArray = inventory_bytes.duplicate()
	var words: Array = role_words.duplicate()
	var returned: Array = []
	for field in range(first_field, last_field + 1):
		var word: int = field * ROLES + role
		if word >= words.size(): return _failure("equipment fields outside the word table")
		var item: int = _signed(words[word])
		if item <= 0: continue
		var added: Dictionary = add_item_amount(candidate, item, 1)
		if added.has("error"): return added
		candidate = added.inventory_bytes
		returned.append({"field": field, "item": item, "mode": added.mode})
		words[word] = 0
	return {"inventory_bytes": candidate, "role_words": words, "returned": returned}
