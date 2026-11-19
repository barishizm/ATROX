#!/usr/bin/env python3
"""Audit the privacy manifests (P101): no tracking, well-formed, and every required-reason API the code uses is declared.

Usage: python3 tools/check_privacy_manifest.py [repo_root]   Exit code 1 when a problem is found.

Checks per target (app: ios/App/Resources + sources shared with the widget; widget: ios/Widgets/Resources):
- the manifest exists and parses as a plist;
- NSPrivacyTracking is false and there are no tracking domains;
- every collected data type is a known Apple constant with Linked/Tracking booleans and known purposes, and none is tracking;
- required-reason API categories used in the target's Swift sources are declared with at least one reason, and no
  declared category is unused (a stale declaration is also a review risk).
Detection is textual and intentionally conservative; it mirrors Apple's list of required-reason API categories.
"""
import plistlib
import re
import sys
from pathlib import Path

DATA_TYPES = {
    "EmailAddress", "Name", "PhoneNumber", "PhysicalAddress", "OtherUserContactInfo", "Health", "Fitness",
    "PaymentInfo", "CreditInfo", "OtherFinancialInfo", "PreciseLocation", "CoarseLocation", "SensitiveInfo",
    "Contacts", "EmailsOrTextMessages", "PhotosorVideos", "AudioData", "GameplayContent", "CustomerSupport",
    "OtherUserContent", "BrowsingHistory", "SearchHistory", "UserID", "DeviceID", "PurchaseHistory",
    "ProductInteraction", "AdvertisingData", "OtherUsageData", "CrashData", "PerformanceData", "OtherDiagnosticData",
    "EnvironmentScanning", "Hands", "Head", "OtherDataTypes",
}
PURPOSES = {"ThirdPartyAdvertising", "DeveloperAdvertising", "Analytics", "ProductPersonalization", "AppFunctionality", "Other"}

# Category -> regex over Swift source. Reasons per Apple's required-reason API documentation.
API_PATTERNS = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage|\.appStorage\b",
    "NSPrivacyAccessedAPICategoryFileTimestamp": r"creationDate|modificationDate|NSFileCreationDate|NSFileModificationDate|contentModificationDateKey|creationDateKey",
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time|\bkern\.boottime\b",
    "NSPrivacyAccessedAPICategoryDiskSpace": r"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|fileSystemFreeSize|statfs\(|NSURLVolume",
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}
TARGETS = {
    "app": {"manifest": "ios/App/Resources/PrivacyInfo.xcprivacy", "sources": ["ios/App", "ios/Shared", "ios/Packages/DataKit/Sources", "ios/Packages/CoachKit/Sources", "ios/Packages/StrengthKit/Sources", "ios/Packages/DesignSystem/Sources"]},
    "widget": {"manifest": "ios/Widgets/Resources/PrivacyInfo.xcprivacy", "sources": ["ios/Widgets/Sources", "ios/Shared"]},
}


def used_categories(root, sources):
    found = set()
    for source in sources:
        for path in (root / source).rglob("*.swift"):
            if "Tests" in path.parts:
                continue
            text = path.read_text(encoding="utf-8", errors="ignore")
            for category, pattern in API_PATTERNS.items():
                if re.search(pattern, text):
                    found.add(category)
    return found


def check_manifest(name, manifest_path, used):
    problems = []
    if not manifest_path.exists():
        return [f"{name}: {manifest_path} is missing"]
    try:
        data = plistlib.loads(manifest_path.read_bytes())
    except Exception as error:  # noqa: BLE001 - any parse failure is a finding
        return [f"{name}: manifest does not parse ({error})"]
    if data.get("NSPrivacyTracking") is not False:
        problems.append(f"{name}: NSPrivacyTracking must be false")
    if data.get("NSPrivacyTrackingDomains"):
        problems.append(f"{name}: NSPrivacyTrackingDomains must be empty")
    seen = set()
    for entry in data.get("NSPrivacyCollectedDataTypes", []):
        kind = str(entry.get("NSPrivacyCollectedDataType", "")).removeprefix("NSPrivacyCollectedDataType")
        if kind not in DATA_TYPES:
            problems.append(f"{name}: unknown collected data type {kind!r}")
        if kind in seen:
            problems.append(f"{name}: data type {kind} declared twice")
        seen.add(kind)
        if not isinstance(entry.get("NSPrivacyCollectedDataTypeLinked"), bool):
            problems.append(f"{name}: {kind} needs a boolean Linked flag")
        if entry.get("NSPrivacyCollectedDataTypeTracking") is not False:
            problems.append(f"{name}: {kind} must declare Tracking = false")
        purposes = [str(p).removeprefix("NSPrivacyCollectedDataTypePurpose") for p in entry.get("NSPrivacyCollectedDataTypePurposes", [])]
        if not purposes or any(p not in PURPOSES for p in purposes):
            problems.append(f"{name}: {kind} has missing or unknown purposes {purposes}")
        if "ThirdPartyAdvertising" in purposes or "DeveloperAdvertising" in purposes:
            problems.append(f"{name}: {kind} declares an advertising purpose; the product decision is no ads/tracking")
    declared = {}
    for entry in data.get("NSPrivacyAccessedAPITypes", []):
        declared[entry.get("NSPrivacyAccessedAPIType")] = entry.get("NSPrivacyAccessedAPITypeReasons", [])
    for category in sorted(used - set(declared)):
        problems.append(f"{name}: code uses {category} but the manifest does not declare it")
    for category, reasons in declared.items():
        if not reasons:
            problems.append(f"{name}: {category} has no reason codes")
        if category not in used:
            problems.append(f"{name}: {category} is declared but no source uses it")
    return problems


def main(argv):
    root = Path(argv[1]) if len(argv) > 1 else Path(__file__).resolve().parent.parent
    problems = []
    for name, target in TARGETS.items():
        problems += check_manifest(name, root / target["manifest"], used_categories(root, target["sources"]))
    for problem in problems:
        print(problem)
    print("privacy manifests: OK" if not problems else f"privacy manifests: {len(problems)} problem(s)")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
