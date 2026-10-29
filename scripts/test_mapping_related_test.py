"""
Tests for related-test selection in scripts/test_mapping.py.

Run from the repo root:
    python -m unittest scripts/test_mapping_related_test.py
"""

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from test_mapping import related_tests, select_tests  # noqa: E402

MAIN = "backend/core/src/main/java/com/careconnect/config/"
TEST = "backend/core/src/test/java/com/careconnect/config/"


class RelatedTestsTest(unittest.TestCase):
    def setUp(self):
        self._tmp = tempfile.TemporaryDirectory()
        self.root = Path(self._tmp.name)

    def tearDown(self):
        self._tmp.cleanup()

    def touch(self, rel: str, text: str = "class X {}\n"):
        p = self.root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(text, encoding="utf-8")

    def test_backend_source_pulls_in_tests_that_extend_its_name(self):
        self.touch(MAIN + "SchemaPatchRunner.java")
        self.touch(TEST + "SchemaPatchRunnerTest.java")
        self.touch(TEST + "SchemaPatchRunnerStartupTest.java")
        self.touch(TEST + "SchemaPatchRunnerEmergencyPassportTest.java")

        self.assertEqual(
            related_tests(MAIN + "SchemaPatchRunner.java", str(self.root)),
            [
                TEST + "SchemaPatchRunnerEmergencyPassportTest.java",
                TEST + "SchemaPatchRunnerStartupTest.java",
            ],
        )

    def test_a_longer_name_that_is_its_own_source_is_not_related(self):
        self.touch(MAIN + "Patient.java")
        self.touch(MAIN + "PatientController.java")
        self.touch(TEST + "PatientTest.java")
        self.touch(TEST + "PatientControllerTest.java")
        self.touch(TEST + "PatientSerializationTest.java")

        self.assertEqual(
            related_tests(MAIN + "Patient.java", str(self.root)),
            [TEST + "PatientSerializationTest.java"],
        )

    def test_a_name_that_only_shares_letters_is_not_related(self):
        self.touch(MAIN + "Patch.java")
        self.touch(TEST + "PatchworkTest.java")  # "work", not "Work"
        self.assertEqual(related_tests(MAIN + "Patch.java", str(self.root)), [])

    def test_frontend_source_pulls_in_underscore_suffixed_tests(self):
        self.touch("frontend/lib/features/x/foo.dart", "void f() {}\n")
        self.touch("frontend/lib/features/x/foo_bar.dart", "void g() {}\n")
        self.touch("frontend/test/features/x/foo_test.dart")
        self.touch("frontend/test/features/x/foo_offline_test.dart")
        self.touch("frontend/test/features/x/foo_bar_test.dart")
        self.touch("frontend/test/features/x/foobar_test.dart")

        self.assertEqual(
            related_tests("frontend/lib/features/x/foo.dart", str(self.root)),
            ["frontend/test/features/x/foo_offline_test.dart"],
        )

    def test_select_tests_runs_related_tests_and_still_requires_the_same_name_test(
        self,
    ):
        self.touch(MAIN + "SchemaPatchRunner.java")
        self.touch(TEST + "SchemaPatchRunnerStartupTest.java")
        # No SchemaPatchRunnerTest.java: still reported missing.

        frontend, backend, missing = select_tests(
            [MAIN + "SchemaPatchRunner.java"], [], str(self.root)
        )
        self.assertEqual(frontend, [])
        self.assertEqual(
            backend, ["com.careconnect.config.SchemaPatchRunnerStartupTest"]
        )
        self.assertEqual(
            missing,
            [(MAIN + "SchemaPatchRunner.java", TEST + "SchemaPatchRunnerTest.java")],
        )

    def test_no_test_folder_means_no_related_tests(self):
        self.touch(MAIN + "Lonely.java")
        self.assertEqual(related_tests(MAIN + "Lonely.java", str(self.root)), [])


if __name__ == "__main__":
    unittest.main()
