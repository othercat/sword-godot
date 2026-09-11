# Source-bound PAL98 equipment entry kernel

`src/native_pal98_equipment_kernel.gd` independently executes a bounded subset of
the recovered PAL.EXE equipment-entry behavior. It is an **internal kernel**;
the ordinary Native package loader, session, authored equipment system and save
contracts do not enable it. It does not yet implement the whole `0075` rebuild.

`read_tables` takes explicit DATA3 (900 bytes), Win95/98 SSS2 (14-byte records)
and SSS4 (8-byte records). It retains all role words and fingerprints each table.
The six-role layout is a source format, not a new restriction on Native actors.
Source bytes and receipts are isolated from caller mutation. Failed reads retain
the previous source; states from a different source are rejected.

`run_equipped_entry(state, role, equipment_field)` follows the initializer's
signed-positive item test and uses object WORD3 as a shared **U2** entry reference.
Each call returns a complete candidate or a source/PC/operand diagnostic without
publishing intermediate writes. The supported actions are:

| Action | Behavior |
| --- | --- |
| `0000` | Return the saved entry to the object's equip reference |
| `0017` | Replace one signed modifier in slots11..17, fields17..30 |
| `0018` | Clear that slot's fields17..30 even for the same item, retain the previous item, and assign the new WORD; the opcode itself does not transfer inventory |
| `001A` | Assign an ordinary current-role field, or an explicitly selected role's base field; current-target fields1/65 require party battle records and are currently rejected |

U2 PC increment wraps `FFFF` to zero, exits without fetching record zero and
writes zero back. A zero starting entry also performs no fetch. The 1..1024 step
budget includes executed terminators; exact-budget wrap can complete. Unsupported
instructions, unimplemented side-effect owners and invalid addresses are explicit
failures. Negative `001A` role selectors remain outside the verified subset.

`effective_stat` adds the signed base and seven modifier slots in order, checking
I2 bounds **after each addition**. It has no zero, 100 or 999 clamp; a later
negative modifier cannot undo an earlier overflow. This getter only covers
fields17..30. It does not replace direct HP/MP reads or the six-slot equipment
menu calculation. Base words and derived modifiers stay separate.

`clear_original_modifier_prefix` preserves the recovered initializer's 490-word
clear of the 588-word table, leaving role5's 98-word tail. It does not clear
inventory `AmountInUse`, reset party flags/status8, copy battle sprite/cooperative
skill fields, reload graphics or schedule rendering. These belong to the larger
initializer and must be integrated before claiming an original new game.

The private source check executes all six equipment fields for source roles0,4,5,
and diagnoses the other three roles at their first unsupported side effect. It
checks actual instructions, preserved base words, shared entries, signed results
and source identity with an independent Python inspector. This is kernel evidence,
not an ordinary playable original package, PALDLL observation or device acceptance.

Run the synthetic checks with `godot --headless --path native --script
res://tests/test_pal98_equipment_kernel.gd -- <fresh-output>`. Add the private
fixture JSON as a second argument for real-source checks. Its bounded binary
tables are sibling files; no original resources are committed here. The product
owner's `docs/evidence/original-v161-20260911/verify_equipment_kernel.py` prepares
and independently checks those fixtures from explicitly hashed DATA/SSS inputs.

Behavior provenance: the product's fixed-source `ORIGINAL_ENTRY_CLOSURE.md`,
Pal98Research's role getter, modifier descriptor, `000B..001F` actions, trigger
U2 dispatch and equipment initializer evidence. These are functional facts from
the identified PAL.EXE; they do not establish whether the specified PALDLL build
overrides a path. No parent GPL implementation or recovered procedural source was
copied or translated into this kernel.
