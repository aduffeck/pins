#!/usr/bin/env python3
"""Register the INDI 3rd-party drivers shipped in the image for Touch-N-Stars.

The Touch-N-Stars plugin offers INDI drivers per device type from its embedded
default lists merged with ``~/Documents/INDI/3rdparty.json``. On a Raspberry
Pi that registry is filled by pinsdaemon whenever a 3rd-party driver package is
installed; in the container the drivers are built into the image, so the
registry is generated from the INDI driver definitions (``/usr/share/indi``)
instead.

Usage:
  indi-3rdparty-registry.py generate [--xml-dir DIR] OUTPUT.json
  indi-3rdparty-registry.py merge GENERATED.json TARGET.json

``generate`` writes the registry for every driver definition except the core
``drivers.xml``. ``merge`` adds the generated entries to an existing registry
(matching on driver name per type) without touching entries that are already
there, and creates the target when it does not exist.
"""

import json
import os
import re
import sys
import xml.etree.ElementTree as ET

TYPES = [
    "camera",
    "dome",
    "filterwheel",
    "flatpanel",
    "focuser",
    "rotator",
    "safetymonitor",
    "switches",
    "telescope",
    "weather",
]

GROUP_TYPES = {
    "CCDs": "camera",
    "Filter Wheels": "filterwheel",
    "Focusers": "focuser",
    "Telescopes": "telescope",
    "Rotators": "rotator",
    "Domes": "dome",
    "Weather": "weather",
}

# Groups without a device type of their own are classified by their label.
LABEL_TYPES = [
    (re.compile(r"flat|panel|cover|cap\b", re.I), "flatpanel"),
    (re.compile(r"safety", re.I), "safetymonitor"),
    (re.compile(r"power|switch|relay|box|hub|dew|light", re.I), "switches"),
]


def classify(group, label):
    if group in GROUP_TYPES:
        return GROUP_TYPES[group]
    for pattern, device_type in LABEL_TYPES:
        if pattern.search(label or ""):
            return device_type
    return None


def generate(xml_dir):
    registry = {t: {} for t in TYPES}
    for name in sorted(os.listdir(xml_dir)):
        if not name.endswith(".xml") or name == "drivers.xml":
            continue
        path = os.path.join(xml_dir, name)
        try:
            root = ET.parse(path).getroot()
        except ET.ParseError as exc:
            print(f"skipping {path}: {exc}", file=sys.stderr)
            continue
        for group in root.iter("devGroup"):
            group_name = group.get("group", "")
            for device in group.iter("device"):
                label = (device.get("label") or "").strip()
                driver = device.find("driver")
                if driver is None or not (driver.text or "").strip():
                    continue
                exe = driver.text.strip()
                device_type = classify(group_name, label)
                if device_type is None:
                    continue
                registry[device_type].setdefault(
                    exe, {"Name": exe, "Label": label or exe, "Type": device_type}
                )
    return {t: sorted(registry[t].values(), key=lambda e: e["Label"].lower()) for t in TYPES}


def load(path):
    if not os.path.exists(path):
        return {}
    with open(path, encoding="utf-8") as f:
        text = f.read()
    if not text.strip():
        return {}
    data = json.loads(text)
    if isinstance(data, list):
        # Flat legacy format: [{"Name", "Label", "Type"}]
        grouped = {}
        for entry in data:
            if isinstance(entry, dict) and entry.get("Type"):
                grouped.setdefault(entry["Type"], []).append(entry)
        return grouped
    return data if isinstance(data, dict) else {}


def merge(generated, target):
    existing = load(target)
    result = {}
    added = 0
    for device_type in sorted(set(TYPES) | set(existing) | set(generated)):
        entries = [e for e in existing.get(device_type, []) if isinstance(e, dict)]
        known = {e.get("Name") for e in entries}
        for entry in generated.get(device_type, []):
            if entry["Name"] not in known:
                entries.append(entry)
                known.add(entry["Name"])
                added += 1
        result[device_type] = entries
    os.makedirs(os.path.dirname(target) or ".", exist_ok=True)
    with open(target, "w", encoding="utf-8") as f:
        json.dump(result, f, indent=2)
        f.write("\n")
    return added


def main(argv):
    if len(argv) >= 3 and argv[1] == "generate":
        args = argv[2:]
        xml_dir = "/usr/share/indi"
        if args[0] == "--xml-dir":
            xml_dir = args[1]
            args = args[2:]
        registry = generate(xml_dir)
        with open(args[0], "w", encoding="utf-8") as f:
            json.dump(registry, f, indent=2)
            f.write("\n")
        total = sum(len(v) for v in registry.values())
        print(f"registered {total} 3rd-party INDI drivers from {xml_dir}")
        return 0
    if len(argv) == 4 and argv[1] == "merge":
        with open(argv[2], encoding="utf-8") as f:
            generated = json.load(f)
        added = merge(generated, argv[3])
        print(f"[pins] INDI 3rd-party registry {argv[3]}: {added} driver(s) added")
        return 0
    print(__doc__, file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
