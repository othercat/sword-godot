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
Skills, items, statuses, revival, authored enemy composition, rewards, original
combat parity and formal hero animation assets remain pending.
