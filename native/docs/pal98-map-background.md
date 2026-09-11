# Original map background stage

`native_pal98_map_background.gd` consumes the admitted graphics records reader.
`load_source` selects MAP/GOP by the same explicit index plus an explicit PAT
chunk/variant; failed replacement preserves the prior bytes. `draw_plan` returns
source addresses, raw descriptors and exact visible cells. `make_view` returns
a detached TileMapLayer candidate; the caller owns replacement and scene lifetime.
No module changes a running session, author resources or save data.

The original `vmap` stage generates a320×200 background. It visits13+half rows,
each with half0/1 then11 columns, immediately drawing lower and upper for each
cell. MAP address is `(row*512+column*8+half*4)&65535`, including linear wrap.
Frame selection is low8 plus bit12 shifted to bit8. Lower0 remains a real frame;
upper0 is absent, otherwise its frame index is one less. Height bits8..11 and
collision bit13 are retained in the plan but do not change background placement.
The initial top-left is(-16,-8), or(-32,-16) for half1, with(32,0) column and
(16,8) half offsets.

Each referenced lower/upper pair becomes a small RGBA tile using explicit
original putp-mode0 literal255 transparency. These per-tile images, not a CPU
screen composite, feed the existing Native terrain atlas builder. The resulting
TileMapLayer enables Y sorting and left-to-right X sorting, retaining the original
row/half/column draw order and lower-before-upper within a cell. It uses nearest
filtering. Source/pair pixels and the existing padded atlas are bounded; oversized
atlas candidates fail instead of silently switching renderer. Existing Native
authored terrain code and its sorting policy are unchanged.

Godot4.7 documents the TileMapLayer X draw-order setting with Y sorting:
https://docs.godotengine.org/en/4.7/classes/class_tilemaplayer.html#class-tilemaplayer-property-x-draw-order-reversed

## Original evidence and verification

Original PALOLD SHA256:
`c6a34e511ed1c7bb2ecddfaaba00992d53006db3ed4b5ab3da61943b417227e8`.
The independent byte review covers vmap VA0x1000369F..100037BA, file0x2A9F,
283 bytes, SHA256
`644a4f6a3e5b0583f4e0187c5777e8c09be4a4681a092238aace68d2e25aa202`.
Implementation uses the recorded address/descriptor/draw-order facts, not a
translated recovered procedure or a parent-project renderer.

Private `original-vmap-host/Probe.cs` calls only the fixed DLL's unpak/vwindow/vmap
exports in an isolated x86 development process. Inputs are pinned full MAP/GOP
hashes; source/target buffers have checked guards. vmap receives an explicit
offscreen target initialized to palette index0, avoiding original display/device
initialization. Original input buffers/files remain unchanged. This oracle is not
a player dependency and does not start PAL.EXE.

`tests/test_pal98_map_background.gd` loads the ordinary compiler-produced source
package and selects PAT0/day explicitly. In `map-background-gpu-01`,128 checks
passed in a real Godot4.7.2 window, OpenGL3.3/NVIDIA5060. All20 views of maps
1/10/12/20, including half0/1, negative coordinates and the last row/column,
match the original vmap output at every RGBA byte. The source window was inspected;
map20's bed remains at its source location. This test uses no external PNG/map
conversion. Evidence lives in Studio's existing
`artifacts/verification/original-v163-codex-review-20260912-01/` directory.
The clean exported staged tree without inspection also passed128 checks in
`map-background-staged-01`; independent read-only review found no necessary fixes.
The private host source SHA256 is
`b7647e510a8cffc3953e9997c192ec82e61256bb3e23355d5d46807ef7feb633`,
host EXE `23e287c92b887a04495195f04ac8015483566620a16e5d8779f14cbd8229b4a2`,
original output report `82d11766663687caf59e822d9b0e402e7c763578230ece986c8ccd423b4bec64`.
The first host compile rejected relative slash paths before execution; rebuilding
with resolved Windows paths succeeded. No failed original rendering was replaced.

Replay with local paths and a fresh output:

```
godot --path native --script res://tests/test_pal98_map_background.gd -- <content.palmod.zip> <original-vmap-01/results.json> <fresh-output>
```

## Remaining scene stages

This implements background generation only. exbb selects occluding map cells
using height*16 in its cutoff test; exmap queues those tiles using height*8 in
SortY/LayerOffset, with the upper layer adding1 to both. ntre subtracts image
height and LayerOffset for its top edge. These are different from background
placement. exmap visits row/column/half, and ntre's signed16 sort is nonstable;
the TileMap Y sort above must not be reused as a claim of ntre parity.

Normal scene rendering first clears the tree/flags, queues events then the party,
calls DrawMap/exmap, constructs spans from the already generated background, then
runs ntre and the output/timer/palette/shake tail. Those stages, scene-script
execution, original cold-start selection, save/load, Mac/AMD and Richard
acceptance remain unfinished. The ordinary source-only session guard remains.
