"""UI then non-UI targets, under one monotonic test-phase budget."""
import argparse
import json
import math
from pathlib import Path
import sys
import time
import uuid

from ci_process import Cancellation, CLEANUP_RESERVE, run_supervised, save_json
from owned_ui_simulator import verified_record, identities, log_json, same_device


def device_id(value):
    if not isinstance(value, str) or str(uuid.UUID(value)).upper() != value.upper():
        raise ValueError("Expected a canonical simulator UUID")
    return value.upper()


def phases(shared_id, ui_id, derived, output):
    shared_id, ui_id = device_id(shared_id), device_id(ui_id)
    if shared_id == ui_id:
        raise ValueError("UI destination must differ from the preexisting simulator")
    common = ["xcodebuild", "-project", "PowerliftingApp.xcodeproj", "-scheme", "PowerliftingApp",
              "-destination-timeout", "60", "-derivedDataPath", str(derived),
              "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
              "CODE_SIGNING_ALLOWED=NO", "test-without-building"]
    return [("test-ui", [*common, "-destination", f"platform=iOS Simulator,id={ui_id}",
                         "-resultBundlePath", str(output / "test-ui.xcresult"), "-only-testing:PowerliftingAppUITests"]),
            ("test-unit", [*common, "-destination", f"platform=iOS Simulator,id={ui_id}",
                           "-resultBundlePath", str(output / "test-unit.xcresult"), "-skip-testing:PowerliftingAppUITests"])]


def execute(plan, output, cancellation, *, budget=560, clock=time.monotonic, runner=run_supervised, validator=None,
            reserves=None, receipt_name="test-phases.json", validation_key="inventory",
            before_phase=None, phase_validator=None, timeouts=None):
    if not math.isfinite(budget) or budget <= CLEANUP_RESERVE:
        raise ValueError("Invalid shared test budget")
    reserves = reserves or {}
    timeouts = timeouts or {}
    if any(not math.isfinite(value) or value < 0 for value in reserves.values()):
        raise ValueError("Invalid following-phase reservation")
    if any(not math.isfinite(value) or value <= 0 for value in timeouts.values()):
        raise ValueError("Invalid child timeout cap")
    started = clock()
    deadline = started + budget
    evidence = {"schemaVersion": 1, "budgetSeconds": budget, "cleanupReserveSeconds": CLEANUP_RESERVE,
                "phases": [], "state": "running", "aggregateExitCode": 125}
    destination = output / receipt_name
    save_json(destination, evidence)
    code = 0
    try:
        for name, command in plan:
            remaining = deadline - clock()
            reserve = CLEANUP_RESERVE + reserves.get(name, 0)
            if code == 0 and cancellation.signum is None and remaining > reserve and before_phase is not None:
                before_phase(name)
                # Ownership reads/validation consume this same budget. Never use
                # the stale allowance or launch after validation cancellation.
                remaining = deadline - clock()
            if code != 0 or cancellation.signum is not None or remaining <= reserve:
                reason = "previous-failure" if code else "cancelled" if cancellation.signum else "shared-deadline-exhausted"
                code = code or (128 + cancellation.signum if cancellation.signum else 124)
                evidence["phases"].append({"name": name, "launched": False, "reason": reason})
                continue
            timeout = min(remaining - reserve, timeouts.get(name, remaining - reserve))
            print(f"Starting {name}; shared remaining {remaining:.3f}s, child budget {timeout:.3f}s", flush=True)
            entry = {"name": name, "command": command, "sharedRemainingSeconds": remaining, "childTimeoutSeconds": timeout,
                     "followingPhaseReserveSeconds": reserves.get(name, 0)}
            evidence["phases"].append(entry)
            save_json(destination, evidence)
            entry.update(runner(command, timeout, output / name, cancellation))
            code = entry["exitCode"]
            (output / (name + ".exit-code")).write_text(str(code) + "\n", encoding="utf-8")
            if code == 0 and phase_validator is not None:
                entry["validation"] = phase_validator(name, output / name)
            if clock() > deadline:
                code = code or 124
            if cancellation.signum is not None:
                code = code or 128 + cancellation.signum
            save_json(destination, evidence)
        if code == 0 and validator is not None:
            evidence[validation_key] = validator()
            if clock() > deadline:
                code = 124
    except Exception as error:
        evidence["error"] = f"{type(error).__name__}: {error}"
        code = 125
    finally:
        if code == 0 and cancellation.signum is not None:
            code = 128 + cancellation.signum
        evidence.update(state="finished", aggregateExitCode=code, elapsedSeconds=clock() - started,
                        cancellationSignal=cancellation.signum)
        save_json(destination, evidence)
    return code


def execute_tests(selected, owned_file, derived, output, cancellation, *, clock=time.monotonic,
                  runner=run_supervised, validator=None):
    owned = verified_record(owned_file, selected)
    if owned.get("bootVerified") is not True or owned.get("state") != "ready":
        raise ValueError("Owned UI simulator has no verified completed boot")
    plan = phases(selected["udid"], owned["udid"], derived, output)
    plan.insert(1, ("test-unit-ready", ["xcrun", "simctl", "list", "--json"]))

    def unchanged(name):
        if verified_record(owned_file, selected) != owned:
            raise ValueError("Owned simulator record changed before " + name)

    def validate_phase(name, prefix):
        unchanged(name)
        if name != "test-unit-ready":
            return None
        devices = identities(log_json(prefix))
        runtime, device = devices[owned["udid"]]
        if not same_device(owned, runtime, device) or device.get("state") != "Booted" or device.get("isAvailable") is not True:
            raise ValueError("No matching available Booted owned simulator before unit tests")
        return {"udid": owned["udid"], "identityMatched": True, "bootedObserved": True}

    # The extra observation is inside560s, not a new readiness budget. UI
    # preserves10s work+20s cleanup for it; both tests use the same fresh device.
    return execute(plan, output, cancellation, clock=clock, runner=runner, validator=validator,
                   reserves={"test-ui": 30}, timeouts={"test-unit-ready": 10},
                   before_phase=unchanged, phase_validator=validate_phase)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--derived", type=Path, required=True)
    parser.add_argument("--selected", type=Path, required=True)
    parser.add_argument("--owned-ui", type=Path, required=True)
    args = parser.parse_args()
    selected = json.loads(args.selected.read_text(encoding="utf-8"))
    cancellation = Cancellation()
    import importlib.util
    spec = importlib.util.spec_from_file_location("test_inventory", Path(__file__).with_name("check-test-inventory.py"))
    inventory = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(inventory)
    def validate():
        result = inventory.verify(Path.cwd(), args.output)
        save_json(args.output / "test-inventory.json", result)
        return result
    with cancellation.handlers():
        return execute_tests(selected, args.owned_ui, args.derived, args.output, cancellation, validator=validate)


if __name__ == "__main__":
    raise SystemExit(main())
