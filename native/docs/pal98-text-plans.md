# PAL98 byte text plans

`src/native_pal98_text_tokens.gd` produces an addressed internal plan from
`package.pal98_sources.open_records()`. `read_message(records, index)` reads a
message; `read_instruction(records, pc)` resolves an FFFF instruction and retains
its source receipt. The internal profile is `pal98.text-byte-plan.v2`.

The scanner works on exact M.MSG bytes with explicit GBK/Big5 source metadata.
It does not decode Unicode, render glyphs, poll input, advance a clock, mutate
dialogue state or enable the ordinary session's SSS interpreter. There is no new
public capability, save schema or rule affecting authored Native dialogue.

| Byte in the scan position | Planned operation |
| --- | --- |
| `"` | Swap the two current text colours |
| `$dd` | Set the character-delay parameter |
| `~dd` | Timed delay; continue scanning the following bytes |
| `(` / `)` | Select icon index 2 / 1 |
| Other | One-byte glyph unless the first byte is greater than 128, then two bytes |

The second byte of a two-byte glyph cannot become a control. NUL and 0x80 remain
single bytes. Planned advances are 8/16 source pixels; they are not a restriction
on the Native renderer's output size. A final double-byte lead reads the original
loader's appended zero: `loader_zero` identifies it, and `size_bytes` still counts
only the actual source byte. This does not promise an invalid glyph's appearance.

For verified decimal parameters 00..99, the integer calculation exactly equals
the recovered Single conversion followed by VB CInt. Values such as 14, 43, 57
and 86 are original timing parameters, not milliseconds or Native logic ticks.
Original `wtime` and `delay1` have different timer reset ordering; scheduling,
focus policy and input semantics belong to the execution owner. A `timed_delay`
token does not itself clear the original line/skip state or perform the wait.

Missing parameter bytes and nondecimal parameters return explicit diagnostics;
the latter are outside the verified arithmetic subset. A message over 255 bytes
is preserved by the source reader but rejected here as
`message_length_u1_unimplemented`, reflecting the original checked U1 loader
boundary. This does not infer how the supplied PALDLL handles such a message.
Bytes after `~dd` are also scanned; malformed parameters there are diagnosed.

Successful plans and scanner failures retain the M.MSG range and the SSS3 pair
of offset addresses. FFFF calls additionally retain the instruction words and
address. A local parameter failure has separate relative/absolute error offsets;
it does not replace the original message range. Returned data is detached from
both the source snapshot and other plans. Failed scans publish no partial plan;
this API property is not a claim of rollback in the original procedure.

`tests/test_pal98_text_tokens.gd` uses synthetic boundary cases and a private
ordinary source-package report. It records every real message's normalized plan
hash, control counts, post-delay continuations and opening addresses. Product integration checks
these with an independent Python byte scanner using float32 rounding. Only test
code and aggregate evidence are committed; original text remains private.

The evidence basis is the recovered PAL.EXE `LoadMessage` (checked length and
trailing zero), `DisplayTextWithTimedInput` T82 (0x0041D3BC; byte branches and loop
continuation) and the caller in T258/RunTrigger. Caller title/body selection, line
overflow, colour/position state, rendering and confirmation remain separate from
this lexical plan. Passing all source-plan checks is not original gameplay or
Mac/AMD acceptance.

## Correction of the recovered prose

Profile v1 and commit `563cdd9` followed a historical T82 opinion that described
`~` as an immediate return. Rechecking the fixed executable's decoded instructions
showed that 0x0040FDCA jumps to 0x0040FF2C, then 0x0040FF30 executes ForNext and can
return to 0x0040FC64. ReturnVoid is at 0x0040FF36. The loop continuation in the raw
instructions takes precedence over the prose and procedural pseudo-code.

The v1 Native and Python checks agreed on that incorrect premise; their prior
passing reports do not establish correct suffix behavior. V2 processes four
additional `$01` controls and the additional `~80`, for 116,032 supported-source
tokens (113 speed changes and 136 timed delays). Prior evidence stays preserved
as superseded. These internal plans were not enabled in a player release.

The internal [body execution helper](pal98-text-execution.md) now consumes v2 plans
and emits acknowledged drawing/wait/input requests. Caller routing and ordinary
session integration remain separate.
