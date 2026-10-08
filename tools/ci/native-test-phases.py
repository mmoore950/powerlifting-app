"""UI then non-UI targets, under one monotonic test-phase budget."""
import argparse
import json
import math
from pathlib import Path
import sys
import time
import uuid

from ci_process import Cancellation, CLEANUP_RESERVE, run_supervised, save_json


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
            ("test-unit", [*common, "-destination", f"platform=iOS Simulator,id={shared_id}",
                           "-resultBundlePath", str(output / "test-unit.xcresult"), "-skip-testing:PowerliftingAppUITests"])]


def execute(plan, output, cancellation, *, budget=560, clock=time.monotonic, runner=run_supervised, validator=None):
    if not math.isfinite(budget) or budget <= CLEANUP_RESERVE:
        raise ValueError("Invalid shared test budget")
    started = clock()
    deadline = started + budget
    evidence = {"schemaVersion": 1, "budgetSeconds": budget, "cleanupReserveSeconds": CLEANUP_RESERVE,
                "phases": [], "state": "running", "aggregateExitCode": 125}
    destination = output / "test-phases.json"
    save_json(destination, evidence)
    code = 0
    try:
        for name, command in plan:
            remaining = deadline - clock()
            if code != 0 or cancellation.signum is not None or remaining <= CLEANUP_RESERVE:
                reason = "previous-failure" if code else "cancelled" if cancellation.signum else "shared-deadline-exhausted"
                code = code or (128 + cancellation.signum if cancellation.signum else 124)
                evidence["phases"].append({"name": name, "launched": False, "reason": reason})
                continue
            timeout = remaining - CLEANUP_RESERVE
            print(f"Starting {name}; shared remaining {remaining:.3f}s, child budget {timeout:.3f}s", flush=True)
            entry = {"name": name, "command": command, "sharedRemainingSeconds": remaining, "childTimeoutSeconds": timeout}
            evidence["phases"].append(entry)
            save_json(destination, evidence)
            entry.update(runner(command, timeout, output / name, cancellation))
            code = entry["exitCode"]
            (output / (name + ".exit-code")).write_text(str(code) + "\n", encoding="utf-8")
            if clock() > deadline:
                code = code or 124
            if cancellation.signum is not None:
                code = code or 128 + cancellation.signum
            save_json(destination, evidence)
        if code == 0 and validator is not None:
            evidence["inventory"] = validator()
            if clock() > deadline:
                code = 124
    except Exception as error:
        evidence["error"] = f"{type(error).__name__}: {error}"
        code = 125
    finally:
        evidence.update(state="finished", aggregateExitCode=code, elapsedSeconds=clock() - started,
                        cancellationSignal=cancellation.signum)
        save_json(destination, evidence)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--derived", type=Path, required=True)
    parser.add_argument("--selected", type=Path, required=True)
    parser.add_argument("--owned-ui", type=Path, required=True)
    args = parser.parse_args()
    from owned_ui_simulator import verified_record
    selected = json.loads(args.selected.read_text(encoding="utf-8"))
    owned = verified_record(args.owned_ui, selected)
    if owned.get("bootVerified") is not True:
        raise ValueError("Owned UI simulator has no verified completed boot")
    plan = phases(selected["udid"], owned["udid"], args.derived, args.output)
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
        return execute(plan, args.output, cancellation, validator=validate)


if __name__ == "__main__":
    raise SystemExit(main())
