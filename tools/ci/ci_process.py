"""Execute the existing owned-process supervisor with bounded outer observation."""
from contextlib import contextmanager
import json
import os
from pathlib import Path
import signal
import subprocess
import sys
import time

CLEANUP_RESERVE = 20.0  # 15s supervisor cleanup, outer observation/reap margin.


class Cancellation:
    def __init__(self):
        self.signum = None

    def request(self, signum, _frame=None):
        if self.signum is None:
            self.signum = signum

    @contextmanager
    def handlers(self):
        previous = {s: signal.signal(s, self.request) for s in (signal.SIGINT, signal.SIGTERM)}
        try:
            yield self
        finally:
            for s, handler in previous.items():
                signal.signal(s, handler)


def save_json(path, value):
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2) + "\n", encoding="utf-8")
    os.replace(temporary, path)


def run_supervised(command, timeout, prefix, cancellation):
    """Cancellation signals the supervisor, which signals/reaps its owned group.

    If that supervisor itself stalls, stop only its owned wrapper group and fail
    with unknown child cleanup. Never claim simulator/escaped-service ownership.
    """
    prefix = Path(prefix)
    receipt = prefix.with_name(prefix.name + ".process.json")
    log = prefix.with_name(prefix.name + ".log")
    if cancellation.signum is not None:
        return {"exitCode": 128 + cancellation.signum, "reason": "cancelled-before-launch", "launched": False}
    if timeout <= 0:
        return {"exitCode": 124, "reason": "no-budget", "launched": False}
    argv = [sys.executable, str(Path(__file__).with_name("supervise-process.py")),
            "--timeout", str(timeout), "--term-grace", "5", "--kill-wait", "5",
            "--receipt", str(receipt), "--", *command]
    outer_deadline = time.monotonic() + timeout + 17
    sent = None
    timed_out = False
    with log.open("x", encoding="utf-8") as stream:
        child = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT,
                                 start_new_session=os.name == "posix")
        while child.poll() is None:
            if cancellation.signum is not None and sent is None:
                try:
                    child.send_signal(cancellation.signum)
                except ProcessLookupError:
                    pass
                sent = cancellation.signum
                outer_deadline = min(outer_deadline, time.monotonic() + 17)
            if time.monotonic() >= outer_deadline:
                timed_out = True
                # The supervisor's separate child session is NOT included here.
                # Its cleanup is unknown unless a completed receipt proves it.
                try:
                    if os.name == "posix":
                        os.killpg(child.pid, signal.SIGKILL)
                    else:
                        child.kill()
                except ProcessLookupError:
                    pass
                break
            time.sleep(0.05)
        try:
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            timed_out = True
    result = {"launched": True, "exitCode": child.returncode if child.returncode is not None else 125,
              "wrapperPID": child.pid, "forwardedCancellationSignal": sent,
              "outerObservationTimedOut": timed_out, "log": log.name, "receipt": receipt.name}
    try:
        if receipt.stat().st_size > 1024 * 1024:
            raise ValueError("Supervisor receipt exceeds bound")
        evidence = json.loads(receipt.read_text(encoding="utf-8"))
        result["supervisor"] = evidence
        complete = (evidence.get("state") == "finished" and evidence.get("cleanupComplete") is True
                    and evidence.get("directChildWaitCompleted") is True
                    and (os.name != "posix" or evidence.get("ownedGroupAbsent") is True)
                    and evidence.get("wrapperExitCode") == child.returncode)
        if child.returncode == 0:
            complete = complete and evidence.get("childReturnCode") == 0
        if not complete or timed_out:
            result.update(exitCode=125, reason="supervisor-cleanup-unverified")
    except (OSError, ValueError) as error:
        result.update(exitCode=125, reason="supervisor-receipt-unverified", error=str(error))
    if cancellation.signum is not None and result["exitCode"] != 125:
        result["exitCode"] = 128 + cancellation.signum
    return result
