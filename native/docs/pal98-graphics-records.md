# Addressed original graphics and portable decoding

The admitted `pal.native.pal98-graphics.v1` snapshot exposes `open_records()`.
The reader retains independent bytes and original table/graphics fingerprints.
`raw_chunk` and `chunk_count` address the MKF directory; `decoded_chunk` explicitly
selects YJ2 for MAP/MGO. A MAP must decode to65536 bytes. GOP is an uncompressed
word-pointer group. `group`, `frame`, `palette` and `rgba_frame` preserve source
file/chunk/frame offsets in results and diagnostics.

No caller palette, frame, direction, transparency or cold-start value is inferred.
Palette variant0/1 selects the first/second768-byte RGB6 region; channels above63
fail. RGBA conversion requires an explicit literal255 policy: original putp mode0
uses transparency, while coverage inspection can preserve the literal. RLE
returns indices, literal coverage and the uninterpreted tail separately. Aliased
or reordered valid frame pointers retain their identity; an invalid unrequested
pointer does not disable another readable frame.

Implementation inputs are the independently recorded byte-stream facts in
Studio `format-spec/PAL98_YJ2.md` and `PAL98_INDEXED_IMAGES.md` at `f2b403d`.
No original DLL, recovered procedure, parent GPL codec, .NET runtime, external
exporter or original payload is linked or shipped. YJ2 reads LSB-first with its
adaptive tree, checked overlapping distances, rescaling and required terminator.
It rejects truncated input, output mismatch and out-of-range references. Its
input limit is16 MiB, default output limit8 MiB and maximum caller limit32 MiB.
The records reader limits a decoded MGO group to8 MiB and holds at most16 MiB in
a FIFO decoded cache. Public results are detached, including cache hits; failed
replacement preserves the prior reader. Image/group and pixel budgets match the
documented bounded format reader, not the original unchecked memory operations.

## Verification

`tests/test_pal98_graphics_records.gd` takes an ordinary compiled private author
ZIP, its earlier independent indexed/YJ2 reference report and a fresh output
directory. It requires explicit original source identities; no original data is
included in the test source. Example (replace paths with local values):

```
godot --headless --path native --script res://tests/test_pal98_graphics_records.gd -- <content.palmod.zip> <indexed-yj2-results.json> <fresh-output>
```

Windows Godot4.7.2 `graphics-records-native-03` passed936 checks. All859 nonempty
MAP/MGO blocks match the earlier original PALOLD `unpak` and managed output
lengths/SHA256; six synthetic vectors include three adaptive rescale boundaries.
All67,715 GOP images /32,503,200 pixels /78,664 tail bytes and4,133 readable MGO
frames match the managed scan. Sixteen map20 RGBA frames match earlier independent
PNG hashes. The complete YJ2 corpus took about15 seconds on this host; that is a
batch diagnostic, not per-frame performance or a device requirement.

MGO571frame1 still reports byte99,396 outside59,516 decoded bytes; frame0 remains
readable. The corpus test explicitly expects that retained source defect, so a
green test does not mean all source frames are valid. Source bytes are unchanged.
The existing ordinary package admission suite also passed60 checks after adding
the reader. An independent read-only review found no necessary code fixes, and
the exported staged Native tree (without inspection) also passed936 checks in
`graphics-records-staged-01`. Evidence is private in Studio's existing
`original-v163-codex-review-20260912-01` directory. Runs01/02 retain test harness
failures (reference label/type and JSON numeric modulo), not successful scans.

This is runtime resource decoding. It does not execute original SSS, select a
cold-start frame/palette, render a scene, alter public saves or remove the normal
source-only session guard. Original gameplay, actual GPU use of this reader,
Mac/AMD, full-system and Richard acceptance remain unverified.
