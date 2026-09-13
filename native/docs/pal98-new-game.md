# The Ordinary New-Game Owner

`native_pal98_new_game.gd` is the production entry for starting the original
from the admitted package. `open(package)` binds the real owners — resource
reload, enter script, entry host, dialogue host with the shared page owner,
equipment kernel, sprite cache, scene-event storage, palette owner, display
executor, scene renderer, the movement owner with the real member executor
(`native_pal98_member_sync.gd`) and the production input frame.

- `new_state(seed)` derives the opening state from the package: runtime scene
  1, the new-game load mask 29, the original party anchor (160,112), the
  MAP20 viewport limit pair 1696/1840 (`0x41B120..0x41B14A`), the day/night
  palettes, the empty inventory backing, the kernel-derived opening party and
  a cold-installed display palette. The RNG seed is a required argument (the
  original new-game seed is unobserved); the zeroed trail is the named Native
  representation of the original's uninitialized walk trail.
- `begin(confirm_gated)` runs the real reload/enter chain. Non-gated (the
  default), the intro auto-answers its dialogues through the real host. With
  `confirm_gated` the intro parks on each page-text draw (`draw_string`);
  a player confirm — a new press on the bound confirm slot delivered through
  `tick` — advances that one real dialogue through the dialogue host and the
  chain continues to the next page. The capture/restore/box/glyph sub-effects
  and waits are not player pages. Gating the page on its text draw is a named
  Native reading: the original confirm gate point is not decoded. A further
  scene entry stops the intro by name instead of inventing player input.
  Display routing is real: palette family through the display executor,
  capture/restore through the shared indexed page owner, map backgrounds
  through the renderer.
- `bind_key_map(map, layer_base)` forwards the host input configuration to
  the input frame; `tick(key_levels)` rebinds the collision probe to the
  current map/events and runs one production logic tick.
- Effects this project has not built — audio (play_midi, play_sound_effect),
  the unfinished T121 transition, the unproved initial capture page, the
  undecoded RGM upper-dialog layout, the walk-loop frame family (frame
  processor, viewport/party update, scene-frame render) and the replay
  clock/runtime — execute only through `bind_named_double`, including an
  explicit host-opted catch-all that records every fall-through. Unbound
  kinds refuse by name.

Known named gaps carried by this owner: the frame-processing owner, the
walk-loop viewport/party update and scene-frame render owners, the RGM
container decode, T121's lane dissolve, audio backends and the original
key-map default. The source-only guard adjustment for the ordinary entry is
a separate app-layer package.
