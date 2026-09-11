# PAL Wanxiang Native preview

## Authored story-boundary notices (2026-09-10)

The optional `pal.native.story-notice.v1` component is pinned to owner
`85658024f4a92a9845e82bd59c19e357a0d2fcc2` (28 schema snapshots). Only explicitly
bound end nodes show authored title/body text; ordinary conversation endings
remain free exploration. The existing interaction hint stays outside a bounded
text scroll. Notices inherit the authored map typography, clear on leaving the
node or changing package, and restore from the committed cursor on save load.
They have no new command, timer, gameplay rule, state extension or save field.
Performance boundaries cannot also bind a notice. Admission checks exact
capability usage and the component schema hash.

`tests/test_story_notice.gd` reuses only the relevant existing practice-route
input helpers: short and 2000-character departure notices, return to camp, and
normal defense commands until independent defeat. Product candidate-03 passed
650 checks in the actual 1280x800 Native window and 16 independently validated
saves. The helper uses today's default arrow keys and an isolated preferences
path; the earlier WASD helper failure remains recorded. Package SHA256 is
`b6c16d84cd046dff0043fae01da051c7b611e3aae6bdb04db0eaf9e14ae10fc7`.
These are injected input and production-loader results on one Windows host,
not physical input, system save-picker, packaged runtime, new art acceptance or
a complete work playthrough. Private real-map sources are outside this repo.

## Party card v2 displayed status cells and command markers (2026-09-10)

The runtime now consumes the additive v2 draft from contract owner
`44f8ea5020f33f736443e5535c5b935212734f8a` (26 pinned schemas). V1 bytes and its
phase-focused active border remain unchanged. V2 icons bind stable status IDs,
show displayed stacks/rounds, support text fallback and `+N` overflow, and enumerate
nested images through package texture/dimension checks. The new action marker
follows the command source across target reactions and clears at round-end ticks,
silent reconciliation and terminal poses; it never changes rules or saves.

The product's `run_party_card_v2_checks.py` ran the production Studio form, owner
validator and `tests/test_party_card_v2.gd` in an actual 1280x800 window. Its final
candidate has 54 author-control checks, 1864 Native checks across eight command
traces, 22 v1 element checks and three independently validated saves. Status
add/tick/clear, imported PNG drawing, command/target separation, pause/focus/modal,
skip/load/package switch and synthetic projection/overflow probes passed. The
authored 112-pixel card-height example improves readability over the retained
64-pixel attempt. This is a four-person synthetic fixture, not new Miaopang art,
physical input, a full playthrough, all aspect ratios or packaged-device acceptance.
Subsequent packaging of this runtime source (`5a17925`) and Studio `c83fd7e`
produced a321-file self-contained Windows candidate. Its actual entrypoints,
64 published-assembly card checks, automatic bundled-player package loading and
byte-identical rebuild passed on the same host. Archive SHA256 is
`cd564ffb2273b79808c9dbae44626e5bf26fbca45adfddc43b42eb46e9be7bfc`;
the product's `party-card-v2-portable-results.json` records its exact closure.
Packaged save/playthrough and other devices remain separate acceptance work.

The optional `pal.native.map-ui.v1` draft now supports scene-bound map, party and
dialogue workspace rectangles, supported panel styles and author camera defaults.
Local view overrides remain outside saves and reset on explicit author-view reset
or package switch. Scrollable dialogue retains focus access; battle transitions
restore original parents, sizing flags and styles. Contract owner is `e1303e6`.
The product's map-UI candidate-04 has 61 workbench checks, 52 actual Native window
checks and three independently verified saves on the preserved real-map source.
Walk/collision results match a package differing only in presentation. The retained
v2 battle-card fixture also survives a package round trip. Map portraits/internal
widgets, full playthrough and human/device acceptance remain separate. This source
(`7850630`) and Studio production `8479931` were subsequently packaged as a fresh
321-file self-contained Windows ZIP. Its SHA256 is
`2a611b27c295ef954d76f07623675cbe469543e8a6b7d437e94586629a71fe18`;
PCK SHA256 is `8cfdcd7b70ddf2c36935f88836f802867c2f9cd62aa6554792a214b52069c759`.
The actual production entrypoints and 71 published-assembly map form/preview
checks passed, automatically loading the authored package with the bundled player
and no Godot project. Owner admission and byte-identical GUI/CLI rebuild passed.
The product's `map-ui-portable-results.json` records the exact closure. Source
movement/battle/save checks remain separate from packaged route/device acceptance;
the earlier card-v2 archive is retained and predates map UI.

Battle status presentation now follows the existing committed event indices.
Add uses the committed total stacks and source; remove/clear happens at its own
event. Silent remaining-round changes reconcile from the exact pre-cleanup result
after all events and before terminal poses. This display boundary does not infer
whether a rule tick ran from the round number, call rules or advance authority.
Body status descriptions and sleep poses share copied display rows during playback;
skip, load and package activation discard that temporary projection.

`tests/test_status_presentation.gd` combines the previously authored status/action
fixtures and traces 90 ordinary commands across 3/4/5 party, including refresh,
stacking, removal, expiry, persistent death and revival. Synthetic cases separately
cover capped/zero application, replace, double-hit event consumption, early enemy
loss versus status-tick victory and failed transaction/callback emission. Windows
GPU runs pass 11613 status checks plus 171 existing animation checks; 45 saves are
independently validated. The product's `run_status_presentation_checks.py` records
exact source/input hashes and failures. This does not add configurable status icons
or certify real art, physical/human acceptance or complete content.

