"""Select an installed iPhone runtime matching the explicitly measured SDK."""
import json
import re
import sys
import uuid
from pathlib import Path


def select(payload, sdk_version):
    if not isinstance(sdk_version, str) or not re.fullmatch(r"[0-9]{1,3}(?:\.[0-9]{1,3}){1,2}", sdk_version):
        raise ValueError("Malformed measured simulator SDK version")
    sdk_parts = tuple(map(int, sdk_version.split(".")))
    if sdk_parts[0] < 17:
        raise ValueError("Simulator SDK must be iOS 17 or later")
    available = {}
    for runtime in payload.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        version = runtime.get("version", "")
        if ".iOS-" not in identifier or runtime.get("isAvailable") is not True:
            continue
        if not re.fullmatch(r"[0-9]+(?:\.[0-9]+){0,2}", version):
            continue
        parts = tuple(map(int, version.split(".")))
        if parts[0] >= 17 and (parts + (0, 0))[:2] == sdk_parts[:2]:
            available[identifier] = parts + (0,) * (3 - len(parts))
    candidates = []
    for runtime_id, devices in payload.get("devices", {}).items():
        if runtime_id not in available:
            continue
        for device in devices:
            if device.get("isAvailable") is not True or not device.get("name", "").startswith("iPhone "):
                continue
            try:
                udid = str(uuid.UUID(device["udid"])).upper()
            except (KeyError, ValueError, AttributeError):
                continue
            candidates.append((available[runtime_id], device["name"], udid, runtime_id))
    if not candidates:
        raise ValueError("No available iPhone simulator matching measured SDK " + sdk_version + " (installed iOS 17+ only)")
    version, name, udid, runtime = sorted(candidates, key=lambda item: (tuple(-n for n in item[0]), item[1], item[2]))[0]
    return {"name": name, "udid": udid, "runtime": runtime, "version": ".".join(map(str, version)),
            "requestedSDK": sdk_version, "matchPolicy": "installed-sdk-major-minor"}


def read_sdk(filename):
    path = Path(filename)
    if path.is_symlink() or not path.is_file() or not 0 < path.stat().st_size <= 128:
        raise ValueError("Missing or invalid measured SDK receipt")
    value = path.read_text(encoding="utf-8").strip()
    if "\n" in value or "\r" in value:
        raise ValueError("SDK receipt must contain one numerical version")
    return value


if __name__ == "__main__":
    if len(sys.argv) != 3:
        raise SystemExit("Usage: select-simulator.py inventory.json measured-sdk-version.txt")
    with open(sys.argv[1], encoding="utf-8") as stream:
        print(json.dumps(select(json.load(stream), read_sdk(sys.argv[2])), indent=2))
