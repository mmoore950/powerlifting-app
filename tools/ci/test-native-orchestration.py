"""Budget/cancellation/identity regressions; simctl is injected, never run here."""
import importlib.util
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch
import ci_process

from ci_process import Cancellation, run_supervised, save_json
from owned_ui_simulator import operation, verified_record

spec = importlib.util.spec_from_file_location("test_phases", Path(__file__).with_name("native-test-phases.py"))
phases_module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(phases_module)
inventory_spec = importlib.util.spec_from_file_location("test_inventory", Path(__file__).with_name("check-test-inventory.py"))
inventory_module = importlib.util.module_from_spec(inventory_spec)
inventory_spec.loader.exec_module(inventory_module)
build_spec = importlib.util.spec_from_file_location("build_phase", Path(__file__).with_name("native-build-phase.py"))
build_module = importlib.util.module_from_spec(build_spec)
build_spec.loader.exec_module(build_module)
SHARED = "11111111-1111-4111-8111-111111111111"
FRESH = "22222222-2222-4222-8222-222222222222"
RUNTIME = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
TYPE = "com.apple.CoreSimulator.SimDeviceType.iPhone-16"


def preserve(root, test_name):
    directory = os.environ.get("ORCHESTRATION_TEST_EVIDENCE_DIR")
    if directory:
        for path in root.iterdir():
            if path.is_file() and not path.is_symlink() and path.stat().st_size <= 4 * 1024 * 1024 and path.name.endswith((".json", ".log", ".exit-code")):
                (Path(directory) / ("orchestration-" + test_name + "-" + path.name)).write_bytes(path.read_bytes())


class Clock:
    def __init__(self): self.now = 10
    def __call__(self): return self.now


class NativeOrchestrationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(preserve, self.root, self._testMethodName)
        self.plan = phases_module.phases(SHARED, FRESH, self.root / "derived", self.root)
        self.clock = Clock()
        self.cancel = Cancellation()

    def evidence(self): return json.loads((self.root / "test-phases.json").read_text())

    def test_shared_remaining_budget_and_complete_target_selection(self):
        calls = []
        def runner(command, timeout, prefix, cancellation):
            calls.append((command, timeout, prefix.name))
            self.clock.now += 20 if len(calls) == 1 else 50
            return {"exitCode": 0, "launched": True}
        self.assertEqual(phases_module.execute(self.plan, self.root, self.cancel, budget=100, clock=self.clock, runner=runner), 0)
        self.assertEqual([x[1] for x in calls], [80, 60])
        self.assertIn("-only-testing:PowerliftingAppUITests", calls[0][0])
        self.assertIn("-skip-testing:PowerliftingAppUITests", calls[1][0])
        self.assertIn(f"platform=iOS Simulator,id={FRESH}", calls[0][0])
        self.assertIn(f"platform=iOS Simulator,id={FRESH}", calls[1][0])
        self.assertIn(str(self.root / "test-ui.xcresult"), calls[0][0])
        self.assertIn(str(self.root / "test-unit.xcresult"), calls[1][0])
        self.assertEqual(self.evidence()["elapsedSeconds"], 70)
        self.assertEqual((self.root / "test-unit.exit-code").read_text(), "0\n")

        def cancelled_validator():
            self.cancel.request(signal.SIGTERM)
            return {"verified": True}
        self.assertEqual(phases_module.execute(self.plan, self.root, self.cancel, clock=self.clock, runner=runner,
                                              validator=cancelled_validator), 143)
        self.assertEqual(self.evidence()["aggregateExitCode"], 143)
        with self.assertRaises(ValueError): phases_module.phases(SHARED, SHARED, self.root, self.root)

    def test_budget_exhaustion_does_not_launch_second_child(self):
        calls = []
        def runner(*args):
            calls.append(args); self.clock.now += 91
            return {"exitCode": 0, "launched": True}
        self.assertEqual(phases_module.execute(self.plan, self.root, self.cancel, budget=100, clock=self.clock, runner=runner), 124)
        self.assertEqual(len(calls), 1)
        self.assertFalse(self.evidence()["phases"][1]["launched"])
        self.assertEqual(self.evidence()["phases"][1]["reason"], "shared-deadline-exhausted")

    def test_cancellation_during_first_child_blocks_second(self):
        calls = []
        def runner(command, timeout, prefix, cancellation):
            calls.append(command); cancellation.request(signal.SIGTERM); self.clock.now += 1
            return {"exitCode": 0, "launched": True}
        self.assertEqual(phases_module.execute(self.plan, self.root, self.cancel, budget=100, clock=self.clock, runner=runner), 143)
        self.assertEqual(len(calls), 1)
        self.assertFalse(self.evidence()["phases"][1]["launched"])
        self.assertEqual(self.evidence()["cancellationSignal"], signal.SIGTERM)

    def test_failure_and_prelaunch_cancellation_keep_partial_evidence(self):
        def runner(*args): return {"exitCode": 7, "launched": True, "receipt": "first.process.json"}
        self.assertEqual(phases_module.execute(self.plan, self.root, self.cancel, clock=self.clock, runner=runner), 7)
        self.assertFalse(self.evidence()["phases"][1]["launched"])
        self.cancel.request(signal.SIGINT)
        def unexpected(*args): self.fail("Cancelled operation launched a child")
        self.assertEqual(phases_module.execute(self.plan, self.root, self.cancel, clock=self.clock, runner=unexpected), 130)
        self.assertTrue(all(p["launched"] is False for p in self.evidence()["phases"]))

    def test_real_supervisor_preserves_process_receipt_and_stdout(self):
        result = run_supervised([sys.executable, "-c", "print('owned-child-output');raise SystemExit(7)"], 2, self.root / "real", self.cancel)
        self.assertEqual(result["exitCode"], 7)
        self.assertTrue(result["supervisor"]["cleanupComplete"])
        self.assertIn("owned-child-output", (self.root / "real.log").read_text())

    def test_actual_periodic_atomic_receipts_preserve_live_progress_then_final_result(self):
        script = ("import sys; from pathlib import Path; from ci_process import Cancellation,run_supervised; "
                  f"result=run_supervised([sys.executable,'-c','import time; time.sleep(8)'],12,Path({str(self.root / 'progress')!r}),Cancellation()); "
                  "raise SystemExit(result['exitCode'])")
        parent = subprocess.Popen([sys.executable, "-c", script], cwd=Path(__file__).parent, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
        samples = None
        try:
            deadline = time.monotonic() + 10
            while time.monotonic() < deadline and parent.poll() is None:
                try:
                    outer = json.loads((self.root / "progress.outer.json").read_text())
                    supervisor = json.loads((self.root / "progress.process.json").read_text())
                    if (outer["state"] == supervisor["state"] == "running"
                            and outer["elapsedSeconds"] >= 5 and supervisor["elapsedSeconds"] >= 5):
                        samples = [outer, supervisor]; break
                except (OSError, json.JSONDecodeError):
                    pass
                time.sleep(.05)
            self.assertIsNotNone(samples, "No actual periodic live receipt pair was observed")
            save_json(self.root / "progress-live.json", {"outer":samples[0],"supervisor":samples[1]},maximum_bytes=2*1024*1024)
            for sample in samples:
                self.assertGreaterEqual(sample["progressSequence"], 3)
                self.assertGreaterEqual(sample["resources"]["processCPUSeconds"], 0)
                self.assertIn("self-process-only", sample["resources"]["scope"])
                self.assertAlmostEqual(sample["deadlineMonotonic"]-sample["observedMonotonic"], sample["remainingSeconds"], places=5)
                self.assertEqual(sample["operation"], "poll-supervisor" if "supervisorPID" in sample else "poll-direct-child")
            self.assertIsNone(samples[0]["supervisorReturnCode"]); self.assertIsNone(samples[1]["childReturnCode"])
            stdout, stderr = parent.communicate(timeout=12)
            self.assertEqual(parent.returncode, 0, stderr)
            for name, bound in [("progress.outer.json",8192),("progress.process.json",1024*1024)]:
                filename=self.root/name; final=json.loads(filename.read_text())
                self.assertEqual(final["state"],"finished");self.assertLessEqual(filename.stat().st_size,bound)
                self.assertGreater(final["progressSequence"],samples[0 if '.outer.' in name else 1]["progressSequence"])
            self.assertEqual(json.loads((self.root/"progress.outer.json").read_text())["reportedExitCode"],0)
            self.assertFalse(any(p.name.endswith('.tmp') for p in self.root.iterdir()))
        finally:
            if parent.poll() is None: parent.kill(); parent.wait(timeout=2)

    def test_diagnostic_file_bound_refuses_without_replacing_previous_receipt(self):
        filename=self.root/'bounded.json';save_json(filename,{'before':True})
        before=filename.read_bytes()
        with self.assertRaisesRegex(ValueError,'fixed file bound'):
            save_json(filename,{'oversized':'x'*8192},maximum_bytes=8192)
        self.assertEqual(filename.read_bytes(),before);self.assertFalse(filename.with_name(filename.name+'.tmp').exists())

    def test_progress_write_failure_keeps_supervisor_observation_and_reap_then_fails(self):
        saved = ci_process.save_json; failed = False
        def save(path, value, **kwargs):
            nonlocal failed
            if path.name.endswith('.outer.json') and value['state']=='running' and not failed:
                failed=True;raise OSError('Injected diagnostic I/O failure after launch')
            return saved(path,value,**kwargs)
        with patch.object(ci_process,'save_json',side_effect=save):
            result=run_supervised([sys.executable,'-c','print("child completed despite progress error")'],2,self.root/'write-failure',self.cancel)
        self.assertTrue(failed);self.assertEqual(result['exitCode'],125)
        self.assertEqual(result['reason'],'outer-progress-evidence-unverified')
        self.assertTrue(result['supervisor']['directChildWaitCompleted']);self.assertTrue(result['supervisor']['cleanupComplete'])
        self.assertEqual(result['supervisor']['childReturnCode'],0)
        self.assertIn('child completed despite progress error',(self.root/'write-failure.log').read_text())
        outer=json.loads((self.root/'write-failure.outer.json').read_text())
        self.assertEqual(outer['state'],'finished');self.assertEqual(outer['reportedExitCode'],125)
        self.assertIn('Injected diagnostic I/O failure',outer['progressWriteError'])

    def test_inventory_failure_propagates_after_both_process_successes(self):
        calls = []
        def runner(command, *args): calls.append(command); return {"exitCode": 0, "launched": True}
        def validator():
            self.assertEqual(len(calls), 2)
            raise ValueError("Missing method in split results")
        code = phases_module.execute(self.plan, self.root, self.cancel, clock=self.clock, runner=runner, validator=validator)
        self.assertEqual(code, 125)
        self.assertEqual(self.evidence()["aggregateExitCode"], 125)
        self.assertIn("Missing method", self.evidence()["error"])
        self.assertEqual((self.root / "test-unit.exit-code").read_text(), "0\n")

    @unittest.skipUnless(os.name == "posix", "Actual signal/group propagation requires POSIX")
    def test_actual_orchestrator_cancellation_reaches_supervised_owned_group(self):
        module_root = str(Path(__file__).resolve().parent)
        ready = self.root / "ready"
        program = (f"import sys;sys.path.insert(0,{module_root!r});from pathlib import Path;"
                   "from ci_process import Cancellation,run_supervised;"
                   "c=Cancellation();ctx=c.handlers();ctx.__enter__();"
                   f"r=run_supervised([sys.executable,'-c',\"import pathlib,time;pathlib.Path({str(ready)!r}).write_text('ready');time.sleep(30)\"],"
                   f"20,Path({str(self.root)!r})/'cancel',c);ctx.__exit__(None,None,None);raise SystemExit(r['exitCode'])")
        child = subprocess.Popen([sys.executable, "-c", program], stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            deadline = time.monotonic() + 5
            while not ready.exists():
                if child.poll() is not None or time.monotonic() > deadline: self.fail("Owned child never became ready")
                time.sleep(0.02)
            child.send_signal(signal.SIGTERM)
            stdout, _ = child.communicate(timeout=20)
            self.assertEqual(child.returncode, 143, stdout)
            receipt = json.loads((self.root / "cancel.process.json").read_text())
            self.assertEqual(receipt["cancellationSignal"], signal.SIGTERM)
            self.assertTrue(receipt["cleanupComplete"]); self.assertTrue(receipt["ownedGroupAbsent"])
            self.assertTrue(receipt["directChildWaitCompleted"])
        finally:
            if child.poll() is None: child.kill(); child.wait(timeout=2)


class InventoryTests(unittest.TestCase):
    def test_union_rejects_missing_duplicate_skip_and_wrong_target_phase(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            output = root / "logs"; output.mkdir()
            sources = [("Packages/LiftingCore/Tests/LiftingCoreTests", "CoreCase", "core"),
                       ("Tests/App", "AppCase", "app"), ("Tests/UI", "UICase", "ui")]
            for directory, classname, name in sources:
                folder = root / directory; folder.mkdir(parents=True)
                (folder / (classname + ".swift")).write_text(f"final class {classname}: XCTestCase {{ func test_{name}() {{}} }}")
            http = root / sources[0][0] / "OPLHTTPContractTests.swift"
            http.write_text("#if os(macOS)\nfinal class HTTPCase: XCTestCase { func testHttp() {} }\n#endif")
            ui = "Test Case '-[PowerliftingAppUITests.UICase test_ui]' passed (0.1 seconds).\n"
            unit = ("Test Case '-[LiftingCoreTests.CoreCase test_core]' passed (0.1 seconds).\n"
                    "Test Case '-[PowerliftingAppTests.AppCase test_app]' passed (0.1 seconds).\n")
            ui_log, unit_log = output / "test-ui.log", output / "test-unit.log"
            ui_log.write_text(ui); unit_log.write_text(unit)
            self.assertEqual(inventory_module.verify(root, output)["passedExactlyOnce"], 3)
            # New source methods automatically become required, without a frozen count.
            additional = root / "Tests/App/Added.swift"
            additional.write_text("final class Added: XCTestCase { func testAdded() {} }")
            with self.assertRaisesRegex(ValueError, "missing"): inventory_module.verify(root, output)
            additional.unlink()
            for malformed in [unit + unit.splitlines()[0] + "\n", unit.replace("test_app]' passed", "test_app]' skipped"), unit.splitlines()[0] + "\n"]:
                unit_log.write_text(malformed)
                with self.assertRaises(ValueError): inventory_module.verify(root, output)
            unit_log.write_text(unit + ui)
            with self.assertRaisesRegex(ValueError, "wrong split"): inventory_module.verify(root, output)


class SimulatorOwnershipTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.addCleanup(preserve, self.root, self._testMethodName)
        self.environment = patch.dict(os.environ, GITHUB_RUN_ID="123", GITHUB_RUN_ATTEMPT="1")
        self.environment.start(); self.addCleanup(self.environment.stop)
        self.selected = {"udid": SHARED, "runtime": RUNTIME}
        self.devices = {SHARED: {"udid": SHARED, "name": "iPhone 16", "deviceTypeIdentifier": TYPE, "isAvailable": True, "state": "Shutdown"}}
        self.calls = []; self.create_id = FRESH; self.delete_effective = True

    def inventory(self):
        return {"devices": {RUNTIME: list(self.devices.values())},
                "runtimes": [{"identifier": RUNTIME, "isAvailable": True}], "devicetypes": [{"identifier": TYPE}]}

    def runner(self, command, timeout, prefix, cancellation):
        self.calls.append(command)
        self.assertGreater(timeout, 0)
        action = command[2]
        if action == "help": text = "Injected simctl help"
        elif action == "create":
            if self.create_id not in self.devices:
                self.devices[self.create_id] = {"udid": self.create_id, "name": command[3], "deviceTypeIdentifier": TYPE, "isAvailable": True, "state": "Shutdown"}
            text = self.create_id
        elif action == "list": text = json.dumps(self.inventory())
        else:
            self.assertEqual(command[3], FRESH, "Action targeted a preexisting simulator")
            if action == "boot": self.devices[FRESH]["state"] = "Booted"
            if action == "shutdown": self.devices[FRESH]["state"] = "Shutdown"
            if action == "delete" and self.delete_effective: del self.devices[FRESH]
            text = ""
        prefix.with_name(prefix.name + ".log").write_text(text + "\nSupervisor: child-exited; exit=0\n")
        return {"exitCode": 0, "launched": True}

    def create(self):
        return operation("create", self.root, self.selected, self.inventory(), Cancellation(), runner=self.runner)

    def cleanup(self):
        return operation("cleanup", self.root, self.selected, None, Cancellation(), runner=self.runner)

    def test_fresh_creation_stays_unbooted_and_owned_only_cleanup(self):
        self.assertEqual(self.create(), 0)
        record = verified_record(self.root / "owned-ui-simulator.json", self.selected)
        self.assertFalse(record["bootRequested"]); self.assertFalse(record["bootVerified"]); self.assertNotEqual(record["udid"], SHARED)
        self.assertEqual(record["state"], "created"); self.assertEqual(self.devices[FRESH]["state"], "Shutdown")
        self.assertFalse(any(c[2] in ["boot", "bootstatus"] for c in self.calls if c[0] == "xcrun"))
        self.assertEqual(self.cleanup(), 0)
        self.assertIn(SHARED, self.devices); self.assertNotIn(FRESH, self.devices)
        receipt = json.loads((self.root / "owned-ui-cleanup.json").read_text())
        self.assertTrue(receipt["cleanupComplete"]); self.assertTrue(receipt["ownedDeviceAbsent"])

    def test_creation_returning_preexisting_uuid_never_boots_or_deletes_it(self):
        self.create_id = SHARED
        self.assertEqual(self.create(), 125)
        self.assertEqual(self.cleanup(), 125)
        self.assertFalse(any(c[2] in ["boot", "shutdown", "delete"] for c in self.calls))
        self.assertIn(SHARED, self.devices)

    def test_empty_malformed_and_preexisting_records_refuse_all_commands(self):
        self.assertEqual(self.create(), 0)
        path = self.root / "owned-ui-simulator.json"; original = json.loads(path.read_text())
        for value in ["", "not-a-uuid", SHARED]:
            with self.subTest(value=value):
                save_json(path, {**original, "udid": value}); self.calls.clear()
                self.assertEqual(self.cleanup(), 125); self.assertEqual(self.calls, [])
                self.assertIn(SHARED, self.devices); self.assertIn(FRESH, self.devices)

    def test_changed_device_identity_refuses_shutdown_delete(self):
        self.assertEqual(self.create(), 0)
        self.devices[FRESH]["name"] = "Another owner"; self.calls.clear()
        self.assertEqual(self.cleanup(), 125)
        self.assertEqual([c[2] for c in self.calls], ["list"])
        self.assertIn(FRESH, self.devices)

    def test_delete_success_without_absence_is_not_cleanup_success(self):
        self.assertEqual(self.create(), 0); self.delete_effective = False
        self.assertEqual(self.cleanup(), 125)
        self.assertFalse(json.loads((self.root / "owned-ui-cleanup.json").read_text())["cleanupComplete"])
        self.assertIn(FRESH, self.devices)

    def test_no_record_is_noop_and_creation_cancellation_never_launches(self):
        self.assertEqual(self.cleanup(), 0); self.assertEqual(self.calls, [])
        cancelled = Cancellation(); cancelled.request(signal.SIGINT)
        self.assertEqual(operation("create", self.root, self.selected, self.inventory(), cancelled, runner=self.runner), 125)
        self.assertEqual(self.calls, []); self.assertEqual(set(self.devices), {SHARED})

    def build(self, runner, clock, cancellation=None):
        return build_module.execute_build(self.selected, self.root / "owned-ui-simulator.json", self.root / "derived",
                                          self.root, cancellation or Cancellation(), clock=clock, runner=runner)

    def prepare_ready_for_tests(self):
        self.assertEqual(self.create(), 0)
        owned_file = self.root / "owned-ui-simulator.json"
        record = json.loads(owned_file.read_text())
        record.update(bootRequested=True, bootVerified=True, state="ready")
        save_json(owned_file, record); self.devices[FRESH]["state"] = "Booted"; self.calls.clear()
        return owned_file

    def test_same_owned_device_avoids_inventory_and_preserves_budget_and_results(self):
        owned = self.prepare_ready_for_tests(); clock = Clock(); calls = []
        def runner(command, timeout, prefix, cancel):
            calls.append((prefix.name, timeout, command))
            self.assertEqual(command[0], "xcodebuild")
            clock.now += {"test-ui": 380, "test-unit": 100}[prefix.name]
            return {"exitCode": 0, "launched": True}
        validated = []
        code = phases_module.execute_tests(self.selected, owned, self.root / "derived", self.root, Cancellation(),
            runner=runner, clock=clock, validator=lambda: validated.append(True))
        self.assertEqual(code, 0); self.assertEqual(validated, [True])
        self.assertEqual([(n,t) for n,t,_ in calls], [("test-ui",420),("test-unit",160)])
        for index in [0,1]: self.assertIn(f"platform=iOS Simulator,id={FRESH}", calls[index][2])
        self.assertIn(str(self.root / "test-ui.xcresult"), calls[0][2])
        self.assertIn(str(self.root / "test-unit.xcresult"), calls[1][2])
        self.assertIn("-only-testing:PowerliftingAppUITests", calls[0][2])
        self.assertIn("-skip-testing:PowerliftingAppUITests", calls[1][2])
        receipt = json.loads((self.root / "test-phases.json").read_text())
        self.assertEqual(receipt["elapsedSeconds"],480); self.assertEqual(receipt["budgetSeconds"],560)
        self.assertEqual(verified_record(owned,self.selected)["selectedUDID"],SHARED)

    def test_changed_owned_record_after_ui_refuses_unit(self):
        owned = self.prepare_ready_for_tests(); original=json.loads(owned.read_text()); calls=[]
        def runner(command, timeout, prefix, cancel):
            calls.append(prefix.name)
            save_json(owned,{**original,"bootVerified":False})
            return {"exitCode":0,"launched":True}
        self.assertEqual(phases_module.execute_tests(self.selected,owned,self.root/"derived",self.root,Cancellation(),
            runner=runner,clock=Clock()),125)
        self.assertEqual(calls,["test-ui"])
        with self.assertRaises(ValueError):
            phases_module.execute_tests(self.selected,owned,self.root,self.root,Cancellation(),runner=runner)
        save_json(owned,{**original,"udid":SHARED})
        with self.assertRaises(ValueError):
            phases_module.execute_tests(self.selected,owned,self.root,self.root,Cancellation(),runner=runner)

    def test_ui_failure_cancellation_or_deadline_never_launches_unit(self):
        owned=self.prepare_ready_for_tests()
        for condition in ["failure","cancelled","deadline"]:
            clock=Clock(); cancel=Cancellation(); calls=[]
            def runner(command,timeout,prefix,cancellation):
                calls.append(prefix.name)
                if condition=="cancelled": cancel.request(signal.SIGTERM)
                if condition=="deadline": clock.now+=561
                return {"exitCode":65 if condition=="failure" else 0,"launched":True}
            code=phases_module.execute_tests(self.selected,owned,self.root/"derived",self.root,cancel,runner=runner,clock=clock)
            self.assertEqual(code,{"failure":65,"cancelled":143,"deadline":124}[condition])
            self.assertEqual(calls,["test-ui"])
            receipt=json.loads((self.root/"test-phases.json").read_text())
            self.assertFalse(receipt["phases"][1]["launched"])

    def test_ownership_prelaunch_validation_cannot_use_stale_budget_or_cancelled_allowance(self):
        plan=phases_module.phases(SHARED,FRESH,self.root,self.root)
        for condition in ['cancelled','deadline']:
            clock=Clock();cancel=Cancellation();calls=[]
            def before(name):
                if condition=='cancelled':cancel.request(signal.SIGTERM)
                else:clock.now+=561
            def unexpected(*args):calls.append(args);self.fail('Stale prelaunch allowance launched a child')
            code=phases_module.execute(plan,self.root,cancel,clock=clock,runner=unexpected,before_phase=before)
            self.assertEqual(code,143 if condition=='cancelled' else 124);self.assertEqual(calls,[])

    def test_build_then_readiness_shares_440_seconds_and_preserves_future_cleanup(self):
        self.assertEqual(self.create(), 0); self.calls.clear(); clock = Clock(); budgets = []
        def runner(command, timeout, prefix, cancellation):
            budgets.append((prefix.name, timeout)); clock.now += {"build-compile": 100, "ui-build-boot": 5, "ui-build-bootstatus": 200, "ui-build-ready": 5}[prefix.name]
            if command[0] == "xcodebuild":
                self.calls.append(command); return {"exitCode": 0, "launched": True}
            return self.runner(command, timeout, prefix, cancellation)
        self.assertEqual(self.build(runner, clock), 0)
        self.assertEqual(budgets, [("build-compile", 320), ("ui-build-boot", 10), ("ui-build-bootstatus", 285), ("ui-build-ready", 115)])
        self.assertEqual(self.calls[0][0], "xcodebuild"); self.assertEqual([c[2] for c in self.calls[1:]], ["boot", "bootstatus", "list"])
        self.assertIn(f"platform=iOS Simulator,id={SHARED}", self.calls[0]); self.assertEqual(self.calls[1][3], FRESH)
        self.assertTrue(verified_record(self.root / "owned-ui-simulator.json", self.selected)["bootVerified"])
        receipt = json.loads((self.root / "build-phases.json").read_text())
        self.assertEqual(receipt["budgetSeconds"], 440); self.assertEqual(receipt["elapsedSeconds"], 310)
        self.assertTrue(receipt["uiReadiness"]["bootedObserved"])

    def test_build_failure_exhaustion_and_cancellation_keep_readiness_unrun(self):
        self.assertEqual(self.create(), 0)
        for condition, expected in [("failure", 7), ("exhausted", 124), ("cancelled", 143)]:
            with self.subTest(condition=condition):
                calls = []; clock = Clock(); cancellation = Cancellation()
                def runner(command, timeout, prefix, cancel):
                    calls.append(command)
                    if condition == "exhausted": clock.now += 391
                    if condition == "cancelled": cancel.request(signal.SIGTERM)
                    return {"exitCode": 7 if condition == "failure" else 0, "launched": True}
                self.assertEqual(self.build(runner, clock, cancellation), expected); self.assertEqual(len(calls), 1)
                receipt = json.loads((self.root / "build-phases.json").read_text())
                self.assertTrue(all(p["launched"] is False for p in receipt["phases"][1:]))
                self.assertFalse(verified_record(self.root / "owned-ui-simulator.json", self.selected)["bootVerified"])

    def test_failed_bootstatus_or_nonbooted_inventory_never_marks_ready(self):
        self.assertEqual(self.create(), 0)
        owned = self.root / "owned-ui-simulator.json"; original = json.loads(owned.read_text())
        for condition, expected in [("timeout", 124), ("nonbooted", 125)]:
            with self.subTest(condition=condition):
                save_json(owned, original); self.devices[FRESH]["state"] = "Shutdown"; self.calls.clear(); clock = Clock()
                def runner(command, timeout, prefix, cancellation):
                    clock.now += 1
                    if command[0] == "xcodebuild": return {"exitCode": 0, "launched": True}
                    if command[2] == "bootstatus" and condition == "timeout": return {"exitCode": 124, "launched": True}
                    if prefix.name == "ui-build-ready": self.devices[FRESH]["state"] = "Shutdown"
                    return self.runner(command, timeout, prefix, cancellation)
                self.assertEqual(self.build(runner, clock), expected)
                self.assertFalse(verified_record(self.root / "owned-ui-simulator.json", self.selected)["bootVerified"])

    def test_owned_record_changed_during_build_refuses_ready(self):
        self.assertEqual(self.create(), 0); owned = self.root / "owned-ui-simulator.json"
        def runner(command, timeout, prefix, cancellation):
            if command[0] == "xcodebuild":
                record = json.loads(owned.read_text()); record["name"] = "Another owner"; save_json(owned, record)
                return {"exitCode": 0, "launched": True}
            return self.runner(command, timeout, prefix, cancellation)
        self.assertEqual(self.build(runner, Clock()), 125)
        self.assertFalse(json.loads(owned.read_text())["bootVerified"])

    def test_build_refuses_reused_boot_request_before_any_child(self):
        self.assertEqual(self.create(), 0); owned = self.root / "owned-ui-simulator.json"
        record = json.loads(owned.read_text()); record["bootRequested"] = True; save_json(owned, record); self.calls.clear()
        with self.assertRaisesRegex(ValueError, "created, unbooted"): self.build(self.runner, Clock())
        self.assertEqual(self.calls, [])

    def test_failed_or_cancelled_boot_request_never_launches_readiness(self):
        self.assertEqual(self.create(), 0); owned = self.root / "owned-ui-simulator.json"; original = json.loads(owned.read_text())
        for condition, expected in [("failure", 124), ("cancelled", 143)]:
            save_json(owned, original); calls = []; cancel = Cancellation(); clock = Clock()
            def runner(command, timeout, prefix, cancellation):
                calls.append(prefix.name); clock.now += 1
                if prefix.name == "ui-build-boot":
                    self.assertEqual(timeout, 10)
                    if condition == "cancelled": cancellation.request(signal.SIGTERM)
                    return {"exitCode": 124 if condition == "failure" else 0, "launched": True}
                return {"exitCode": 0, "launched": True}
            self.assertEqual(self.build(runner, clock, cancel), expected)
            self.assertEqual(calls, ["build-compile", "ui-build-boot"])
            record = json.loads(owned.read_text()); self.assertFalse(record["bootVerified"]); self.assertFalse(record["bootRequested"])
            receipt = json.loads((self.root / "build-phases.json").read_text())
            self.assertTrue(all(p["launched"] is False for p in receipt["phases"][2:]))

    def test_creation_with_unexpected_booted_inventory_refuses_ready(self):
        def runner(command, timeout, prefix, cancellation):
            if command[2] == "list": self.devices[FRESH]["state"] = "Booted"
            return self.runner(command, timeout, prefix, cancellation)
        self.assertEqual(operation("create", self.root, self.selected, self.inventory(), Cancellation(), runner=runner), 125)
        record = json.loads((self.root / "owned-ui-simulator.json").read_text())
        self.assertFalse(record["createdValidated"]); self.assertFalse(record["bootRequested"])
        self.assertFalse(any(c[2] == "boot" for c in self.calls))


if __name__ == "__main__":
    unittest.main()