Optional `pal.native.party-card.v1` separates internal panel, portrait, text,
HP/MP bars and decorative images from the outer HUD layout. Encounter templates
contain ordered, individually clipped percentage rectangles; actor-definition
overrides replace the list for that character, independently of battle seats.
Absence/removal keeps the old card renderer. Bars crop fill art in any of four
directions; text measures, shrinks/ellipsizes and aligns inside its own rectangle.
Images use registered PNG identities/dimensions, tint and the existing sampling
precedence. There is no arbitrary script or font loading.

All elements consume one displayed actor snapshot, including effective maxima,
and never read already-settled values during playback. Decorative controls ignore
mouse input, reuse draw nodes and remain outside save authority. Status icons can
use the display projection above but are not part of this component version.
Studio supports selection/drag/resize/nudge, list ordering, per-character copies,
PNG decode before import, one-apply undo and restoration of the legacy template.
The current 25-schema snapshot is `f50b3da867260a8aa0788cfcb2cc75f01bd8be8b`.
The product repo's party-card receipt records actual-window and save evidence.
Four production-Studio packages pass 5885 checks in 20 GPU windows and eight
independent save checks, with 21 admission cases agreeing with the Python owner.
The probe also renders separate synthetic long-name/large-number/zero-maximum,
death and narrow-card cases without changing authority. Original portrait PNGs
remain low resolution; this does not certify HD art, human or cross-platform use.

Optional `pal.native.hud-placement.v2` adds independently authored aspect layouts.
Each encounter retains default geometry and an ordered list of rational minimum
width:height conditions. All consumers select once from the unreserved logical
battle stage, then lay out cards, actor canvas and commands from that selection.
Window decorations, the logical stage and render pixels are recorded separately
in the actual-window probe; resizing never writes gameplay or save authority.
Studio can edit names, conditions, geometry and per-count cards, preview five
common ratios or custom dimensions, and apply/undo the entire profile at once.

The aspect-v2 verification pinned `23b6c12b201657f88c0fe5eb45984f47f603327f`.
V2 requires its own exact hash/capability pair; the v1 schema bytes and old package
behavior remain intact. Empty variant lists retain default geometry. Duplicate
identities/equivalent ratios, unsorted conditions and invalid nested rectangles
or seat tables reject admission. This selects presentation only, not more actors.

Six actual Studio fixtures pass 1214 checks in 30 GPU windows and twelve independent
save checks; thirty admission cases agree with the Python owner. Headless geometry
adds 982 aspect checks to the existing 4144 base checks. The window probe asserts
actual sizes and commands/target cancellation at every size. The author's common
presets show square bottom rows, 4:3/16:10/16:9 bottom cards and 21:9 right cards;
edited thresholds/left cards also work. Default Boss fixtures use all-action
occupied extents with common group fit/separation; old manual overflow fixtures
remain separate. Evidence and source hashes are in the PAL Wanxiang product repo's
`hud-aspect-results.json`. These checks do not certify artwork or physical input.

Optional `pal.native.hud-placement.v1` adds authored party-card regions and actor
canvas rectangles, plus independent per-count card rectangles. Left/top/free
Studio presets use the same runtime layout path. Unspecified counts retain flow
layout; the original HUD schema and content without the component stay unchanged.
Cards keep existing portrait/data bindings, and command images retain their own
layout relative to the actor canvas. Background canvas configuration is independent
and still fills the stage by default. Geometry is display-only, never saved state.

The v1 verification used owner `dd805bd04858e85e76b471e8546a9400eeedc080`. Admission requires
the paired capability, exact schema hash, an existing responsive HUD, bounded
rectangles and complete, unique count tables. Malformed components are rejected
without crashing early HUD validation. Geometry tests cover 4144 checks, including
small regions and 1/3/4/5/16 seats. Four actual Studio packages pass 366 checks in
12 GPU windows and eight independent save validations; the 16 admission cases
also agree with the independent Python owner. These Windows/Godot 4.7.2 samples
use five actual combatants, original command artwork and private Boss sprites.
They do not expand the Dream 1–5 gameplay gate or certify art/physical input.
Arbitrary map UI and complete mod-editor coverage remain pending.

The optional `pal.native.sampling.v1` presentation component now requires the exact
owner schema hash and `graphics.sampling.v1`. ClassicLowRes and PixelHD default to
nearest filtering; IllustratedHD defaults to linear. Explicit scope choices take
precedence over existing widget filters, which precede profile defaults. Packages
without the component retain their previous filters, including inherited values.

The runtime applies the nine scopes to map sprites (including performances), flat
and depth terrain, map background, battle sprites/background, HUD portraits and
bitmap imagery, command images and final surface. Separate CanvasItems keep battle
background and HUD portraits independent of neighboring imagery. A successful new
package load resets the surface policy; a rejected load preserves the active session.
This does not upscale source detail, quantize RGBA, implement integer display scaling,
change combat or provide cross-content save migration.

`tests/test_sampling.gd` accepts a fixture manifest and isolated output directory for
windowed checks; `--baseline` restricts it to old-content screenshot comparisons.
The product workspace owns fixture derivation from local author art. The current
verification covers three HUD layouts, profile and mixed overrides, old reloads,
invalid admissions and same-package saves on Windows/OpenGL. Studio GUI filtering,
formal artwork acceptance, sustained high-refresh and other platforms remain pending.

