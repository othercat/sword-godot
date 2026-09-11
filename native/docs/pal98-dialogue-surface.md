# PAL98 dialogue rendering target

`src/native_pal98_dialogue_surface.gd` supplies one actual rendered target for
the internal dialogue caller's text, capture and restore requests. It is a
320x200 RGBA presentation candidate, using the existing system-font adapter.
It does not execute general SSS, construct an original scene, schedule ticks,
poll input, publish Session state or implement original indexed GDI pixels.

Configure once with an explicit font, 256-colour palette and opaque 320x200
Image. Mipmaps are removed from the private copy, preserving the supplied image
and using only its base pixels. Inputs are detached; invalid input does not replace the
target. The surface owns its background and text nodes and requires an active
renderer, membership in the scene tree and `UPDATE_ALWAYS`.

`await apply_request(request, encoding, source)` accepts `draw_glyph`,
`draw_string`, `capture_background` or `restore_background`. A text request
returns a `drawn` event only after a render barrier and the text node's command
submission. Capture reads the actual rendered pixels, including earlier text.
Restore puts back that image, removes subsequent text nodes and checks the
rendered RGBA hash before returning `restored`. Missing snapshots and unimplemented
Box/icon requests diagnose explicitly; they never receive fake acknowledgements.

`await replace_scene_frame(image, source)` replaces displayed pixels with an
explicit opaque scene frame and removes text nodes, while preserving the captured
dialogue image. It checks the rendered pixels against the supplied frame before
returning `scene_frame_drawn`. The caller's state fields and capture/restore gates
are not changed by this presentation method.

While a request waits, another request is rejected. Tree membership, size and
update mode are rechecked after the barrier; a global frame signal alone does not
prove this target was refreshed. Failure publishes no acknowledgement, but does
not undo pixels or nodes already changed before the failure. The host must stop
the failed invocation and explicitly recover; it must not retry as an implicit
rollback. Ownership and lifetime cancellation of the enclosing Session remain
outside this internal adapter.

The 36 real-window checks in `tests/test_pal98_dialogue_surface.gd` cover actual
pixel capture/restore, scene replacement, bad input, unsupported UI resources,
concurrent requests, disabled updates, removal from the tree and resizing while
pending, plus unchanged mipmapped input. Source hashes are recorded before and
after the run. An early test's
deferred-start race was corrected with an explicit start signal and a watchdog;
that failed run is not included in passing evidence.

Five real source messages (PC10/13/14/16/17) now use the same rendered target.
The probe explicitly supplies a synthetic opaque background and mode setup,
replaces the frame for source PC11 and restores the captured title at PC15.
It compares every request boundary with the separately verified caller trace.
There are 44 body glyphs and one whole-string title; the displayed progression
and six capture/replace/restore effects are independently checked from source
receipts and decoded PNG pixels. This is not a Trigger execution or an original
game scene. Logical ticks/input remain explicit zero-cost probe events, not
elapsed rendering time or physical keys.

The original-font raster, indexed palette/fade behavior, Box/icon resources,
complete original scene/actor state, actual clock/input, ordinary-player entry,
public save integration and Mac/AMD acceptance remain separate work. Existing
caller and text-kernel behavior is unchanged by this new adapter.

API references: [SubViewport update modes](https://docs.godotengine.org/en/stable/classes/class_subviewport.html#enum-subviewport-updatemode)
and [Image.clear_mipmaps](https://docs.godotengine.org/en/stable/classes/class_image.html#class-image-method-clear-mipmaps).
