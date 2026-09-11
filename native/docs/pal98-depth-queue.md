# Original depth rows and GPU overlay

`native_pal98_depth_queue.gd` accepts explicit decoded rows in their original
caller's submission order. It does not select a scene, palette, party frame or
event state. `load_rows` validates and snapshots a replacement atomically;
`rows` and `draw_order` return detached data. `make_view` returns a caller-owned,
nearest-filtered GPU candidate clipped to X[0,320) and Y[0,clipBottom).

The original ntre compares signed16 depth values using non-adjacent exchanges.
This is not stable: [A22,B22,C18] becomes [C,B,A]. Its final top coordinate is
`signed16(sortY - layerOffset - imageHeight)`. Literal RLE payload indices0 and255
are both opaque in this IPNA overlay stage; only skip commands are transparent.
The background putp stage has a different literal255 policy.

`row_for_sprite` independently expresses T163's reviewed coordinate facts:
X=screenX-W div2, party SortY=screenY+B+10 and Layer=B+6; event SortY=screenY+B+9
and Layer=B+2. These caller operations have checked signed16 intermediates,
including screenY+B. An overflow may not wrap back into a valid final value.
This differs from ntre's later WORD subtraction. The helper does not mark map
occlusion or filter event records.

Rows are limited to255 and decoded source pixels to32Mi. Original addtre can
store256 rows, but ntre's DIV DL cannot represent that count and traps. Native
reports this boundary without reproducing a host crash. Dimensions are bounded
to1..8192 and both decoded planes must match them. Invalid replacement leaves
the previous queue intact. Candidate node lifetime and replacement belong to the
calling scene, not this component; this is not an IPNA memory-span emulator.

Three known original clipping-overflow paths fail explicitly: a surviving
negative-top skip whose pixel product exceeds65535, a visible row whose X+width
exceeds32767, and a nonnegative-top bottom comparison whose top+height-clipBottom
exceeds32767. Original WORD arithmetic can select different source pixels or
unsafe row heads. The horizontal gate is conservative, including fully offscreen
terminal literals; it does not claim all rejected images would draw incorrectly.
Skip65535 remains supported. Failed candidates preserve the source queue.

## Evidence

Fixed original PALOLD SHA256:
`c6a34e511ed1c7bb2ecddfaaba00992d53006db3ed4b5ab3da61943b417227e8`.
Reviewed ranges (right-exclusive) are ntre/sort VA0x100035BC..10003683,
file0x29BC/199 bytes, SHA
`c8ca20f5f8dffa2d23795abaead96a89500000323252bddef8a3f695227757a1`;
putipna VA0x10003907..10003C64, file0x2D07/861 bytes, SHA
`38d2e7101ff17a1a4b3ef9746ebef7584b607739eda3512e483d1a9e3e8c7f8f`;
nipwa VA0x10003C64..10003D28, file0x3064/196 bytes, SHA
`49a5ab4d41b330931ad312c38fac1435062b9266571c22b4d3d6a33611a903fc`.
Fixed PAL.EXE SHA
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`;
T163 VA0x004111BC..00411558, file0x105BC/924 bytes, SHA
`70c47fd31610c4f54520ba8bf2347c6779741cc93f33eb590af0dfb084275d11`.
Only these behavioral facts are implementation inputs; recovered procedures,
original binaries, source resources and parent-project rendering code are not
copied into the Native implementation.

Private evidence remains in Studio's existing
`artifacts/verification/original-v163-codex-review-20260912-01/`:
`original-depth-host-03/probe.cpp` is an isolated x86 development oracle calling the
fixed DLL's clear/add/depth/IPNA exports into guarded offscreen buffers. It does
not launch PAL.EXE, initialize a display device or become a player dependency.
Original ntre clobbers EDI; the private host saves/restores nonvolatile registers
at its own call boundary. Original DLL bytes are unchanged.

Oracle source SHA
`b9b220827a79e512d5da7b08241cfffcc9728fce95dea38bbc303d02914a714f`,
host EXE SHA
`21700ced9eda62a9e6cee45e97ba12c2605e3d30e434befc24499b9bc54628f7`,
`original-depth-03/results.json` SHA
`9f68c146f38d94ae39a4699c83bb3919089b0d4af6bfc608b24bebdb0ca602e0`.
All13 cases preserve source/target guards and verify that original ntre consumes
its tree without stale replay. They cover empty, nonstable ties and reversed
caller order, literal0/255, clipping on all edges and clipBottom0/11/200, signed
depth, wrapped top and fully offscreen sprites. Two added cases demonstrate the
original quirks: W512/H130/top-129 selects source row1 instead of row129;
W16/H1/X32759 with a skip9 then literal7 wraps seven pixels onto the left edge.
The unsafe bottom-row-head overflow is diagnosed from reviewed original bytes
(VA0x10003981..10003993); it is deliberately not executed in the DLL host.

`depth-queue-gpu-04` passed74 checks in an actual Godot4.7.2/OpenGL3.3/NVIDIA5060
window. Ten320x200 GPU RGBA outputs match original offscreen indices mapped
through an explicit synthetic RGB6 palette. Three oracle cases receive explicit
overflow diagnostics. Additional checks cover detached snapshots, invalid
replacements,255/256 rows, clear, T163 checked anchors and clipping boundaries.
The captured window was inspected; it is a synthetic pixel diagnostic, not a
scene or gameplay acceptance image. Earlier `depth-queue-gpu-01` passed58 checks;
`gpu-02` and the first staged export passed63 before the overflow review. The
review exposed the three missing diagnostics, now added. `gpu-03` retained a
test-only failure: it compared the canonical queued frame to input metadata
(tail/consumed_bytes), rather than the pre-render queue snapshot. `gpu-04` fixes
that assertion and passes. Earlier source/oracle/failed outputs remain private.
The final clean export `v163-depth-index02/native`, tree
`2e1b9a6a65e3ba03663cbabaa28280a11266ad51`, also passed74 checks in
`depth-queue-staged-02`. That snapshot excludes inherited inspection drafts.

Replay with local paths and a fresh output directory:

```
godot --path native --script res://tests/test_pal98_depth_queue.gd -- <original-depth-03/results.json> <fresh-output>
```

## Remaining callers

Do not merge the two original caller orders: RenderSceneFrame queues events
then party (PAL.EXE0x404668/40466E), while the normal SubMain chain queues party
then events (0x41B3A8/41B3AE). Map tiles follow via exmap. This module deliberately
receives their explicit final sequence; it does not silently choose one owner.

T163's five-neighbor exbb marks and exmap tile rows are now implemented in
`pal98-map-occlusion.md`, including explicit-source GPU composition comparisons.
Original caller-owned state/scene composition remains pending. Out-of-map mark addresses must not silently
wrap to14 bits; the original expanded bounding box has no such clipping rule.
Original cold-start state, scripts, ordinary Session, save/load, Mac/AMD execution
and Richard acceptance remain pending. The source-only admission guard remains.
