# PAL98 dialogue caller requests

`src/native_pal98_dialogue_caller.gd` composes the recovered FFFF and ClearText
call order around the T82 text kernel. This is an internal, bounded request API,
not a general Trigger interpreter, ordinary Session or public save component.
It does not render, poll devices, schedule a wall clock, load PAL or alter sources.

The product review binds PAL.EXE SHA256
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`,
T258 `[417834,4180A0)`, and eight complete Box/Strip/Clear/input/background helpers.
No recovered procedural implementation or game resource is copied into Native.

## Explicit context and calls

Supply every signed I2 field in `WORD_FIELDS`, four signed I2 `colours`, and the
unsigned32 `timer_counter`. Coordinates distinguish caller-local line origin,
global origin/title positions and the global advancing T82 drawing cursor.
There are no inferred cold-start values. `enter_trigger_context` applies only
the fields initialized at T258 entry; call it once per Trigger invocation,
not before each FFFF. It preserves other explicitly supplied values.

`begin_message` or `begin_instruction` starts one FFFF invocation. The latter
preserves its SSS instruction receipt through child T82 parsing and runtime
failures. `begin_clear` starts the separate ClearText helper. A `return` request
means this invocation completed; it does not mean the surrounding Trigger
returned. The original common command/next-entry dispatch remains outside this API.

Each call returns detached state, a source receipt and one host request. Resume
using `step(records, state, event)`. Record identity and phase invariants are
checked before accepting an event. `Text.inspect_state` validates and reads the
pending child request without advancing it.

| Request | Host event / meaning |
| --- | --- |
| `capture_background` | `captured`, after retaining the actual target background |
| `restore_background` | `restored`, after restoring that background |
| `draw_dialogue_icon` | `drawn`, using the explicit icon and old T82 draw position |
| `draw_dialogue_box` | `box_drawn`; half byte length and `shadow_enabled_word` are explicit |
| `draw_string` / `draw_glyph` | `drawn`, only after the requested drawing has occurred |
| `poll_input` | `input` with signed I2 `action`; semantics depend on the request's model |
| `wait` | `tick`, one explicit original timer unit |
| `return` | Complete; further events are rejected |

Ticks also advance the unsigned counter while a host operation is pending.
That is an explicit input, not an implicit render-frame clock. Overflow of this
counter wraps; checked I2 coordinate/counter arithmetic diagnoses overflow.

## FFFF order

When line count exceeds three, IconWait clears skip, optionally draws an icon,
and waits for nonzero input in every mode, including mode zero. It clears line
count but preserves boxed count. Background restore then clears the two separate
capture/restore gates. At line zero the caller copies its global origin into
local X/Y and captures only when the capture gate is zero. Capture sets no gate.

Dispatch follows this priority:

1. Signed mode >= 10: center X by truncated half byte length, draw Box with
   `shadow_enabled_word=0`, then whole text at `(X+6,Y+8)`, palette64 and
   DrawString `shadow_word=3`. Advance local Y by18, increment boxed count, then
   copy boxed count to line count. Box's nonzero-enabled flag has the opposite
   meaning from DrawString's zero-enabled shadow flag.
2. A qualifying title: mode>0, line zero, ending in `A1 47`, `A3 BA` or `3A`.
   Draw the whole source at title X/Y with palette140 and shadow word0. Do not
   alter the T82 cursor, line count or local Y. One-byte `:` qualifies because
   the original penultimate read sees the length prefix.
3. Mode9: draw the whole string with the current primary colour. When localY
   <=100, add28 to **X**. Advance both global originY and localY by16; no line
   increment. The title path has priority over this mode.
4. Other modes, including3: increment line count before T82, keep its evolving
   cursor separate from local X/Y, then add18 to localY for mode0 or16 otherwise.
   T82's `~` may clear line count; the caller does not add the line back.

For an empty message outside the boxed branch, the original non-short-circuit
title predicate reads buffer index -1. Its behavior is not closed, so the caller
diagnoses `empty_message_title_read_unimplemented`, even when mode or line would
make the Boolean title condition false. T82's known empty-body behavior does not
prove this caller path. Source messages over255 bytes remain explicitly unsupported.

## ClearText order

Nonzero boxed count selects at most160 input polls. Each zero action is followed
by `wtime(1)`; a nonzero action exits immediately. A carried timer can satisfy a
wait without another tick. This is not one `delay1(160)`. Afterward, a nonzero
restore gate requests background restore, then both counts are cleared. This
path preserves skip and the global nonzero-input action field.

Otherwise, nonzero line count uses IconWait and clears both counts; it does not
restore merely because the restore gate is nonzero. With both counts zero there
is no wait or drawing. The nonzero-input helper clears and updates its own action
field; the bounded-input helper's local result does not update that global field.

## Evidence and remaining integration

`tests/test_pal98_dialogue_caller.gd` has82 checks, including bad source/context,
phase tampering, mode/title priority, checked arithmetic and full FFFF receipts.
It exports five real opening-message traces and18 synthetic boundary cases.
An independent product procedural reference matches all864 state/request
boundaries and checks the ordinary package and all four unchanged source files.

The real probes explicitly inject mode setup and the earlier008E host effect;
they do not execute a Trigger. All host effects are acknowledged by the probe,
without actual rendering, physical input or a wall clock. The separate text
drawing adapter remains a system-font candidate, not original GDI pixel parity.
Box/icon resources, target buffers, clock/input policy, general SSS, public
state/save, ordinary-player activation and Mac/AMD acceptance remain separate work.

An error publishes no candidate state. It does **not** undo a draw, capture or
restore already acknowledged by the host. Stop the failed invocation and surface
its source diagnostic; do not automatically retry the old pending state as if
external effects had been rolled back.
