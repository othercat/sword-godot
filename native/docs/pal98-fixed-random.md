# Locked original-package random arithmetic

`native_pal98_fixed_random.gd` independently implements the ordinary controlled
random path of the locked PAL.dll1.6.2.0, plus SubMain's new-game experience
projection and explicit local-time startup seeding. It is internal: no ordinary
original Session, public save contract or game-wide RNG
dispatch is enabled by these increments.

The fixed DLL SHA256 is
`3074423f2ea58529fd22b8e72a05ef289adf15a3b796841447e03db3417446ff`.
In a complete private runtime copy, CDB at InitCD observed the installed
VB40032 `rtcRandomNext` entry jump to DLL RVA`0xE53E0`.
The copy's unchanged configuration/log identifies `RandomControl=0`, no forced
override and the fixed VB authority gate. The hook bytes, constants and PE
imports were then checked offline, without loading the protected source DLL.
Current PALDLL source and its different Release binary were only lookup clues.

The arithmetic is two successive updates
`seed = (seed * 0xFD43FD + 0xC39EC3) & 0xFFFFFF` per ordinary call. Its local
static mirror reads the live VB DWORD only on the first controlled call;
later live-seed writes do not reset that mirror. Each call writes the second
seed back to both locations. An explicit live DWORD is required; Unknown is
not replaced with zero. The detached state retains both seed identities.

The second seed divided by2^24 is multiplied by10,000,000 in Single precision,
rounded halfway away from zero by `roundf`, divided by10,000,000 in Single,
then clamped by `fminf`/`fmaxf` to `[0, 0x3F7FFFFE]` as float bits. The
intermediate Single rounding matters; Godot's default RNG and unrounded double
arithmetic are not substitutes. The ordinary context must be explicit. Mode1,
forced diagnostics, poison bypass/zero-bucket compatibility and implicit
Randomize dispatch are not implemented by this helper. A future interpreter must select
the correct context before calling it; these exclusions are not silent no-ops.

SubMain's original loop iterates roles0..4, categories0..7. Category0 stores
base level/count0 without consuming random values. Every other category calls
ordinary RNG for `CInt(Rnd*2+2)` and then `CInt(Rnd*20)`, in that order. x87
extends the Single result for these exact short expressions; CInt uses nearest
even. Levels use checked signed-I2 addition. Success therefore consumes70
calls/140 LCG steps and returns the subsequent RNG state. Failure returns no
partial projection or consumed state: this deliberately differs from an
original exception after earlier array writes. The5×8 result describes only
level/count, not the complete VB array descriptor, EXP record or save layout.

## Startup Timer and explicit Randomize

`fresh_startup` requires one explicit local hour/minute/second/millisecond
sample. Fixed VB allocation writes seed0x050000. `rtcGetTimer` calls
`GetLocalTime`, combines whole seconds with the binary64 constant0.001 times
milliseconds, and PAL's initializer stores the result as VT_R4. The helper
preserves Single rounding, including23:59:59.999 rounding to86400. The host
must acquire the sample once at process initialization; calling this factory
for each new game would incorrectly reset the DLL's persistent mirror.

