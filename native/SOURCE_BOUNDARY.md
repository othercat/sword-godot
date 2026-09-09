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
