# Original trigger script control flow

`native_pal98_trigger.gd` independently expresses the reviewed T258
`RunTriggerScript` dispatcher over admitted source records. It owns the
fetch/dispatch loop, the local control opcodes 0000–000A, FFFF message
composition through the existing dialogue caller, and the per-invocation
entry/exit state. Every effect (T240 command execution, battle, two-option
menu, party/scene frames, dialogue drawing) is an explicit host request with
an acknowledgement receipt; the driver never executes those owners itself.
This is not an ordinary original Session, a public save format, a general SSS
interpreter or a gameplay activation. Original EnterScript callers, real
command owners and save integration remain pending.

State is an explicit `{globals, events, dialogue, rng}` dictionary validated
against the admitted source before start and after every host response. The
input state is never mutated; completion returns a detached candidate with the
final U2 return entry and the instruction trace. Request receipts carry the
instance, generation and serial, so stale ids, cancel and host errors are
diagnosed without disturbing the pending request.

## Loop and entry boundaries

Each invocation sets the G0302 script-success word to -1, saves the initial
entry, zeroes both dialogue line counters and applies the fixed colours
79/45/26/141, dialog mode1 and layout 12/8 with text origin 44/26. Recursion
re-enters through the same block, because both original recursive calls target
the procedure entry. The loop head exits on entry zero or above the script
maximum (SSS4 bytes/8 - 1), and every exit runs the ClearText composition.
`IncrementScriptEntry` wraps U2 65535 to zero, which then exits and is written
back.

Every continuing path, including FFFF and the local controls, reaches the T240
`execute_command` request with the four record words and the ByRef entry/event
context before the entry increments. Only a signed command word above 10
clears the dialogue state first; u16 values at or above 32768 other than FFFF
are signed <= 10 and skip the clear, matching the original branch.

0002/0003 read, increment and store the event record's +24 idle count, jumping
to Arg0 while the count stays below the signed Arg1 limit; 0002 exits the
invocation (cross-call yield), 0003 restarts the loop in-call, and reaching
the limit resets the count to zero. 0004 recurses with the current event
context, or converts a positive signed Arg1 through the current scene record's
+6 base word with the original range gate; the child's ByRef return writes the
parent's record Arg0 local. 0006 consumes one two-step ordinary Rnd before
reading its target and applies the strict `signedI2(Arg0) < CSng(Rnd*100)`
gate with the product rounded back to Single. 0005 clears, splits FBP restore
from the redraw chain (G02EE, Arg1 default1, optional party rebuild, render,
reset), 0007 clears, battles and branches on results1/2 without the command
gate, 0008 saves current+1, 0009 runs defaulted real frames, and 000A clears
both line counters directly (not ClearText) and repeats menu19 until a
non-negative choice.

## Explicit differences and open boundaries

- `MAX_STEPS` (65536 instructions) and `MAX_DEPTH` (64 frames) are synthetic
  guards with explicit diagnostics. The original has neither: recursion uses
  the native stack and the loop is unbounded.
- The idle count's original increment uses checked I2 addition; at 32767 the
  original raises a VB overflow error. Native publishes an explicit
  `TriggerIdleFrame I2 overflow` diagnostic instead of a process fault.
- The recursion local-coordinate save/restore covers only the dialogue
  caller's synthesized cursor fields `local_x`/`local_y`. These are not among
  the original's 68-byte locals (saved entry, record-word copies, temps); all
  original dialog fields are globals. Whether the parent should restore or
  inherit the child's cursor has no original-byte evidence and remains an open
  question; the current behaviour is deliberate but not recovered.
- `globals.trigger_success_word` is this driver's authoritative G0302 store.
  The equipment kernel's separate top-level field is marked as belonging to
  this caller; the future host that connects the equipment kernel binds the
  two. This task did not change the equipment kernel.

## Fixed source evidence

