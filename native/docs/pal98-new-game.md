# Internal original-source new-game coordination

This owner coordinates Reload, EnterScript, current state/cache leases and explicit hosts. It does not open the source-only ordinary Session gate.

`open(package)` checks source and all bindings. `new_state(seed, probe_configuration)` requires explicit globals, dialogue, role selection, party/trail and inventory inputs. These unproved initializer fields have moved to `tests/fixtures/pal98_new_game_probe.gd`. Source event/equipment tables and palette remain real. The recovered startup RNG/experience initializer is a separate next-stage capability; a seed argument and synthetic trail do not establish original initialization.

`begin()` follows actual reload requests without a scene-count completion shortcut. A request and its final result carry the same candidate sprite cache and map cache; EnterHost mutations use that cache. State, cache identity, map backing and collision binding are validated before adoption. A binding failure cannot reuse an older probe.

Dialogue:
- Draw requests are processed immediately by the explicitly bound host. `draw_string` is not a page-confirmation gate.
- Actual `poll_input` and `wait` requests park the chain with its current pending state.
- `tick(keys, timer_tick=false)` polls input without moving the map while dialogue is pending. A supplied nominal timer event advances at most one wait continuation; merely calling the method is not elapsed time.
- Ordinary poll accepts action 0 and can accept action 2 for character skip. Only `until_nonzero` denotes an indefinite input wait; `bounded_clear` can finish by its own timer sequence.
- `resume_dialogue(id,event)` forwards the exact input/tick contract. One input cannot release a series of later requests. Old IDs cannot write or cancel a newer generation.

Cancellation or host failure releases both Reload and Enter continuations, clears pending requests, terminal records and captured pages, and allows the same owner to restart. No generic state-bearing request receives an automatic ACK; test policies must bind each missing kind by name. Wildcard hosts are refused.

The recording dialogue host is still a glyph policy, not a physical display. Audio, RGM upper layout, T121 transition, event/frame helpers and physical input remain named dependencies. The production nested-T212 coordinator and formal application entry remain separate work packages.

The exact input used for current probes is an **edited original-source author sample**, ZIP SHA256
`8d946e34f202487353c12e7b50fe1c3df9159945453e616be712a5ff3c07f2fb`.
Its message 2 already contains “对白编辑技术验证：保留原包与其他记录。”; it is not the untouched original message stream.

`test_pal98_new_game.gd` uses explicit synthetic initialization, nominal timing and skip/confirm input. Frame, audio, RGM and transition gaps are named test doubles. The current MAP12 event sprites decode correctly from the adopted cache; the earlier zero-source-data explanation is withdrawn.

`window_ordinary_new_game.gd` is a bounded GPU/window probe: it checks real party/event pixels, replays actual source text requests onto a displayed surface, and verifies both composed and window pixels change after movement. Composition errors fail the check, never save an old frame as success. Text replay in this probe does not complete live dialogue integration or ordinary new-game acceptance.
