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

## Addressed source record views

`package.pal98_sources.open_records()` opens an independent immutable reader, or
returns null before admission. A later replacement of the source object does not
change an already opened reader. A failed reader replacement keeps its previous
snapshot. Calls return either a value with source receipts or an error with a
source diagnostic; returned arrays, bytes and metadata do not alias stored data.

The reader in `native_pal98_source_records.gd` exposes:

- Six 75-WORD roles from field-major DATA3; their receipts describe 12-byte WORD
  spacing, not a fictitious contiguous role record. Words retain all 16 bits.
- SSS0 32-byte event and SSS2 14-byte object records as raw words. These views do
  not guess unknown field semantics or manufacture Native entity identities.
- SSS1 raw 8-byte records, including the final boundary record. `scene()` excludes
  that terminal record and verifies the requested scene's half-open SSS0 range
  using the next record. `scene_for_runtime_id(1)` explicitly selects raw index 0.
  Other scene ranges and unexecuted entry references are not silently repaired.
- SSS4 8-byte instructions with raw opcode/operand words. Index zero and unknown
  opcodes remain inspectable; execution, zero-entry return and PC wrap belong to
  the future interpreter.
- Exact ten-byte WORD entries and M.MSG spans selected by adjacent SSS3 offsets.
  Empty messages, NUL, spaces and undecodable bytes are retained. The unindexed
  M.MSG tail has its own view. `message_for_instruction()` resolves an FFFF
  reference and keeps the referring instruction address on success or failure.

Receipts bind the source fingerprint, relative package path, file SHA256, record
index and exact file offsets. Message receipts also identify both SSS3 boundary
entries. This is an internal read API, not a new public save format. It neither
decodes GBK/Big5 nor executes text controls or confirmation/timing behavior.

SSS0/SSS1 remain opaque at source-package admission: requesting malformed record
tables or scene ranges produces a local diagnostic. It does not discard the
source, reject previously valid source-bearing packages, or prevent reading an
independent valid table. No new capability, schema, ordinary session behavior or
runtime formula is introduced.

`tests/test_pal98_source_records.gd` checks synthetic record/address boundaries,
snapshot replacement and malformed local views, then reads every record from a
caller-provided ordinary source package. Reconstructed table hashes and opening
addresses are independently checked by the product integration evidence. This
establishes source consumption, not scene execution, event scheduling or gameplay.

The internal [byte text planner](pal98-text-plans.md) consumes these message and
instruction receipts without replacing them with decoded text. It preserves
timed-return suffixes and rejects unsupported loader/parameter boundaries;
ordinary session execution is still separate.
