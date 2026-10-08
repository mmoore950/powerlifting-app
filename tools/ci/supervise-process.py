#!/usr/bin/env python3
"""Bound one command and its newly created POSIX process group, without a shell.

OS services and descendants that leave this session are outside this ownership
boundary. Windows supports only the direct child; it cannot validate macOS cleanup.
"""
import argparse
import errno
import json
import math
import os
from pathlib import Path
import signal
import subprocess
import time
import traceback

KILL_SIGNAL = getattr(signal, "SIGKILL", 9)


def group_present(pgid, evidence):
    """EPERM is uncertain presence, never proof that an owned group is gone."""
    evidence["operation"] = "observe-owned-group"
    try:
        os.killpg(pgid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError as error:
        if error.errno != errno.EPERM:
            raise
        evidence["groupProbePermissionErrors"] = evidence.get("groupProbePermissionErrors", 0) + 1
        evidence["lastGroupProbeError"] = f"{type(error).__name__}: {error}"
        # The existing grace/KILL deadlines still bound observation. Persistent
        # uncertainty must fail cleanup; actual signaling errors are not ignored.
        return True


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("Expected a finite positive duration")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--timeout", type=positive, required=True)
    parser.add_argument("--term-grace", type=positive, default=5)
    parser.add_argument("--kill-wait", type=positive, default=5)
    parser.add_argument("--receipt", type=Path, required=True)
    parser.add_argument("command", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    command = args.command
    if command[:1] == ["--"]:
        command = command[1:]
    if not command:
        parser.error("A command is required after --")

    started = time.monotonic()
    requested_signal = None
    child = None
    posix = os.name == "posix"
    evidence = {
        "schemaVersion": 1, "state": "starting", "command": command,
        "ownership": "new-posix-process-group" if posix else "direct-child-only",
        "timeoutSeconds": args.timeout, "termGraceSeconds": args.term_grace,
        "killWaitSeconds": args.kill_wait, "signalsSent": [],
        "escapedProcessesAndOSServicesOwned": False,
    }

    def save():
        evidence["elapsedSeconds"] = round(time.monotonic() - started, 3)
        temporary = args.receipt.with_name(args.receipt.name + ".tmp")
        temporary.write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")
        os.replace(temporary, args.receipt)

    def cancelled(signum, _frame):
        nonlocal requested_signal
        if requested_signal is None:
            requested_signal = signum

    def owned_alive():
        # Poll also reaps the direct child. killpg(0) observes group existence;
        # it cannot distinguish a live descendant from an unreaped zombie.
        evidence["operation"] = "poll-direct-child"
        child.poll()
        if not posix:
            return child.returncode is None
        return group_present(child.pid, evidence)

    def send(signum):
        try:
            evidence["operation"] = "signal-owned-group" if posix else "signal-direct-child"
            if posix:
                os.killpg(child.pid, signum)
            elif child.poll() is None:
                if signum == KILL_SIGNAL:
                    child.kill()
                else:
                    child.terminate()
            else:
                return
            evidence["signalsSent"].append("SIGKILL" if signum == KILL_SIGNAL else signal.Signals(signum).name)
        except ProcessLookupError:
            pass

    def wait_owned(seconds):
        deadline = time.monotonic() + seconds
        while owned_alive():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return False
            time.sleep(min(0.05, remaining))
        return True

    def cleanup(first_signal):
        try:
            if owned_alive():
                send(first_signal)
                if not wait_owned(args.term_grace):
                    send(KILL_SIGNAL)
                    wait_owned(args.kill_wait)
        except Exception:
            evidence["cleanupFailureOperation"] = evidence.get("operation")
            raise
        finally:
            # Observation/signaling errors must not skip the direct-child wait.
            # Grandchildren are not waitable by this process.
            try:
                evidence["operation"] = "wait-direct-child"
                child.wait(timeout=max(0.01, args.kill_wait if child.poll() is None else 0.01))
            except subprocess.TimeoutExpired:
                evidence["directChildWaitCompleted"] = False
            else:
                evidence["directChildWaitCompleted"] = True
            evidence["childReturnCode"] = child.returncode
        evidence["ownedGroupAbsent"] = not owned_alive() if posix else None
        return evidence["directChildWaitCompleted"] and (not posix or evidence["ownedGroupAbsent"])

    handlers = {s: signal.signal(s, cancelled) for s in (signal.SIGINT, signal.SIGTERM)}
    exit_code = 125
    try:
        save()
        child = subprocess.Popen(command, start_new_session=posix)
        evidence.update(state="running", childPID=child.pid,
                        ownedProcessGroupID=child.pid if posix else None)
        save()
        deadline = started + args.timeout
        while True:
            code = child.poll()
            if requested_signal is not None:
                reason, exit_code = "cancelled", 128 + requested_signal
                break
            if time.monotonic() >= deadline:
                reason, exit_code = "timeout", 124
                break
            if code is not None:
                reason = "child-exited"
                exit_code = code if code >= 0 else 128 - code
                break
            time.sleep(min(0.1, max(0, deadline - time.monotonic())))
        evidence["reason"] = reason
        evidence["cancellationSignal"] = requested_signal
        if not cleanup(requested_signal or signal.SIGTERM):
            evidence["cleanupComplete"] = False
            exit_code = 125
        else:
            evidence["cleanupComplete"] = True
        # Cancellation during cleanup also must not become a successful result.
        if requested_signal is not None and exit_code != 125:
            evidence.update(reason="cancelled", cancellationSignal=requested_signal)
            exit_code = 128 + requested_signal
    except Exception as error:
        evidence.update(reason="supervisor-error", error=f"{type(error).__name__}: {error}",
                        errorOperation=evidence.get("cleanupFailureOperation", evidence.get("operation")),
                        errorTraceback=traceback.format_exc())
        if child is not None:
            try:
                evidence["cleanupComplete"] = cleanup(signal.SIGTERM)
            except Exception as cleanup_error:
                evidence.update(cleanupComplete=False, cleanupError=str(cleanup_error),
                                cleanupErrorOperation=evidence.get("operation"),
                                cleanupErrorTraceback=traceback.format_exc())
        exit_code = 125
    finally:
        evidence.update(state="finished", wrapperExitCode=exit_code)
        try:
            save()
        finally:
            for signum, previous in handlers.items():
                signal.signal(signum, previous)
    print(f"Supervisor: {evidence.get('reason')}; exit={exit_code}; "
          f"cleanup={evidence.get('cleanupComplete')}; receipt={args.receipt}", flush=True)
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
