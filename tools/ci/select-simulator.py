"""Select a real available iPhone from simctl JSON, without assuming a device name."""
import json
import re
import sys
import uuid


def select(payload):
    available = {}
    for runtime in payload.get("runtimes", []):
        identifier = runtime.get("identifier", "")
        version = runtime.get("version", "")
        if ".iOS-" not in identifier or runtime.get("isAvailable") is not True:
            continue
        if not re.fullmatch(r"\d+(?:\.\d+){0,2}", version):
            continue
        parts = tuple(map(int, version.split(".")))
        if parts[0] >= 17:
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
        raise ValueError("No available iPhone simulator with an available iOS 17+ runtime")
    version, name, udid, runtime = sorted(candidates, key=lambda item: (tuple(-n for n in item[0]), item[1], item[2]))[0]
    return {"name": name, "udid": udid, "runtime": runtime, "version": ".".join(map(str, version))}


if __name__ == "__main__":
    with open(sys.argv[1], encoding="utf-8") as stream:
        print(json.dumps(select(json.load(stream)), indent=2))
