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

## Reviewed night-batch corrections (2026-09-13)

The `e757e80` batch added `0023`, `0022`, `0080` and `008C`, viewport clamping,
and condition backing. Its earlier green tests did not establish arithmetic or
host sequencing parity. The current corrections supersede the historical
coverage/gap summaries below:

- `G0150` is a fixed **WORD** array: descriptor `0x00401CA0` gives two-byte
  elements and `0x600` elements, totaling **3072 bytes**. The P-Code indices
  day/night/work/color `0/384/768/1152` address byte offsets
  `0/768/1536/2304`; each palette is 768 bytes. These windows are separate.
  `G026C` and request `offset` remain WORD indices; the explicit `byte_offset`,
  `length` and `bytes` describe the payload. The former 1920-byte backing,
  overlap claim and old research `byte[0x780]` declaration are superseded by
  the original EXE descriptor and VB array-index helper.
- `cvpate` compares **signed bytes** and moves an unequal byte by **one**.
  In the original rising branch, ADD 2 falls through DEC; it is not +2.
  The 43-byte PALOLD body at `0x100030C6` hashes to
  `555b8b38c1a3c00e24b1761f18ee22c543dc1c15e9ad4f6810936c14a90c8599`.
- `0080` emits all 32 work-palette installs and all 32 wait or event/frame
  groups. Only after their acknowledgements does it adopt the target offset
  and read the final palette bytes. The extra final install is acknowledged
  before clearing G0250. Failed host calls publish no EnterScript candidate.
- `008C` converges the second pointer pushed by its P-Code (local FF26),
  which is also the pointer installed by `intpate`. It keeps the 63 iterations,
  A1-zero default, A2 swap and forward copies into separate buffers;
  it does not borrow `0080`'s terminal offset/gate behavior.
- `0046` validates all five formation/trail writes before changing globals,
  records or trail. Its independent-axis ffxy clamp and original opening
  world `(1024,1024)` / viewport `(864,912)` stay intact.
- `0022` checks complete role mapping, all 450 U2 words and every condition
  row before applying HP/status changes. Its division-before-multiplication,
  checked difference/total, poison-script preservation and -1/0 truth remain.
  `0023` shares the complete U2-table check before interpreting item IDs.
- `0075` keeps inactive status/poison slots across shrink/regrow; only the
  active role/field projections resize. The real equipment owner still clears
  status8 on the members it rebuilds. See [equipment backing](pal98-equipment-kernel.md).

`tests/test_pal98_night_review.gd` includes nonuniform palette vectors, signed
byte boundaries, request counts, last-receipt writes, invalid backing,
failure recovery and real Trigger/EntryHost integration.
`tests/test_pal98_palette_layout.gd` independently checks every RGB byte of
both complete source palettes, color255, destination direction and unchanged
reference windows. Palette installations
remain explicit host requests. Synthetic ACKs, scene-return counts and this
internal owner do not enable or verify ordinary gameplay, real display,
audio, saving, or Mac/AMD acceptance. The private original byte input remains
outside the distributable runtime; no original DLL is loaded by this module.

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

Every failure after a start cancels the suspended Trigger invocation, clears
the relay/continuation state and invalidates its request generation while
keeping the returned diagnostics and trace. The same owner can start again;
an old acknowledgement is rejected without disturbing the new invocation.

The ByRef entry keeps the original opcode semantics, which the checks pin:
opcode `0001` increments the already advanced entry once more before exiting,
while opcode `0000` restores the saved entry.

### DAY-01 Astra review corrections (2026-09-12)

The review of `a79384d` retained the field-major role layout, current-inventory
handoff and party projection lifecycle fixes. Additional regressions in
`test_pal98_role_table.gd`, `test_pal98_vitals_context.gd`,
`test_pal98_viewport_move.gd` and `test_pal98_viewport_relay.gd` pin the default
context, checked change total/Boolean word, viewport host boundaries and
failure/restart semantics described here. The relay suite takes one fresh JSON
output path; the other three take the admitted package and a fresh output path.
The main entry suite keeps its package/output arguments. These are component
checks with explicit host doubles, not ordinary Session acceptance.

### 0020 inventory review corrections (2026-09-12)

