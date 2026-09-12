# Original EnterScript owner and the reviewed entry commands

`src/native_pal98_enter_script.gd` answers the `enter_script` request that
`native_pal98_resource_reload.gd` raises for the T212 chain. It is the real
caller of the reviewed T258 control flow over the admitted SSS4 instruction
pool: it re-reads the scene record, runs the entry script from that entry word,
consumes the T240 commands it can execute, relays the remaining host effects,
and returns the ByRef entry plus the updated state.

`src/native_pal98_script_commands.gd` is the bounded T240
`ExecuteScriptCommand` consumer for the commands the ordinary scene-entry path
needs first. It changes explicit state for the implemented cases and ends the
invocation with a named diagnostic for every other command; it never turns an
unknown command into a silent no-op.

Neither module activates an ordinary Session. There is no rendering, audio,
save, input or map-cache work here, and `native_session.gd` keeps its
source-only preview guard.

## What the caller does

`load_source(source)` binds the admitted source once: the addressed record
reader, the scene-event storage, the T258 driver and the T240 consumer. A
failed replacement keeps the previous snapshot.

`start(state, scene_id, entry, event_id)`:

1. Requires an explicit state with `globals`, `events`, `dialogue`, `rng`,
   `party_records` and `equipment`. Nothing is inferred from a cold start.
2. Resolves `scene_id` through the source scene table and requires the loaded
   scene record's enter word (`scene_records[(scene-1)*8+2]`) to equal the
   requested entry. That record is what T212 read and what T212 writes the ByRef
   result back into, so it — not the immutable source record — is the authority.
   The source value is kept in the receipt for review.
3. Runs `native_pal98_trigger.gd` from that entry and advances it:
   - an `execute_command` request is consumed by the T240 consumer and the
     trigger resumes with the returned state, entry and event context;
   - every other request (dialogue and future host effects) is relayed outward
     with this owner's own request id, and `resume()` forwards the host's
     completion to the trigger.
4. On terminal success returns `{state, return_entry, return_event_id, steps,
   scene, scene_source, effects, unimplemented, trace}`. The caller adopts the
   state and entry only then; a failure publishes no candidate and leaves the
   caller's state untouched.

The ByRef entry keeps the original opcode semantics, which the checks pin:
opcode `0001` increments the already advanced entry once more before exiting,
while opcode `0000` restores the saved entry.

## Implemented T240 commands

