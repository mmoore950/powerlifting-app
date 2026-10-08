"""Create/boot and later clean only a recorded fresh simulator for this run."""
import argparse
import json
import os
from pathlib import Path
import re
import time
import uuid

from ci_process import Cancellation, CLEANUP_RESERVE, run_supervised, save_json


def canonical(value):
    if not isinstance(value, str) or str(uuid.UUID(value)).upper() != value.upper():
        raise ValueError("Malformed simulator UUID")
    return value.upper()


def identities(payload):
    result = {}
    for runtime, entries in payload["devices"].items():
        for entry in entries:
            identity = canonical(entry["udid"])
            if identity in result:
                raise ValueError("Duplicate simulator UUID in inventory")
            result[identity] = (runtime, entry)
    return result


def run_identity():
    run, attempt = os.environ["GITHUB_RUN_ID"], os.environ["GITHUB_RUN_ATTEMPT"]
    if not re.fullmatch(r"[1-9][0-9]*", run) or not re.fullmatch(r"[1-9][0-9]*", attempt):
        raise ValueError("Invalid workflow run identity")
    return run, attempt


def verified_record(filename, selected):
    if filename.is_symlink() or not 0 < filename.stat().st_size <= 1024 * 1024:
        raise ValueError("Invalid owned simulator record")
    record = json.loads(filename.read_text(encoding="utf-8"))
    run, attempt = run_identity()
    identity, existing = canonical(record["udid"]), canonical(selected["udid"])
    before = [canonical(x) for x in record["preexistingUDIDs"]]
    if (record.get("schemaVersion") != 1 or record.get("createdValidated") is not True
            or record.get("runID") != run or record.get("runAttempt") != attempt
            or canonical(record["selectedUDID"]) != existing or identity == existing or identity in before
            or existing not in before or record.get("runtime") != selected["runtime"]
            or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+){0,2}", record.get("runtime", ""))
            or not re.fullmatch(r"LiftToolkit-UI-" + run + "-" + attempt + r"-[a-f0-9]{8}", record.get("name", ""))
            or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[A-Za-z0-9-]+", record.get("deviceType", ""))):
        raise ValueError("Fresh simulator ownership is unverified; no device action permitted")
    return record


def same_device(record, runtime, entry):
    return (runtime == record["runtime"] and entry.get("name") == record["name"]
            and entry.get("deviceTypeIdentifier") == record["deviceType"])


def log_json(prefix):
    filename = prefix.with_name(prefix.name + ".log")
    if filename.stat().st_size > 4 * 1024 * 1024:
        raise ValueError("simctl output exceeds bound")
    text = filename.read_text(encoding="utf-8").lstrip()
    value, end = json.JSONDecoder().raw_decode(text)
    if any(not line.startswith("Supervisor:") for line in text[end:].strip().splitlines()):
        raise ValueError("Unexpected output around simctl JSON")
    if not isinstance(value, dict):
        raise ValueError("Expected simctl object")
    return value


def operate(mode, output, selected, inventory=None, *, clock=time.monotonic, runner=run_supervised):
    cancellation = Cancellation()
    with cancellation.handlers():
        return operation(mode, output, selected, inventory, cancellation, clock=clock, runner=runner)


