"""Regression tests for formatter-only diff coverage handling."""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

from coverage_gate import exclude_formatter_only_failures, is_formatter_only_dart_change


@unittest.skipUnless(shutil.which("dart"), "Dart SDK is needed for formatter comparison")
class FormatterOnlyCoverageTest(unittest.TestCase):
    SOURCE = "frontend/lib/example.dart"

    def setUp(self):
        self.temp_dir = tempfile.TemporaryDirectory(prefix="careconnect-coverage-test-")
        self.addCleanup(self.temp_dir.cleanup)
        self.root = Path(self.temp_dir.name)
        self.source = self.root / self.SOURCE
        self.source.parent.mkdir(parents=True)
        self.git("init", "-q")

    def git(self, *args):
        return subprocess.run(
            ["git", *args], cwd=self.root, capture_output=True, text=True, check=True
        ).stdout.strip()

    def commit_base(self, content):
        self.source.write_text(content, encoding="utf-8")
        self.git("add", self.SOURCE)
        self.git(
            "-c", "user.name=Coverage Test", "-c", "user.email=test@example.invalid",
            "commit", "-q", "-m", "baseline",
        )
        return self.git("rev-parse", "HEAD")

    def test_reformatting_entire_file_is_skipped(self):
        base = self.commit_base('String greeting(){return "hello world";}\n')
        self.source.write_text(
            'String greeting() {\n  return "hello world";\n}\n', encoding="utf-8"
        )
        self.assertTrue(is_formatter_only_dart_change(self.SOURCE, base, str(self.root)))
        failures, skipped = exclude_formatter_only_failures(
            [(self.SOURCE, 0.0, 0, 2)], base, str(self.root)
        )
        self.assertEqual(failures, [])
        self.assertEqual(skipped, [self.SOURCE])

    def test_whitespace_inside_a_string_is_not_ignored(self):
        base = self.commit_base('String greeting(){return "hello world";}\n')
        self.source.write_text(
            'String greeting() {\n  return "helloworld";\n}\n', encoding="utf-8"
        )
        self.assertFalse(is_formatter_only_dart_change(self.SOURCE, base, str(self.root)))

    def test_substantive_change_in_reformatted_file_still_fails(self):
        base = self.commit_base('int answer(){return 1;}\n')
        self.source.write_text('int answer() {\n  return 2;\n}\n', encoding="utf-8")
        failures, skipped = exclude_formatter_only_failures(
            [(self.SOURCE, 0.0, 0, 1)], base, str(self.root)
        )
        self.assertEqual(failures, [(self.SOURCE, 0.0, 0, 1)])
        self.assertEqual(skipped, [])

    def test_new_file_is_not_skipped(self):
        self.source.write_text('int answer() => 42;\n', encoding="utf-8")
        self.assertFalse(is_formatter_only_dart_change(self.SOURCE, "HEAD", str(self.root)))


if __name__ == "__main__":
    unittest.main()