The facts below come from the product's fixed-source review of PAL.EXE SHA256
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`. This work
package re-hashed each cited case range from the local private copy of that
executable before writing the code (see the evidence section) and used the real
source bytes for every operand.

| Opcode | P-Code case | Effect implemented here |
| --- | --- | --- |
| `0x0015` | `0x0042149E..0x004214DC` | `G026E = A0`; the party record `A2` frame word becomes `G026E*3 + A1` with checked I2 arithmetic |
| `0x003B` | `0x0042322E..0x00423272` | dialog globals: mode 0, text origin (80,40) |
| `0x003D` | `0x0042331A..0x004233C2` | lower dialog globals: mode 2, title (12,108), body origin (44,126) |
| `0x0041` | `0x004234D6..0x004234F0` | `G0302 = 0` |
| `0x0046` | `0x00423834..0x004239F4` | world position `((2*A0+A2)*16, (2*A1+A2)*8)`, previous-position copies, viewport `world - (party_x, party_y)`, the fixed five-slot party/trail writes and the non-battle background replay |
| `0x0048` | `0x00423A16..0x00423A2C` | explicit original no-op |
| `0x0059` | `0x004243B8..0x00424408` | for a valid changed scene: `G0306 |= 12`, `G026A = A0` |
| `0x0065` | `0x0042477E..0x004247CC` | role `A0` map sprite field index 2 of the admitted role table becomes `A1` |
| `0x0075` | `0x004255D8..0x0042568C` | rebuilds the active party from `A0..A2` (a nonpositive first argument selects role 0, later nonpositive arguments end the list), writes the member count and both role projections, then requests the sprite and equipment owners |
| `0x008E` | `0x004264EE..0x00426506` | clears both dialog gates and requests the host's `RestoreDialogBackground` (`0x0041D2B4`) before the trigger resumes |

Three boundaries are stated rather than hidden:

- `0x0046` is implemented for the world/previous/viewport words only. The
  original rewrites the fixed `G04AC` party records for indices `0..4`; Native
  writes the slots it has explicit backing for and reports the rest as a named
  gap, because slots beyond the active party are not consumed by any reviewed
  owner yet.
- `0x0059` records that the unnamed `G028A = 0` write has no reviewed Native
  field; the mask and requested scene are applied, and the gap is reported.
- `0x003B` writes the three reviewed dialog globals and reports the `G022A`
  colour word as a named gap instead of guessing its value; `0x003D` applies its
  geometry and reports the `0x0041D29C` capture and `0x0041D44C` layout calls,
  because the opening passes zero arguments and the documented effect for that
  case is the fixed geometry with no portrait or colour change.

`0x0065` with a nonzero reload argument fails explicitly: outside-battle sprite
loading belongs to the sprite-cache owner and is not implemented here.

`0x0075` applies its composition, then hands the original callees to the caller
as owner requests: `load_party_sprites` (T99 `0x0041C864`,
`LoadPlayerAndFollowerSprites`) and `rebuild_party_equipment` (T156
`0x0041D374`, `InitializePartyBattleAndEquipmentState`). The trigger stays
suspended until each request is answered with an explicit completion, so the
real sprite cache and equipment kernel do the work rather than the consumer.
The third callee, T230 `0x0041D2E4` `SyncMembersFromTrail`, has no Native owner
yet and is reported as a named sub-effect gap while the composition still
applies.

The next named gap is `0x003B` (`mode0`, text origin 80/40), followed by
`0x003D`, `0x008E` and the rest of the opening's text commands. Every diagnostic
carries that opcode, the real instruction words, the admitted instruction
receipt and the cited case range/hash when it is known.
`0x0002/0x0003/0x0004/0x0006/0x0007/0x0009/0x000A` and `0xFFFF` are dispatched
by T258 itself and return through the consumer untouched, as the original shared
tail does; a run's trace shows those `dispatch_tail` receipts explicitly.

## Real opening entry

The admitted source's runtime scene 1 is raw scene 0: map word 20, enter word 4
and an empty event range. Instruction 4 is `0046 0020 0040 0000`, followed by
`0065 0000 00C1 0000`, `0015 0000 0000 0000` and `0075 0001 0000 0000`. Running
that entry through this owner produces, in original order:

1. `party_map_position`: world `(1024,1024)`, viewport `(864,912)`;
2. `role_map_sprite`: role 0 sprite word 193;
3. `party_direction_frame`: direction 0, frame 0;

`0075 0001 0000 0000` then rebuilds the single-member party (role 0) and requests
the sprite and equipment owners. The entry continues through the local `0005`
control, `003B`, the five `FFFF` messages, `003D`, `008E` and `0059 0002`, and
returns with opcode `0000`. The run therefore:

1. applies the real world/viewport, role sprite, frame and party rebuild;
2. relays five dialogue invocations and the `008E` background restore to the host;
3. asks runtime scene 2 with `G0306 |= 12`;
4. returns ByRef entry 4, which the T212 caller writes back into the loaded scene
   record before restarting the resource chain for scene 2.

Feeding that result back into `native_pal98_resource_reload.gd` restarts the
chain (second `entry`), commits scene 1's events, loads scene 2's event backing
and map identity, and then stops on the documented sprite-cache boundary:
`original sprite cache bytes are Unknown`. That cold-start backing is the next
real blocker after the entry script itself; the text and scene-request commands
are no longer the stop point.

## Evidence

### Real owner adapter (2026-09-12, commit after 7cb3199)

`native_pal98_entry_host.gd` answers the EnterScript owner's command-owner
requests with the real Native owners instead of an echoing test double:

- `load_party_sprites` calls `native_pal98_sprite_cache.gd.load_party` with the
  state's counters, the fixed party records and the role sprite projection that
  `0x0065` just wrote, and returns the updated records;
- `rebuild_party_equipment` calls the T156 equipment kernel's
  `prepare_party_equipment` with the state's equipment block and inventory
  backing, and returns both updated blocks;
- requests belonging to a display, audio or save owner are forwarded to an
  explicitly bound owner or refused by name, so a test double must be declared
  by the caller and the adapter never acknowledges work it did not do.

The ordinary opening chain now runs through those real owners: role 0's map
sprite 193 (written by `0x0065`) loads from MGO into the T98/T99 cache
(4893 words), the T156 kernel clears all 256 inventory usage fields and rebuilds
the member equipment state, and the display double records the
`render_current_map_background`, `restore_dialog_background` and scene-frame
requests. 85 checks pass; the sprite/equipment results are asserted from the
adapter's own receipts rather than from the host's acknowledgements.

### Dialogue host (2026-09-12)

`native_pal98_dialogue_host.gd` answers the T258 dialogue caller's requests and
keeps the real text: `draw_string`/`draw_glyph` runs are decoded with the
admitted CP936/CP950 codec (the caller's trailing NUL load sentinel is stripped
before decoding), the other draw/capture/restore requests are recorded, and
`poll_input`/`wait` follow an explicitly declared input policy and an explicit
tick counter. It renders nothing and polls no device, so pixels, physical input
and a wall clock stay with their owners.

With this host bound, the ordinary opening's five messages run through the real
decoder: the typewriter path emits per-glyph draws with decoded codepoints and
the title path draws message 1 as one whole string whose composed text equals
the decoded source bytes. 91 checks pass.

### Full T212 cycle (2026-09-12)

The suite also drives one complete `native_pal98_resource_reload.gd` cycle over
the admitted sources with this owner answering the entry request: events load,
the scene map decodes, event sprites load, the background request is answered,
the party sprites load through the real cache, the entry script runs through the
real owner adapter and dialogue host, the MIDI request is answered, and the real
equipment kernel prepares the party before the cycle completes with
`resource_flags == 0`. The scene record is redirected to a real minimal entry
block so the cycle stays on implemented commands; the sources, graphics and
instruction bytes are the admitted originals.

A second scenario drives the same chain through a **scene-request restart**: the
first scene's entry is a real `0059 0002` block from the admitted pool, so the
script asks for scene 2 with `G0306 |= 12`; the chain commits scene 1's events,
loads scene 2's (redirected empty) event range and map identity, runs scene 2's
own entry script through the same real owners, and finishes with
`current_scene == requested_scene == 2` and a consumed mask. Both entry scripts
appear in the trace and their applied effects are recorded per run. 103 checks
pass in the working tree.

### Decoded facts behind the 0x0046 loop

The full case body was decoded with the pinned token table before the loop was
written, which corrected three separate things:

- `G0274/G0276` receive **copies of the new** world position, not the previous
  one, so the next frame does not interpolate across the teleport; the earlier
  `previous_world` receipt stored the old value and was wrong.
- the member step tables come from the generated initializer
  (`0x00418350..0x00418448`): `G041C = [-16,-16,16,16]` and
  `G0434 = [8,-8,-8,8]` per direction, subtracted from the running member
  screen position, and `G04AC[i]` keeps the leader's `+6` frame word.
- the loop bound is `For i = 0 To 4` (`PushI2Const0`,
  `PushAddressOfLocal 0xFF66`, `PushI4Const4`, `ForI2Initialize`), matching the
  five-entry `G04C4` trail rather than an arbitrary party size.

Token names, the `PushI4Const<N>` family and the relative-branch base
`0x420FC0` come from the pinned research verifier tables; the two tables above
came from re-decoding the private image, and the values in the module reproduce
the documented `G050C = {0,3,1,5,2,4}` initializer exactly, which is what makes
the decode trustworthy.

### Self-review follow-up (2026-09-12, commit 636e466)

The first review of this owner found three things worth fixing and one worth
pinning, all in the same chain:

- a terminal success that still carries named sub-effect gaps now reports
  `partial: true`, so a caller cannot read a partly implemented entry script as
  full completion;
- every relayed host effect now carries the pending explicit state (previously
  only dialogue did), so a host can answer with the same backing the trigger
  validates on the way back;
- the failure path is pinned by a check: a failed invocation publishes neither a
  candidate state nor a ByRef entry, and the caller's state stays untouched;
- the clean-export check was repeated for this chain: the committed tree at
  `636e466` was exported with `git archive` (no inspection drafts present, 25
  `native_pal98_*.gd` files) and its 49 checks passed in that export, so the
  earlier 45-check run was not the only evidence for the committed source.

Files: `enter-script-07-review.json` (working tree, 49 checks) and
`enter-script-clean-export-02.json` (export of `636e466`, 49 checks).

Studio private root
`artifacts/verification/original-v163-enter-script-20260912-01/`:

| Item | Result |
| --- | --- |
| `verify_opcode_case_hashes.py` / `opcode-case-hashes.json` | reads the cited case ranges from the research evidence files, maps them through the PE image of the local private PAL.EXE and re-hashes them: identity `75d612b9…c450`, all seven ranges match |
| `dump_sss.py` / `sss-original.json` | read-only structural dump of the private `SSS.MKF`: five chunks (162464/2360/7910/54056/348456 bytes), 295 scene records, 43557 instructions, the per-scene enter words and the opcode histograms used above |
| `enter-script-06.json` | `tests/test_pal98_enter_script.gd`, 45 checks, 0 failed, on the private ordinary author build |
| `enter-script-01..05.json` | the earlier runs of the same suite while its fixtures were being fixed; kept as the failure trail |

The suite mixes synthetic admitted sources (record/entry mismatch, scene range,
ByRef return, slot and anchor refusals, `0x0065` reload refusal, relayed
dialogue, stale and cancelled completions) with the admitted ordinary source
package (real opening scene, real entry execution, a real minimal
`0x0015`/return block, and the T212 request chain up to its named stop point).
Every host effect is an explicit acknowledgement; no GPU, audio, save, input or
original process was involved, and `test_pal98_scene_events.gd`,
`test_pal98_dialogue_caller.gd` and the other real-source suites were not
re-run because no shared file changed.

Replay with a fresh output path:

```
godot --headless --path native --script res://tests/test_pal98_enter_script.gd -- <content.palmod.zip> <fresh-results.json>
```

The package must carry both an admitted `pal98-sources` component and a graphics
component with real MAP/GOP bytes, because the last checks drive the T212
resource chain.
