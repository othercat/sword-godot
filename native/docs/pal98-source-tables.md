# Immutable PAL98 source data admission

`pal.native.pal98-sources.v1` is an optional source component, pinned to the MIT
contract owner `45c3daf6e232c78d7ee8411dcf2bfd4cd9432b0f` alongside 29 existing schemas.
Packages require `sources.pal98-win95.v1` and the exact component schema hash.
The four base schemas, ordinary rules and save format are unchanged.

The ordinary ZIP/directory loader admits complete DATA.MKF, SSS.MKF, WORD.DAT and
M.MSG under `content/pal98-sources/<fingerprint>/`. Every attachment must appear in
the source component and manifest with identical kind, role path, length and hash.
Only that declared set is admitted. Unapproved sources require local-preview scope.
All input remains local data; no mounted PCK, external library, network transport
or legacy executable is introduced.

`native_pal98_sources.gd` checks the bounded MKF and source table layout and stores
an immutable snapshot. `metadata()`, `counts()`, `copy_bytes()` and `copy_chunk()`
return copies. A failed source replacement does not change the previous snapshot;
a rejected package publishes no source object. GBK/Big5 is explicitly fingerprinted
metadata, without a claim of full text decoding. Empty source chunks and messages,
unknown instruction words and unindexed M.MSG tails remain intact.

Transport readers now allow a zero-byte ordinary file; the specific component and
format validators determine whether it is valid. Directories still require zero
ZIP payload length, and all existing path, size, count, hash and closure checks
remain. SHA256 of an empty byte array uses a started/finished hash context without
calling Godot's unsupported zero-length update.

The source object is available to data consumers as `package.pal98_sources` after
the complete package passes validation. The normal session does not execute SSS,
initialize legacy actors or serialize the internal equipment-kernel dictionary.
The kernel can independently read DATA3/SSS2/SSS4 copies from this admitted package;
this establishes a data path, not complete party initialization or game parity.

`tests/test_pal98_sources.gd` consumes a private Studio source-window report. It
checks real ZIP/directory admission, byte and metadata isolation, normal session
activation, six source-role equipment results, and malformed/synthetic package
cases. All source references and fixture bytes are caller-provided private inputs;
only synthetic values and the tests are committed. Window, physical-input,
original-gameplay, Mac15.7.7 and AMD acceptance are separate evidence boundaries.
