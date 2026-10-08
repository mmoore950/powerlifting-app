"""Compile then require fresh UI readiness within one shared 440s build budget."""
import argparse
import importlib.util
import json
from pathlib import Path
import time

from ci_process import Cancellation, run_supervised, save_json
from owned_ui_simulator import verified_record, identities, log_json, same_device

spec = importlib.util.spec_from_file_location("native_phases", Path(__file__).with_name("native-test-phases.py"))
phases_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phases_module)


def execute_build(selected, owned_file, derived, output, cancellation, *, clock=time.monotonic, runner=run_supervised):
    owned = verified_record(owned_file, selected)
    if owned.get("bootRequested") is not True or owned.get("bootVerified") is not False:
        raise ValueError("Fresh owned simulator needs a completed boot request, not a reused ready record")
    plan = [
        ("build-compile", ["xcodebuild", "-project", "PowerliftingApp.xcodeproj", "-scheme", "PowerliftingApp",
                           "-destination", f"platform=iOS Simulator,id={selected['udid']}", "-destination-timeout", "60",
                           "-derivedDataPath", str(derived), "-resultBundlePath", str(output / "build.xcresult"),
                           "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                           "CODE_SIGNING_ALLOWED=NO", "build-for-testing"]),
        ("ui-build-bootstatus", ["xcrun", "simctl", "bootstatus", owned["udid"], "-b"]),
        ("ui-build-ready", ["xcrun", "simctl", "list", "--json"]),
    ]

    def validate_ready():
        current = verified_record(owned_file, selected)
        if current != owned:
            raise ValueError("Owned simulator record changed during build")
        devices = identities(log_json(output / "ui-build-ready"))
        runtime, device = devices[owned["udid"]]
        if not same_device(owned, runtime, device) or device.get("state") != "Booted" or device.get("isAvailable") is not True:
            raise ValueError("Fresh inventory has no matching available Booted UI simulator")
        return {"udid": owned["udid"], "identityMatched": True, "bootedObserved": True}

    # Future reservation: 20s minimum bootstatus work + its20s cleanup + final
    # inventory10s work + its20s cleanup. Bootstatus preserves that final30s.
    code = phases_module.execute(plan, output, cancellation, budget=440, clock=clock, runner=runner,
        reserves={"build-compile": 70, "ui-build-bootstatus": 30}, receipt_name="build-phases.json",
        validator=validate_ready, validation_key="uiReadiness")
    if code == 0 and cancellation.signum is None:
        owned.update(bootVerified=True, state="ready")
        save_json(owned_file, owned)
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--derived", type=Path, required=True)
    parser.add_argument("--selected", type=Path, required=True)
    parser.add_argument("--owned-ui", type=Path, required=True)
    args = parser.parse_args()
    selected = json.loads(args.selected.read_text(encoding="utf-8"))
    cancellation = Cancellation()
    with cancellation.handlers():
        return execute_build(selected, args.owned_ui, args.derived, args.output, cancellation)


if __name__ == "__main__":
    raise SystemExit(main())
