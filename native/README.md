# PAL Wanxiang Native preview

Optional `world.scene-travel.v1` now supports named party entrances, explicit
interaction portals with reciprocal checks, and atomic `scene_transfer` nodes.
The same actor instances move to authored, adjacent arrival slots after checking
capacity, map validity, non-party occupancy and sprite/movement compatibility.
Arrival dialogue/end safe points, saved arrival revisions, render/input resets
and 3/4/5-member round trips are exercised by `tests/test_scene_travel.gd` using
three actual Studio packages. Run it with the 4-, 3-, 5-member ZIP paths and an
isolated output directory. The test includes window input and synthetic failure
cases; it does not certify battle, full playthrough, human input, general region
triggers, persistent follower trails or other platforms. This module is independent
MIT code, as described in SOURCE_BOUNDARY.md.

This is the Native runtime in the existing sword-godot repository. It is an
independently implemented MIT source boundary; see [SOURCE_BOUNDARY.md](SOURCE_BOUNDARY.md).
It is **an implementation preview, not a finished RPG/platform release**.

From this directory, using Godot 4.7.2 standard:

```text
godot --path . -- --package <StoryStudio content.palmod.zip>
```

Or start the project and choose **打开 MOD**. The same application handles package
selection, TileMapLayer rendering, four-or-more party state, dialogue/choices,
movement, pause and checkpoint save/load. Save files go under a separate Godot
user directory `PALWanxiang/NativePreview`; original PAL game data/saves are not
read or written. Each save is a new generation, preserving older ones.

StoryStudio's Native workbench now builds and starts this same application with
`--save-root <isolated preview saves> --preview-stop-file <session/stop.request>`.
Only this explicit development mode polls the empty local stop marker every 0.5s
and prints package/error messages for the author's diagnostic pane. It executes no
file commands and uses no IP transport. Normal player startup has no such polling.
The `application/native_api` project marker prevents accidental selection of the
parent research project by Studio; it is a compatibility marker, not a license or
cryptographic trust assertion. Public tool handshake/stream contracts remain separate.

Arrow keys/WASD move; Space/Enter interact; Escape pauses; F5 saves; F9 opens the
save list. Saving is available at declared `safe_points`. Graphics settings expose
60/100/120/144/240/unlimited presentation rates; the logic clock remains 60Hz.
High refresh display/hardware acceptance remains separate from synthetic tests.

## Implemented boundary

- Offline, data-only ZIP reader; bounded central/local preflight, hashes, exact
  payload set, draft schema/capability/identity/reference validation. It never
  mounts PCK, extracts mod paths or evaluates mod code. A rejected candidate
  retains the active session.
- Dialogue/choice/set/branch/party/end; declared types/scopes, transactional
  automatic-node budget, actor definitions/instances separate, roster distinct
  from active party and narrative cast. No three-slot or six-definition limit.
- Authoritative tile movement with named `native.grid.v1` (eight ticks) and
  `pal.walk.v1` (six ticks / nominal 100 ms), separate presentation lerp.
  Orthogonal and isometric TileMapLayer centers match the shared zero-centered
  projection, including nonzero map origins. PAL input distinguishes new presses,
  held multi-key cancellation and physical aliases; collision checks map and NPC
  occupancy before committing. No GPL source is imported. This is a named Native
  rule, not complete PAL parity; scalable party trails/joins/reorders remain open.
- PNG texture decoding with an 8192-edge/32Mi-pixel aggregate budget; the 2048px
  synthetic texture test preserves its resolution. Map idle/walk clips now have
  explicit per-frame microsecond timing, PNG dimensions, foot anchors and scale,
  directional fallback, and the required `graphics.map-animation.v1` capability.
  Corrupt declared assets reject the package. RGB/RGBA uses truecolor textures,
  without a 256-color quantizer. Transparent-edge preparation changes only
  invisible RGB: all nonzero-alpha source pixels are restored after the engine's
  edge fix, preserving low-alpha effects. Original PNG bytes/hashes are unchanged.
  Audio/font payloads, battle clips, depth masks and DOS/Win legacy codecs are not
  implemented yet.
- Optional `world.tile-layers.v1` terrain: explicit available cells, PNG tiles,
  image dimensions/anchors/scales, flat layers and actor-shared Y-sorted layers.
  Spawn, movement and saved positions reject rectangle gaps. Flat layers share
  one padded TileSet when their scale permits the atlas path; other scales use
  CanvasItem texture drawing without downsampling. A sort offset changes depth,
  not raster placement. Real maps use a clamped following camera at a current
  fixed 2x view; absent terrain retains the diagnostic map. The imported Legacy
  height policy is a declared approximation, not original-game occlusion parity.
