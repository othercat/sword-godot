# SPDX-License-Identifier: MIT
"""Exact rational numeric oracle; not a run of the original game or DLL.

The assertions bind the recovered arithmetic to the locked private binaries.
Only synthetic seeds, numeric results and hashes are written to the report.
"""
import argparse
from fractions import Fraction as F
import hashlib
import json
from pathlib import Path
import struct


def single_bits(value):
    value = F(value)
    if not value:
        return 0
    assert value > 0
    exponent = value.numerator.bit_length() - value.denominator.bit_length()
    if value < F(2) ** exponent:
        exponent -= 1
    assert -126 <= exponent <= 127
    mantissa = round(value / F(2) ** (exponent - 23))
    if mantissa == 1 << 24:
        mantissa >>= 1
        exponent += 1
    return ((exponent + 127) << 23) | (mantissa - (1 << 23))


def from_bits(bits):
    if bits == 0:
        return F(0)
    return F((bits & 0x7fffff) | 0x800000) * F(2) ** ((bits >> 23) - 150)


def sample(seed):
    first = (seed * 0xfd43fd + 0xc39ec3) % (1 << 24)
    second = (first * 0xfd43fd + 0xc39ec3) % (1 << 24)
    scaled = from_bits(single_bits(F(second, 1 << 24) * 10_000_000))
    rounded = (scaled + F(1, 2)).numerator // (scaled + F(1, 2)).denominator
    bits = min(single_bits(F(rounded, 10_000_000)), 0x3f7ffffe)
    return {'seed': seed, 'intermediate': first, 'next': second, 'value_bits': bits}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('private_runtime', type=Path)
    parser.add_argument('output', type=Path)
    args = parser.parse_args()
    authority = {'PAL.dll': '3074423f2ea58529fd22b8e72a05ef289adf15a3b796841447e03db3417446ff',
                 'PAL.EXE': '75d612b9cbd9c1f0884f18c9a6d2ee522b227f2f6b3da92495bae8f73161c450',
                 'VB40032.DLL': '0f1604c9a7398cbb317383799b88c4e1aa7ce0b2c968392f0a7a9ddff22ec57d'}
    for name, expected in authority.items():
        assert hashlib.sha256((args.private_runtime / name).read_bytes()).hexdigest() == expected
    exe = (args.private_runtime/'PAL.EXE').read_bytes()
    assert hashlib.sha256(exe[0x1a42a:0x1a42a+220]).hexdigest() == '9f84d1d294e72a5afaeeb67245d842315e43af11b8f888ec02748d56d495dbcd'
    # Sample every output exponent plus rounding, CInt and upper-clamp edges.
    # Invert the bijective LCG twice to choose exact second-step values.
    modulus = 1 << 24
    inverse = pow(0xfd43fd, -1, modulus)
    targets = {0, 1, 2, modulus - 1, modulus - 2, modulus - 3}
    for bit in range(24):
        for delta in (-1, 0, 1):
            targets.add(max(0, min(modulus-1, (1 << bit)+delta)))
    for boundary in (F(1, 4), F(3, 4), F(1, 40), F(3, 40), F(39, 40)):
        middle = round(boundary * modulus)
        targets.update(range(middle-3, middle+4))
    seeds = {0, 1, 0x50000, 0x24de00, 0xffffff, 0x80000000, 0xffffffff}
    for target in targets:
        previous = ((target-0xc39ec3) * inverse) % modulus
        seeds.add(((previous-0xc39ec3) * inverse) % modulus)
    # Deterministic spread independent of the target LCG.
    seeds.update((index * 2654435761) % (1 << 32) for index in range(1024))
    vectors = [sample(seed) for seed in sorted(seeds)]
    sequences = []
    levels = [-32768, -1, 0, 99, 32763]
    for initial in (0, 1, 0x50000, 0x24de00, 0xffffff, 0xffffffff):
        seed = initial
        rows = []
        calls = []
        for level in levels:
            categories = [{'level': level, 'count': 0}]
            for _ in range(7):
                a = sample(seed); seed = a['next']; calls.append(a)
                b = sample(seed); seed = b['next']; calls.append(b)
                categories.append({'level': level + round(from_bits(a['value_bits'])*2+2),
                                   'count': round(from_bits(b['value_bits'])*20)})
            rows.append(categories)
        sequences.append({'initial': initial, 'final': seed, 'base_levels': levels,
                          'experience': rows, 'calls': calls})
    # Sanity: exact rational conversion agrees with IEEE packing across vectors.
    for vector in vectors:
        value = from_bits(vector['value_bits'])
        assert struct.unpack('<I', struct.pack('<f', float(value)))[0] == vector['value_bits']
    report = {'authority': authority, 'kind': 'exact-rational synthetic arithmetic oracle',
              'original_gameplay': False, 'vectors': vectors, 'sequences': sequences}
    timer_vectors = []
    # Fraction(float) captures the exact binary64 0.001 constant in VB's image.
    for seconds in (0, 1, 31, 32, 8191, 8192, 16383, 16384, 20117, 32767, 32768, 65535, 65536, 86399):
        for ms in range(1000):
            value_bits = single_bits(F(seconds) + F(0.001) * ms)
            value = float(from_bits(value_bits))
            high = struct.unpack('<II', struct.pack('<d', value))[1]
            seed = ((high << 8) ^ (high >> 8)) & 0xffff00
            timer_vectors.append({'fields': [seconds//3600, seconds//60 % 60, seconds % 60, ms],
                                  'timer_bits': value_bits, 'seed': seed})
    report['timer_vectors'] = timer_vectors
    report['randomize_r8_vectors'] = []
    for value in (0.0, -0.0, 0.5, -0.5, 20117.587890625, -12345.625, 86400.0, 1e100):
        high = struct.unpack('<II', struct.pack('<d', value))[1]
        for seed in (0, 0x050000, 0xabcdef12, 0xffffffff):
            report['randomize_r8_vectors'].append({'value': value, 'seed': seed,
                'next': (seed & 0xff0000ff) | (((high << 8) ^ (high >> 8)) & 0xffff00)})
    with args.output.open('x', encoding='utf-8') as out:
        json.dump(report, out, indent=2); out.write('\n')
    print(f'{len(vectors)} RNG vectors, {len(sequences)} complete 70-call sequences, {len(timer_vectors)} Timer vectors')


if __name__ == '__main__':
    main()
