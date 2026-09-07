# PAL Wanxiang Native preview

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
- Authoritative tile movement and ordered followers, separate presentation lerp.
  This eight-tick grid movement is still a technical sample. PAL-style isometric
  motion will use PalWalkDemo/original-research behavior, with collision and
  scalable party trails implemented separately; no GPL source is imported here.
- PNG texture decoding with an 8192-edge/32Mi-pixel aggregate budget; the 2048px
  synthetic texture test preserves its resolution. Map idle/walk clips now have
  explicit per-frame microsecond timing, PNG dimensions, foot anchors and scale,
  directional fallback, and the required `graphics.map-animation.v1` capability.
  Corrupt declared assets reject the package. Audio/font payloads, battle clips,
  multi-layer/depth masks and DOS/Win legacy codecs are not implemented yet.
- Save envelope + state payload hash validation, write/verify/publish of a new
  immutable ZIP generation, incomplete generations ignored, failure retains old
  state, epoch rebinding and RTA never rewinds. Unknown extension data and modified
  origin survive ordinary load/save. Timing is explicitly practice/ineligible.

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
```

The UI test injects engine mouse/keyboard input into the same application and
retains real window pixels under ignored `generated/pal/visual_tests`. It is not
physical human input or a complete playthrough. Synthetic tests do not establish
real-resource, battle, high-refresh-device, Windows ARM64/macOS/Linux acceptance.

The animation fixture is built by the actual Studio from eight generated geometric
RGBA images; the product `run_animation_checks.py` reproduces it without reading
game/art references. Thirty-two window checks cover variable-sized frame anchors,
10ms timing without a logic tick, pause, per-instance facing, save cooldown/history
reset and malformed package rejection. No formal Miaopang art is implied.

Shared contract snapshots are refreshed only with:

```text
python -B tools/sync_contracts.py --contracts-root <existing contracts repo>
python -B tools/sync_contracts.py --contracts-root <existing contracts repo> --check
```

Godot is still needed to run this preview; self-contained player exports/templates,
engine/third-party notices and portable licensed CJK fonts are the next packaging
work. Existing system font fallback was observed only on this Windows host.
