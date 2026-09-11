# Source-bound current-scene event storage

The resource lifecycle supplies an explicit current scene to
`commit_current_events(state, current_scene)`. A switch without resource flag4
retains the loaded buffer, so its last-loaded scene cannot determine T175's
writeback base. Existing callers may omit the argument to use the last loaded
scene. See `pal98-resource-reload.md` for the retained-buffer regression.

`native_pal98_scene_events.gd` independently implements the reviewed T201/T175
event-table copy boundaries. It takes an admitted source snapshot, keeps all
32-byte record fields and returns detached runtime candidates. Source bytes and
author files are never modified. This is internal state storage, not a public
save schema, original save writer, complete resource loader or ordinary Session.

`source_state` creates a source-bound working copy of global SSS0 event bytes
and SSS1 scene records. Its `loaded_scene_id=0` means this Native component has
not loaded a scene; it is not a claim about original cold-start globals. All160
active backing slots initially contain explicit Unknown (`null`), not fabricated
zero records. The160-slot limit describes this legacy owner, not Native actors.

`load_scene_events` treats runtime scene1 as raw scene0. It uses the current
scene boundary and following boundary, with checked signed count subtraction,
then caps counts above160. Exactly that prefix is copied into runtime slots
1..count. Loading fewer records retains previously known backing beyond count;
a zero-count scene does not clear the backing. Reads distinguish current-count
records, older known slots and never-loaded Unknown slots. The original helper
has no lower clamp for negative counts; Native diagnoses unsupported negative
copy lengths and out-of-owned addresses instead of executing a memory hazard.
High-bit boundary addresses remain explicitly unsupported pending their complete
signed/array-address semantics. No wrapped address or zero record is invented.

`replace_event_record` replaces one known32-byte runtime slot and leaves the
global table unchanged. `commit_current_events` copies exactly the caller's
current count back at the current scene's boundary. It does not recompute the
next-scene difference, even if that difference was changed to a negative value.
The source/load/commit methods remain separate so their caller must preserve the
actual original resource-switch/save ordering. No automatic scene switch,
EnterScript, sprite reload, event0 record or initializer is supplied here.

State/source identity, table lengths, current count and known-or-unknown slot
shapes are validated before work. Invalid source replacement retains the prior
source. Invalid state, unknown slot or invalid copy range returns an addressed
diagnostic without publishing a partial candidate. All untouched global bytes,
including events beyond the160-record cap and unknown words in copied records,
are preserved.

## Fixed source evidence

Original PAL.EXE SHA256:
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`.
The implementation uses independently expressed behavioral facts from:

| Owner | Fixed P-Code interval / file offset / bytes | SHA256 |
| --- | --- | --- |
| T201 LoadSceneEventObjectsFromGlobalTable | 0x405318..4053B2 /0x4718 /154 | `6d1e2a3406e1ba3ec5114bd4e7f3b39712be89029072ca23da625dbb5a2675af` |
| T175 CommitCurrentSceneEventObjectsToGlobalTable | 0x403B10..403B62 /0x2F10 /82 | `beab5e69c4a69ee99f5233d4a80690e30cf0533761f9ac849f38f39f256f9296` |

Intervals are right-exclusive and were rehashed from the fixed executable.
T201's caller at0x409332 supplies the selected scene before resource loading.
T175 is called before scene switching at0x4092F0 and on the save path at0x41062A.
These facts do not prove the surrounding resource/script/save owners implemented.
No recovered procedure, parent game code or original payload is copied into
Native; no original process or memory-copy export is executed by this test.

## Validation

`tests/test_pal98_scene_events.gd` passes24 checks in
`scene-events-02.json`, under Studio's existing private
`artifacts/verification/original-v163-codex-review-20260912-01/` evidence root.
It covers source identity, failed-source preservation, Unknown backing, exact
prefix copies, smaller/empty scene preservation,160/167 truncation, current-only
editing, exact writeback and return to a changed scene, untouched neighbors,
independent T175 count/base and invalid signed/copy ranges. The ordinary compiler
package supplies all294 real scene intervals for byte-exact loading; a runtime
edit survives commit/reload while the admitted source remains unchanged.

The earlier `scene-events-01.json` also passed24 checks but its T175 assertion
used a zero next difference. The current assertion deliberately uses a negative
difference, proving writeback does not reuse T201 range validation. These are
headless storage checks plus fixed-byte evidence, not original-PAL execution,
gameplay, ordinary Session, actual Native save/load or Mac/AMD acceptance.
Independent read-only review found no necessary fixes. The inspection-free
export `v163-scene-events-index01/native`, tree
`f71fb0511df0d24e598dfe7b1c0eab0b00e12d8f`, also passes24 checks in
`scene-events-staged-01.json`.

Replay with a fresh report path:

```
godot --headless --path native --script res://tests/test_pal98_scene_events.gd -- <content.palmod.zip> <fresh-results.json>
```
