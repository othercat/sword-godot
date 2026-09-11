# PAL98 source decoding and drawing candidate

`native_pal98_text_codec.gd` strictly decodes the source component's explicit
`gbk` / `big5` as Windows CP936 / CP950. It does not detect the host code page,
trim fixed records, remove controls, re-encode source files or interpret T82.
The internal profile is `pal98.codepages-dotnet8.v1`; this is not a new content
schema or save extension.

`open(encoding)` verifies a bundled table's length, header and SHA256. `decode`
returns detached Unicode `codepoints` and `utf8` bytes. A `text` Godot String is
also returned unless the decoded data contains U+0000, which Godot would replace.
That valid data instead carries `text_projection_error=godot_string_contains_nul`.
No replacement text is published. Invalid source sequences return their byte
offset without a partially decoded candidate. Input is bounded to 8 MiB.

`read_word` and `read_message` keep the original reader result, including raw
bytes and full source/offset-directory receipts, and attach `decoded`. Source
encoding mismatches fail rather than reinterpret a GBK component as Big5.

## Reproducible software data

`encodings/` is software data, not game text or font data. The two 263,180-byte
tables derive from the MIT `System.Text.Encoding.CodePages` NuGet 8.0.0 provider
assembly pinned in `tools/ExportCodePages/Program.cs`. Its .NET and third-party
notices are included alongside a provenance manifest. No provider DLL or .NET
runtime is needed by the player. Keep `encodings/*` in both the isolated software
copy and PCK include filter; also include its notices in the distributable notices.

The development exporter uses an isolated assembly load context for the pinned
provider and compares every complete one-/two-byte sequence against the current
.NET 8 framework provider used by StoryStudio. It writes tables to a **fresh**
output first, along with private binary oracles and a private source-record
reference. It does not write the runtime tree or original package. Use:

```text
dotnet run --project native/tools/ExportCodePages --configuration Release --artifacts-path <private-build> -- --package <NuGet-CodePages-8.0.0-directory> --gui-report <source-window-report> --output <fresh-private-output>
```

Review the generated manifest and copy only `encodings/` to this project. The
private oracle/reference files are test evidence and are not software assets.
The player tests compare all 131,584 one-/two-byte outcomes and error positions,
plus the ordinary package's 565 untrimmed words, 13,862 messages and separate tail
against the current framework. All 14,428 real records decode strictly, including
the first all-NUL word. The 528-byte message can be **decoded**; it still exceeds
the separate T82 byte-plan subset and is not thereby executable.

## Drawing adapter

`native_pal98_text_layer.gd` accepts already-dispatched `draw_glyph` or
`draw_string` requests. Its host supplies a Font and an explicit 256-colour
palette. The ordinary app and the drawing probe share `native_ui_font.gd`, which
preserves the existing system-font candidate list unchanged. There is no copied
Simsun font, new skin or original-resource redistribution.

The adapter uses bytes before the first NUL, then strict decoding. It draws text
at the requested text-cell top-left using Godot TextLine at size 16; it does not
use shaped text width to advance T82's independent 8/16-byte cursor. Foreground
uses the colour WORD's low byte. A zero shadow WORD enables palette-index-0 ink
at (+1,+1); a nonzero WORD disables it. Each run is clipped to the default
320×200 target's remaining width and at most 20 rows. These dimensions are local
to the PAL98 adapter, not a limit on ordinary Native content or UI.

`append_draw` only queues rendering. `commands_submitted(serial)` becomes true
when the run has issued its drawing commands; a host observes the frame before
acknowledging `drawn` to the text execution kernel. The adapter has no wall clock,
input polling, script dispatch, line counting, background capture, dialogue
confirmation or save state. `clear_text` explicitly discards its display runs.
Bad requests do not clear prior text. Receipts retain the **full** message source
span and a separate glyph/draw offset, never a fabricated shortened source span.

Negative/out-of-surface target coordinates, malformed byte sequences, control
character ink, missing glyphs and transparent foreground with enabled shadow are
diagnosed. That last case needs an indexed mask which erases foreground coverage
from the shadow; simply skipping the foreground would be incorrect. Up to 4096
runs are retained until explicitly cleared. Palette colours are captured on
submission; palette animation/fades require later indexed-surface integration.

The real-window test displays four source-bound opening body requests and the
separate title string. It acknowledges each draw only after a rendered frame;
timer ticks and input action 0 are explicit probe events, not original wall-clock
or device sampling. It checks Chinese/Big5 ink, shadow toggling, palette low byte,
NUL termination, clipping, precise source diagnostics and queued/painted order.
The title test supplies its already-recovered branch explicitly; it does not
execute RunTrigger's dispatch.

This is a system-font rendering candidate, **not original GDI pixel parity**.
Original DrawString uses a Simsun request and a 320×20 indexed temporary surface;
Godot shaping, glyph rasterization, anti-aliasing and fallback selection differ.
The original proxy forwarding, actual selected font and final visual acceptance
remain unobserved. No Mac, AMD, full original game or human acceptance follows
from these tests. The ordinary NativeSession still does not execute original SSS.

API sources: [TextLine](https://docs.godotengine.org/en/stable/classes/class_textline.html)
defines top-left drawing and shaping; [Font](https://docs.godotengine.org/en/stable/classes/class_font.html)
documents coverage/fallback metrics. Product evidence separately binds original
DrawString, font setup, strlen and target-copy machine-code spans.
