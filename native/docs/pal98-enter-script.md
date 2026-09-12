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
| `0x0041` | `0x004234D6..0x004234F0` | `G0302 = 0` |
| `0x0046` | `0x00423834..0x004239F4` | world position `((2*A0+A2)*16, (2*A1+A2)*8)`, previous world words, and the viewport `world - (party_x, party_y)` |
| `0x0048` | `0x00423A16..0x00423A2C` | explicit original no-op |
| `0x0059` | `0x004243B8..0x00424408` | for a valid changed scene: `G0306 |= 12`, `G026A = A0` |
| `0x0065` | `0x0042477E..0x004247CC` | role `A0` map sprite field index 2 of the admitted role table becomes `A1` |

Two boundaries are stated rather than hidden:

- `0x0046` is implemented for the world/previous/viewport words only. The
  original also rewrites the `G04AC` party viewport records and the `G04C4`
  five-entry trail and re-renders the map background in non-battle mode; those
  three sub-effects are reported per invocation as `unimplemented` entries. A
  viewport outside the recovered ffxy bounds (1696x1840) fails the invocation
  instead of inventing a clamp.
- `0x0059` records that the unnamed `G028A = 0` write has no reviewed Native
  field; the mask and requested scene are applied, and the gap is reported.

`0x0065` with a nonzero reload argument fails explicitly: outside-battle sprite
loading belongs to the sprite-cache owner and is not implemented here.

The next named gap is `0x0075` (`0x004255D8..0x0042568C`: rebuild an up-to-three
member party, load resources, rebuild equipment state and sync members). The
diagnostic carries that opcode, the real instruction words, the admitted
instruction receipt and the cited case range/hash. `0x0002/0x0003/0x0004/
0x0006/0x0007/0x0009/0x000A` and `0xFFFF` are dispatched by T258 itself and
return through the consumer untouched, as the original shared tail does.

## Real opening entry

The admitted source's runtime scene 1 is raw scene 0: map word 20, enter word 4
and an empty event range. Instruction 4 is `0046 0020 0040 0000`, followed by
`0065 0000 00C1 0000`, `0015 0000 0000 0000` and `0075 0001 0000 0000`. Running
that entry through this owner produces, in original order:

1. `party_map_position`: world `(1024,1024)`, viewport `(864,912)`;
2. `role_map_sprite`: role 0 sprite word 193;
3. `party_direction_frame`: direction 0, frame 0;

and then stops on `0x0075` with the real operands. That is the current stop
point of the ordinary opening path, and it is named rather than skipped.

## Evidence

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
