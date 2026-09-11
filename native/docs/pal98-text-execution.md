# PAL98 text body execution requests

`src/native_pal98_text_execution.gd` independently steps the recovered T82 body
text behavior using explicit context and acknowledged requests. Its internal
profile is `pal98.text-execution-subset.v1`. It is not wired into NativeSession,
the renderer, a real timer, input devices or the public save contract.

`begin_message(records, index, context)` and `begin_instruction(records, pc,
context)` consume the admitted source reader and corrected byte-plan v2. The
instruction overload only resolves FFFF's message address. The caller must first
select the T82 body branch: actual RunTrigger also has title, mode, overflow,
background and confirmation paths. Opening message1 takes the title path and is
not one of this helper's opening body tests.

Context must supply `x`, `y`, `colour`, `alternate_colour`, `icon`, `line_count`,
`skip_word`, `delay_units` as signed I2 values, and `timer_counter` as unsigned32.
There are no inferred cold-start defaults. Entry copies coordinates and resets
icon to zero, even for an empty message. The drawing cursor is separate from
RunTrigger's local line origin; the original coordinate arguments are not written
back. A caller must supply its line origin again for the next invocation, rather
than reuse the final glyph X from `context_from(state)`.

Each result contains detached state, source receipts and one request:

| Request | Accepted acknowledgement / behavior |
| --- | --- |
| `draw_glyph` | `{"kind":"drawn"}` starts the optional wtime, then advances X and polls input |
| `wait` | `{"kind":"tick"}` advances exactly one nominal original timer unit |
| `poll_input` | `{"kind":"input","action":...}` supplies the signed I2 action; only 2 sets skip to -1 |
| `return` | The invocation is complete; further signals are rejected |

Timer ticks can also occur while drawing or input acknowledgement is pending.
They advance only this explicit timer counter. Requests do not call Godot's clock,
advance a simulation frame, update palette animation, poll devices, load a DLL or
run a source process. The future host owns tick scheduling, focus policy, target
surface, draw acknowledgement, input mapping and candidate publication.

For each glyph, the exact sequence is draw → optional wtime → checked I2 X advance
→ input. X remains at the glyph origin during the wait. Overflow is diagnosed at
the consumed glyph's source address after the wait, with the resulting timer
counter, and publishes no candidate. The original already-performed draw/wait is
not reversible; callers must not interpret that API failure as renderer rollback.
Nonzero skip suppresses wtime but never suppresses drawing or the post-glyph poll.

The draw request contains original NUL-terminated bytes, colour and shadow=0.
It does not decode Unicode or select a font. A final DBCS lead distinguishes the
loader-supplied zero from the additional string terminator, while the receipt
keeps the actual source length. A NUL source glyph still follows the recovered
coordinate/wait/input sequence; its actual ink belongs to DrawString.

Immediate controls exchange colours, select icons or change delay. `~` clears
line and skip, resets the timer, waits, and continues through the following bytes.
It does not reset colour/delay/icon or introduce a confirmation. EOF returns
without incrementing the caller's line count or local Y.

The original PAL.DLL machine code gives two distinct timer operations:

- `wtime` compares against the existing counter, then clears it on completion.
- `delay1` clears before waiting and retains the counter on completion. A following
  short wtime can therefore complete without another tick.

Both compare `uint32(sign_extend_int16(request))` against the unsigned counter.
Negative requests are not clamped to zero. The counter wraps after 0xFFFFFFFF;
settimer requests a nominal 10 ms callback period. These facts were checked in
the original DLL also present as the supplied package's PALOLD.dll. The package's
1.6.2 proxy forwarding and actual wall-clock behavior remain unobserved.

The 77 checks in `tests/test_pal98_text_execution.gd` cover source/context errors,
request order, skip, zero/negative waits, timer carry/wrap, post-wait coordinate
overflow, icon reset, source isolation and nine private real-message probes.
Four use the opening body PCs; five exercise bytes after a timed delay. Initial
skip/timer and a zero-cost draw/input schedule are explicit probe inputs, not
claims about original cold start. An independent product reference compares all
1,374 request boundaries and binds the executable and timer machine-code evidence.

Early development reports used the wrong pre-wait X advance and missed entry
icon reset. Both were corrected from raw T82 instructions before this feature's
first commit. Earlier reports remain preserved as superseded development evidence.
No visual, original-playthrough, Mac or AMD acceptance follows from these tests.
