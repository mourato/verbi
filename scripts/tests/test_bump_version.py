#!/usr/bin/env python3
"""Version-bump contracts on temporary repositories, with native PlistBuddy."""

import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[2]


class VersionBumpTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory(prefix="verbi-bump-test-")
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name).resolve()
        for directory in ["scripts/hooks", "scripts/config", "App",
                          "Packages/MeetingAssistantCore/Sources/Common"]:
            (self.root / directory).mkdir(parents=True)
        for name in ["scripts/bump-version.sh", "scripts/hooks/first-commit-version-bump.sh",
                     "scripts/config/app_identity.sh", "Makefile"]:
            shutil.copy2(ROOT / name, self.root / name)
        self.swift = self.root / "Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift"
        self.swift.write_text('private static let hardcodedVersion = "1.0.0"\n'
                              'private static let hardcodedBuild = "7"\n')
        self.plist = self.root / "App/Info.plist"
        self.write_plist({"CFBundleShortVersionString": "1.0.0", "CFBundleVersion": "7",
                          "UnrelatedKey": "preserve"})

    def write_plist(self, value):
        self.plist.write_bytes(plistlib.dumps(value))

    def bump(self, version="1.0.1", build="8"):
        return subprocess.run([str(self.root / "scripts/bump-version.sh"), "--version", version,
                               "--build", build], capture_output=True, text=True, cwd="/tmp")

    def assert_versions(self, version, build):
        plist = plistlib.loads(self.plist.read_bytes())
        self.assertEqual(plist["CFBundleShortVersionString"], version)
        self.assertEqual(plist["CFBundleVersion"], build)
        self.assertEqual(plist["UnrelatedKey"], "preserve")
        self.assertIn(f'hardcodedVersion = "{version}"', self.swift.read_text())
        self.assertIn(f'hardcodedBuild = "{build}"', self.swift.read_text())

    def test_bump_succeeds_without_removed_ai_target_from_another_directory(self):
        result = self.bump()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_versions("1.0.1", "8")
        self.assertFalse((self.root / "MeetingAssistantAI").exists())

    def test_invalid_inputs_leave_both_files_unchanged(self):
        original = (self.swift.read_bytes(), self.plist.read_bytes())
        for version, build in [("1.2", "8"), ("1.2.3", "-1"), ('1.2.3"', "8"), ("1.2.3", "eight")]:
            with self.subTest(version=version, build=build):
                self.assertNotEqual(self.bump(version, build).returncode, 0)
                self.assertEqual((self.swift.read_bytes(), self.plist.read_bytes()), original)

    def test_missing_or_malformed_plist_does_not_change_swift(self):
        original = self.swift.read_bytes()
        for contents in [None, b"malformed", plistlib.dumps({"CFBundleShortVersionString": "1.0.0"})]:
            with self.subTest(contents=contents):
                self.plist.unlink(missing_ok=True)
                if contents is not None:
                    self.plist.write_bytes(contents)
                self.assertNotEqual(self.bump().returncode, 0)
                self.assertEqual(self.swift.read_bytes(), original)

    def test_invalid_swift_pattern_does_not_change_plist(self):
        original = self.plist.read_bytes()
        self.swift.write_text("missing version constants")
        self.assertNotEqual(self.bump().returncode, 0)
        self.assertEqual(self.plist.read_bytes(), original)

    def test_make_target_passes_version_and_build(self):
        result = subprocess.run(["make", "-C", str(self.root), "bump-version", "VERSION=2.3.4", "BUILD=42"],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assert_versions("2.3.4", "42")

    def test_daily_hook_stages_only_current_version_files(self):
        def git(*args):
            return subprocess.check_output(["git", *args], cwd=self.root, text=True,
                                           stderr=subprocess.DEVNULL).strip()
        git("init", "-q")
        git("config", "core.hooksPath", "/dev/null")
        git("config", "user.name", "Bump Fixture")
        git("config", "user.email", "fixture@example.invalid")
        git("config", "commit.gpgSign", "false")
        git("add", ".")
        git("commit", "-qm", "fixture")
        result = subprocess.run([str(self.root / "scripts/hooks/first-commit-version-bump.sh")],
                                cwd=self.root, env=dict(os.environ, FORCE_DAILY_VERSION_BUMP="1",
                                                       SKIP_DAILY_VERSION_BUMP="0"),
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(set(git("diff", "--cached", "--name-only").splitlines()),
                         {"App/Info.plist", "Packages/MeetingAssistantCore/Sources/Common/AppVersion.swift"})
        self.assertEqual(plistlib.loads(self.plist.read_bytes())["CFBundleVersion"], "8")


if __name__ == "__main__":
    unittest.main(verbosity=1)
