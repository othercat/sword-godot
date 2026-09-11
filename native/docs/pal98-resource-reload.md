# Original resource reload owner

`native_pal98_resource_reload.gd` independently expresses fixed T212/T246 over
admitted source tables, current events, loaded sprite/map caches and the existing
equipment kernel. It is internal: script/display/audio/save completion requests
must be fulfilled by their real owners. It does not activate an original Session.

`load_source(tables, graphics)` binds source identities. `start` takes explicit
globals/event/party/equipment/inventory state, a sprite-cache owner and optional
previous MAP/GOP snapshot. It forks sprite buffers and clones state/maps. The
caller adopts the returned state and caches together only on terminal success.
Immutable source-reader FIFO data may be shared; game buffers are detached.

The flow preserves these distinctions:

- Entry clears battle/movement fields. Bit32 requests the save owner first,
  skipping the non-save scene-change wave clear and current-event writeback.
- A non-save scene change clears wave state and commits at the CURRENT scene's
  base. Bit4 controls the subsequent event copy; otherwise old backing remains.
- Common work writes normal-map mode, anchor160/112 and current scene, then
  optionally copies events, ensures MAP/GOP and loads event sprites. T244 ring
  offsets clear and its viewport snapshot updates before requesting background.
- T246 compares mutable scene MapId with loaded MapId. A change actually reads
  decoded MAP and raw GOP; equality retains known matching buffers. Both branches
  assign loaded MapId. An ID without known cache backing diagnoses.
- Only after background completion does bit1 load party/follower sprites. Bit8
  then retains only bit2 and requests EnterScript/event0. Its returned ByRef
  entry updates the original scene even when the script requests another scene;
  such a change restarts the complete owner, including writeback and resources.
- Bit2 requests current MIDI with loop1. Its completion precedes flag clear and
  actual inventory-use/equipment preparation through the existing T156 kernel.

Requests carry owner/generation/sequence identities. Stale replies, overlapping
starts and cancelled generations cannot adopt state. Script/save replies require
source-bound state; EnterScript also returns its entry WORD. Display/audio need
explicit boolean completion. Test-double acknowledgement is not actual execution.

T175 now accepts an explicit current scene; the standalone default remains the
last loaded scene. The resource owner always passes CURRENT scene, since a switch
without bit4 retains old backing but changes the future writeback base.
`loaded_scene_id` still records the last T201 load.

Failure publishes no candidate state/cache. Previously completed external effects
cannot be rolled back here. The64-entry restart budget, safer shape/resource
checks and atomic candidate boundary are Native behavior, not original exception
or rollback claims. Existing equipment-kernel limitations remain, including its
nonempty legacy party projection and supported equipment-trigger subset.

## Evidence

Fixed PAL.EXE SHA256:
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`.
The original P-Code ranges were rehashed from the complete private copy:

| Owner | Start/length | SHA256 |
| --- | --- | --- |
| T212 | 409288 /352 | `7949078111e43008c56b2b34e5eda769c5d180ae287c40b9499eff8e891fb984` |
| T246 | 4081C0 /282 | `b391294a6c04e312db4861a4ec82aa7c757bba56f2a50ada99d9ab6d7c7bdb29` |
| T244 | 405C38 /190 | `4d77498ab81a4bc3baa93ac74ef2d264788ed97803dda0591306cafe52ae5a19` |

Studio private `artifacts/verification/v163-startup-02/resource-reload-04.json`
passes30 checks. Admitted MAP20/MAP10, MGO and equipment entries execute inside
explicit lifecycle fixtures. Display/audio/script/save callbacks are test doubles,
not GPU/interpreter/audio/save acceptance. Checks cover order, flags, loaded bytes,
detached caches, request mutation, same-map reuse, save branch, current-vs-loaded
event writeback, redirected ByRef entries, invalid/stale/cancelled replies and
cyclic restart bounds. `scene-events-reload-01.json` retains24 prior checks.
The inspection-free `resource-reload-index01/native` export, tree
`1fccdb60247ee90bbef746dc72b1eef51f55d07a`, also passes30 checks in
`resource-reload-staged-01.json`, before this documentation-only addition.

The first attempt failed GDScript's return-path check before owner instantiation.
Its owned process was stopped and `resource-reload-01-failure.txt` preserved; an
explicit terminal return fixed compilation. Reports02/03 are earlier23/27-check
successes. These results do not remove the source-only preview guard or release
a candidate. Local review completed; no additional independent review is claimed.

```
godot --headless --path native --script res://tests/test_pal98_resource_reload.gd -- <content.palmod.zip> <fresh-results.json>
```
