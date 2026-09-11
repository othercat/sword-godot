# Loaded original sprite caches and state-driven GPU composition

`native_pal98_sprite_cache.gd` implements explicit T98/T99 resource reloads and
T163 cached frame addressing. `native_pal98_scene_composition.gd` joins current
event/party state, the existing request consumers and those loaded frames to the
background TileMap, map marks and depth GPU view. Both are internal components;
the ordinary Session still rejects source-only original packages. They do not
initialize a new game, advance scripts, choose Unknown defaults, replace a save
format or provide full original gameplay.

The cache receives admitted table and graphics snapshots with a matching source
origin, retaining both current table and graphics fingerprints. It owns separate
event and party byte arrays. Every byte starts Unknown and records which loaded
MGO supplied it. A reload overwrites only the bytes actually produced by unpak;
old known tails survive. The65536-byte arena is this adapter's bounded nonnegative
signed-WORD address space, not a claim that the original allocation has that size.
Negative, unowned or Unknown addresses diagnose explicitly. No fabricated zero
terminator is supplied.

## Load and draw semantics

Both original caches store WORD offsets. PALOLD paksize reads a signed32 header,
shifts right arithmetically by1, and the VB destination truncates to low16 bits.
It is not a checked conversion:65536 decoded bytes yield signed-32768 WORDs.
Positive odd lengths use floor(length/2); unpak still writes the decoded terminal
byte, which a later append at that WORD boundary can overwrite. Later additions
use checked signed16 arithmetic.

T98 traverses current event slots1..count. Positive SpriteId values read that
direct MGO index; repeated IDs use the last matching earlier event's current
cache offset. New groups first check accumulated+size, then require that sum to
be positive before unpak and offset publication. A nonpositive sum clears the
SpriteId. The common tail, including events whose SpriteId was already
nonpositive, scans signed-positive WORDs from the stored offset until the first
nonpositive entry. It writes the count directly at+0x1C, with no subtraction;
zero count clears SpriteId. This is not the generic sprite-group frame count.
For example, source MGO571 has prefix3,49698,0: its T98 count is1.

T99 ordinary slots0..MemberLast read RoleId and role field2, deduplicating by that
MGO index. The following1..FollowerCount loop uses MemberLast+follower as its slot
and the record's RoleId directly as MGO, without deduplication. It has no T98
positive-sum gate. Its original accumulation check occurs after unpak and the
offset write. Native returns an atomic failure instead of publishing the
original partial writes on failure; callers must not treat this as original
exception-side-effect parity. Negative counters are not normalized into a
different loop; invalid resulting backing addresses diagnose.

T163 reads the supplied cache offset rather than looking up current SpriteId or
role field2. It checks base+frame, reads the signed directory WORD, checks
base+pointer, reads width, checks address+1, then reads height. A negative relative
pointer can validly refer to earlier known bytes when its sum with base is valid.
High-bit or excessive dimensions are explicitly rejected by the existing
1..8192 RLE dimension and32Mi-pixel limits. Returned frames keep only rendering
planes/dimensions/consumption, not duplicated unused tails. Provenance includes
the directory and all MGO chunks contributing consumed cached bytes.

Source replacement failure, bad event state, malformed resources, Unknown data
and loader arithmetic failures retain both published cache and caller state.
Successful loads return detached event/party candidates. The synchronous caller
must adopt the returned state together with that successful cache reload; this
component does not independently schedule a Session update or save it. Replacing
the source successfully clears both caches to Unknown. Drawing never reloads.

## Composition boundary

The caller provides a known map ID, palette/index variant, pixel viewport,
map mode, depth clip, party projection and composition owner. Only DrawMap mode0
is implemented. Palette Unknown and other modes are diagnostics, not day0 or
ordinary-scene fallback. Graphics/cache fingerprints must match. T209/T213
retain their event/party/follower filters and owner order. T163 rows and exbb
marks precede exmap rows, preserving original depth submission order. exrij
derives the background cell from the pixel viewport. No caller-supplied cell
coordinate can silently disagree with the viewport.

