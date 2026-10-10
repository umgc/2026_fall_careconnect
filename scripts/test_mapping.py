#!/usr/bin/env python3
"""
scripts/test_mapping.py
-----------------------
Maps files changed on a PR to their unit tests by naming convention, and
requires every changed, non-exempt source file that gains new lines to have
one (a file whose diff only deletes lines needs no test):

    frontend/lib/foo/bar.dart
        -> frontend/test/foo/bar_test.dart
    backend/core/src/main/java/com/careconnect/Foo.java
        -> backend/core/src/test/java/com/careconnect/FooTest.java

Test files changed directly on the PR are run as well. Exemptions live in
scripts/test-exemptions.txt and are shared with coverage_gate.py.

Usage:
    python scripts/test_mapping.py \
        --diff-base <git-sha> \
        --frontend-out frontend-tests.txt \
        --backend-out backend-tests.txt \
        --repo-root .

Outputs:
    --frontend-out  one test path per line, relative to frontend/
    --backend-out   one test class per line (com.careconnect.FooTest)

Exit codes:
    0  Every changed source file has a test (or is exempt, or only lost lines)
    1  One or more changed source files have no same-name test
"""

import argparse
import fnmatch
import re
import subprocess
import sys
from pathlib import Path


EXEMPTIONS_FILE = "scripts/test-exemptions.txt"

FRONTEND_LIB = "frontend/lib/"
FRONTEND_TEST = "frontend/test/"
BACKEND_MAIN = "backend/core/src/main/java/"
BACKEND_TEST = "backend/core/src/test/java/"


# ---------------------------------------------------------------------------
# Shared helpers (also used by coverage_gate.py)
# ---------------------------------------------------------------------------