def operation(mode, output, selected, inventory, cancellation, *, clock=time.monotonic, runner=run_supervised):
    owned_file = output / "owned-ui-simulator.json"
    cleanup_file = output / "owned-ui-cleanup.json"
    deadline = clock() + (90 if mode == "create" else 100)
    commands = []

    def command(label, argv, maximum=20):
        remaining = deadline - clock() - CLEANUP_RESERVE
        if remaining <= 0 or cancellation.signum is not None:
            raise RuntimeError("Simulator operation cancelled/shared budget exhausted")
        prefix = output / label
        result = runner(argv, min(maximum, remaining), prefix, cancellation)
        commands.append({"name": label, "command": argv, **result})
        if result["exitCode"] != 0:
            raise RuntimeError(f"{label} failed: {result['exitCode']}")
        return prefix

    record = None
    cleanup = {"schemaVersion": 1, "commands": commands, "cleanupComplete": False}
    try:
        if mode == "create":
            if owned_file.exists() or owned_file.is_symlink():
                raise ValueError("Owned simulator record already exists; no retry")
            selected_id = canonical(selected["udid"])
            existing = identities(inventory)
            runtime, device = existing[selected_id]
            runtimes = {r["identifier"]: r for r in inventory["runtimes"]}
            device_type = device["deviceTypeIdentifier"]
            if (runtime != selected["runtime"] or runtimes[runtime].get("isAvailable") is not True
                    or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9]+(?:-[0-9]+){0,2}", runtime)
                    or device.get("isAvailable") is not True
                    or not re.fullmatch(r"com\.apple\.CoreSimulator\.SimDeviceType\.iPhone-[A-Za-z0-9-]+", device_type)
                    or device_type not in {d["identifier"] for d in inventory["devicetypes"]}):
                raise ValueError("Selected available iPhone/runtime/type mismatch")
            run, attempt = run_identity()
            record = {"schemaVersion": 1, "runID": run, "runAttempt": attempt,
                      "selectedUDID": selected_id, "preexistingUDIDs": sorted(existing),
                      "name": f"LiftToolkit-UI-{run}-{attempt}-{uuid.uuid4().hex[:8]}",
                      "runtime": runtime, "deviceType": device_type, "commands": commands,
                      "createdValidated": False, "bootVerified": False, "state": "create-intent"}
            save_json(owned_file, record)
            command("ui-create-help", ["xcrun", "simctl", "help", "create"], maximum=5)
            command("ui-bootstatus-help", ["xcrun", "simctl", "help", "bootstatus"], maximum=5)
            created = command("ui-create", ["xcrun", "simctl", "create", record["name"], device_type, runtime])
            lines = created.with_name(created.name + ".log").read_text(encoding="utf-8").splitlines()
            ids = [canonical(line.strip()) for line in lines if re.fullmatch(r"[0-9a-fA-F-]{36}", line.strip())]
            if len(ids) != 1 or ids[0] == selected_id or ids[0] in existing:
                raise ValueError("Creation did not return exactly one fresh canonical UUID")
            record.update(udid=ids[0], state="created-unverified")
            save_json(owned_file, record)
            after = identities(log_json(command("ui-after-create", ["xcrun", "simctl", "list", "--json"])))
            created_runtime, created_device = after[record["udid"]]
            if not same_device(record, created_runtime, created_device) or created_device.get("isAvailable") is not True:
                raise ValueError("Created simulator inventory does not match this run")
            record.update(createdValidated=True, state="booting")
            save_json(owned_file, record)
            command("ui-boot", ["xcrun", "simctl", "boot", record["udid"]], maximum=10)
            command("ui-bootstatus", ["xcrun", "simctl", "bootstatus", record["udid"], "-b"], maximum=40)
            ready = identities(log_json(command("ui-ready", ["xcrun", "simctl", "list", "--json"], maximum=10)))
            ready_runtime, ready_device = ready[record["udid"]]
            if not same_device(record, ready_runtime, ready_device) or ready_device.get("state") != "Booted":
                raise ValueError("Created simulator has no verified Booted state")
            record.update(bootVerified=True, state="ready")
            save_json(owned_file, record)
            print(json.dumps({k: record[k] for k in ("udid", "name", "runtime", "bootVerified")}))
        else:
            if not owned_file.exists() and not owned_file.is_symlink():
                cleanup.update(cleanupComplete=True, reason="no-owned-record")
                save_json(cleanup_file, cleanup)
                return 0
            record = verified_record(owned_file, selected)
            cleanup["udid"] = record["udid"]
            before = identities(log_json(command("ui-cleanup-before", ["xcrun", "simctl", "list", "--json"])))
            if record["udid"] in before:
                runtime, entry = before[record["udid"]]
                if not same_device(record, runtime, entry):
                    raise ValueError("Owned UUID now has a different identity; refusing shutdown/delete")
                if entry.get("state") != "Shutdown":
                    command("ui-shutdown", ["xcrun", "simctl", "shutdown", record["udid"]])
                command("ui-delete", ["xcrun", "simctl", "delete", record["udid"]])
            after = identities(log_json(command("ui-cleanup-after", ["xcrun", "simctl", "list", "--json"])))
            if record["udid"] in after:
                raise ValueError("Owned simulator still present after cleanup")
            cleanup.update(cleanupComplete=True, ownedDeviceAbsent=True, reason="verified-absent")
            save_json(cleanup_file, cleanup)
        return 0
    except Exception as error:
        failure = f"{type(error).__name__}: {error}"
        if mode == "create" and record is not None:
            record.update(error=failure, state="failed")
            save_json(owned_file, record)
        else:
            cleanup.update(error=failure, cancellationSignal=cancellation.signum)
            save_json(cleanup_file, cleanup)
        print(f"Owned simulator {mode} failed: {failure}", flush=True)
        return 125


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["create", "cleanup"])
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    selected_file = args.output / "selected-simulator.json"
    if args.mode == "cleanup" and not selected_file.exists() and not (args.output / "owned-ui-simulator.json").exists():
        save_json(args.output / "owned-ui-cleanup.json", {"schemaVersion": 1, "cleanupComplete": True, "reason": "preparation-not-started"})
        return 0
    try:
        if selected_file.is_symlink() or not 0 < selected_file.stat().st_size <= 1024 * 1024:
            raise ValueError("Invalid selected simulator record")
        selected = json.loads(selected_file.read_text(encoding="utf-8"))
        inventory = None
        if args.mode == "create":
            inventory_file = args.output / "simulators.json"
            if inventory_file.is_symlink() or not 0 < inventory_file.stat().st_size <= 4 * 1024 * 1024:
                raise ValueError("Invalid simulator inventory")
            inventory = json.loads(inventory_file.read_text(encoding="utf-8"))
        return operate(args.mode, args.output, selected, inventory)
    except Exception as error:
        save_json(args.output / "owned-ui-cleanup.json", {"schemaVersion": 1, "cleanupComplete": False,
            "reason": "input-validation-failed-no-device-action", "error": f"{type(error).__name__}: {error}"})
        print(f"Simulator input validation failed: {error}", flush=True)
        return 125


if __name__ == "__main__":
    raise SystemExit(main())
