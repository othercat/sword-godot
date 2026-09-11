# Locked original-package random arithmetic

`native_pal98_fixed_random.gd` independently implements the ordinary controlled
random path of the locked PAL.dll1.6.2.0, plus SubMain's new-game experience
projection. It is internal: no ordinary original Session, initial Timer seed,
public save contract or game-wide RNG dispatch is enabled by this increment.

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
forced diagnostics, poison bypass/zero-bucket compatibility and Randomize
dispatch are not implemented by this helper. A future interpreter must select
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