Desktop input defaults to classic arrows and the traditional left-hand actions:
F skills, E battle items, D guard, Q escape, S effective party status, W map
equipment. Enter/Space/Ctrl confirm; Esc/Alt cancel. The player can select the
earlier WASD movement preset or preview and apply a local PALDLL `key.ini` in
the header's key settings. Only `[Remap]` is imported; sparse rows retain missing
classic bindings, explicit zero disables a key, duplicate scans keep the first
row with a notice. Unknown/malformed rows reject the whole import. Original
configuration, package files and saves are not edited. Local `user://input.json`
is saved with a unique backup; `--input-profile <path>` isolates preview tests.

This independently written adapter uses Godot physical key positions and key
location, not Windows hooks or DirectInput polling. Left/right modifier and
keypad fixtures are covered by injected events; physical NumLock/layout/AltGr,
OS focus behavior and Mac/ARM hardware are not yet verified. Native adds keypad
Enter as a default confirm alias. Row order is retained in preferences; this
does not reproduce CKey simultaneous-key priority, legacy polling cadence or PALDLL's
optional action buffering. Confirmation is edge-triggered; movement retains the
existing named cadence, and arrow/page keys navigate current enabled controls.
Embedded dialogs retain normal text and UI keys. Mouse input remains available.

Repeat, surround/auto attack and battle throwing are explicitly unavailable;
map spells/items and cooperative rules are still separate work. They are not
silently translated into other commands. Existing skill/item targets, defense,
escape eligibility, animation playback and immutable save transactions remain
the authority. `tests/test_input.gd` covers import/configuration, actual window
key/mouse events, command and target selection, modal/focus guards, persistence
and retained original-art author packages. Test reports separate synthetic
signals and injected events from physical keyboard or complete-play evidence.

An explicitly authored `pal.native.attack-formula.v1` component selects the
deterministic `pal98.base-physical.v1` ordinary-attack adaptation. Native uses
the shared contract's wide-integer base curve: party attacks request twice the
base, enemies once; guarding doubles defense before an enemy ordinary hit.
Zero damage still consumes the action, without damage-triggered status removal.
Progression, equipment and Native status modifiers feed effective attack/defense.
Skills and items retain their existing calculations. This component alone has
no randomness or critical hits. Resistance, cover, legacy status mapping and
extra-script semantics remain future work; this is not complete PAL98 combat.
Packages without the component retain their old results.
Its capability/schema hash and rules version 0.15.0 are checked on admission;
changing the choice changes content and rules locks, not existing player saves.
`tests/test_attack_formula.gd` consumes independently specified arithmetic vectors
and an actual Studio-authored package; it labels synthetic cases separately.

An additional optional `pal.native.attack-random.v1` component selects the
partial `pal98.player-hit.v1` profile, capability `battle.attack-random.v1` and
rules version 0.16.0. Its author seed, explicit critical-status binding and
bonus actor-definition list are part of content/rule identity. Each party
ordinary hit consumes exactly four `pal.native.lcg24.v1` draws for additive
variation, critical, proportional variation and an optional actor bonus.
The arithmetic follows the new contract's exact rational, nearest-even rules;
it does not copy recovered procedural code or reproduce legacy I2 overflow.

The existing state RNG object saves a canonical seed and draw cursor. Loading
resumes that cursor even if the live session has advanced; validation checks
the authored seed/algorithm/cursor using logarithmic jump-ahead. Cancelled or
failed commands preserve the complete state and RNG. Rendering, save IDs and
wall-clock time do not advance this gameplay stream. New runs deliberately use
the author's chosen seed. The generator is deterministic, not tamper protection.

The standalone 0.16 profile excludes full physical resistance, double/all attacks, hidden
experience, enemy random/block/cover, attached scripts and original rendering
random consumption. It cannot claim full original per-seed combat parity.
`tests/test_attack_random.gd` covers the real author package, 3/4/5 party variants,
replay, failed callbacks, exhausted cursors, status/definition bindings and
separate synthetic 60/100 display steps; physical high-refresh output is not
certified. Removing this optional component restores the fixed formula.

Native packages now open from a local directory or its exact `manifest.json`,
as well as the existing ZIP. The player picker offers both entries; Studio's
default preview selects its emitted `content.palmod/manifest.json`. The same
package admission checks validate hashes, rules, identities and decoded PNGs.
Directory content is read once into the loaded session, with no live asset
overrides or base-game lookup. Identical manifest bytes mean identical save
compatibility, independent of storage form. `.palsave` storage is unchanged.

`native_directory.gd` checks the complete tree and rejects links, undeclared
files and portable-name/size conflicts. Its local path checks precede reading;
no ACL or permission changes are needed. `tests/test_loose_package.gd` exercises
the production application with original-art packages, cross-storage saves,
malformed directories and Windows junctions in disposable local copies.
This does not implement direct MKF loading or player release packaging. Other
OS filesystem behavior, hostile concurrent replacements and physical file-picker
input require separate verification. See the contract owner's `docs/native-v1.md`.

