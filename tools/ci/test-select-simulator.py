"""Pure selector/receipt checks. No simulator boot or Apple runtime validation."""
import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location("selector", Path(__file__).with_name("select-simulator.py"))
selector = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selector)
OLD = "com.apple.CoreSimulator.SimRuntime.iOS-18-5"
NEW = "com.apple.CoreSimulator.SimRuntime.iOS-26-2"
FIRST = "11111111-1111-4111-8111-111111111111"
SECOND = "22222222-2222-4222-8222-222222222222"

def fixture():
    return {"runtimes": [{"identifier": OLD, "version": "18.5", "isAvailable": True},
                         {"identifier": NEW, "version": "26.2", "isAvailable": True}],
            "devices": {OLD: [{"name": "iPhone 16", "udid": FIRST, "isAvailable": True}],
                        NEW: [{"name": "iPhone 17", "udid": SECOND, "isAvailable": True}]}}

class SelectorTests(unittest.TestCase):
    def test_measured_sdk_selects_matching_installed_runtime_and_normalizes_patch(self):
        data = fixture()
        for sdk in ("18.5", "18.5.0", "18.5.1"):
            selected = selector.select(data, sdk)
            self.assertEqual(selected["runtime"], OLD)
            self.assertEqual(selected["version"], "18.5.0")
            self.assertEqual(selected["requestedSDK"], sdk)
            self.assertEqual(selected["matchPolicy"], "installed-sdk-major-minor")
        data["runtimes"][0]["version"] = "18.5.2"
        self.assertEqual(selector.select(data, "18.5")["version"], "18.5.2")
    def test_absent_or_unavailable_match_never_falls_back_to_newest(self):
        for change in ("absent", "unavailable", "wrong-minor", "malformed"):
            data = fixture()
            if change == "absent": data["runtimes"] = data["runtimes"][1:]
            elif change == "unavailable": data["runtimes"][0]["isAvailable"] = False
            elif change == "wrong-minor": data["runtimes"][0]["version"] = "18.6"
            else: data["runtimes"][0]["version"] = "18.5.invalid"
            with self.assertRaisesRegex(ValueError, "matching measured SDK"):
                selector.select(data, "18.5")
    def test_malformed_or_below_minimum_sdk_refuses_selection(self):
        for sdk in (None, True, "", "latest", "18", "16.4", "18.5.extra", "18.5\n26.2", "\u0661\u0668.\u0665"):
            with self.assertRaises(ValueError): selector.select(fixture(), sdk)
    def test_valid_iphone_selection_is_deterministic_and_rejects_missing_candidates(self):
        data = fixture()
        data["devices"][OLD] = [{"name": "iPhone 16", "udid": SECOND, "isAvailable": True},
            {"name": "iPhone 16", "udid": FIRST.lower(), "isAvailable": True},
            {"name": "iPhone 15", "udid": "invalid", "isAvailable": True},
            {"name": "iPhone 14", "udid": FIRST, "isAvailable": False},
            {"name": "iPad 17", "udid": FIRST, "isAvailable": True}]
        before = copy.deepcopy(data)
        self.assertEqual(selector.select(data, "18.5")["udid"], FIRST)
        data["devices"][OLD].reverse()
        self.assertEqual(selector.select(data, "18.5")["udid"], FIRST)
        self.assertEqual(before["runtimes"], data["runtimes"])
        data["devices"][OLD] = data["devices"][OLD][:3]
        with self.assertRaises(ValueError): selector.select(data, "18.5")
    def test_sdk_receipt_is_required_bounded_and_single_version(self):
        with tempfile.TemporaryDirectory() as directory:
            receipt = Path(directory) / "sdk.txt"
            with self.assertRaises(ValueError): selector.read_sdk(receipt)
            receipt.write_text("18.5\n", encoding="utf-8")
            self.assertEqual(selector.select(fixture(), selector.read_sdk(receipt))["runtime"], OLD)
            for text in ("", "1" * 129, "18.5\n26.2"):
                receipt.write_text(text, encoding="utf-8")
                with self.assertRaises(ValueError): selector.read_sdk(receipt)

if __name__ == "__main__":
    unittest.main()