`0x0020` was implemented in `905c8f0`. Its case is `0x00421F00..0x00421F60`
(end exclusive), SHA256
`68ce75cfdbf65d5dc20ab0825678b6867c4fad7f29037bc77410d71a18645471`.
Only `A1==0` defaults to 1; `count<A1` and `A2!=0` write ByRef entry `A2-1`,
otherwise the command enters the removal path. The two entry points
`0x0041CFB4` and `0x0041CE1C` are stubs for existing P-Code bodies, not unknown
native helper implementations: T173 count (`0x00403D0C..0x00403D64`), T153
equipped count (`0x0040501C..0x004050AA`) and T135 removal
(`0x00409104..0x00409260`, including equipment-shortage handling) already have
research evidence; no new decoding toolchain is a prerequisite.

The follow-up review adds complete 450-U2 role backing validation and requires
an unambiguous projection for every active member. Inventory count and removal
reject missing or repeated active roles instead of shortening the original
inclusive member loop. The legacy projection has 1..3 slots; this is not a
limit on Native platform parties. Only the actual shortage-jump branch performs
the signed I2 subtraction: `A2=0x8000` fails, while `A2=0xffff` returns the U2
encoding of -2. An unused A2 does not cause a removal-path failure.

Both count and removal read the latest state's inventory. Candidate failure
atomicity is the Native publication contract, not an assertion that VB rolls
back preceding writes on an exception. Exact stock exhaustion keeps the item
word with zero Amount; only a strictly insufficient record clears that word.
The `shortage_left` receipt is the inventory deficit before equipment clearing,
not the deficit after it. Rebuilding through the real EntryHost preserves both
the current quantity and cleared equipment fields.

`tests/test_pal98_count_remove_item_review.gd` takes the admitted package and a
fresh JSON output path. Its 18 review vectors include real Trigger jump routing
and real EntryHost rebuilding. The same formal test exposes six failures in
`905c8f0`; the independent baseline evidence remains in the private product
review directory. These checks do not activate an ordinary Session.

## Implemented T240 commands

