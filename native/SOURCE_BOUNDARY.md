# Native implementation boundary

This directory is the independent Native runtime in the existing
`othercat/sword-godot` owner repository. New code here is MIT. The parent project's
GPL license and history are unchanged. This notice does not relicense parent
files or grant redistribution rights in game art, music or stories.

Implementation inputs: PAL Wanxiang PRD and naming/tool addendum, new MIT Native
contract schemas from `othercat/pal98-runtime-contracts`, the actual synthetic
StoryStudio package, Godot public API documentation, JSON and ZIP format rules.
No parent game code, translated implementation, autoload, resource, binary helper,
font, shader or test was copied into this directory. `contracts/receipt.json`
records the allowlisted draft schema snapshot, exact hashes and owner commit.

The desktop key.ini adapter independently implements the public scan/action
format and observed sparse-default/explicit-disable/first-row semantics. The
product review records exact PALDLL source hashes and consumers. No PALDLL hook,
polling code, key buffer or Windows message injection is included. Godot's
physical_keycode and left/right location API provide portable identities; this
does not claim hardware scan or original polling parity.

The optional ordinary-attack base curve also uses recovered mathematical
behavior recorded by the product's source review, expressed as a new public
contract and fixed arithmetic vectors. Its short integer implementation is
independently written; no PALDLL hook, recovered procedural source or GPL game
implementation is included. The profile explicitly documents its adaptation
boundaries, rather than claiming full original combat or legacy overflow parity.

The fixed-package controlled RNG independently expresses recovered integer and
Single arithmetic and the new-game experience formulas. Its numeric oracle uses
exact rational synthetic inputs. No DLL, hook implementation or process memory
access is a Native dependency. See `docs/pal98-fixed-random.md` for the explicit
ordinary-context boundary and remaining initial-seed/Session/save owners.

The loaded sprite caches and scene composition independently express T98/T99 and
T163 instruction facts, retaining Unknown bytes and explicit reload owners.
GPU comparisons use private original-resource fixtures; no recovered procedure,
source artwork, original DLL or development oracle is a player dependency.
See `docs/pal98-sprite-cache-and-composition.md` for safety/exception differences
and the remaining ordinary Session boundary.

The scene sprite request consumer independently expresses fixed T209/T213 state
and arithmetic facts, without recovered procedure code or source payloads.
It does not invent initial state or bind resources at draw time. See
`docs/pal98-scene-sprite-requests.md` for evidence and execution boundaries.

The internal PAL98 equipment-entry kernel uses independently expressed behavioral
facts from the product's fixed-source review: signed modifier assignment, checked
I2 summation, source object entry references and bounded dispatch. Private DATA3
and SSS tables are test inputs and remain outside public source releases. No
recovered procedural implementation is copied or translated. This internal kernel
does not enable original scripts in the ordinary Native session; its exact subset
and missing owners are documented in `docs/pal98-equipment-kernel.md`.

The optional immutable source-table component admits user-selected legacy data
through the shared MIT schema and existing bounded ZIP/directory transports.
Its parser is independently expressed from file-format boundaries; it does not
translate a legacy game implementation or introduce a source-script interpreter.
Complete resource bytes remain private local-preview inputs unless the author
explicitly approves redistribution. No original payload is committed here.

The internal text planner and body execution requests independently express byte
controls and observable draw/wait/input ordering from the product's pinned
PAL.EXE/PALOLD.dll instruction review. They do not copy procedural recovery code,
load the DLL, include original font data or enable SSS in an ordinary session.
The corrected evidence and separate caller/renderer boundaries are documented in
`docs/pal98-text-plans.md` and `docs/pal98-text-execution.md`.

The addressed graphics reader independently implements the documented YJ2,
word-pointer, RLE and RGB6 byte formats. Studio's published format facts and
private original-DLL/managed comparison hashes are verification inputs; no
original or parent-project codec code, DLL or image payload is shipped. Exact
budgets, source defect and execution boundaries are in `docs/pal98-graphics-records.md`.

The map background and depth adapters independently express reviewed source
addressing, descriptor, coordinate, transparency and ordering facts. Guarded
original-DLL offscreen outputs are private development comparisons only. No
recovered rendering procedure or binary is translated or shipped; ordinary
scene state and script execution are not supplied by these components. Exact
facts and comparison boundaries are in `docs/pal98-map-background.md` and
`docs/pal98-depth-queue.md`.
The map occlusion adapter similarly uses independently expressed exrij/exbb/exmap
coordinate and addressing facts. Its real-resource compositions use explicit
development inputs, not recovered original caller code or a shipped DLL. See
`docs/pal98-map-occlusion.md` for source identities and unresolved scene owners.
Current-scene event storage independently expresses the reviewed T201/T175 byte
copy boundaries, retaining unknown record fields and uninitialized backing as
explicit Unknown. No recovered procedure or original save layout is copied or
claimed; source inputs stay private. See `docs/pal98-scene-events.md`.

The portable source decoder additionally contains derived CP936/CP950 software
tables from the MIT .NET CodePages provider. Exact provider/table hashes and
upstream .NET/third-party notices accompany `encodings/`. No proprietary game
text, original font, provider DLL or .NET player dependency is included. The
internal text drawing adapter independently implements the reviewed call
parameters using the existing Native system-font candidates and Godot TextLine.
It does not copy the recovered GDI implementation or claim pixel parity. See
`docs/pal98-text-codec-and-drawing.md` for reproduction and display boundaries.

The internal dialogue caller independently composes reviewed FFFF/ClearText
branch and helper-call facts. It does not copy or translate recovered procedures,
import parent ScriptVM code, include original UI sprites or enable the ordinary
Session. Its host requests and explicit failure boundaries are documented in
`docs/pal98-dialogue-caller.md`; private source text and probe traces remain outside
this repository.

The dialogue surface connects those requests to an independently implemented
Godot RGBA target with actual pixel capture/restore and render acknowledgements.
No original scene art, font or indexed raster implementation is included. The
source-message probe uses an explicit synthetic background, not a replacement
for original-game scene validation; see `docs/pal98-dialogue-surface.md`.

Build with this directory as the project root. Parent root exports are not Native
releases. `.gdignore` prevents the parent editor from scanning this nested project.
The Native rendering path uses its own TileMapLayer adapter; the parent's
PalTileMapWorld/CPU comparison rules describe its Legacy implementation and do not
authorize moving that GPL implementation across this boundary. Native also uses
the TileMap GPU path, with window evidence required for visual claims.

The user authorized committing and pushing completed, verified work in the owner
repository. No upstream contribution is presumed. This boundary does not include
private workspace inventories or reference game artwork in public source releases.

Official API references (2026-09-07):
- https://docs.godotengine.org/en/stable/classes/class_tilemaplayer.html
- https://docs.godotengine.org/en/stable/classes/class_zipreader.html
- https://docs.godotengine.org/en/stable/classes/class_json.html
- https://docs.godotengine.org/en/stable/about/complying_with_licenses.html

Godot's standard JSON reader permits several non-JSON constructs. Native's bounded
data reader rejects duplicate keys, invalid UTF-8/escapes and trailing commas.
The ZIP reader checks declared sizes before any decompression; it never mounts a
PCK, loads a script from a mod, or extracts package paths to the filesystem.
