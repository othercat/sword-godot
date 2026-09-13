# Production scene display owner

`native_pal98_scene_display.gd` presents the live new-game state: every
`tick_presented(keys)` runs the coordinator's real input tick and then
composes and publishes the resulting state to the bound `SubViewport`
target. The composition caller is derived from the current state (viewport,
party, layers) and the palette view follows the current day/night word, never
a fixed palette number. A composition failure is returned by name; the
previously published frame stays untouched and is never reported as the new
frame's success.

This owner does not initialize a game, inject input policy, decode fonts or
play audio. Probe initialization, scripted presses and the named gap list
remain explicit in the window suites; `window_scene_display.gd` checks that
each tick's T209 request position is the composed frame's party position,
that successive displayed ticks change the actual window pixels, and that a
broken current sprite frame is refused with the old frame left unpublished.
It does not establish ordinary new-game acceptance, live dialogue (F03) or
physical input (F08).