The result is one caller-owned320x200 clipped Control containing palette0-colour
underlay, background TileMap and depth sprites. No scene state or loaded cache
is changed; failed construction publishes no view and releases created nodes.
Validation is batched and atomic. The complete pipeline does not claim the first
original exception or intermediate mutations when multiple inputs are invalid.
Ordinary map/resource switching, enter scripts, draw-skip/transition cadence,
retained-view lifecycle and the actual game loop still belong to their owners.

## Fixed binary facts

| Binary / right-exclusive interval | SHA256 |
| --- | --- |
| PAL.EXE | `75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450` |
| PALOLD.dll | `c6a34e511ed1c7bb2ecddfaaba00992d53006db3ed4b5ab3da61943b417227e8` |
| VB40032.DLL | `0f1604c9a7398cbb317383799b88c4e1aa7ce0b2c968392f0a7a9ddff22ec57d` |
| T98 0x40A910..40AAF4 | `9a4116444190357837cdff03b1f984b725ba1114c5196ae2272cd878ae2df5bf` |
| T99 0x40B168..40B370 | `45d3e97f7b73e584ff454a45a4b53178e83e03887a2dd84363b26a2e3133d19b` |
| T163 0x4111BC..411558 | `70c47fd31610c4f54520ba8bf2347c6779741cc93f33eb590af0dfb084275d11` |

paksize reads/shifts at0x10001507/1509. VB StoreLocalI2 at0x0F7A251C writes BX
without overflow checking; fixed-array WORD addressing is at0x0F7A3C97.
T98 precheck/positive gate are0x40A9D6/A9DA, offset write0x40AA16,
directory address/read/count/write0x40AA84/AA8E/AA9E/AABA.
T99 ordinary unpak/offset/accumulation are0x40B262/B27C/B288; followers use
0x40B338/B352/B35E. Older research prose calling T98 offsets bytes and implying
frame-count-minus-one is superseded by these actual instruction facts.
The implementation is independent code from these facts; recovered procedures,
original payloads and a player-side original DLL dependency are not included.

## Validation and remaining coverage

Private evidence stays under Studio's existing
`artifacts/verification/original-v163-codex-review-20260912-01/` root.
`sprite-cache-03.json` passes57 checks, including stale bindings, reload and
source isolation, both duplicate rules, Unknown/cold tails, odd-byte overwrite,
zero-size/nonpositive sums, signed truncation, T98-before/T99-after overflow,
signed relative pointers and dimension/height-address boundaries. Source MGO
2/56/193/571 first frames match the separately addressed graphics reader.
MGO571's second pointer still diagnoses. These real resource fixtures do not
invent a real source event in the empty initial scene.

`sprite-cache-01.json` is a retained failed test run: its assertion included
Unknown inactive slots, and its real-resource fixture assumed an event in an
empty source scene. Those two fixture errors were corrected before the53-check
`sprite-cache-02.json`; four additional address/dimension checks yield57 in03.
No production fix or original-state default was introduced for those failures.

`scene-state-gpu-01/results.json` passes78 checks through the new state/cache
composition API. Six320x200 GPU frames and all16384 flags match the existing
guarded fixed-DLL oracle `original-scene-graphics-02/results.json` (SHA256
`180d4fbc20e2b34aa917451b6f057a13313d273ae958103d6eeb4b6fb7dacde6`).
MAP12 has7 occluding rows, MAP10 has12/12/15, and MAP20 supplies controls.
The MAP10 actual window was inspected. These are explicit resource/state fixtures
on Windows/NVIDIA/OpenGL, not original new game, ordinary Session, gameplay,
save/load, Mac/AMD or Richard acceptance. No new gameplay candidate is released.

Independent read-only review found no necessary implementation fixes. The clean
inspection-free export `v163-scene-cache-index01/native`, tree
`94930d00c0f3e05552f10b097ef28664100ce11f`, also passes57 cache checks in
`sprite-cache-staged-01.json` and78 GPU checks in
`scene-state-staged-01/results.json`.

```
godot --headless --path native --script res://tests/test_pal98_sprite_cache.gd -- <content.palmod.zip> <fresh-results.json>
godot --path native --script res://tests/test_pal98_scene_composition.gd -- <content.palmod.zip> <original-scene-graphics-02/results.json> <fresh-output-directory>
```
