#!/usr/bin/env python3
# SPDX-License-Identifier: MIT
"""Copy only the shared MIT schema interface, never an implementation module."""
import argparse
import hashlib
import json
import subprocess
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--contracts-root", type=Path, required=True)
parser.add_argument("--check", action="store_true")
args = parser.parse_args()
source = args.contracts_root.resolve()
target = Path(__file__).resolve().parents[1] / "contracts"
origin = subprocess.check_output(["git", "remote", "get-url", "origin"], cwd=source, text=True).strip()
if origin not in ("https://github.com/othercat/pal98-runtime-contracts.git", "git@github.com:othercat/pal98-runtime-contracts.git"):
    raise SystemExit("Unexpected contract owner")
files = {f"pal.native.{kind}.v1.schema.json": source / "schemas" / f"pal.native.{kind}.v1.schema.json" for kind in ("content", "package", "state", "save", "enemy-actions", "progression", "equipment", "battle-layout")}
files["pal.native.battle-layout.v2.schema.json"] = source / "schemas/pal.native.battle-layout.v2.schema.json"
files["pal.native.battle-ui.v1.schema.json"] = source / "schemas/pal.native.battle-ui.v1.schema.json"
files["pal.native.pal98-sources.v1.schema.json"] = source / "schemas/pal.native.pal98-sources.v1.schema.json"
files["pal.native.pal98-graphics.v1.schema.json"] = source / "schemas/pal.native.pal98-graphics.v1.schema.json"
files["pal.native.attack-formula.v1.schema.json"] = source / "schemas/pal.native.attack-formula.v1.schema.json"
files["pal.native.attack-random.v1.schema.json"] = source / "schemas/pal.native.attack-random.v1.schema.json"
files["pal.native.player-physical.v1.schema.json"] = source / "schemas/pal.native.player-physical.v1.schema.json"
files["pal.native.training.v1.schema.json"] = source / "schemas/pal.native.training.v1.schema.json"
files["pal.native.enemy-physical.v1.schema.json"] = source / "schemas/pal.native.enemy-physical.v1.schema.json"
files["pal.native.battle-hud.v1.schema.json"] = source / "schemas/pal.native.battle-hud.v1.schema.json"
files["pal.native.hud-placement.v1.schema.json"] = source / "schemas/pal.native.hud-placement.v1.schema.json"
files["pal.native.hud-placement.v2.schema.json"] = source / "schemas/pal.native.hud-placement.v2.schema.json"
files["pal.native.party-card.v1.schema.json"] = source / "schemas/pal.native.party-card.v1.schema.json"
files["pal.native.party-card.v2.schema.json"] = source / "schemas/pal.native.party-card.v2.schema.json"
files["pal.native.map-ui.v1.schema.json"] = source / "schemas/pal.native.map-ui.v1.schema.json"
files["pal.native.story-notice.v1.schema.json"] = source / "schemas/pal.native.story-notice.v1.schema.json"
files["pal.native.initial-vitals.v1.schema.json"] = source / "schemas/pal.native.initial-vitals.v1.schema.json"
files["pal.native.battle-canvas.v1.schema.json"] = source / "schemas/pal.native.battle-canvas.v1.schema.json"
files["pal.native.battle-formation.v1.schema.json"] = source / "schemas/pal.native.battle-formation.v1.schema.json"
files["pal.native.enemy-overlay.v1.schema.json"] = source / "schemas/pal.native.enemy-overlay.v1.schema.json"
files["pal.native.command-panel.v1.schema.json"] = source / "schemas/pal.native.command-panel.v1.schema.json"
files["pal.native.performance.v1.schema.json"] = source / "schemas/pal.native.performance.v1.schema.json"
files["pal.native.sampling.v1.schema.json"] = source / "schemas/pal.native.sampling.v1.schema.json"
files["LICENSE"] = source / "LICENSE"
committed = all(subprocess.run(["git", "show", "HEAD:" + path.relative_to(source).as_posix()], cwd=source, capture_output=True).stdout == path.read_bytes().replace(b"\r\n", b"\n") for path in files.values())
receipt = {"owner": origin, "base_commit": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=source, text=True).strip(),
           "source_state": "committed-snapshot" if committed else "working-tree-snapshot", "status": "draft", "license": "MIT", "text_normalization": "LF", "files": {}}
for name, path in files.items():
    data = path.read_bytes().replace(b"\r\n", b"\n")
    receipt["files"][name] = hashlib.sha256(data).hexdigest()
    if args.check:
        assert (target / name).read_bytes() == data, name
    else:
        target.mkdir(parents=True, exist_ok=True)
        (target / name).write_bytes(data)
if not args.check:
    (target / "receipt.json").write_bytes((json.dumps(receipt, indent=2) + "\n").encode("utf-8"))
else:
    assert json.loads((target / "receipt.json").read_text()) == receipt
print("Native MIT contract snapshot: " + ("verified" if args.check else "updated"))
