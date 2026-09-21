#!/usr/bin/env python3
import os
from pathlib import Path

root = Path(os.environ.get("MANIFEST_ROOT", Path(__file__).parents[1] / "manifests"))
expected = {
    "remove-user0.txt": 106,
    "remove-privileged.txt": 0,
    "preserve-core.txt": 59,
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

required_settings_bridge = {
    "com.amazon.adep",
    "com.amazon.audiohome",
    "com.amazon.ceviche",
    "com.amazon.dcp",
    "com.amazon.device.messaging",
    "com.amazon.device.sale.service",
    "com.amazon.ftv.screensaver",
    "com.amazon.tv.launcher",
    "com.amazon.vizzini",
    "com.amazon.whasettings",
}
missing = required_settings_bridge - sets["preserve-core.txt"]
assert not missing, f"preserve-core.txt: missing stock settings bridge packages {sorted(missing)}"

print("MANIFEST_GATE=PASS")