- Save envelope + state payload hash validation, write/verify/publish of a new
  immutable ZIP generation, incomplete generations ignored, failure retains old
  state, epoch rebinding and RTA never rewinds. Unknown extension data and modified
  origin survive ordinary load/save. Timing is explicitly practice/ineligible.
- Explicit local source previews accept false asset distribution registrations
  only with the paired `package.local-preview.v1` capability and exact
  `pal.native.distribution: {"scope":"local-preview"}` extension. Null/malformed
  markers reject. The title identifies this scope; all data/hash/budget checks
  stay enabled. Studio's ordinary export still requires distribution registrations.

Runtime caps are currently 16MiB per ZIP entry and 272MiB total, 4096 entries and
65536 map cells. Compiler schema maxima can exceed these operational budgets;
such packages are refused explicitly. ZIP64/multi-volume/comments/stubs/encryption
are unsupported. Empty standard directory entries are accepted as container
metadata, never as content. Concurrent hostile modification of the same package
path while the ZIP is opened is not an established safety guarantee.

The save generation design follows PALDLL's existing transaction principles, but
has no complete journal/current pointer/profile transaction or power-loss fsync
proof yet. Foreign/missing definitions/content locks are rejected; no migration
is silently guessed. G1 tool transport/event stream, fair timing and save editor
transactions remain unfinished. Do not claim full save durability or tool support.

## Tests

```text
godot --headless --path . --script res://tests/test_runtime.gd -- <package> <scratch>
godot --path . --script res://tests/test_ui.gd -- <package> <scratch>
godot --path . --script res://tests/test_animation.gd -- <animation-fixture-package> <scratch>
godot --path . --script res://tests/test_walk.gd -- <pal-walking-fixture-package> <scratch>
godot --path . --script res://tests/test_source_assets.gd -- <local-source-preview-package> <scratch>
godot --path . --script res://tests/test_terrain.gd -- <local-terrain-preview-package> <scratch> <independent-flat-map-reference.png>
```

The UI test injects engine mouse/keyboard input into the same application and
retains real window pixels under ignored `generated/pal/visual_tests`. It is not
physical human input or a complete playthrough. Synthetic tests do not establish
real-resource, battle, high-refresh-device, Windows ARM64/macOS/Linux acceptance.

The animation fixture is built by the actual Studio from eight generated geometric
RGBA images; the product `run_animation_checks.py` reproduces it without reading
game/art references. Thirty-nine window checks cover variable-sized frame anchors,
10ms timing without a logic tick, pause, per-instance facing, save cooldown/history
reset and malformed package rejection. They also preserve 4,099 opaque RGB colors
per frame and all 256 alpha levels through the package and runtime textures, with
GPU readback and a raw-versus-prepared linear-filter edge comparison. No formal
Miaopang art, HDR/color-management or cross-device acceptance is implied.

The additional PAL walking fixture uses twelve geometric PNGs and the real Studio
compiler. Fifty-six checks cover projection, direction edges/aliases, all four
leader/follower phases, collision rejection, saved cadence, malformed save state,
synthetic 30/60/100/144/240 display schedules and actual window keyboard input.
Optional `pal.walk-phase.v1` playback uses three authored stride frames; time-based
HD clips remain available. Save input cadence and pose phase are logic facts;
render interpolation/GPU history are reset on load. No real assets or physical
human acceptance are claimed for that synthetic suite. Shared snapshot receipt:
40ca20946668c7af6f97914a3797c66db6e1cd47. Terrain changes the exact draft schema
hash; older source can be rebuilt, while old package/save identities are retained.

The parameterized source suite separately exercises two imported 12-frame groups
through the production application: 119 checks cover all directions and stride
phases, texture-foot anchors, collision, save/load history, distribution-marker
rejection and retained sessions. The test accepts a locally supplied Studio package;
no original images are stored here. Its map/story remain synthetic; no HD artwork,
full map occlusion, original resource-set lineage or complete playthrough is certified.

The terrain suite accepts local resources without storing them in this repository.
It covers actual tile/collision counts, shared flat atlases, unavailable cells,
four-member movement/save/load and following view, plus full flat-map GPU comparison
against a supplied exporter image. Synthetic cases separately cover HD scale and
front/back/equal-depth ordering. Neither those cases nor the flat image comparison
establish Legacy actor occlusion or a complete playthrough.

Shared contract snapshots are refreshed only with:

```text
python -B tools/sync_contracts.py --contracts-root <existing contracts repo>
python -B tools/sync_contracts.py --contracts-root <existing contracts repo> --check
```

Godot is still needed to run this preview; self-contained player exports/templates,
engine/third-party notices and portable licensed CJK fonts are the next packaging
work. Existing system font fallback was observed only on this Windows host.
