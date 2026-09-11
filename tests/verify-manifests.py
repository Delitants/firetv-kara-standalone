#!/usr/bin/env python3
import os
from pathlib import Path

root = Path(os.environ.get("MANIFEST_ROOT", Path(__file__).parents[1] / "manifests"))
expected = {
    "remove-user0.txt": 115,
    "remove-privileged.txt": 1,
    "preserve-core.txt": 49,
    "preserve-compatibility.txt": 16,
}

sets = {}
for name, count in expected.items():
    values = [line.strip() for line in (root / name).read_text().splitlines() if line.strip() and not line.startswith("#")]
    assert len(values) == count, f"{name}: expected {count}, got {len(values)}"
    assert len(values) == len(set(values)), f"{name}: duplicate package"
    assert all(value.startswith(("com.amazon.", "amazon.")) for value in values), f"{name}: non-Amazon package"
    sets[name] = set(values)

names = list(sets)
for index, left in enumerate(names):
    for right in names[index + 1:]:
        overlap = sets[left] & sets[right]
        assert not overlap, f"{left}/{right}: overlap {sorted(overlap)}"

print("MANIFEST_GATE=PASS")
