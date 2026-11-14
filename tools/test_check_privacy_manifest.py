#!/usr/bin/env python3
"""Tests for check_privacy_manifest.py (run: python3 tools/test_check_privacy_manifest.py)."""
import plistlib
import tempfile
import unittest
from pathlib import Path

import check_privacy_manifest as checker


def manifest(**overrides):
    data = {"NSPrivacyTracking": False, "NSPrivacyTrackingDomains": [], "NSPrivacyCollectedDataTypes": [],
            "NSPrivacyAccessedAPITypes": []}
    data.update(overrides)
    return data


def write(path, data):
    path.write_bytes(plistlib.dumps(data))
    return path


def entry(kind="Health", linked=True, tracking=False, purposes=("AppFunctionality",)):
    return {"NSPrivacyCollectedDataType": f"NSPrivacyCollectedDataType{kind}", "NSPrivacyCollectedDataTypeLinked": linked,
            "NSPrivacyCollectedDataTypeTracking": tracking,
            "NSPrivacyCollectedDataTypePurposes": [f"NSPrivacyCollectedDataTypePurpose{p}" for p in purposes]}


USER_DEFAULTS = "NSPrivacyAccessedAPICategoryUserDefaults"


class ManifestTests(unittest.TestCase):
    def check(self, data, used=()):
        with tempfile.TemporaryDirectory() as tmp:
            return checker.check_manifest("t", write(Path(tmp) / "m.xcprivacy", data), set(used))

    def test_clean_manifest_passes(self):
        data = manifest(NSPrivacyCollectedDataTypes=[entry()],
                        NSPrivacyAccessedAPITypes=[{"NSPrivacyAccessedAPIType": USER_DEFAULTS, "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}])
        self.assertEqual(self.check(data, {USER_DEFAULTS}), [])

    def test_tracking_is_rejected(self):
        self.assertTrue(any("NSPrivacyTracking" in p for p in self.check(manifest(NSPrivacyTracking=True))))
        self.assertTrue(any("Tracking = false" in p for p in self.check(manifest(NSPrivacyCollectedDataTypes=[entry(tracking=True)]))))

    def test_undeclared_and_stale_api_categories(self):
        self.assertTrue(any("does not declare" in p for p in self.check(manifest(), {USER_DEFAULTS})))
        stale = manifest(NSPrivacyAccessedAPITypes=[{"NSPrivacyAccessedAPIType": USER_DEFAULTS, "NSPrivacyAccessedAPITypeReasons": ["CA92.1"]}])
        self.assertTrue(any("no source uses it" in p for p in self.check(stale)))

    def test_bad_entries(self):
        self.assertTrue(any("unknown collected data type" in p for p in self.check(manifest(NSPrivacyCollectedDataTypes=[entry("Bogus")]))))
        self.assertTrue(any("advertising" in p for p in self.check(manifest(NSPrivacyCollectedDataTypes=[entry(purposes=("ThirdPartyAdvertising",))]))))
        self.assertTrue(any("declared twice" in p for p in self.check(manifest(NSPrivacyCollectedDataTypes=[entry(), entry()]))))

    def test_missing_manifest(self):
        self.assertTrue(checker.check_manifest("t", Path("/nonexistent/x.xcprivacy"), set()))

    def test_repository_manifests_are_clean(self):
        root = Path(__file__).resolve().parent.parent
        for name, target in checker.TARGETS.items():
            used = checker.used_categories(root, target["sources"])
            self.assertEqual(checker.check_manifest(name, root / target["manifest"], used), [], name)


if __name__ == "__main__":
    unittest.main()
