#!/usr/bin/env python3
"""Exercise release CLI with real Git history and offline process boundaries."""

import base64
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import tempfile
import unittest


SOURCE = Path(__file__).resolve().parents[1]


class ReleaseWorkflowTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="verbi-release-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.real_git = shutil.which("git")
        (self.root / "scripts").mkdir()
        (self.root / "App").mkdir()
        (self.root / "bin").mkdir()
        shutil.copy2(SOURCE / "release.py", self.root / "scripts/release.py")
        (self.root / ".gitignore").write_text("dist/\ncalls.jsonl\nbin/\n")
        with (self.root / "App/Info.plist").open("wb") as stream:
            plistlib.dump({"CFBundleShortVersionString": "1.2.3"}, stream)
        self.executable("scripts/create-dmg.sh", '''
import os, pathlib, plistlib, sys
assert os.environ['MA_RELEASE_SIGNING_MODE'] == 'identity'
assert os.environ['MA_RELEASE_CODE_SIGN_IDENTITY'] == 'Prisma Local Code Signing'
assert sys.argv[1:] == ['--ci', '--no-finder-layout']
dist = pathlib.Path('dist')
(dist / 'Verbi.app/Contents').mkdir(parents=True, exist_ok=True)
with (dist / 'Verbi.app/Contents/Info.plist').open('wb') as f:
    plistlib.dump({'CFBundleShortVersionString': '1.2.3'}, f)
(dist / 'Verbi-1.2.3.zip').write_bytes(b'fixture ZIP')
(dist / 'Verbi.dmg').write_bytes(b'fixture DMG')
''')
        prelude = '''
import json, os, pathlib, sys
with pathlib.Path(os.environ['FIXTURE_ROOT'], 'calls.jsonl').open('a') as f:
    f.write(json.dumps([pathlib.Path(sys.argv[0]).name, *sys.argv[1:]]) + '\\n')
'''
        self.executable("bin/codex", prelude + '''
data = sys.stdin.read()
assert '--ephemeral' in sys.argv and '--ignore-user-config' in sys.argv
assert 'shell_tool' in sys.argv and 'web_search="disabled"' in sys.argv
assert '--sandbox' in sys.argv and 'read-only' in sys.argv
assert pathlib.Path.cwd() != pathlib.Path(os.environ['FIXTURE_ROOT'])
for text in json.loads(os.environ.get('EXPECTED_HISTORY', '[]')):
    assert text in data, text
for text in json.loads(os.environ.get('EXCLUDED_HISTORY', '[]')):
    assert text not in data, text
if os.environ.get('FAIL_AI'):
    sys.exit(19)
print('## Improvements\\n- Faster meeting capture and clearer recording controls.')
for marker in ['EVIDENCE_START', 'EVIDENCE_MIDDLE', 'EVIDENCE_END']:
    if marker in data:
        print(marker)
''')
        self.executable("bin/codesign", '''
import os, sys
assert sys.argv[1:3] == ['-d', '-r-']
print('designated => cdhash H"00"' if os.environ.get('ADHOC_BUILD')
      else 'designated => identifier "com.mourato.verbi" and certificate leaf = H"00"')
''')
        self.executable("bin/gh", prelude + '''
args = sys.argv[1:]
if args[:2] == ['release', 'view']:
    print(json.dumps({'tagName': 'v1.2.2'}))
elif args[:2] == ['release', 'create']:
    assert '--draft' in args
    if os.environ.get('FAIL_UPLOAD'):
        sys.exit(21)
    print('https://github.com/example/verbi/releases/tag/v1.2.3')
elif args[:2] == ['release', 'edit']:
    assert '--draft=false' in args
elif args[0] == 'api' and 'homebrew-tap' in args[1]:
    if os.environ.get('TAP_MISSING'):
        sys.exit(1)
    if '--method' in args and os.environ.get('FAIL_TAP_UPDATE'):
        sys.exit(28)
    print('cask-sha')
elif args[0] == 'api':
    if args[1].endswith('/git/refs') and os.environ.get('FAIL_TAG_CREATION'):
        sys.exit(27)
    print(args[1].rsplit('/', 1)[-1])
else:
    sys.exit(22)
''')
        self.executable("bin/git", '''
import os, sys
if sys.argv[1] == 'ls-remote':
    print(os.environ.get('REMOTE_TAG', ''))
else:
    os.execv(os.environ['REAL_GIT'], [os.environ['REAL_GIT'], *sys.argv[1:]])
''')
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        FIXTURE_ROOT=str(self.root), REAL_GIT=self.real_git,
                        VERSION="", FROM="", PYTHONDONTWRITEBYTECODE="1")
        self.git("init", "-q")
        self.git("config", "user.name", "Release Fixture")
        self.git("config", "user.email", "fixture@example.invalid")
        self.git("config", "core.hooksPath", "/dev/null")
        self.git("config", "commit.gpgSign", "false")
        self.git("remote", "add", "origin", "https://github.com/example/verbi.git")
        self.commit("old feature excluded")
        self.git("tag", "v1.2.2")
        self.base_branch = self.git("branch", "--show-current")
        self.git("checkout", "-qb", "capture-improvement")
        (self.root / "capture.txt").write_text("capture")
        self.commit("Improve capture", "Full body explains faster meeting capture.")
        self.git("checkout", self.base_branch)
        (self.root / "controls.txt").write_text("controls")
        self.commit("Clarify controls")
        self.git("merge", "--no-ff", "capture-improvement", "-m", "Merge capture improvements")

    def executable(self, name, code):
        path = self.root / name
        path.write_text("#!/usr/bin/env python3\n" + code)
        path.chmod(0o755)

    def git(self, *args):
        return subprocess.check_output([self.real_git, *args], cwd=self.root,
                                       stderr=subprocess.DEVNULL, text=True).strip()

    def commit(self, subject, body=None):
        self.git("add", ".")
        self.git("commit", "--allow-empty", "-qm", subject, *(["-m", body] if body else []))

    def release(self, command, *args, **environment):
        return subprocess.run(["python3", str(self.root / "scripts/release.py"), command, *args],
                              cwd=self.root, env=dict(self.env, **environment),
                              capture_output=True, text=True, timeout=30)

    def calls(self):
        path = self.root / "calls.jsonl"
        return [json.loads(line) for line in path.read_text().splitlines()] if path.exists() else []

    @property
    def prepared(self):
        return self.root / "dist/releases/v1.2.3"

    def test_notes_cover_merged_branch_bodies_and_exclude_previous_release(self):
        result = self.release("notes", EXPECTED_HISTORY=json.dumps([
            "Improve capture", "Full body explains faster meeting capture.",
            "Clarify controls", "Merge capture improvements"]),
            EXCLUDED_HISTORY=json.dumps(["old feature excluded"]))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("## Improvements", result.stdout)
        self.assertIn("/compare/v1.2.2...", result.stdout)
        self.assertFalse((self.root / "dist").exists())

    def test_prepare_then_publish_preserves_reviewed_notes_and_commit(self):
        result = self.release("prepare")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(any(call[:3] == ["gh", "release", "create"] for call in self.calls()))
        cask = (self.prepared / "verbi.rb").read_text()
        zip_sha = json.loads((self.prepared / "release.json").read_text())["assets"]["Verbi-1.2.3.zip"]
        self.assertIn('version "1.2.3"', cask)
        self.assertIn(f'sha256 "{zip_sha}"', cask)
        self.assertIn("github.com/example/verbi/releases/download/", cask)
        (self.prepared / "release-notes.md").write_text("## Reviewed\n- Approved English notes.\n")
        result = self.release("publish")
        self.assertEqual(result.returncode, 0, result.stderr)
        calls = self.calls()
        create = next(call for call in calls if call[:3] == ["gh", "release", "create"])
        tag_create = next(call for call in calls if call[:3] ==
                          ["gh", "api", "repos/example/verbi/git/refs"])
        self.assertIn("POST", tag_create)
        self.assertIn("ref=refs/tags/v1.2.3", tag_create)
        self.assertIn("sha=" + self.git("rev-parse", "HEAD"), tag_create)
        self.assertIn("--verify-tag", create)
        self.assertIn(str(self.prepared / "Verbi-1.2.3.zip"), create)
        self.assertIn(str(self.prepared / "Verbi-1.2.3.dmg"), create)
        self.assertEqual(create[create.index("--repo") + 1], "example/verbi")
        self.assertEqual((self.prepared / "release-notes.md").read_text(),
                         "## Reviewed\n- Approved English notes.\n")
        self.assertTrue(any(call[:3] == ["gh", "release", "edit"] for call in calls))
        update = next(call for call in calls if "PUT" in call)
        self.assertEqual(update[2], "repos/example/homebrew-tap/contents/Casks/verbi.rb")
        self.assertIn("sha=cask-sha", update)
        content = next(arg for arg in update if arg.startswith("content="))[len("content="):]
        self.assertEqual(base64.b64decode(content).decode(), (self.prepared / "verbi.rb").read_text())
        self.assertNotEqual(self.release("prepare").returncode, 0)

    def test_missing_tap_leaves_release_published(self):
        self.assertEqual(self.release("prepare").returncode, 0)
        result = self.release("publish", TAP_MISSING="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("not found", result.stdout)
        self.assertFalse(any("PUT" in call for call in self.calls()))

    def test_failed_tap_update_reports_manual_step(self):
        self.assertEqual(self.release("prepare").returncode, 0)
        result = self.release("publish", FAIL_TAP_UPDATE="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Release published", result.stderr)
        self.assertTrue(any(call[:3] == ["gh", "release", "edit"] for call in self.calls()))

    def test_dirty_or_mismatched_version_stops_before_ai_and_build(self):
        result = self.release("prepare", "--version", "v9.9.9")
        self.assertIn("App version", result.stderr)
        (self.root / "uncommitted.txt").write_text("dirty")
        result = self.release("prepare")
        self.assertIn("clean checkout", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_adhoc_build_stops_before_staging(self):
        result = self.release("prepare", "--version", "v1.2.3", ADHOC_BUILD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not certificate-signed", result.stderr)
        self.assertFalse(self.prepared.exists())

    def test_modified_asset_or_source_commit_blocks_publication(self):
        self.assertEqual(self.release("prepare").returncode, 0)
        asset = self.prepared / "Verbi-1.2.3.zip"
        asset.write_bytes(b"tampered")
        result = self.release("publish")
        self.assertIn("Asset changed", result.stderr)
        asset.write_bytes(b"fixture ZIP")
        self.commit("New change after packaging")
        result = self.release("publish")
        self.assertIn("does not match", result.stderr)
        self.assertFalse(any(call[:3] == ["gh", "release", "create"] for call in self.calls()))

    def test_existing_remote_tag_and_failed_upload_never_publish(self):
        result = self.release("prepare", REMOTE_TAG="abc\trefs/tags/v1.2.3")
        self.assertIn("Remote tag already exists", result.stderr)
        self.assertFalse(self.prepared.exists())
        self.assertEqual(self.calls(), [])
        self.assertEqual(self.release("prepare").returncode, 0)
        result = self.release("publish", REMOTE_TAG="abc\trefs/tags/v1.2.3")
        self.assertIn("Remote tag already exists", result.stderr)
        result = self.release("publish", FAIL_TAG_CREATION="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:3] == ["gh", "release", "create"] for call in self.calls()))
        result = self.release("publish", FAIL_UPLOAD="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(any(call[:3] == ["gh", "release", "edit"] for call in self.calls()))

    def test_ai_failure_and_invalid_range_leave_no_prepared_release(self):
        result = self.release("prepare", FAIL_AI="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.prepared.exists())
        result = self.release("notes", "--from", self.git("rev-parse", "HEAD"))
        self.assertIn("No commits", result.stderr)
        result = self.release("notes", "--from", "ROOT",
                              EXPECTED_HISTORY=json.dumps(["old feature excluded"]))
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_long_history_is_batched_without_truncating_evidence(self):
        self.commit("Large historical change", "EVIDENCE_START\n" + "x" * 65000 +
                    "\nEVIDENCE_MIDDLE\n" + "y" * 65000 + "\nEVIDENCE_END")
        result = self.release("notes")
        self.assertEqual(result.returncode, 0, result.stderr)
        for marker in ["EVIDENCE_START", "EVIDENCE_MIDDLE", "EVIDENCE_END"]:
            self.assertIn(marker, result.stdout)
        self.assertEqual(sum(call[0] == "codex" for call in self.calls()), 4)

    def test_headless_dmg_packages_app_and_applications_link_without_finder(self):
        shutil.copy2(SOURCE / "create-dmg.sh", self.root / "scripts/create-dmg.sh")
        (self.root / "scripts/config").mkdir()
        for name in ["app_identity.sh", "release_signing.sh"]:
            shutil.copy2(SOURCE / "config" / name, self.root / "scripts/config" / name)
        self.executable("scripts/build-release.sh", '''
import pathlib, sys
assert sys.argv[1:] == ['--ci']
pathlib.Path('dist/Verbi.app').mkdir(parents=True, exist_ok=True)
''')
        native_hdiutil = shutil.which("hdiutil")
        self.executable("bin/hdiutil", f"NATIVE_HDIUTIL = {native_hdiutil!r}\n" + '''
import pathlib, subprocess, sys
assert sys.argv[1] == 'create'
assert sys.argv[sys.argv.index('-format') + 1] == 'UDZO'
stage = pathlib.Path(sys.argv[sys.argv.index('-srcfolder') + 1])
assert (stage / 'Verbi.app').is_dir()
assert (stage / 'Applications').is_symlink()
assert str((stage / 'Applications').readlink()) == '/Applications'
raise SystemExit(subprocess.call([NATIVE_HDIUTIL, *sys.argv[1:]]))
''')
        # Existing DMG script uses absolute /usr/bin/codesign for image signing.
        # Native disk image creation/signing is quiet: no mounts or Finder opens.
        for tool in ["osascript", "diskutil"]:
            self.executable(f"bin/{tool}", "raise SystemExit('Unexpected interactive DMG path')\n")
        result = subprocess.run([str(self.root / "scripts/create-dmg.sh"), "--ci", "--no-finder-layout"],
                                cwd=self.root, env=dict(self.env, MA_RELEASE_SIGNING_MODE="adhoc"),
                                capture_output=True, text=True, timeout=60)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue((self.root / "dist/Verbi.dmg").is_file())
        self.assertFalse((self.root / "dist/dmg_staging").exists())
        self.assertFalse((self.root / "dist/dmg_mount").exists())


if __name__ == "__main__":
    unittest.main(verbosity=1)