Original PAL.EXE SHA256
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`;
VB40032.DLL SHA256
`0f1604c9a7398cbb317383799b88c4e1aa7ce0b2c968392f0a7a9ddff22ec57d`.
The implementation uses independently expressed behavioral facts from the
product's read-only reference research (Pal98Research files are unmodified):

| Owner | Fixed P-Code interval | SHA256 / anchor |
| --- | --- | --- |
| T258 RunTriggerScript | 0x417834..0x4180A0 (right-exclusive), 2156 bytes, 586 instructions | `da498b4af7832ca3adcb137423b7b8724b4468a0ded84fa032ae816d108ecde7` |
| T240 ExecuteScriptCommand partition | preamble calls T69 DoEventsGateLoop before the signed <= 10 early return; top-level command marks cover 0x000B..0x00A7 | `PAL98_EXECUTE_SCRIPT_COMMAND_PARTITION_STAGE_OPINION.md` |
| T6W opcode-0006 random gate | Rnd at 0x417E94, Single product token 0x0232, strict `<`, jump targets 0x417EC8/0x417ED8 | `PAL_VB4_TRIGGER_SCRIPT_RANDOM_STAGE_OPINION.md` |
| 000A direct counter clear | 0x417FF0/0x417FFA store zero to both line-count globals; menu19 loop at 0x418008 | product `RESUME.md` (original-v161) |

A read-only review of the draft against the decoded token stream found all
flagged points conforming: the common tail at 0x41805E calls T240 for every
continuing path (all `Branch 0x2a08` targets), the signed >10 clear split at
0x41804C, idle-count storage/reset at +24 (operand 0x18), the 0004 base
conversion and range gate (0x417DB2..0x417E16), child ByRef writeback to the
parent record-word local (0x417DF6 pushes its address), 0007's direct loop-head
return without T240 (0x417F52), and both record-word defaults (0005 Arg1 at
0x417E50, 0009 Arg0 at 0x417F96) that T240 later observes. One research-side
caveat: the reference C# pseudo shows the T240 call only inside the `default`
branch; the decoded P-code is the authority and matches this driver, not the
pseudo simplification. The draft's SHA256
`20b048d1806311de3d48a7161cd159f25d4a9c386cea81a91311ea862cfbd568` was unchanged
by the review.

## Validation

The draft parses and instantiates under Godot4.7.2 headless (`PARSE_OK`).
`tests/test_pal98_trigger.gd` passes69 checks in `native-03/results.json`,
covering 0000/0001/0008 returns and U2 wrap-to-zero writeback, T240 timing
with the clear split observed through a pending message line, 000A menu
repeat and both choices, 0002/0003 idle-count storage, reset and the
yield/restart difference, 0004 positive/negative/out-of-range/depth-budget and
missing-scene paths, 0006 at the exact Single boundary (seed251392 yields
product exactly43.0; threshold43 fails the strict gate, 42 jumps) with exactly
one consumed two-step Rnd, the FFFF caller chain, 0005 FBP/non-FBP, 0007
battle branches, 0009 frames, and stale/cancel/host-error/double-start
isolation with input-state detachment. All effects are acknowledged by the
synthetic host; no original gameplay, save or Session is executed.

The fixed-random regression passes48 checks in `rng-regression-02.json`
against the previously generated `v163-startup-02/fixed-rng-oracle-02.json`.
`test_pal98_scene_events.gd` and `test_pal98_dialogue_caller.gd` were not
rerun: both hard-require the private original-source package, and this change
adds two files without touching their dependencies. These are headless
synthetic checks plus fixed-byte evidence, not original-PAL execution,
gameplay, ordinary Session, actual save/load or device acceptance.

Review evidence lives in Studio's
`artifacts/verification/original-v163-trigger-20260912-01/`: `review-notes.md`
(per-point conclusions and anchors), `commands.md`, `parse_check.gd` /
`parse_check.log`, `native-03/results.json` and `rng-regression-02.json`. The
reviewed draft backup remains byte-identical under
`original-v163-codex-to-kimi-20260912-01/drafts/`.

Replay with a fresh output directory:

```
godot --headless --path native --script res://tests/test_pal98_trigger.gd -- <fresh-output-dir>
godot --headless --path native --script res://tests/test_pal98_fixed_random.gd -- <fixed-rng-oracle.json> <fresh-results.json>
```