`capture_startup` now acquires a portable host sample using Godot's fractional
UTC Unix time and current timezone offset in minutes. It retries a timezone
change during acquisition, records integer epoch milliseconds/offset, and
converts that single sample to local time before the above arithmetic. This is
wall time only, never the game's logical clock. The adapter follows the
[Godot Time API](https://docs.godotengine.org/en/stable/classes/class_time.html#class-time-method-get-unix-time-from-system);
its current timezone API and fractional timestamp are not an assertion that
two independently sampled Windows/Native processes receive identical time.
Explicit integer conversion also handles pre-epoch times and int64 endpoints
without overflowing the timezone addition. `startup-clock-01.json` passes48
checks, retaining all arithmetic tests and recording an actual Windows host
sample that reconstructs the same initial state. Mac/AMD clock acquisition and
ordinary application integration are not yet tested.

PAL then uses explicit Randomize, which converts its argument to R8 and mixes
the **high DWORD**: `mixed = ((high << 8) ^ (high >> 8)) & 0xFFFF00`, preserving
old live seed bits0..7 and24..31. `randomize_r8` changes only live seed, retaining
an already initialized controlled mirror. The separate missing-argument Timer
branch and general VARIANT conversion are outside this API.

This corrects the historical `PAL_VB4_RANDOM_EVIDENCE.json` / stage opinion's
"low DWORD" prose. At RVA74303, `push esi` means `[esp+0xC]` is the R8 high
DWORD: entry stack is return/low/high. The fixed package's new no-input CDB
sample corroborates that reading: Timer Single bits469D2B2D =20117.587890625,
converted R8 lowA0000000/high40D3A565, seed050000→E5B600. The low-word formula
would yieldA00000 and is not used. Reference research files remain unmodified.

Private `cdb-randomize-03.log` SHA256
`73b51c8b2f6d00d48295a8a73edd986dc4bb30c8c6c0a5dd1e53a9ed8deafb2a`
records hardware entry/return breaks at PAL thunks401048/40104E, ESI4180D2/
4180E4 and live seed before/after. CDB q exited before GUI input, with no game
variable write. `timer-randomize-pe-evidence.json` binds GetLocalTime IAT9C2F0,
constant RVA92518, seed initialization RVA2524 and timer/randomize byte ranges.
The explicit mixing range RVA74303,42 bytes has SHA256
`606a59e80b52b11b1602e64fb8ee9237c30929851fd9c90dae1b96612c5e845f`.
The private runtime retained only its three known log/output changes;
`randomize-03-after-audit.json` rehashes all1579 protected source files with
zero changes/extras. Original saves/config/resources remain unchanged.

`fixed-rng-oracle-02.json` adds14,000 rational local-time vectors over14 second
values and every millisecond,32 explicit R8 cases, and the observed sample.
`fixed-rng-02.json` passes44 checks, including all previous controlled sequence
tests. This closes these arithmetic paths, not later seed stability, ordinary
Session/new-game execution or device acceptance.
The inspection-free `timer-seed-index01/native` export, tree
`eceb2c69adc8d8d139c3867a2e8574d35b07c180`, also passes44 checks in
`timer-seed-staged-01.json`, before this documentation-only evidence addition.

Evidence in Studio's ignored `artifacts/verification/v163-startup-02/`:

- `cdb-rng-hook-02.log` SHA256
  `ba3922e9fc6cff0a434bbdc30796792adff9502d069b0081a8a7a2f3626b8a8e`.
  This observes the installed entry and instructions, not the70 calls executing.
- `fixed-rng-pe-evidence.json`: constants at RVA19BCB8/19BE34;
  `roundf`/`fminf`/`fmaxf` imports at IAT RVA15F65C/15F660/15F664.
  Hook RVA E53E0,1582 bytes SHA256
  `727c3c441dd06067beb5b7af356af03b92118fda8fd8227edd35af4de85ad863`;
  mode/math E573E,610 bytes
  `9d250d1408c746250e0de7fbfec8d2d3ffe94144e3702b855c76301228190cfe`.
- Fixed PAL.EXE SHA256
  `75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450`;
  SubMain loop VA41B02A,220 bytes SHA256
  `9f84d1d294e72a5afaeeb67245d842315e43af11b8f888ec02748d56d495dbcd`.
  VB40032 SHA256
  `0f1604c9a7398cbb317383799b88c4e1aa7ce0b2c968392f0a7a9ddff22ec57d`.
  Recovered FMultiply/FAdd retain x87 operands; FloatToI2 uses `frndint`.
- `fixed-rng-oracle-01.json` uses independently expressed exact rational
  Single rounding and integer nearest-even arithmetic.1134 vectors include
  inverted second-seed boundaries, every exponent and deterministic DWORD
  spread; six complete70-call sequences cover five signed base levels.
- `fixed-rng-01.json`:32 checks pass in Godot4.7.2, including exact Single bits,
  both seeds, complete experience projections, retained mirror, bad input and
  atomic overflow. This is a numeric oracle, not execution of the original DLL.
  The inspection-free staged export `fixed-rng-index01/native`, tree
  `8b58ef26cf0a20f53506f340bdf014d2d82b51fa`, also passes32 checks in
  `fixed-rng-staged-01.json` (before this documentation-only evidence addition).

No private binary, game resource or original implementation is included or
loaded by the Native helper. The independent read-only review attempt failed
at service capacity before delivering findings; local diff/evidence review was
completed. No successful independent review is claimed.

```
uv run --managed-python --python 3.13 python -B native/tests/pal98_fixed_random_oracle.py <private-runtime-copy> <fresh-oracle.json>
godot --headless --path native --script res://tests/test_pal98_fixed_random.gd -- <fresh-oracle.json> <fresh-results.json>
```
