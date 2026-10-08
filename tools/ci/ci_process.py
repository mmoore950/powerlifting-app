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
PROGRESS_INTERVAL = 5.0


def process_observations():
    """Cheap measurements of this process; no diagnostic child or OS-service query."""
    result = {"scope": "self-process-only; not command/tree/service totals", "processCPUSeconds": time.process_time()}
    if os.name == "posix":
        import resource
        try:
            usage = resource.getrusage(resource.RUSAGE_SELF)
            result.update(selfUserCPUSeconds=usage.ru_utime, selfSystemCPUSeconds=usage.ru_stime,
                          selfPeakRSSBytes=usage.ru_maxrss * (1 if sys.platform == "darwin" else 1024))
        except OSError as error:
            result["resourceObservationError"] = str(error)[:256]
    return result


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


def save_json(path, value, *, maximum_bytes=None):
    payload = (json.dumps(value, indent=2) + "\n").encode("utf-8")
    if maximum_bytes is not None and len(payload) > maximum_bytes:
        raise ValueError("Diagnostic receipt exceeds fixed file bound")
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_bytes(payload)
    os.replace(temporary, path)


def run_supervised(command, timeout, prefix, cancellation):
    """Cancellation signals the supervisor, which signals/reaps its owned group.

    If that supervisor itself stalls, stop only its owned wrapper group and fail
    with unknown child cleanup. Never claim simulator/escaped-service ownership.
    """
    prefix = Path(prefix)
    receipt = prefix.with_name(prefix.name + ".process.json")
    log = prefix.with_name(prefix.name + ".log")
    outer_receipt = prefix.with_name(prefix.name + ".outer.json")
    if cancellation.signum is not None:
        return {"exitCode": 128 + cancellation.signum, "reason": "cancelled-before-launch", "launched": False}
    if timeout <= 0:
        return {"exitCode": 124, "reason": "no-budget", "launched": False}
    argv = [sys.executable, str(Path(__file__).with_name("supervise-process.py")),
            "--timeout", str(timeout), "--term-grace", "5", "--kill-wait", "5",
            "--receipt", str(receipt), "--", *command]
    started = time.monotonic()
    outer_deadline = started + timeout + 17
    sent = None
    timed_out = False
    progress = {"schemaVersion": 1, "state": "starting", "supervisorPID": None,
                "supervisorReturnCode": None, "progressSequence": 0,
                "ownership": "wrapper-group-only; separate command group is not owned here"}
    next_progress = started

    def save_progress(operation, *, force=False):
        nonlocal next_progress
        now = time.monotonic()
        if force or now >= next_progress:
            progress.update(operation=operation, elapsedSeconds=now-started,
                            deadlineMonotonic=outer_deadline, observedMonotonic=now,
                            remainingSeconds=outer_deadline-now, cancellationSignal=cancellation.signum,
                            forwardedCancellationSignal=sent, outerObservationTimedOut=timed_out,
                            resources=process_observations(), progressSequence=progress["progressSequence"]+1)
            next_progress = now + PROGRESS_INTERVAL
            try:
                save_json(outer_receipt, progress, maximum_bytes=8192)
            except (OSError, ValueError) as error:
                # Once launched, diagnostic I/O failure must not abandon the
                # owned supervisor. Continue cancellation/timeout/reap, then fail.
                if progress["state"] == "starting":
                    raise
                progress["progressWriteError"] = f"{type(error).__name__}: {error}"[:256]

    with log.open("x", encoding="utf-8") as stream:
        save_progress("launch-supervisor", force=True)
        child = subprocess.Popen(argv, stdout=stream, stderr=subprocess.STDOUT,
                                 start_new_session=os.name == "posix")
        progress.update(state="running", supervisorPID=child.pid)
        save_progress("poll-supervisor", force=True)
        while True:
            save_progress("poll-supervisor")
            progress["supervisorReturnCode"] = child.poll()
            if child.returncode is not None:
                break
            if cancellation.signum is not None and sent is None:
                try:
                    child.send_signal(cancellation.signum)
                except ProcessLookupError:
                    pass
                sent = cancellation.signum
                outer_deadline = min(outer_deadline, time.monotonic() + 17)
                save_progress("forward-cancellation", force=True)
            if time.monotonic() >= outer_deadline:
                timed_out = True
                # The supervisor's separate child session is NOT included here.
                # Its cleanup is unknown unless a completed receipt proves it.
                save_progress("kill-wrapper-group-only", force=True)
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
            save_progress("wait-supervisor", force=True)
            child.wait(timeout=1)
        except subprocess.TimeoutExpired:
            timed_out = True
    result = {"launched": True, "exitCode": child.returncode if child.returncode is not None else 125,
              "wrapperPID": child.pid, "forwardedCancellationSignal": sent,
              "outerObservationTimedOut": timed_out, "log": log.name, "receipt": receipt.name,
              "outerReceipt": outer_receipt.name}
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
    if "progressWriteError" in progress:
        result.update(exitCode=125, reason="outer-progress-evidence-unverified",
                      outerProgressWriteError=progress["progressWriteError"])
    progress.update(state="finished", supervisorReturnCode=child.returncode, reportedExitCode=result["exitCode"],
                    supervisorCleanupVerified=result.get("supervisor", {}).get("cleanupComplete") is True
                    and result["exitCode"] != 125)
    save_progress("receipt-verified" if result["exitCode"] != 125 else "receipt-unverified", force=True)
    if "progressWriteError" in progress:
        result.update(exitCode=125, reason="outer-progress-evidence-unverified",
                      outerProgressWriteError=progress["progressWriteError"])
    return result
