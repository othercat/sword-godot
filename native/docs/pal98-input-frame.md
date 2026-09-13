# Input frame and current member state

One `tick(state, key_levels)` is a supplied nominal map tick, not a physical keyboard or timing implementation.

1. Resolve eight mapped directional slots, convert to the isometric pair and probe the current world candidate.
2. Apply extf facing, preserving caller-owned pre-step world derived from viewport + party anchor.
3. A pending step uses checked I2 viewport addition, explicit ffxy limits and whole-step rollback if either clamped axis stayed unchanged.
4. A pending step calls PostMoveUpdate. No pending step rebuilds standing frames only; it never shifts the trail or replays a walking frame on key release.
5. Return current T209 party and, when bound, T213 event requests. T213 receives `state.events`, not the outer state.

`poll(key_levels)` validates the same input mapping without moving the map. Optional confirm is exactly level 2; level 3 is held. Mapping indices and values 0..3 are validated. This host mapping is explicit; the original physical key map is still not supplied.

The recovered member body is 0x00411580..0x0041196E, end exclusive, SHA256
`884404deeae08e638b7e577b57429c8951701ed3d4a101aa0deec418876aecb0`.
The fixed original PAL.EXE identity is
`75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`.

- Both ordinary members form from trail[1]. Member 1 subtracts G041C/G0434; member 2 adds 8 to Y and adds/subtracts 16 to X by trail direction parity. Probe world sums; a blocked formation uses the base trail position.
- Both ordinary member frame directions use trail[2]. Current request `equipment.role_words[field*6+role]` owns DATA3 field64. Four-frame roles use walk_phase; other moving roles use the three-frame leader/party offsets.
- Followers use trail[follower+2] and fixed three-frame selection, without role-table lookups. Relative coordinate arithmetic is checked I2 after WORD signed readback.
- Stationary selection uses field64 when nonzero, otherwise three frames, and zero offset. It does not reposition members or change the trail. The stationary phase toggle does not require clearing stored movement offsets.
- Internal party position is x/y; screen_x/screen_y belong to draw requests only. Malformed or duplicate ordinary role identities, incomplete current backing and arithmetic overflow refuse without publishing state.

Compile and focused tests: test_pal98_input_frame, test_pal98_member_sync_review, test_pal98_execution03_review. Collision/formation, software requests, GPU probes and ordinary gameplay are separate evidence classes.
