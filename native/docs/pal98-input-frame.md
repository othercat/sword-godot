# Input Frame Tick and the Member Formation/Frame Executor

## `native_pal98_input_frame.gd` — the production logic tick

One `tick(state, key_levels)` call is one logic tick of the ordinary-map loop,
assembled from the real owners instead of a test fixture:

1. `PollAndResolveDirection` (0x0041CCE4 port) resolves at most one axis from
   the eight logical key slots and the bound G0854-style slot map.
2. The SubMain inline (0x0041B1BA) converts the cartesian direction to the
   isometric diagonal pair; `ProbeAndPrepareMove` (0x0041B1F0) builds the
   candidate from party-in-viewport + viewport and probes it through the
   two-level collision owner (map bit 0x2000, then event proximity).
3. A accepted step faces the party through the real extf owner, refreshes the
   previous-position words (this owner is PostMoveUpdate's caller on the
   input path, exactly like the reviewed walk loop), and applies the 16/8
   viewport step.
4. `PostMoveUpdate` (0x0041D2CC) runs every tick — moving or stationary — so
   the world words, walk phase and the trail/member sync always execute.
5. The T209 party requests (and T213 event requests when a scene-events
   storage is bound) are computed from the resulting state by
   `native_pal98_scene_sprite_requests.gd` and returned with it.

Boundaries: the tick publishes nothing on a refused or failed step; the
caller's own state is never mutated; a blocked candidate is a normal
stationary tick (phase settles through `(phase & 2) ^ 2`, draw requests still
publish); the scene-events storage must be rebound when the scene or its
events change; previous_x/y are refreshed only when the tick moves.

## `native_pal98_member_sync.gd` — the member half of SyncMembersFromTrail

The executor `bind_member_sync` requires. For every active slot it selects
the sprite frame as `direction * frames_per_direction + frame_offset`, where
the per-direction count comes from that slot's own sprite source through the
bound provider (DATA3 field64: 4 takes the ×4 path, anything else ×3 — the
`0x411594` decode). Leader uses `leader_frame_offset_word`, every other slot
`party_frame_offset_word`, both from the recovered PostMoveUpdate.

Members (slots 1..member_last) take their screen position from the probed
trail candidate `trail[slot+1] - viewport`; a rejected probe falls back to
the generated formation tables `G041C=[-16,-16,16,16]`/`G0434=[8,-8,-8,8]` subtracted
from the running position — a named Native adaptation of the decoded march
step. The executor may only change active slots' `current_frame` and member
slots' `x/y`; the movement owner verifies exactly that shape and refuses
anything wider.

Named evidence gaps, not silently closed: the 0x0041D2E4 byte body is not
decoded, so the member trail stride `slot+1` (against the reviewed follower
stride `follower+2`) is the Native reading that keeps the entries distinct,
and the formation-fallback application inside the arrival sync is an
adaptation. Frames-per-direction is read from the slot's source per slot;
the owner never guesses a count and refuses unknown ones by name.