An encounter can now opt into `pal.native.battle-hud.v1` with the paired
`graphics.battle-hud.v1` capability and exact component schema hash. Studio's
status-bar layout section authors bottom 3/4/5 presets or a right stack,
geometry, RGBA colors, font/filter and registered portrait bindings separately.
`native_box_layout.gd` only computes rectangles; `native_responsive_battle_hud.gd`
renders the supported HP/MP widget from stable actor identities and the current
playback snapshot. Reserving HUD space fits battle presentation into the
remaining area. Source PNG sizes do not force card dimensions. No stat, timer,
rule, save identity or action direction is defined by this layout component.

This v1 component still requires an explicit classic/Dream presentation layout.
It cannot coexist with the fixed-slot PNG UI skin on the same encounter; remove
that binding explicitly first. No component means the previous behavior.
The generic rectangle helper does not yet implement new enemy formations or
side-view cameras. Large-party geometric fit is not a readability verdict.
Contract details: `pal98-runtime-contracts/docs/native-battle-hud-v1.md`.
Run `tests/test_box_layout.gd` for synthetic geometry and
`tests/test_responsive_hud.gd <fixtures.json> <fresh-output>` for authored
packages with routed window input. Screenshots/art acceptance, physical input,
full gameplay and cross-platform verification remain separate evidence.

The first battle presentation milestone has an explicit Dream preset,
`pal.dream-oblique.v1`, carried by optional `pal.native.battle-layout.v2` and
`graphics.battle-layout.v2`. Studio selects it through its existing battle page.
It uses the named Dream source's 1–5 party feet, four bottom status boxes plus
the fifth at right-middle, and 30x30 root commands shifted up by 47 reference
pixels for four or five participants. Imported enemy positions bind stable
instance IDs to the selected DATA positions plus the recorded unsigned Y offset.
This preset checks 1–5 party/enemies at authoring, battle entry and save loading;
the generic 32-enemy mode and old v1 presentation keep their existing scope.

`native_dream_battle_hud.gd` shares the battlefield's 320x200 reference transform
and disposable animation snapshot. Reference coordinates do not constrain PNG
resolution or RGBA colors. Dream sprites retain authored scale and clip at the
stage boundary. The independent glyph/frame drawing is not the original RLE UI;
submenu confirmation, approach animation and current training damage remain
Native behavior. Cooperative stays disabled. Future rule calibration starts with
confirmed PALDLL_DX9 evidence, then SDLPal-lcx gaps and Dream-only behavior.

`tests/test_dream_battle.gd <geometry.json> <fresh-output>` takes independently
recorded source expectations and Studio packages. The current Windows run passed
405 checks over 1–5 party at 1280x800, 1920x1080 and 1680x720; imported outcome
checks passed 68 and retained v1 window regression passed 522. The contract owner
independently inspected 24 saves. These use injected window input and synthetic
display-clock steps, not physical input, sustained high-refresh or full gameplay.
Source artwork and captures remain local. Low-resolution source-art integration,
loose external player assets and direct MKF loading remain subsequent work;
today imported author PNGs are compiled into the content package.

Studio's `samples/miaopang-camp-native-practice` now connects the existing runtime
features into a named opening slice: optional five-person camp drill, solo audience,
one supply package, reunion and three-person departure. The new
`tests/test_miaopang_practice.gd` uses ordinary session commands and injected window
input over the same compiled content, including defeat, escape and save resumption.
No runtime rules or contract bytes change in this round. This is not a full chapter,
an exported player application, an art approval or high-refresh acceptance.

Optional `actors.equipment.v1` adds per-instance worn item references and an in-game
equipment menu. Studio authors slot identities, signed attribute modifiers and
definition eligibility; initial loadouts debit existing shared inventory once.
Changing gear is an atomic inventory/loadout transaction outside combat. Lower
maxima clip HP/MP without healing or reviving; growth, status effects, targeting,
battle settlement and saves consume the same derived attributes. The additive
equipment component is pinned separately and the four base schemas retain their
bytes. Existing packages remain unchanged. See the contract owner's
`docs/native-equipment-v1.md` and Studio's `docs/native/NATIVE_EQUIPMENT.md`.
Current gear does not grant skills, dynamic affixes, durability or enemy loadouts.
No legacy memory layout or equipment scripts are copied into this MIT project.

Optional `battle.enemy-actions.v1` now runs ordered per-instance enemy skills through
the existing target/effect/status engine. The additive component is stored in content
extensions and pinned separately; the four base schema files remain byte-compatible.
`native_enemy_actions.gd` selects rules, while `native_battle_effects.gd` admits complete
player/enemy action blocks and `native_session.gd` rejects more than 8192 events before
publishing a candidate. Enemy casts use the existing committed animation and show the
authored skill name. No enemy script runtime, Legacy slot projection, or new save engine.
See the shared owner contract `docs/native-enemy-actions-v1.md` and product evidence
`PAL-Wanxiang/docs/evidence/g1-native-20260907/ENEMY_ACTION_IMPLEMENTATION.md`.
`tests/test_enemy_actions.gd <compiled-variant-list.json> <isolated-output>` covers
3/4/5-party windows, revival seats, action-time retargeting, item/cast blocks, silence,
HP policies, multi-cast saves and complete candidate rollback. Frames/state stress
cases are explicitly synthetic; this is not complete gameplay or art acceptance.

Optional `world.portal-gates.v1` evaluates the existing condition AST on portal
interaction before changing any gameplay state. Each direction is independent;
players see only authored blocked text. Successful entry clears earlier refusal
messages. Loading re-evaluates restored scopes; direct story transfers stay
independent. Rules 0.7.0 include `native.portal-gates.v1`. The parameterized
`tests/test_portal_gates.gd` exercises the actual window with injected input,
story unlocking and saved-state restoration; it is not human playthrough proof.

