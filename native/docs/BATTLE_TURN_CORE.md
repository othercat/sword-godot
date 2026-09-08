# Battle turn core

The independent MIT Native runtime consumes the shared draft capability
`battle.turn-core.v1`. It does not import the parent research runtime or its
PAL/SDLPal battle implementation. Contract snapshots remain offline build inputs.

`src/native_battle.gd` validates encounter/state consumers and executes attack,
guard, ordered enemy retaliation and explicitly allowed escape. Actual ordered
party instances determine turns; no fixed three-member array is introduced.
Combat uses max(1, attack − defense), ceil-half guarding and current-HP clamping.
These are new training rules, not original PAL damage parity.

`native_session.gd` owns candidate publication, battle entry, three outcome story
callbacks, pause/input exclusion and save admission. Each command either publishes
all effects and its callback or keeps the previous state. The pending execution ID
is bound to run, activation, executor step and battle node. Load does not re-enter
the battle or replay already committed settlement.

`native_battle_view.gd` uses geometric preview cards, variable party layout and
0.35-second attack/target feedback. Display time does not execute combat. Load and
battle transitions change its history key; pause/focus/modal boundaries freeze it.
Formal actor action sets, animation queues and high-refresh hardware acceptance
remain separate work. Existing RGBA texture preparation and truecolor paths remain
in use for world assets and are not replaced by palette quantization.

Reproduce with three owner-built packages and a fresh output directory:

```text
godot --path native --script res://tests/test_battle.gd -- four.palmod.zip three.palmod.zip five.palmod.zip output
```

The test uses actual application windows and injected mouse events, plus explicit
synthetic loss/callback-failure variants. It retains command-wait saves for
independent contract validation. It is not physical-user acceptance or a full game.
Ordered player skills, items, fixed rewards and battle statuses are additive
capabilities. Original combat parity and formal hero animation assets remain
separate work.

## Authored enemy composition

Studio now authors ordered enemy instances, shared or cloned actor definitions,
names, HP/MP maxima and attack/defense through its existing compiler. Definitions
remain shared data; each enemy receives separate current HP/MP at battle entry.
New worlds initialize actor maxima; editing does not migrate a running state or
an old content-locked save. No schema or ruleset change was needed for this UI.

The view and target buttons share stable encounter ordinals. Eight enemies fit
each presentation page; all 1–32 entries remain in the battle state. Page changes
do not issue commands or change target identity, enemy turn order or HP/MP. The
window keeps ticking normally. Loading resets the display page while restoring
all saved enemies, including those on other pages.

```text
godot --path native --script res://tests/test_battle_composition.gd -- four.palmod.zip three.palmod.zip five.palmod.zip capacity32.palmod.zip output
```

This parameterized window test checks three actual Studio-authored variants and
an explicitly synthetic 32-enemy expansion. It targets duplicate-name enemies,
skips dead retaliation, settles only after every enemy dies, saves/restores four
states and rejects cross-content saves. Pagination compares the entire state
after accounting for elapsed clock ticks and their one-per-tick revision delta.
Capacity geometry and target 32 are checked at 1280×800; no other window size,
32-enemy performance, balance or full-playthrough acceptance is implied.

## Ordered player skills

`src/native_skills.gd` consumes shared `battle.skills.v1` / `native.skill-effects.v1`
definitions and static actor loadouts. `plan` rejects unknown/unowned skills,
insufficient MP and wrong-side/life targets before mutation. `apply` charges once
and applies each authored damage/heal/revive effect to the original selected
targets in order. Damage subtracts defense and respects guarding; healing clamps
to maxima without reviving; revival preserves MP and can precede healing. Actor
loadouts remain content-locked, not a second mutable learned-skills list in saves.
Enemy AI still uses ordinary attacks, even when its definition lists skills.

The battle/session consumers retain all effects, turn order, callbacks and saved
results in one candidate transaction. A revived earlier party slot waits for the
next round. New `cast` and indexed effect events drive disposable visual feedback;
loading never replays costs or effects. Definitions and saved results are checked
against the shared schema and semantic rules, not original PAL numeric slots.

`native_skill_menu.gd` owns an eight-entry skill/target page, explicit all-target
confirmation and cancellation. It binds choices to timeline epoch, execution id,
command step and actor; loading or changing turns clears stale choices. Choosing,
paging or cancelling does not issue a battle command; normal clock ticks continue.

```text
godot --path native --script res://tests/test_skills.gd -- four.palmod.zip three.palmod.zip five.palmod.zip output
```

The Studio owner produces the three packages through actual author controls and
the existing compiler. This window test covers MP debit once for all targets,
single-instance selection, ordered revival/healing, natural enemy-caused death,
turn order, cancellation, stale input, callback rollback and six before/after
revival saves. The callback failure is an explicitly synthetic mutation; normal
skills use owner-built content. Independent owner validation reads each actual
save. This skill suite alone is not learned-skill, enemy-AI, item/status, formal
animation or complete RPG acceptance. Final commands and file hashes live in the
product evidence repo.

## Authored battle statuses

`native_statuses.gd` consumes optional `battle.statuses.v1` / rules0.11.0,
`native.battle-statuses.v1`. Definitions are authored in Studio; instances live
only in the existing battle extension, with stable actor/status/source IDs,
stacks and remaining rounds. No PAL poison script or fixed memory array is used.
`native_battle_effects.gd` shares add/remove effects between skills and items.

Refresh/stack/replace, attack/defense percent deltas, skip turn, block skills,
hit/death clearing and ordered round-end damage/heal use the shared contract's
explicit semantics. Enemy actions precede party-order then enemy-order periodic
effects. The current round counts: effects happen before duration decrements.
Healing cannot revive; retained dead-actor statuses still lose duration. Full
battle completion removes every transient instance. Capacity failure after an
earlier effect, or callback failure after death clearing, discards the complete
session candidate, including HP/MP/inventory/turn changes.

Menu commands recheck control restrictions. The view displays status summaries
and full hover text; periodic results drive damage/heal feedback using the
existing presentation clock. They are never executed by rendering or loading.
Save admission binds last status mutations, reapplication amounts and remaining
rounds, and rejects repeated/out-of-order periodic components and invalid clears.
It allows self-applied silence and explicitly retained status after death; it
does not reconstruct an entire prior battle or act as save anti-cheat.

```text
godot --path native --script res://tests/test_statuses.gd -- four.palmod.zip three.palmod.zip five.palmod.zip output
```

The packages come from the actual Studio status/skill/item controls. The test
uses injected mouse input for four round-end boundaries, a normal skill victory,
and natural periodic death followed by revival. It retains seven actual saves
per party configuration for independent contract inspection. Separately labeled
in-memory probes cover replace/stat rules, enemy skips, self-silence, 16-kind
capacity, forged records and full candidate rollback. A layout frame is awaited
before clicking newly rebuilt controls after load. Source/package/command hashes
and first-failure logs are retained by the product evidence runner.

Status probability/resistance, equipment, enemy skill AI, Legacy parity, formal
hero action sets, physical-user and cross-platform release acceptance remain
outside this increment. Existing external RGBA/alpha-edge rendering is retained.
