# Original scene state to sprite cache requests

`native_pal98_scene_sprite_requests.gd` consumes current source-bound event
storage and an explicit party/caller projection. It independently expresses
T209/T213, returning ordered cache-slot requests. A request does not load an MGO,
choose new-game defaults or activate the ordinary original Session. In particular,
changing an event SpriteId or a role's field2 does not silently reload graphics.
The recorded SpriteId is gate/provenance data, not a new resource binding.

T213 tests signed State first. It then performs checked signed16 X/Y minus
viewport and Layer times8, before screen and SpriteId filters. The screen gate
includes X=-64..384 and Y=0..328. Only a FramesPerDirection value of3 maps
CurrentFrame2 to0 and3 to2; other values and signed directions remain unchanged.
Direction multiplication is checked before the signed-positive SpriteId gate;
the final frame addition is checked only after that gate. No modulo or invented
direction/frame clamp is applied.

T209 uses the inclusive upper bound checked(MemberLast+FollowerCount), actual
party X/Y/CurrentFrame and team layer. It has no event screen filter or three-frame
remapping. Missing backing or Unknown fields diagnose. Both public helpers check
the actual integer input type before conversion. Combined requests retain the
original depth queue's safe255-row limit.

The caller is required: RenderSceneFrame requests events then party, while
SubMain requests party then events. This also determines the first diagnostic.
Neither collection nor failure mutates source/runtime state. The later resource
loader must retain loaded cache identity and resolve these slots explicitly.

## Fixed evidence and validation

PAL.EXE SHA256 is
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`.
The right-exclusive P-Code intervals are:

| Owner | Interval | SHA256 |
| --- | --- | --- |
| T209 | 0x404578..4045EA | `bad972c387608d6771fcdad460a2e9ebd705dffc5e00e11946c4acf5336c3175` |
| T213 | 0x409FB0..40A150 | `6171d2f7d377039529dd19f2873493a4c8d376ed6d4184d2c42c245e65c92e02` |

The distinct owner calls are at0x404668/40466E and0x41B3A8/41B3AE.
Independent read-only review found and prompted correction of public typed-int
parameters accepting converted floats; direct-helper rejection cases cover it.
The deterministic tests cover filter/arithmetic order, remapping, signed inputs,
cache-slot identity, followers, owner order, Unknowns, budgets and preservation.
They do not execute original gameplay or certify Mac/AMD or player acceptance.

Private reports `sprite-requests-02.json` and `sprite-requests-staged-01.json`
each pass29 checks under Studio's existing v1.63 evidence root. The clean export
`v163-sprite-requests-index01/native`, tree
`7d729fd152e4a7de73a75c7058f93e6a9e8ee777`, excludes inherited inspection drafts.
The earlier27-check report precedes the two direct-helper type checks.

```
godot --headless --path native --script res://tests/test_pal98_scene_sprite_requests.gd -- <fresh-results.json>
```