Optional `world.regions.v1` adds leader enter/exit rectangles, typed conditions,
once/repeat/cooldown policies and persistent per-run mutex winners. Overlapping
crossings run in priority/ID order in one candidate transaction; dialogue queues
survive saves and transfers clear stale queues. Rules 0.6.0 declare
`native.regions.v1`. `tests/test_regions.gd <actual Studio region ZIP> <isolated output>`
covers the author package and explicitly labeled synthetic policy/failure cases.
`tests/test_region_ui.gd` uses the same region ZIP and an isolated output directory
to exercise actual application keyboard/mouse events: crossing, dialogue input
reset, queued save/load and once behavior. Injected input is not human acceptance.
The owner contract `docs/native-regions-v1.md` documents draft migration, graph
budgets and save checks. This does not implement every PRD event or Echo credit.

Optional `story.conditions.v1` adds bounded typed condition trees to existing
`branch` nodes. `native_condition.gd` evaluates declared scopes against the same
candidate transaction as preceding `set` effects; errors roll back the activation.
Legacy `variable`/`equals` branches remain valid source. The condition tree is
limited to depth 8 / 128 nodes; integer comparison and typed set membership do not
coerce strings or booleans. Rules 0.5.0 declare `native.conditions.v1`.
`tests/test_conditions.gd` consumes an actual Studio-authored package and an
isolated output directory, with synthetic numeric/scoped-state fixtures. It
checks both branches, rollback and exact save recovery; no region scheduler,
once/cooldown/mutex, battle or full-story acceptance is implied.

Optional `world.scene-travel.v1` now supports named party entrances, explicit
interaction portals with reciprocal checks, and atomic `scene_transfer` nodes.
The same actor instances move to authored, adjacent arrival slots after checking
capacity, map validity, non-party occupancy and sprite/movement compatibility.
Arrival dialogue/end safe points, saved arrival revisions, render/input resets
and 3/4/5-member round trips are exercised by `tests/test_scene_travel.gd` using
three actual Studio packages. Run it with the 4-, 3-, 5-member ZIP paths and an
isolated output directory. The test includes window input and synthetic failure
cases; it does not certify battle, full playthrough, human input, general region
triggers or other platforms. Persistent follower trails have their own suite below. This module is independent
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
compiler. Fifty-seven checks cover projection, direction edges/aliases, all four
leader/follower phases, collision rejection, saved cadence, malformed save state,
synthetic 30/60/100/144/240 display schedules and actual window keyboard input.
Optional `pal.walk-phase.v1` playback uses three authored stride frames; time-based
HD clips remain available. Save input cadence and pose phase are logic facts;
render interpolation/GPU history are reset on load. No real assets or physical
human acceptance are claimed for that synthetic suite. Shared snapshot receipt:
c1a1685cab8645bea9060b778fa1fc9e0686511d. Optional party trails change the exact draft schema
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

The optional `native.party-trail.v1` rule plans bounded, cardinal rendezvous paths
and retains pending footsteps through turns, idle catchup, joins, leader reordering,
scene travel and save/load. Its capability is `movement.party-trail.v1`; the Studio
sample now opts in. Active members can overlap during reversal or rendezvous;
inactive actors block movement. Planning never teleports actors and is shared only
by this runtime. Whole-story budget/obstruction failures retain preceding state.
`tests/test_party_trail.gd` accepts three locally compiled 3/4/5-member packages
whose second choice reaches a Studio-authored party node, plus an output directory.
Its 326 checks cover pending-path continuation, invalid saves, atomic changes and
the real zero-input application loop/TileMap window. Package/model tests are
synthetic; the separate parameterized source/terrain suites provide real-art/map
evidence. This is not a complete battle, 32-member performance or device acceptance.

The [battle turn core](docs/BATTLE_TURN_CORE.md) adds ordered 3/4/5-member command
testing, attack/guard/escape, three story outcomes and command-wait save/restore.
Its geometric presentation is a foundation, not full skills/items or hero art.

Shared contract snapshots are refreshed only with:

```text
python -B tools/sync_contracts.py --contracts-root <existing contracts repo>
python -B tools/sync_contracts.py --contracts-root <existing contracts repo> --check
```

Godot is still needed to run this preview; self-contained player exports/templates,
engine/third-party notices and portable licensed CJK fonts are the next packaging
work. Existing system font fallback was observed only on this Windows host.

## 物品与库存（2026-09-08）

`inventory.items.v1` / `native.inventory-items.v1` 接入可选稳定物品定义、初始库存、剧情增减和完整保存。`native_inventory.gd` 维护有界排序库存，`native_battle_effects.gd` 是技能/物品共用的目标与效果结算；`native_skills.gd` 仍负责技能归属和MP，物品独立负责数量。`native_session.gd` 将数量/效果/胜败回调纳入同一候选事务，失败全部保留。`native_skill_menu.gd` 的独立技能/物品实例共用分页与目标选择，epoch/执行/步数/角色变化清理待确认状态。

合法物品使用只在消耗标记打开时扣一件；全体仍扣一次，不扣MP。非消耗品也需持有，零收益合法治疗仍消耗行动和物品。故事发放节点提交稳定执行ID；读取等待保存不重放。保存校验包含使用后余额、技能扣费后MP上界及完整有序结果，不能当作反作弊历史重建。

