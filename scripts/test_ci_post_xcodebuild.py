"""Offline checks for ci_scripts/ci_post_xcodebuild.sh (Xcode Cloud backend check)."""
import os
import plistlib
import subprocess
import tempfile
import unittest
from pathlib import Path

CI_SCRIPTS = Path(__file__).resolve().parent.parent / "ci_scripts"
SCRIPT = CI_SCRIPTS / "ci_post_xcodebuild.sh"


def make_archive(root, apps=1, info=None):
    archive = Path(root) / "RunSmart.xcarchive"
    applications = archive / "Products" / "Applications"
    applications.mkdir(parents=True)
    for index in range(apps):
        app = applications / f"App{index}.app"
        app.mkdir()
        (app / "Info.plist").write_bytes(plistlib.dumps(info or {}))
    return archive


class CiPostXcodebuildTests(unittest.TestCase):
    def run_script(self, env):
        return subprocess.run([str(SCRIPT)], env={"PATH": os.environ["PATH"], **env},
                              capture_output=True, text=True)

    def test_script_is_executable_and_checker_ships_with_it(self):
        self.assertTrue(os.access(SCRIPT, os.X_OK), "Xcode Cloud runs it as zsh without +x")
        checker = CI_SCRIPTS / "verify-release-backend.py"
        self.assertTrue(checker.is_symlink())
        self.assertEqual(checker.resolve(), (CI_SCRIPTS.parent / "scripts" / "verify-release-backend.py").resolve())

    def test_non_archive_actions_skip(self):
        result = self.run_script({"CI_XCODEBUILD_ACTION": "build-for-testing", "CI_XCODEBUILD_EXIT_CODE": "0"})
        self.assertEqual(result.returncode, 0)
        self.assertIn("skipped", result.stdout)

    def test_failed_xcodebuild_skips_without_masking_the_failure(self):
        result = self.run_script({"CI_XCODEBUILD_ACTION": "archive", "CI_XCODEBUILD_EXIT_CODE": "65"})
        self.assertEqual(result.returncode, 0)
        self.assertIn("already failed", result.stdout)

    def test_missing_archive_path_fails(self):
        result = self.run_script({"CI_XCODEBUILD_ACTION": "archive", "CI_XCODEBUILD_EXIT_CODE": "0"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("CI_ARCHIVE_PATH", result.stderr)

    def test_archive_without_exactly_one_app_fails(self):
        for count in (0, 2):
            with tempfile.TemporaryDirectory() as root:
                archive = make_archive(root, apps=count)
                result = self.run_script({"CI_XCODEBUILD_ACTION": "archive", "CI_XCODEBUILD_EXIT_CODE": "0",
                                          "CI_ARCHIVE_PATH": str(archive)})
                self.assertNotEqual(result.returncode, 0, count)
                self.assertIn("exactly one .app", result.stderr)

    def test_bad_packaged_backend_fails_before_any_network_call(self):
        with tempfile.TemporaryDirectory() as root:
            archive = make_archive(root, info={"SUPABASE_URL": "http://example.invalid",
                                               "SUPABASE_PUBLISHABLE_KEY": "wrong"})
            result = self.run_script({"CI_XCODEBUILD_ACTION": "archive", "CI_XCODEBUILD_EXIT_CODE": "0",
                                      "CI_ARCHIVE_PATH": str(archive)})
            self.assertEqual(result.returncode, 1)
            self.assertIn("Missing HTTPS backend", result.stdout)


if __name__ == "__main__":
    unittest.main()
