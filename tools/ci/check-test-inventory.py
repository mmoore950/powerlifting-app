"""Require the split logs' passing test IDs to match this repository's iOS tests.

Current source uses one XCTestCase per file and named test methods. New conditional
or generated test forms must be reviewed instead of silently weakening this gate.
"""
from collections import Counter
import json
from pathlib import Path
import re


def expected(root):
    identifiers = set()
    paths = [("LiftingCoreTests", "Packages/LiftingCore/Tests/LiftingCoreTests"),
             ("PowerliftingAppTests", "Tests/App"), ("PowerliftingAppUITests", "Tests/UI")]
    for target, directory in paths:
        for filename in (root / directory).glob("*.swift"):
            text = filename.read_text(encoding="utf-8")
            # Entire HTTP test is macOS-only; it is absent, not skipped, on iOS.
            if filename.name == "OPLHTTPContractTests.swift" and text.startswith("#if os(macOS)\n"):
                continue
            if re.search(r"^\s*#(?:if|elseif|else)\b", text, re.MULTILINE):
                raise ValueError("Conditional XCTest inventory needs review: " + str(filename))
            classes = re.findall(r"\bclass\s+(\w+)\s*:\s*XCTestCase\b", text)
            methods = re.findall(r"\bfunc\s+(test\w+)\s*\(", text)
            if len(classes) != 1 or not methods:
                raise ValueError("Unsupported XCTest declaration: " + str(filename))
            for method in methods:
                identifier = f"{target}/{classes[0]}/{method}"
                if identifier in identifiers:
                    raise ValueError("Duplicate source test identifier: " + identifier)
                identifiers.add(identifier)
    return identifiers


def verify(root, output):
    required = expected(root)
    found = Counter()
    for phase in ("test-ui", "test-unit"):
        filename = output / (phase + ".log")
        if filename.is_symlink() or not 0 < filename.stat().st_size <= 32 * 1024 * 1024:
            raise ValueError("Missing/invalid test log")
        text = filename.read_text(encoding="utf-8")
        if re.search(r"Test Case .*\b(?:failed|skipped)\b", text):
            raise ValueError("Unexpected failed/skipped iOS test")
        matches = re.findall(r"Test Case '-\[(\w+)\.(\w+) (test\w+)\]' passed", text)
        for target, classname, method in matches:
            if (phase == "test-ui") != (target == "PowerliftingAppUITests"):
                raise ValueError("Test target appeared in wrong split phase")
            found[f"{target}/{classname}/{method}"] += 1
    missing, extra = sorted(required - set(found)), sorted(set(found) - required)
    duplicates = sorted(key for key, count in found.items() if count != 1)
    if missing or extra or duplicates:
        raise ValueError(json.dumps({"missing": missing, "extra": extra, "duplicates": duplicates}))
    return {"expected": len(required), "passedExactlyOnce": len(found), "missing": [], "extra": [], "duplicates": []}