工坊通过物品页及物品变化节点生成同一包；`tests/test_items.gd` 接收三个3/4/5人作者包和隔离结果目录，验证真实引擎窗口输入、使用/复活/奖励及12份保存。正常基础规则、MP技能、地图和RGBA路径分别保留。测试内容为合成训练属性，非物理输入、正式美术或完整游玩；战外背包/商店/装备/随机掉落/库存条件继续后续工作。

## 战斗状态（2026-09-08）

`native_statuses.gd` 接入 draft `battle.statuses.v1`，通过既有技能/物品效果添加解除。作者可配置叠层、刷新/替换、持续轮数、攻击/防御修正、跳过行动、禁止技能、受伤/死亡解除与每轮末的伤害/治疗。稳定身份、来源和剩余轮数随战斗保存；状态清除、容量失败和战后回调共享会话候选事务，失败不半写。气血栏显示状态，悬停查看完整列表。详见[战斗文档](docs/BATTLE_TURN_CORE.md#authored-battle-statuses)。

`tests/test_statuses.gd` 用工坊控件生成的三个作者包，验证3/4/5人正常输入、周期结算、控制、获胜与自然死亡/复活，保存21个待独立检查的合成状态。非法存档与容量/回调故障为单独标注的内存测试。高刷呈现不推进状态效果；正式角色动作、完整战斗平衡、其他设备与人工玩法验收仍需后续工作。

## Battle targets and layout (2026-09-08)

Enemy command buttons show stable ordinals, names and HP; full MP/status detail
is available in their tooltip. Hover a command or use Tab and Enter to choose its
target. The most recent mouse/focus interaction owns the preview, including
single/all-target skills, items and dead-ally revival. Battlefield sprites are
not directly clickable. Party information remains in the shared sidebar.

The view uses one fitted projection for bodies, ordinals, target marks and effect
text. All authored action extents participate in fitting; large groups preserve
relative image scale and may make smaller actors less readable. The application
currently keeps its 1280x800 logical canvas and letterboxes other window ratios.
`tests/test_battle_layout.gd` checks actual GUI input, GPU feedback, package
release, five-party art and explicit large-art stress at four window sizes.
These automated cases do not certify full playthroughs or additional devices.

## Committed battle action presentation (2026-09-08)

`graphics.battle-animation.v1` binds optional actor `battle_sprite_set` to a
separate side-facing action table, sharing map frame/PNG validation. The existing
package loader validates actual PNG dimensions and side consumers; no DOS data,
Python, native compiler or automatic mirror is used by the player path.

`native_battle_presentation.gd` receives committed before/result/outcome copies.
Source action, hit, lethal dead and metadata phases project bounded result values
without rerunning rules. Hidden map/dialogue/command input is gated during playback;
pause, modal and focus freeze it. Saving writes authority, and load/skip/package
change clears the queue and package reference. Geometry remains explicit fallback.
Three/four/five seats use an independently authored ascending diagonal, while all
party information remains in the same sidebar. No gameplay formation is implied.

Tests `test_battle_animation.gd` and `test_battle_art.gd` use the actual application
window: synthetic author packages and generated Miao art are separate evidence.
They distinguish injected input, diagnostic phase selection, legal command chains,
actual save files and synthetic60/100/144/240 timing. High-refresh devices, final
companions/pets/formations, ATB/realtime and three-platform delivery remain pending.
The MIT native boundary is unchanged; no GPL SDLPal/PAL research code was copied.


## Instance growth and level learning (2026-09-08)

`actors.progression.v1` consumes the optional MIT `pal.native.progression.v1`
component. `native_progression.gd` keeps authored curves separate from persistent
world-actor XP, level and learned skills. Battle enemies keep their base stats.
Effective stats flow through attacks, healing/revival, statuses, target selection,
menus and save inspection. The sidebar displays level/XP and the last reward.

The first defeat of each enemy records the living party at that moment. Victory
settlement separately applies final eligibility, per-enemy death percentage and
XP saturation, all in the same candidate as the callback. Loading preserves the
ledger without paying or learning again. Node/run/executor identity and current
command defeat events are checked; this is not a complete anti-cheat replay.

The four base schemas remain byte-identical. New packages pin the optional schema
hash and require rule version 0.13.0. Old content locks/saves are not silently
migrated to new curves. Tests in `tests/test_progression.gd` use the actual window
and saved files, with explicit synthetic HP/status/callback fault cases. They
cover 3/4/5-member author packages; this does not certify final game balance,
secondary training XP, random learning, complete stories or additional devices.

## Terrain rendering and measurement (2026-09-08)

Flat terrain layers now share a bounded packed GPU atlas. Uneven HD dimensions
fall back to individual sources before a large common-cell allocation. Padding
keeps explicit anchors and visible RGBA unchanged. Depth-sorted sprites retain
their existing actor-relative ordering. Only the current immutable map is kept
across scene/party/save presentation resets; new packages or maps release it.
Real terrain no longer allocates an invisible diagnostic tile grid.

`tests/test_terrain.gd` covers full-map GPU comparison, unequal anchors, actual
packing fallback, depth ties and map/package lifetime. The parameterized
`tests/measure_camp_performance.gd` measures a fixed camp package in the normal
application window, using injected movement and ordinary session commands:

```text
godot --path native --script res://tests/measure_camp_performance.gd -- <camp-package> <isolated-output> 8 1280 800 0 0 sweep
```

Keep the window visible and focused. Interrupted phases remain in the data and
are excluded from performance comparisons. Raw frame intervals, separate render
CPU/GPU counters, loading and transfers are recorded. The 30 FPS case is a timing
diagnostic; the author-facing menu still offers 60/100/120/144/240/unlimited.
The current 1280x800 canvas uses a 982x481 world viewport, including when scaled
into a larger window. These short single-host measurements do not certify native
1080p, physical high-refresh output, long-duration frame pacing or other platforms.

## Retained v1 classic battle presentation

Packages may opt an encounter into `pal.native.battle-layout.v1` with the paired
`graphics.battle-layout.v1` capability and exact component contract hash. Studio
authors this component and portrait bindings through the existing battle editor.
The classic preset contains the entire 320x200 reference stage and background,
projects explicit 1–5 party foot arrangements, uses authored frame proportions,
and displays per-instance HP/MP and optional matching portraits along the bottom.
The reference canvas is independent of texture resolution and RGBA color depth.
In this retained v1 preset, enemy placement remains the Native generic formation.
The new v2 Dream option above adds source positions; neither reproduces the full
original RLE command icon skin.

`native_classic_battle.gd` owns presentation configuration; `native_battle_hud.gd`
consumes the same disposable actor snapshot as the battlefield. Root Attack opens
the target menu, Escape cancels it, and focused commands scroll into view. Skipping,
pausing, loading and final party retirement keep gameplay settlement independent.
No camera/HUD fields enter save authority, no gameplay rules version changes, and
old packages without the component retain their prior presentation. Content locks
still change with presentation edits; this does not implement save migration.

`tests/test_classic_battle.gd` accepts three camp packages (5/4/3), an unchanged
camp package, a directory of deliberately malformed package fixtures, and a fresh
output directory. The product runner builds the private variants through Studio,
drives real author controls and runtime window input, and inspects emitted saves
through the contract owner. This is not physical user acceptance or cross-platform
proof. No original portraits or game assets are included in this repository.

## Optional player physical actions

The subsequent `pal.native.player-physical.v1` component selects rules version
0.17.0. It adds authored enemy level/resistance, single/double/all-target ordinary
actions, explicit instance order, and saved per-battle action counters. Single
actions use 5 or 9 draws; all-target actions use 2 or 3. Bouts calculate before
aggregate HP settlement; presentation plays recorded hits without another RNG
call. The previous four-draw profile remains unchanged when used without this
component. On its own, this profile records counters without secondary growth.
`tests/test_player_physical.gd` covers the author-built package, commands,
status-triggered double hits, save replay and separate synthetic cases.

## Optional secondary training and escape checks

The additional `pal.native.training.v1` selects combined rules 0.18.0 and the
paired capabilities `actors.secondary-training.v1` and `battle.escape-check.v1`.
Studio authors seven caps, a cost table, initial per-definition secondary values
and enemy dexterity. `native_training.gd` owns command counts, final-living
encounter rewards, seven-category growth, recovery and saved receipts. Ordinary
physical attacks, casts, guarding and failed escape supply the relevant counts.
Magic strength can grow through casts. Dexterity has authored initial values
and persistent fields but no normal action count, so normal play cannot advance
it. Neither stat yet affects skill damage or scheduling. Flee rate checks one logical RNG draw against the
sum of living enemy-instance difficulties. Failed escape spends a command.

At the maximum secondary level, remaining XP consumes full thresholds without
extra growth draws. Primary growth, secondary gains and caps precede existing
equipment bonuses; HP/MP recovery clamps to effective maxima. Candidate state
publishes progression, RNG and outcome callbacks together or leaves all intact.
Save inspection reconstructs enemy HP events before escape and checks the
action/award/RNG chain. These bounded receipts are consistency evidence, not
cryptographic protection or full historical battle replay.

`tests/test_training.gd` covers a Studio-authored package, 3/4/5-person variants,
failure/success escape, skill/guard/attack counts, battle outcomes, save replay,
RNG exhaustion and callback failure. The private product runner separately
verifies author controls, package admission and old packages. Costs/caps are
explicit author choices, not an included original table. No original code or
assets, Legacy save migration, unchanged original RNG sequence, full original
battle parity or cross-platform acceptance is claimed by this increment.

## Authored formation, ground shadows and enemy HP widgets

Optional `graphics.battle-formation.v1` maps per-encounter party/enemy regions,
manual stable-instance/party-slot points, group scale, offsets and shared fitting
to the complete actor canvas. `native_battle_formation.gd` owns disposable geometry;
`native_battle_view.gd` shares resolved anchors with ordinary targeting and playback.
All-action alpha bounds include static fallback, target markers, shadows and HP.
Contain-mode cover/attack movement uses the moving actor's own extent.

Group and individual shadow settings draw translucent ellipses attached either
to the current PNG's bottom occupied pixels or to the authored ground anchor.
Original PNGs are unchanged. Source contact may need author correction for long
weapons/tails or flying creatures; this is not a physical lighting model.

`graphics.enemy-overlay.v1` renders a bounded HP widget with per-instance offset
and width overrides, display-state values and whole-widget canvas clamping.
Font measurement and paint use one local layout and uniform transform. No new
network, original-game dependency, combat authority, save or timer fields are
introduced. Old packages without these components retain their existing behavior.
The contract owner documents precise defaults and limits in
`docs/native-battle-formation-v1.md`. New draft content locks require matching saves.

## Independent authored command panel

`graphics.command-panel.v1` optionally replaces the responsive HUD's default
command rectangles and appearance. `native_command_panel.gd` resolves one geometry
table on initial creation and resize, preserving existing focus/input/rule dispatch.
Each of four stable commands has an independently sized rectangle, builtin/image
appearance and optional normal/focus/disabled PNGs. Group anchor, offsets, uniform
scale, clamp, sampling, image fit and RGBA multiplication are content parameters.
Button image bytes are unchanged. Accessible names and tooltips remain even when
native Button text is suppressed to remove its minimum-size floor. Builtin labels
are painted within the same uniformly fitted rectangle.

The optional component requires a responsive HUD and exact capability/schema hash;
old Dream PNG skins retain their existing admission boundary. HUD disposal does
not mutate package content. State and saves contain no command-panel fields.
The current cooperative command is still unavailable: artwork cannot enable it.
Disabled imagery is used only while disabled; normal/focus images return when a
command becomes available. The product retains original dark-red disabled art;
muted bronze/gray is an alternative. Original shapes must not be redesigned.
Actual window/asset and injected-input coverage is separate from manual artwork
acceptance; see the product command-panel receipt for precise tested sources.

## Named map performances (draft)

`story.performance.v1` consumes the owner contract `pal.native.performance.v1`.
The optional component binds explicit end-node boundaries to named PNG clips,
world-instance tracks, a duration and a continuation. This does not extend the
old map idle/walk enum or replace its renderer. The existing frame sampler and
foot-anchor drawing handle performance frames of different sizes and scales.
Offsets affect projected visual feet and depth sorting, not gameplay positions.

The session waits at the boundary and advances elapsed 60 Hz logic ticks. Pause,
focus loss and modal UI freeze it. Completion and permitted skip use the normal
transactional executor; failed continuations keep the prior state and tick.
The app holds a pending map timeline while an earlier battle result is still
being presented. Render calls never dispatch continuation effects. Per-frame
sampling currently follows saved logic ticks; higher-rate interpolation and
the unified sampling profiles are separate pending work.

Baked-composite tracks can hide explicitly listed participant visuals. No actor
is deleted or merged; scene, position, HP, pose and identity remain independent.
The map rebuilds transient actor presentation on finish, skip and timeline/load
changes. Actors must be in the current scene and the waiting scene/node must
have an authored save boundary. The existing immutable save reader/writer stores
and validates the active node and elapsed tick. Old packages omit both component
and capability and retain their original state shape; old runtimes reject the
new required capability. Keep old content locks with their matching save/runtime.

`tools/create_performance_fixture.py` creates a diagnostic copy of a supplied
local package with synthetic color markers. It is not a second authoring
compiler, an artwork importer or a distributable content product. The input is
read-only and its existing distribution declarations remain in the output.
`tests/test_performance.gd` exercises actual app/TileMap presentation, timeline
guards, save/load, failed continuation rollback and the injected skip button.
Studio authoring/adoption, genuine named artwork in the story, physical input,
full playthrough and high-refresh hardware acceptance remain separate gates.

## Authored starting health and mana

Optional `pal.native.initial-vitals.v1` content is gated by
`actors.initial-vitals.v1` and the exact component schema hash. It configures
absolute HP/MP per world instance after initial progression, training and equipment,
before entry-story execution. Unlisted instances still start at their effective
maximum. Zero is allowed; excessive, negative, duplicate and unresolved values
reject admission. Initial values are never reapplied on party changes or save load.

`tests/test_initial_vitals.gd` takes the `native-fixtures.json` emitted by Studio's
`NativeStudioSmoke --initial-vitals` and a fresh evidence directory. Run with
`--headless --path native --script res://tests/test_initial_vitals.gd -- <fixtures> <output>`.
It exercises real compiled packages, actual save files, derived limits, ordinary
party transitions, rejection and rollback. Its synthetic results do not establish
original-game or cross-device acceptance. Existing package/rules/state/save schemas
and packages without this extension retain their prior format and behavior.

`tests/test_legacy_role_import.gd` consumes the six `native-fixtures.json` packages
from Studio's `NativeStudioSmoke --legacy-role` and a fresh evidence directory:
`--headless --path native --script res://tests/test_legacy_role_import.gd -- <fixtures> <output>`.
It checks source names and starting HP/MP, opaque DATA3 receipt preservation, and
actual saves and reloads. This is integration of the five explicitly imported
fields; other source fields, original rules and original gameplay are not executed.
The fixture packages and source resources stay outside this repository.

## Settled knockout presentation

A non-looping `dead` clip holds its last frame when the actor is already dead
and has no active presentation phase. Loading a knockout save or skipping the
fall therefore cannot restart the clip from a standing first frame. The original
committed death phase still plays its complete authored duration. Looping death
clips, idle/static fallbacks, gameplay HP and save schemas are unchanged.

`tests/test_settled_battle_frames.gd` covers the selection boundaries without
private artwork. The product's `capture_m2_knockout.gd` additionally exercised
normal authored battle commands, all 36 fall frames, pause, mid-fall/settled saves
and load in a real window; see its source/package hashes in product evidence.
This is display regression coverage, not character artwork acceptance.