The facts below come from the product's fixed-source review of PAL.EXE SHA256
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`. This work
package re-hashed each cited case range from the local private copy of that
executable before writing the code (see the evidence section) and used the real
source bytes for every operand.

| Opcode | P-Code case | Effect implemented here |
| --- | --- | --- |
| `0x0015` | `0x0042149E..0x004214DC` | `G026E = A0`; the party record `A2` frame word becomes `G026E*3 + A1` with checked I2 arithmetic |
| `0x0016` | `0x004214DC..0x004215E0` | zero target is the original no-op; a negative target writes the current event slot, a positive one resolves against the scene event base, and anything outside the scene range writes the global event table record `A0-1`; fields `+20/+22` take `A1/A2` |
| `0x001A` | `0x00421708..0x004217C0` | positive `A2` selects absolute role `A2-1` in the `field*6+role` table; otherwise the invoking `event_id` selects a represented party slot (0..4), with fields 1/65 routed to that slot's projection and other fields to its mapped role; unrepresented context is diagnosed |
| `0x001D` | `0x00421B6C..0x00421E6A` | adds signed `A1` to living targets' HP/MP with independent clamps; zero `A0` selects the invoking context, nonzero selects members 0..member_last; checked I2 additions, differences, absolute values and accumulated change precede all writes; `G0302` is -1 for actual change, otherwise 0 |
| `0x003B` | `0x0042322E..0x00423272` | dialog globals: mode 0, text origin (80,40) |
| `0x003D` | `0x0042331A..0x004233C2` | lower dialog globals: mode 2, title (12,108), body origin (44,126) |
| `0x0041` | `0x004234D6..0x004234F0` | `G0302 = 0` |
| `0x0046` | `0x00423834..0x004239F4` | world position `((2*A0+A2)*16, (2*A1+A2)*8)`, previous-position copies, viewport `world - (party_x, party_y)`, the fixed five-slot party/trail writes and the non-battle background replay |
| `0x0048` | `0x00423A16..0x00423A2C` | explicit original no-op |
| `0x0059` | `0x004243B8..0x00424408` | for a valid changed scene: `G0306 |= 12`, `G026A = A0` |
| `0x0065` | `0x0042477E..0x004247CC` | role `A0` map sprite field index 2 of the admitted role table becomes `A1`; a nonzero `A2` outside battle requests the T99 field reload (`0x0041C864`) instead of skipping it |
| `0x0075` | `0x004255D8..0x0042568C` | rebuilds the active party from `A0..A2` (a nonpositive first argument selects role 0, later nonpositive arguments end the list), writes the member count and both role projections, then requests the sprite and equipment owners |
| `0x008E` | `0x004264EE..0x00426506` | clears both dialog gates and requests the host's `RestoreDialogBackground` (`0x0041D2B4`) before the trigger resumes |
| `0x0035` | `0x00422F16..0x00422F52` | screen-shake count and amplitude with the original default amplitude 4 |
| `0x0047` | `0x004239F4..0x00423A16` | requests `PlaySoundEffectIfEnabled` (`0x0041D284`) with the instruction's index |
| `0x004A` | `0x00423AEC..0x00423B08` | `G0280 = A0` (battlefield selector) |
| `0x0053` / `0x0054` | `0x004241B4..0x004241CE` / `0x004241CE..0x004241EA` | `G026C = 0` / `G026C = 384` (day and night palette offsets) |
| `0x0073` | `0x004254E4..0x00425516` | requests `ClearEffectiveCrossFade` (`0x0041CEC4`) with `A0` defaulting to 1 |
| `0x0024` | `0x00422276..0x00422336` | same target resolution as `0x0016`, writing the resolved record's `+10` word |
| `0x0049` | `0x00423A2C..0x00423AEC` | same target resolution, writing the resolved record's `+12` word |
| `0x0071` | `0x00425400..0x00425426` | `G0298 = A0`, `G029A = A1` (screen-wave phase and amplitude) |
| `0x0077` | `0x004256AC..0x004256FE` | `A0` defaults to 1; a zero `A1` requests the CD-track query, then the media stop request runs and a non-battle context clears `G027C` |
| `0x0050` / `0x0051` | `0x004240E6..0x0042411C` / `0x0042411C..0x00424152` | requests `FadePaletteToBlackOnce` (`0x0041CDD4`) and `FadePaletteToRepeatedColorBlock` (`0x0041CDEC`) with `A0` defaulting to 1 |
| `0x0025` | `0x00422336..0x004223F6` | same target resolution as `0x0016`, writing the resolved record's `+8` word |
| `0x008B` | `0x00426338..0x0042637A` | requests the palette selection (`0x0041D11C`) and, when the explicit `G0250` fade gate is zero, the palette apply (`0x004174D0`) at the `G026C` day/night offset |
| `0x0093` | `0x004266E8..0x00426704` | requests `FadeScenePaletteAndUpdateFrames` (`0x0041CE04`) with the instruction's argument |
| `0x0099` | `0x004268EC..0x0042694E` | writes the scene record's map word; a negative `A0` means the current scene and additionally requests `EnsureMapResourcesLoaded` (`0x0041C834`) |
| `0x001F` | `0x00421EC4..0x00421F00` | defaults a nonpositive amount to 1 and requests `CompressInventoryAndReturnLastSlot` (T152 `0x0041C96C`) plus `AddInventoryItemAmount` (T140 `0x0041CCCC`) from the inventory owner |
| `0x0020` | `0x00421F00..0x00421F60` | last active inventory Amount plus active equipped copies; a shortage with nonzero A2 returns checked signed `A2-1` as a ByRef U2, otherwise removes inventory and then equipment copies; only zero A1 defaults to one |
| `0x006D` | `0x004250D8..0x00425178` | for a positive scene writes the record's enter (`+2`) and leave (`+4`) script words, or clears the pair when both arguments are zero |
| `0x006E` | `0x00425178..0x00425206` | copies the world position and viewport into their previous slots, adds the `A0/A1` deltas to the viewport, stores `A2*8` as the party layer word and, when the party actually moves, requests `PostMoveUpdate` (`0x0041D2CC`) and `UpdateViewportAndPartyPosition` (`0x0041CC3C`) |
| `0x009A` | `0x0042694E..0x00426A56` | resolves `A0/A1` against the scene event base and writes the state word (`+12`) for the inclusive range, falling back to the global event record when the start is out of range |
| `0x00A3` | `0x0042759A..0x004275D6` | normalizes the third argument (at most 1 becomes `Arg2 Xor 1`) and requests `PlayCdOrMidiTrack` (`0x0041D23C`) with the three ByRef words |
| `0x0085` | `0x004261A4..0x004261C6` | a nonzero argument requests the delay helper (`0x004170C4`) with `Arg0 * 10`; the pinned bytes show the small constant 10, not the reference summary's factor 80 |
| `0x007F` | `0x00425A7C..0x00425D24` | `(0,0,-1)` restores anchor `(160,112)` and viewport without a host call; otherwise `A2` counts rounds (nonpositive defaults to one). Only `(A0 OR A1 OR A2)==0` re-anchors; negative A2 is absolute and the remaining branch is delta. Background completion precedes dependent anchor/member calculations, followed by frame, update only for `A2>=0`, and render |
| `0x0036` | `0x00422F52..0x00422F80` | requests the RNG animation load (`0x0041D134`) with the argument word and sets the `G0306` animation bit (16) |
| `0x0037` | `0x00422F80..0x00422FCA` | defaults the end to 999 and the speed to 10, then requests `PlayCurrentRngAnimation` (`0x0041D464`) with the three words |

Three boundaries are stated rather than hidden:

- `0x0046` is implemented for the world/previous/viewport words only. The
  original rewrites the fixed `G04AC` party records for indices `0..4`; Native
  writes the slots it has explicit backing for and reports the rest as a named
  gap, because slots beyond the active party are not consumed by any reviewed
  owner yet.
- `0x0059` clears the same party layer word (`G028A`) that `0x006E` sets to
  `A2*8`, so that earlier named gap is closed rather than guessed: the mask, the
  requested scene and the layer clear are applied together.
- `0x003B` writes the three reviewed dialog globals and reports the `G022A`
  colour word as a named gap instead of guessing its value; `0x003D` applies its
  geometry and reports the `0x0041D29C` capture and `0x0041D44C` layout calls,
  because the opening passes zero arguments and the documented effect for that
  case is the fixed geometry with no portrait or colour change.

`0x0065` with a nonzero reload argument requests the real sprite owner outside
battle and reports a named gap when battle mode suppresses that request.

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
and map identity, and then proceeds into scene 2's own `render_background`
request. The former stop point — the `original sprite cache bytes are Unknown`
refusal in the cache word read — is resolved (2026-09-13): the cache buffer is
zero-initialized exactly like the original's, so a never-written word decodes
as 0 and terminates a T98 directory walk instead of refusing. The cold-start
backing is therefore no longer a blocker; the remaining scene-2 boundaries are
the host-owned display kinds (background render, dialog restore, midi) that the
adapters still answer with named doubles.

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

### Chain-driven dialogue frame (2026-09-12)

### Inventory owner (2026-09-12)

### Decoded grounds for the shared party-walk body (next package)

### Historical remaining-entry triage (before DAY-01 review, 2026-09-12)

The following counts and zero-sprite attribution are historical, not the current
baseline. The DAY-01 role-table correction reads the real field-major sprite
row `[2,3,7,525,5,26]`; those six source words are nonzero. Current boundaries
must be read from the exact candidate's coverage diagnostics.

The latest coverage report separates the sixteen scenes that still stop without
a named command opcode from the ones that do, so the next packages have a ranked
input:

| Blocker | Scenes | Nature |
| --- | --- | --- |
| walk step budget | 7 | the host double only approximates the external `extf` facing, so long real walks exhaust the Native 512-step guard |
| `paksize header unavailable` | 9 | the admitted DATA3 has no map sprite (value 0) for the roles those scenes select; the sprite cache diagnoses the empty chunk instead of inventing a load |
| `0x009B` FBP / cross-fade | 2 | unimplemented; the research carries a recovered body (`FbpMode`, view offsets, `mode 0` map reload, `mode 1/2` FBP chunk load and the `speed` default 2) |
| `0x0075` equipment projection | 2 | the fixture models three active members; these scenes ask for more |
| `0x001A` role slot | 1 | same three-member projection limit |
| `0x001D`, `0x0020`, `0x0023`, `0x0080`, `0x008C` | 1 each | unimplemented single-scene commands (HP/MP clamps, inventory count/remove and branch, unequip, day/night palette fade, colour fade) |

That ranking is the next package's starting order: `0x009B` first (it has a
recovered body and two scenes), then the single-scene commands, while the walk
budget and DATA3 sprite limits stay documented data/host boundaries rather than
engine gaps.

### Party walk (2026-09-12, implemented)

`native_pal98_party_walk.gd` implements the shared body for `0x0070` (speed 2)
and the `0x007A`/`0x007B` entries (speeds 4/8), now that the remaining
instructions were decoded:

- the step tables are `G044C = [-1,-1,1,1]` and `G0464 = [1,-1,1,-1]` from the
  generated initializer, and the body scales X by `speed*2` and Y by `speed`,
  i.e. the original 2:1 walk step;
- the body copies the world position into the previous-position words, then per
  iteration faces the party through the external `extf` stub (`0x004172D8`),
  advances the viewport, and calls `PostMoveUpdate` (`0x0041D2CC`),
  `StartFrameAndProcessEvents(0)` (`0x0041D17C`),
  `UpdateViewportAndPartyPosition` (`0x0041CC3C`) and `RenderSceneFrame(1)`
  (`0x0041CB64`) before re-checking the target;
- arrival runs the member/trail sync on the reviewed `SyncMembersFromTrail`
  owner (`0x0041D2E4`).

`extf` has no body in `PAL.EXE` (the research marks it as an external call), so
facing stays an explicit owner request, and the world/trail arithmetic stays with
`PostMoveUpdate`. Because a step contains a real frame, the enter-script owner
gained a per-command continuation: a command may return owner requests plus a
`pending` state, and the owner re-enters `continue_command` after each answered
round until the command reaches its terminal result. Owner answers now also keep
the relayed state current for the remaining requests of the same command.

`MAX_STEPS` (512) is a Native guard like the trigger's step budget, not original
behaviour: with a host that only approximates facing, a real long walk can
exhaust it and the run stops with that named diagnostic. 163 checks pass
(including an eight-step walk that lands exactly on a tile-derived target,
asserting the per-iteration facing/update/render sequence and the single arrival
sync), and the real-pool coverage rises to 120 entries with 27.36 average
command depth.

The four remaining movement cases share one implementation, so the next package
can start from decoded facts instead of re-deriving them:

- `0x007A` and `0x007B` store the speed (`4` and `8`) in the same local and
  branch into `0x00425278`, which is the body `0x0070` enters with speed `2`;
- the body computes the walk target with the same formula as `0x0046`
  (`((2*A0+A2)*16, (2*A1+A2)*8)`), copies the world position into the
  previous-position words, saves the viewport into the `G0330/G0332` copies, and
  only when the target differs from the current world position does it call
  `0x004172D8` (`extf`) to face the party and continue stepping;
- `0x007F` (`0x00425A7C..0x00425D24`, 680 bytes) is the viewport move state
  machine that the walk and `0x007D/0x007E` feed; `0x41D2CC` `PostMoveUpdate`
  and `0x41CC3C` `UpdateViewportAndPartyPosition` are its owners, and `0x006E`
  now requests both through this chain.

That makes the movement package a single owner (target, direction, per-step
deltas, layer/clip, timed update/render and retry) rather than four unrelated
cases. The current chain stops at those opcodes with a named diagnostic, so the
coverage numbers above already separate them from implemented work.

The rest of the body is decoded too, so the package can be implemented directly:

1. `0x0070` stores speed 2 in the shared local; `0x007A`/`0x007B` store 4/8 and
   branch to the same head.
2. The head recomputes the target with the `0x0046` formula, copies the world
   position into the previous-position words and the viewport into the
   `G0330/G0332` copies, computes `dx/dy` and, when they are not both zero,
   faces the party through `0x004172D8` (the reviewed `extf` direction helper)
   writing `G026E`.
3. Per step it advances the viewport by the reviewed formation tables scaled by
   the speed (`G041C`/`G0434` and the `G0464` pair), then calls, in order,
   `PostMoveUpdate` (`0x0041D2CC`, world recompute plus walk phase and trail
   sync), `StartFrameAndProcessEvents(0)` (`0x0041D17C`), 
   `UpdateViewportAndPartyPosition` (`0x0041CC3C`) and `RenderSceneFrame(1)`
   (`0x0041CB64`), looping while the world position has not reached the target.
4. After arrival it runs the trail sync loop over the party slots.

Two consequences for the implementation: the per-step sequence contains a real
frame with input processing, so the walk cannot be computed synchronously inside
one command result - the consumer needs a continuation that resumes the command
after the host has answered each step's requests; and `PostMoveUpdate`'s world/
walk-phase/trail arithmetic is the owner that `0x006E` already requests, so the
same module should serve both callers.

`native_pal98_inventory.gd` implements the reviewed inventory arithmetic over the
explicit 256-slot six-byte backing (`ItemId +0`, `Amount +2`, `AmountInUse +4`):

- `add_item_amount` (T140 `0x0041CCCC`): a nonpositive item id returns
  immediately, the first living record with the same item takes a checked I2
  delta, otherwise the first slot with `Amount <= 0` receives
  `Amount = delta`, `ItemId = item` and cleared usage, and a full inventory ends
  silently. There is no delta default, no 99 cap and no success value in this
  path, matching the review.
- `find_last_active_slot` (T144 `0x0041CF84`): the highest matching living slot,
  or -1.
- `compress_and_return_last_slot` (T152 `0x0041C96C`): clamps amounts above 99,
  moves living records to the front with the original swap sequence and returns
  the last living slot, or -1 for an empty inventory.

`0x001F` routes through the entry host's inventory binding, so the chain's add
uses the real owner (`CompressInventory…` then `AddInventoryItemAmount`) and the
updated bytes travel back with the state. 145 checks pass, and the coverage scan
binds the same owner, which lifts the run-to-return count to 116 with 13.71
average command depth.

`tests/window_enter_script_dialogue.gd` drives the same real opening entry, and
when the caller composes the whole-string draw for the opening title the raw
source bytes go through `native_pal98_dialogue_surface.gd` on a real 320x200
target over an explicit opaque probe frame with the admitted 256-colour day
palette. The window is captured as `dialogue-frame-04.png`; 8 checks pass. The
captured frame shows the real message text (`李逍遥:`) drawn in the source
colour, with the project's system-font candidate rather than original GDI pixel
parity, and no input device, audio, save or original process is involved.

### Entry coverage over the real pool (2026-09-12)

### Chain-driven opening frame (2026-09-12)

`tests/window_enter_script_opening.gd` is a window probe that renders the opening
from the chain's own effects: the real entry script produces the world position,
viewport and role 0 map sprite id, the viewport maps through the original `exrij`
relation to cell `(27,57,0)`, and the verified background and depth composition
build the 320x200 frame with the explicit day palette. The window is captured as
`opening-frame-02.png` beside its results JSON; 16 checks pass, including the
documented cell, the decoded source sprite frame and composed pixel content.

The frame is mostly the empty area of MAP20 with the leader sprite at the party
anchor, which matches the recorded data: the map's bed tiles sit at row 23..26 /
column 14..17, i.e. elsewhere, and the camera is deliberately not moved to expose
them. No input device, audio, save or original process is involved.

The suite also runs **every** admitted scene's real enter script until the first
command the consumer cannot execute, and reports the depth and the blocking
opcode per scene. With the reviewed commands above in place and an explicit
synthetic lifecycle state, the current report is:

| Metric | Value |
| --- | --- |
| Scenes with a nonzero enter word | 160 |
| Scene entries that run to a return | 112 |
| Average applied-command depth | 13.16 |
| Deepest entries | scene 39 (23 commands), scene 1 (15 commands) |

The remaining blockers, by scene count: `0x0075` 10 (scenes whose arguments need
the party/equipment backing the coverage fixture does not model), `0x007F` 6,
`0x007B` 4, `0x0036` 4, `0x001F` 3 and a tail of
single-scene commands. The coverage fixture now models the fixed five-slot
`G04AC`/`G04C4` projection, so `0x0046` and `0x0015` no longer report unbacked
slots. This table is a coverage report
over the admitted pool with synthetic state; it is not an original Session,
gameplay or acceptance claim.

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
