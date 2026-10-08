"""Real short processes, including owned grandchildren and signals on POSIX."""
import json
import errno
import importlib.util
import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest
from unittest.mock import patch

SUPERVISOR = Path(__file__).with_name("supervise-process.py")


class SupervisorTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.receipt = self.root / "process.json"
        self.addCleanup(self.preserve_receipt)

    def preserve_receipt(self):
        directory = os.environ.get("SUPERVISOR_TEST_EVIDENCE_DIR")
        if directory and self.receipt.is_file():
            destination = Path(directory) / ("supervisor-" + self._testMethodName + ".process.json")
            destination.write_bytes(self.receipt.read_bytes())

    def preserve_result(self, stdout, stderr, suffix=""):
        directory = os.environ.get("SUPERVISOR_TEST_EVIDENCE_DIR")
        if directory:
            prefix = Path(directory) / ("supervisor-" + self._testMethodName + suffix)
            prefix.with_name(prefix.name + ".stdout.log").write_text(stdout, encoding="utf-8")
            prefix.with_name(prefix.name + ".stderr.log").write_text(stderr, encoding="utf-8")
            if self.receipt.is_file():
                prefix.with_name(prefix.name + ".process.json").write_bytes(self.receipt.read_bytes())

    def command(self, source, timeout=3):
        return [sys.executable, str(SUPERVISOR), "--timeout", str(timeout),
                "--term-grace", "0.3", "--kill-wait", "1",
                "--receipt", str(self.receipt), "--", sys.executable, "-c", source]

    def run_child(self, source, timeout=3):
        result = subprocess.run(self.command(source, timeout), timeout=8,
                                capture_output=True, text=True)
        receipt = json.loads(self.receipt.read_text())
        self.preserve_result(result.stdout, result.stderr)
        details = json.dumps(receipt, sort_keys=True) + "\n" + result.stdout + result.stderr
        # CI failures must retain the actual supervisor error rather than a
        # secondary KeyError or a TemporaryDirectory that disappears at teardown.
        print(f"{self.id()}: {details}", flush=True)
        self.assertEqual(receipt["state"], "finished")
        self.assertEqual(receipt["wrapperExitCode"], result.returncode)
        self.assertTrue(receipt.get("directChildWaitCompleted"), details)
        return result, receipt

    def test_success(self):
        result, receipt = self.run_child("print('child-output', flush=True)")
        self.assertEqual(result.returncode, 0)
        self.assertIn("child-output", result.stdout)
        self.assertEqual(receipt["reason"], "child-exited")
        self.assertTrue(receipt["cleanupComplete"])
        self.assertEqual(receipt["ownership"], "new-posix-process-group" if os.name == "posix" else "direct-child-only")

    def test_nonzero(self):
        result, receipt = self.run_child("raise SystemExit(7)")
        self.assertEqual(result.returncode, 7)
        self.assertEqual(receipt["childReturnCode"], 7)

    def test_timeout(self):
        # Deterministic uncertainty checks supplement the real subprocess check;
        # these injected errno cases do not claim macOS runtime coverage.
        spec = importlib.util.spec_from_file_location("supervisor_probe", SUPERVISOR)
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        evidence = {}
        with patch.object(module.os, "killpg", create=True,
                          side_effect=[PermissionError(errno.EPERM, "probe denied"),
                                       ProcessLookupError(errno.ESRCH, "group gone")]):
            self.assertTrue(module.group_present(123, evidence))
            self.assertFalse(module.group_present(123, evidence))
        self.assertEqual(evidence["groupProbePermissionErrors"], 1)
        with patch.object(module.os, "killpg", create=True,
                          side_effect=PermissionError(errno.EPERM, "still uncertain")):
            self.assertTrue(module.group_present(123, evidence))
            self.assertTrue(module.group_present(123, evidence))
        self.assertEqual(evidence["groupProbePermissionErrors"], 3)
        with patch.object(module.os, "killpg", create=True,
                          side_effect=PermissionError(errno.EACCES, "different error")):
            with self.assertRaises(PermissionError):
                module.group_present(123, evidence)
        result, receipt = self.run_child("import time; time.sleep(30)", timeout=0.4)
        self.assertEqual(result.returncode, 124)
        self.assertEqual(receipt["reason"], "timeout")
        self.assertTrue(receipt["cleanupComplete"])
        self.assertLess(receipt["elapsedSeconds"], 4)

    def test_launch_error(self):
        command = self.command("pass")
        command[-3:] = [str(self.root / "missing-command")]
        result = subprocess.run(command, capture_output=True, text=True, timeout=8)
        self.preserve_result(result.stdout, result.stderr)
        receipt = json.loads(self.receipt.read_text())
        self.assertEqual(result.returncode, 125)
        self.assertEqual(receipt["reason"], "supervisor-error")
        self.assertNotIn("childPID", receipt)

    @unittest.skipUnless(os.name == "posix", "POSIX process-group coverage needs a POSIX host")
    def test_timeout_kills_uncooperative_child(self):
        result, receipt = self.run_child("import signal,time; signal.signal(signal.SIGTERM, signal.SIG_IGN); time.sleep(30)", 0.5)
        self.assertEqual(result.returncode, 124)
        self.assertEqual(receipt["signalsSent"], ["SIGTERM", "SIGKILL"])
        self.assertTrue(receipt["ownedGroupAbsent"])

    @unittest.skipUnless(os.name == "posix", "POSIX signal forwarding needs a POSIX host")
    def test_signal_cancels_and_reaps_child(self):
        for signum in (signal.SIGTERM, signal.SIGINT):
            with self.subTest(signal=signum):
                self.check_signal(signum)

    def check_signal(self, signum):
        self.receipt.unlink(missing_ok=True)
        process = subprocess.Popen(self.command("import time; time.sleep(30)"),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        self.addCleanup(lambda: process.poll() is None and process.kill())
        deadline = time.monotonic() + 3
        while time.monotonic() < deadline:
            if self.receipt.exists() and json.loads(self.receipt.read_text())["state"] == "running":
                break
            time.sleep(0.02)
        else:
            self.fail("Supervisor never recorded its owned child")
        process.send_signal(signum)
        stdout, stderr = process.communicate(timeout=5)
        actual_code = process.returncode
        self.preserve_result(stdout, stderr, "-" + signal.Signals(signum).name)
        receipt = json.loads(self.receipt.read_text())
        print(f"{self.id()} signal={signum}: {json.dumps(receipt, sort_keys=True)}\n{stdout}{stderr}", flush=True)
        self.assertEqual(actual_code, 128 + signum, json.dumps(receipt, sort_keys=True))
        self.assertEqual(receipt["reason"], "cancelled")
        self.assertEqual(receipt["cancellationSignal"], signum)
        self.assertTrue(receipt["ownedGroupAbsent"])
        self.assertTrue(receipt["directChildWaitCompleted"])

    @unittest.skipUnless(os.name == "posix", "Grandchild supervision needs a POSIX host")
    def test_timeout_stops_child_and_grandchild(self):
        heartbeat = self.root / "heartbeat"
        grandchild = "import time,pathlib; p=pathlib.Path(" + repr(str(heartbeat)) + ");\nwhile True:\n p.write_text(str(time.monotonic())); time.sleep(0.02)"
        # Parent reaps its own child when the supervisor signals the group.
        source = ("import subprocess,sys,signal,time\n"
                  f"p=subprocess.Popen([sys.executable,'-c',{grandchild!r}])\n"
                  "def stop(s,f):\n p.wait(timeout=2); raise SystemExit(0)\n"
                  "signal.signal(signal.SIGTERM,stop)\ntime.sleep(30)")
        result, receipt = self.run_child(source, 0.7)
        self.assertEqual(result.returncode, 124)
        self.assertTrue(receipt["ownedGroupAbsent"])
        before = heartbeat.read_text()
        time.sleep(0.1)
        self.assertEqual(heartbeat.read_text(), before)

    @unittest.skipUnless(os.name == "posix", "Group isolation needs a POSIX host")
    def test_timeout_preserves_unrelated_process(self):
        unrelated = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(30)"],
                                     start_new_session=True)
        try:
            result, receipt = self.run_child("import time; time.sleep(30)", 0.4)
            self.assertEqual(result.returncode, 124)
            self.assertTrue(receipt["ownedGroupAbsent"])
            self.assertIsNone(unrelated.poll())
        finally:
            unrelated.terminate()
            unrelated.wait(timeout=3)

    @unittest.skipUnless(os.name == "posix", "Orphan group observation needs a POSIX host")
    def test_normal_child_exit_stops_remaining_descendant(self):
        heartbeat = self.root / "orphan-heartbeat"
        grandchild = "import time,pathlib; p=pathlib.Path(" + repr(str(heartbeat)) + ");\nwhile True:\n p.write_text(str(time.monotonic())); time.sleep(0.02)"
        source = ("import subprocess,sys,pathlib,time\n"
                  f"subprocess.Popen([sys.executable,'-c',{grandchild!r}])\n"
                  f"p=pathlib.Path({str(heartbeat)!r})\n"
                  "deadline=time.monotonic()+2\n"
                  "while not p.exists() and time.monotonic()<deadline: time.sleep(0.02)\n"
                  "raise SystemExit(0)")
        result, receipt = self.run_child(source)
        self.assertEqual(receipt["reason"], "child-exited")
        self.assertEqual(receipt["childReturnCode"], 0)
        self.assertIn("SIGTERM", receipt["signalsSent"])
        # Orphan reaping belongs to the OS: a lingering zombie is conservatively
        # reported as incomplete rather than claimed absent or waited as a child.
        self.assertEqual(result.returncode, 0 if receipt["ownedGroupAbsent"] else 125)
        self.assertEqual(receipt["cleanupComplete"], receipt["ownedGroupAbsent"])
        before = heartbeat.read_text()
        time.sleep(0.1)
        self.assertEqual(heartbeat.read_text(), before)


if __name__ == "__main__":
    unittest.main()