def get_changed_files(diff_base: str, repo_root: str) -> list[str]:
    """Return files changed since diff_base (relative to repo root), excluding deletions."""
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=d", diff_base],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if result.returncode != 0:
        print(f"ERROR: git diff failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return [f.strip() for f in result.stdout.splitlines() if f.strip()]


_HUNK = re.compile(r"^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@")


def get_added_lines(diff_base: str, repo_root: str) -> dict[str, set[int]]:
    """
    Return {path: line numbers added or modified since diff_base} for files
    that still exist. A file whose diff only deletes lines maps to an empty set.
    """
    result = subprocess.run(
        ["git", "diff", "-U0", "--no-color", "--diff-filter=d", diff_base],
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=repo_root,
    )
    if result.returncode != 0:
        print(f"ERROR: git diff failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)

    added: dict[str, set[int]] = {}
    current = None
    for line in result.stdout.splitlines():
        if line.startswith("+++ "):
            target = line[4:]
            current = target[2:] if target.startswith("b/") else None
            if current is not None:
                added.setdefault(current, set())
        elif current is not None and line.startswith("@@"):
            m = _HUNK.match(line)
            if m:
                start = int(m.group(1))
                count = int(m.group(2)) if m.group(2) is not None else 1
                added[current].update(range(start, start + count))
    return added


def load_exemptions(repo_root: str) -> list[str]:
    path = Path(repo_root) / EXEMPTIONS_FILE
    if not path.exists():
        return []
    patterns = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if line and not line.startswith("#"):
            patterns.append(line)
    return patterns


def is_exempt(path: str, patterns: list[str]) -> bool:
    return any(fnmatch.fnmatchcase(path, p) for p in patterns)


_COMMENTS = re.compile(r"//[^\n]*|/\*.*?\*/", re.DOTALL)
_DART_DIRECTIVES = re.compile(r"\b(?:import|export|part|library)\b[^;]*;", re.DOTALL)
_JAVA_NO_CODE_TYPE = re.compile(
    r"^\s*(?:public\s+)?(?:sealed\s+|non-sealed\s+)?@?interface\s+\w+", re.MULTILINE
)


def has_executable_code(path: str, repo_root: str) -> bool:
    """
    False for files that can never show line coverage: empty or
    import/export-only Dart files, and Java interfaces/annotations
    without default methods.
    """
    full = Path(repo_root) / path
    try:
        text = full.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return True

    if path.endswith(".dart"):
        body = _DART_DIRECTIVES.sub("", _COMMENTS.sub("", text))
        return bool(body.strip())

    if path.endswith(".java"):
        code = _COMMENTS.sub("", text)
        if re.search(r"\b(?:class|enum|record)\s+\w+", code):
            return True  # a class may nest an interface; still has code
        if _JAVA_NO_CODE_TYPE.search(code) and not re.search(r"\bdefault\s+\w", code):
            return False
        return True

    return True


def is_frontend_source(path: str) -> bool:
    return path.startswith(FRONTEND_LIB) and path.endswith(".dart")


def is_backend_source(path: str) -> bool:
    return path.startswith(BACKEND_MAIN) and path.endswith(".java")


def needs_test(path: str, patterns: list[str], repo_root: str) -> bool:
    """True if path is a source file that must have its own unit test."""
    if not (is_frontend_source(path) or is_backend_source(path)):
        return False
    if is_exempt(path, patterns):
        return False
    return has_executable_code(path, repo_root)


def expected_test(path: str) -> str | None:
    """Repo-root path of the test a source file must have, or None if not a source."""
    if is_frontend_source(path):
        rel = path.removeprefix(FRONTEND_LIB).removesuffix(".dart")
        return f"{FRONTEND_TEST}{rel}_test.dart"
    if is_backend_source(path):
        rel = path.removeprefix(BACKEND_MAIN).removesuffix(".java")
        return f"{BACKEND_TEST}{rel}Test.java"
    return None


# ---------------------------------------------------------------------------
# Test selection
# ---------------------------------------------------------------------------

def select_tests(
    changed: list[str],
    patterns: list[str],
    repo_root: str,
    added_lines: dict[str, set[int]] | None = None,
):
    """
    Returns (frontend_tests, backend_tests, missing) where missing is a list
    of (source, expected_test) for changed sources with no test.

    With added_lines, a source whose diff only deletes lines is not reported
    as missing: there is no new code for a test to cover.
    """
    root = Path(repo_root)
    tests: set[str] = set()
    missing: list[tuple[str, str]] = []

    for f in changed:
        is_test = (
            (f.startswith(FRONTEND_TEST) and f.endswith("_test.dart"))
            or (f.startswith(BACKEND_TEST) and f.endswith("Test.java"))
        )
        if is_test:
            tests.add(f)
            continue

        if not needs_test(f, patterns, repo_root):
            continue

        candidate = expected_test(f)
        if (root / candidate).is_file():
            tests.add(candidate)
        elif added_lines is None or added_lines.get(f):
            missing.append((f, candidate))

    frontend = sorted(
        t.removeprefix("frontend/") for t in tests if t.startswith(FRONTEND_TEST)
    )
    backend = sorted(
        t.removeprefix(BACKEND_TEST).removesuffix(".java").replace("/", ".")
        for t in tests if t.startswith(BACKEND_TEST)
    )
    return frontend, backend, missing


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Map changed files to unit tests")
    parser.add_argument("--diff-base", required=True, help="Git SHA to diff against")
    parser.add_argument("--frontend-out", required=True)
    parser.add_argument("--backend-out", required=True)
    parser.add_argument("--repo-root", default=".")
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="Report sources without a test but exit 0 (verified develop syncs only)",
    )
    args = parser.parse_args()

    changed = get_changed_files(args.diff_base, args.repo_root)
    patterns = load_exemptions(args.repo_root)
    added = get_added_lines(args.diff_base, args.repo_root)
    frontend, backend, missing = select_tests(changed, patterns, args.repo_root, added)

    Path(args.frontend_out).write_text("".join(f"{t}\n" for t in frontend))
    Path(args.backend_out).write_text("".join(f"{t}\n" for t in backend))

    print(f"Frontend tests to run ({len(frontend)}):")
    for t in frontend:
        print(f"  {t}")
    print(f"Backend tests to run ({len(backend)}):")
    for t in backend:
        print(f"  {t}")

    if not missing:
        print("\n✅ Every changed source file has a matching unit test.")
        sys.exit(0)

    mark = "⚠️" if args.allow_missing else "❌"
    print(f"\n{mark} {len(missing)} changed source file(s) have no matching unit test:\n")
    for src, test in sorted(missing):
        print(f"  {src}")
        print(f"    expected: {test}")
    if args.allow_missing:
        # A verified develop sync imports other teams' already-reviewed code;
        # the syncing team is not asked to backfill tests for it.
        print("\nAllowed: these files arrive through a verified develop sync.")
        sys.exit(0)
    print(
        "\nAdd a test at the expected path (same directory, same name + "
        "_test.dart / Test.java). If the file genuinely needs no unit test, "
        f"add it to {EXEMPTIONS_FILE}."
    )
    sys.exit(1)


if __name__ == "__main__":
    main()
