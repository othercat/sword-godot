# Original map marks and depth composition

`native_pal98_map_occlusion.gd` snapshots the admitted MAP/GOP records and owns
an explicit16384-byte mark buffer. New source selection clears that buffer;
failed replacement preserves the previous source and marks. `replace_marks`,
`mark_cells` and `mark_sprite` also preserve prior state on failure. Outputs are
detached. This component does not choose party/event state or own a Session.

## Source behavior

`world_to_cell` implements the fixed original exrij geometry. Either negative
signed16 input makes all three outputs zero. Otherwise X/32 and Y/16 give the
base cell; u=X%32, v=Y%16, s=u+2v and t=32-u+2v select the diamond:
s<16 keeps half0, s>=48 advances both axes, and the middle s interval uses
t<16 to advance X, t>=48 to advance Y, or half1 otherwise. Finally X is capped
at63 and Y at127, leaving the selected half unchanged.

exbb computes a WORD flag index `(128*row+2*column+half)&65535`. Its flags pointer
receives that full zero-extended index; only the MAP byte offset wraps again as
`(4*index)&65535`. Column64 may alias the next row. Negative expanded coordinates
may address well beyond the owned16KiB flags, so Native diagnoses those addresses
without wrapping them to14 bits. The complete requested mark batch is atomic.
For each layer, nonzero H=(descriptor>>8)&15 marks its bit when
`signed16(16*(row+H)+8*half+8)>=cutoffY`. Existing flags are OR-preserved.

T163 marks the full decoded sprite bounding area around its original foot,
without first clipping to screen: ceil(height/16) rows above the exrij center,
width div64 cells on either side, inclusive, five neighbor calls per cell.
The half0 and half1 neighbor topology remains distinct. Caller coordinate sums
are checked signed16. Nonzero explicit map-skip state or layerBase>=72 skips
only marks; the caller still owns the independent sprite depth row.

`queue_rows` scans flags in original row/column/half order and lower then upper.
The last byte at index16383 is read but not emitted. X, SortY and LayerOffset
use the reviewed exmap facts documented with the depth queue. Height contributes
H*8 to layer/depth here, unlike the exbb H*16 cutoff. A marked upper index0
does not mean absent: the original wraps its directory lookup to GOP+65534.
Native diagnoses that unimplemented path instead of using background vmap's
absent-upper rule. Existing depth row count/pixel limits apply; decoded frame
tails are discarded before caching so aliases cannot multiply unbudgeted bytes.

## Fixed evidence and tests

Fixed original PALOLD SHA256 is
`c6a34e511ed1c7bb2ecddfaaba00992d53006db3ed4b5ab3da61943b417227e8`.
Reviewed byte ranges are right-exclusive:

| Function | VA range / file offset / length | SHA256 |
| --- | --- | --- |
| exrij | 0x10003278..10003363 / 0x2678 /235 | `6c8c1d333788405ed9716c383b10d9c6ba1bc7e027a117e5654544b7d5de259e` |
| exbb | 0x10003363..100033F2 / 0x2763 /143 | `f2aecd28ed5cb4de57f44bf7852077a446f3230a2b8f8be9a6ffd59bbe85ddfc` |
| exmap | 0x100033F2..1000352B / 0x27F2 /313 | `f8105cdefd2e6ef25097c138ad40b811f89e7cb1f8272228650368e8b6eefc46` |

T163 source identity is in `pal98-depth-queue.md`. These are behavioral facts,
not copied/translated recovered procedures. Private evidence remains in Studio's
`artifacts/verification/original-v163-codex-review-20260912-01/`:

- `original-map-occlusion-01`:5305 original exrij inputs,13 exbb requests and8
  synthetic exmap/IPNA outputs. A guarded64KiB development flags arena makes the
  original zero-extended addresses observable without assuming the game's
  allocation owns that extra memory. Sources/guards are unchanged. Oracle report
  SHA `ad209039d526826ad1c4ac31ba86a47be06bd7467c0c3a3369bb2ed26e7a82f5`;
  host source `e30756bc4a6d2f3a41b5f797bcd26e4b38c4c6d3319e9965c1cffb79d57f23b8`,
  host EXE `5574273cd4552b11186dca7dd9e8842df68dbaed6224f9c6dd0f5c497a3c06bc`.
- `map-occlusion-gpu-02`:86 checks pass. All5305 coordinates, owned flag outputs
  and8 actual GPU compositions match the original. Review found and fixed
  decoder-tail duplication under directory aliases and a missing integer-half
  check; tests cover both. Earlier `gpu-01`82 checks predates these fixes.
- `original-scene-graphics-02`:6 guarded compositions from fixed MAP/GOP/MGO
  files, using original unpak/vmap/exrij/exbb/exmap/addtre/ntre/IPNA and explicit
  test sprite inputs. Report SHA
  `180d4fbc20e2b34aa917451b6f057a13313d273ae958103d6eeb4b6fb7dacde6`;
  host source `66012fd2ea29d76cfefc041c92a23224bfe2a5e14ea4cca59075fd04fa55eea8`,
  host EXE `e0626ae9d663d1ae958b67edd70201c87cb96b627a2f02fd62f5862c4f2f5d73`.
- `scene-graphics-gpu-02`:69 checks pass using the ordinary compiler-produced
  source package, its admitted decoder, TileMap background and depth adapter.
  All6 RGBA buffers and all6 complete mark buffers match original output.
  MAP12 contributes7 depth tiles; MAP10 contributes12/12/15 tiles, including
  reversed explicit party/event input and raised event layer. MAP20 has no
  nonzero height nibble and remains a background/sprite-only control. The
  inspected MAP10 window displays the source building with both sprites.
  First `scene-graphics-gpu-01`65 checks selected blank/nonoccluding regions;
  those outputs are retained but do not count as occlusion coverage. Current
  tests require nonempty map depth rows for MAP10/12.

The final inspection-free export `v163-map-occlusion-index01/native`, tree
`2164a06179ab4b162b54c3595ae1588765fcdb33`, passed both suites again:
`map-occlusion-staged-01`86 checks and `scene-graphics-staged-01`69 checks.
Read-only review confirmed the two budget/input fixes; the main writer ran the
GPU/source checks. No inherited inspection files are part of this snapshot.

These hosts are isolated x86 development probes, never shipped to players and
never launch PAL.EXE. GPU tests use Godot4.7.2/OpenGL3.3/NVIDIA5060, explicit
PAT0/day and source MGO2/56/193 frames. They do not prove original cold-start
frame/palette selection, original scripts, Session lifecycle, save/load or a
gameplay candidate. RenderSceneFrame and SubMain still need their own state
consumers and distinct submission orders; source-only admission remains guarded.
Mac/AMD execution and Richard acceptance remain pending.

Replay with local paths and fresh outputs:

```
godot --path native --script res://tests/test_pal98_map_occlusion.gd -- <original-map-occlusion-01/results.json> <fresh-output>
godot --path native --script res://tests/test_pal98_scene_graphics.gd -- <content.palmod.zip> <original-scene-graphics-02/results.json> <fresh-output>
```
