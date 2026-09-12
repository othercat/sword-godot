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

var error: String = ""

static func _i2(value) -> bool:
	return typeof(value) == TYPE_INT and value >= -32768 and value <= 32767

func _shape_issue(inventory_bytes) -> String:
	if not inventory_bytes is PackedByteArray or inventory_bytes.size() != SLOTS * RECORD_BYTES:
		return "inventory requires 256 six-byte records"
	return ""

func _failure(message: String) -> Dictionary:
	error = "pal98-inventory: " + message
	return {"error": error}

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
