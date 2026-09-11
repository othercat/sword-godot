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

The current internal profile is `pal98.equipment-entry-subset.v2`. Its fingerprint
includes that version; the older five-field kernel state is not silently reused.
`initial_state([role_ids])` declares a 1..3-member source party with distinct roles
for this subset; repeated-role party commands are not implemented. All six disk roles
can be selected, including role5 in party slot0. Party status rows use **party slot**
identity, while base fields and modifiers use **role** identity. The two known
party temporaries are represented by `battle_sprite_word` and
`cooperative_magic_word`, corresponding to byte offsets0 and22 of G05CC. Their
projection does not claim an unknown full record stride or confuse byte22 with
WORD22. This internal state is not a public Native save format.

`run_equipped_entry(state, role, equipment_field)` follows the initializer's
signed-positive item test and uses object WORD3 as a shared **U2** entry reference.
Each call returns a complete candidate or a source/PC/operand diagnostic without
publishing intermediate writes. The supported actions are:

| Action | Behavior |
| --- | --- |
| `0000` | Return the saved entry to the object's equip reference |
| `0017` | Replace one signed modifier in slots11..17, fields17..30 |
| `0018` | Clear that slot's fields17..30 even for the same item, retain the previous item, and assign the new WORD; the opcode itself does not transfer inventory |
| `001A` | Assign an ordinary current-role field, or an explicitly selected role's base field; current-target fields1/65 instead update the current party projection |
| `002D` | For non4 status, replace signed duration when `(status>4 or old<=0) and old<requested`; Arg2 is unused. Status4 with positive signed HP leaves its duration and clears trigger success. Status4 with nonpositive HP explicitly requires the missing render/RNG owner |

U2 PC increment wraps `FFFF` to zero, exits without fetching record zero and
writes zero back. A zero starting entry also performs no fetch. The 1..1024 step
budget includes executed terminators; exact-budget wrap can complete. Unsupported
instructions, unimplemented side-effect owners and invalid addresses are explicit
failures. Negative `001A` role selectors remain outside the verified subset.
The trigger caller sets its success word to-1 even for starting PC zero; skipped
nonpositive item IDs do not call it. Non4 `002D` does not change this word, including
when it retains an existing duration. Status4's living-role failure sets zero,
and a later non4 action in the same entry does not turn that back into success.
For nonpositive HP, status4 requires four rendered frames, shared RNG and a
temporary frame write/reset; this kernel rejects that entire entry before
publishing any state instead of reducing it to a duration assignment.

`effective_stat` adds the signed base and seven modifier slots in order, checking
I2 bounds **after each addition**. It has no zero, 100 or 999 clamp; a later
negative modifier cannot undo an earlier overflow. This getter only covers
fields17..30. It does not replace direct HP/MP reads or the six-slot equipment
menu calculation. Base words and derived modifiers stay separate.

`clear_original_modifier_prefix` preserves the recovered initializer's 490-word
clear of the 588-word table, leaving role5's 98-word tail. It does not clear
inventory `AmountInUse`. `rebuild_party_equipment` then processes each member in
order: clear that role's field4, copy base fields1/65 into its party projection,
clear the party slot's status8, and execute its six equipment entries before
preparing the next member. Earlier equipment can therefore change a later member's
base before its copy. The complete rebuild returns one candidate or a member/PC
diagnostic, rolling back all earlier members on failure. Inventory use counts,
graphics reload, trails and rendering still belong to the larger initializer and
must be integrated before claiming an original new game.

The private source check executes all six equipment fields for each of six source
roles in its own single-member party. All complete the supported subset, including
role1 status8, role2's base flag and temporary battle sprite, and role3's temporary
cooperative skill. It checks actual instructions, base/modifier separation, shared
entries, signed results, party projections and source identity with an independent
Python inspector. This is kernel evidence,
not an ordinary playable original package, PALDLL observation or device acceptance.

Run the synthetic checks with `godot --headless --path native --script
res://tests/test_pal98_equipment_kernel.gd -- <fresh-output>`. Add the private
fixture JSON as a second argument for real-source checks. Its bounded binary
tables are sibling files; no original resources are committed here. The product
owner's `docs/evidence/original-v161-20260911/verify_equipment_kernel.py prepare
--party-context ...` prepares the current v3 private binary fixtures from explicitly
hashed DATA/SSS inputs. Its `verify` command also retains inspection of the earlier
v2 fixtures and v1-kernel evidence; these are different state/profile combinations.

Behavior provenance: the product's fixed-source `ORIGINAL_ENTRY_CLOSURE.md`,
Pal98Research's role getter, modifier descriptor, `000B..001F` actions, trigger
U2 dispatch and equipment initializer evidence. These are functional facts from
the identified PAL.EXE; they do not establish whether the specified PALDLL build
overrides a path. No parent GPL implementation or recovered procedural source was
copied or translated into this kernel.
