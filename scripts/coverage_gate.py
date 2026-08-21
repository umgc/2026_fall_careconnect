#!/usr/bin/env python3
"""
scripts/coverage_gate.py
------------------------
Checks test coverage for changed files on a PR against a minimum threshold.

Usage:
    python scripts/coverage_gate.py \
        --diff-base <git-sha> \
        --threshold 0.95 \
        --jacoco-xml backend/core/target/site/jacoco/jacoco.xml \
        --lcov-info frontend/coverage/lcov.info \
        --repo-root .

Exit codes:
    0  All changed files meet the coverage threshold (or no changed files found)
    1  One or more changed files are below the threshold
"""

import argparse
import subprocess
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


THRESHOLD_DEFAULT = 0.95


# ---------------------------------------------------------------------------
# Git helpers
# ---------------------------------------------------------------------------

def get_changed_files(diff_base: str, repo_root: str) -> list[str]:
    """Return list of files changed since diff_base (relative to repo root)."""
    result = subprocess.run(
        ["git", "diff", "--name-only", diff_base],
        capture_output=True,
        text=True,
        cwd=repo_root,
    )
    if result.returncode != 0:
        print(f"ERROR: git diff failed: {result.stderr}", file=sys.stderr)
        sys.exit(1)
    return [f.strip() for f in result.stdout.splitlines() if f.strip()]


# ---------------------------------------------------------------------------
# Java / JaCoCo
# ---------------------------------------------------------------------------

def parse_jacoco(jacoco_xml: str) -> dict[str, float]:
    """
    Parse JaCoCo XML and return a dict of:
        { "com/example/Foo" -> line_coverage_ratio }
    where line_coverage_ratio is between 0.0 and 1.0.
    Returns empty dict if file doesn't exist.
    """
    path = Path(jacoco_xml)
    if not path.exists():
        return {}

    coverage = {}
    tree = ET.parse(path)
    root = tree.getroot()

    for package in root.findall("package"):
        pkg_name = package.attrib.get("name", "")
        for cls in package.findall("class"):
            cls_name = cls.attrib.get("name", "")
            # cls_name is like "com/example/Foo" (may include inner classes with $)
            # Skip inner classes — they are covered by their outer class test
            if "$" in cls_name:
                continue

            missed = 0
            covered = 0
            for counter in cls.findall("counter"):
                if counter.attrib.get("type") == "LINE":
                    missed = int(counter.attrib.get("missed", 0))
                    covered = int(counter.attrib.get("covered", 0))
                    break

            total = missed + covered
            ratio = (covered / total) if total > 0 else None
            coverage[cls_name] = ratio

    return coverage


def check_java_coverage(
    changed_files: list[str],
    jacoco_coverage: dict[str, float],
    threshold: float,
    repo_root: str,
) -> list[tuple[str, float | None]]:
    """
    For each changed Java source file, look up its coverage in jacoco_coverage.
    Returns list of (file, coverage) tuples for files that fail the threshold.
    """
    failures = []

    for f in changed_files:
        # Only check Java source files in src/main/java
        if not f.endswith(".java") or "src/main/java/" not in f:
            continue
        if "src/test/java/" in f:
            continue

        # Convert file path to JaCoCo class key
        # e.g. backend/core/src/main/java/com/careconnect/service/FooService.java
        #   -> com/careconnect/service/FooService
        try:
            after_java = f.split("src/main/java/")[1]
            class_key = after_java.replace(".java", "")
        except IndexError:
            continue

        if class_key not in jacoco_coverage:
            # Class not in report — likely not executed by any test
            # Treat as 0% coverage (no tests ran for it)
            failures.append((f, 0.0))
            continue

        ratio = jacoco_coverage[class_key]
        if ratio is None:
            # No executable lines (e.g. interface) — skip
            continue

        if ratio < threshold:
            failures.append((f, ratio))

    return failures


# ---------------------------------------------------------------------------
# Dart / Flutter (lcov)
# ---------------------------------------------------------------------------

def parse_lcov(lcov_info: str) -> dict[str, float]:
    """
    Parse lcov.info and return a dict of:
        { "lib/features/foo/bar.dart" -> line_coverage_ratio }
    Returns empty dict if file doesn't exist.
    """
    path = Path(lcov_info)
    if not path.exists():
        return {}

    coverage = {}
    current_file = None
    lines_found = 0
    lines_hit = 0

    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("SF:"):
                current_file = line[3:]
                lines_found = 0
                lines_hit = 0
            elif line.startswith("LF:"):
                lines_found = int(line[3:])
            elif line.startswith("LH:"):
                lines_hit = int(line[3:])
            elif line == "end_of_record" and current_file:
                ratio = (lines_hit / lines_found) if lines_found > 0 else None
                # Normalize path: strip leading "./" or absolute prefix
                key = current_file.lstrip("./")
                coverage[key] = ratio
                current_file = None

    return coverage


def check_flutter_coverage(
    changed_files: list[str],
    lcov_coverage: dict[str, float],
    threshold: float,
) -> list[tuple[str, float | None]]:
    """
    For each changed Dart lib file, look up its coverage in lcov_coverage.
    Returns list of (file, coverage) tuples for files that fail the threshold.
    """
    failures = []

    for f in changed_files:
        if not f.endswith(".dart"):
            continue
        if not f.startswith("frontend/lib/"):
            continue

        # lcov paths are relative to frontend/ directory
        # e.g. "frontend/lib/features/foo/bar.dart" -> "lib/features/foo/bar.dart"
        lcov_key = f.removeprefix("frontend/")

        if lcov_key not in lcov_coverage:
            # File not in coverage report — no tests ran for it
            failures.append((f, 0.0))
            continue

        ratio = lcov_coverage[lcov_key]
        if ratio is None:
            continue  # No executable lines

        if ratio < threshold:
            failures.append((f, ratio))

    return failures


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Coverage gate for changed files")
    parser.add_argument("--diff-base", required=True, help="Git SHA to diff against")
    parser.add_argument("--threshold", type=float, default=THRESHOLD_DEFAULT,
                        help="Minimum coverage ratio (default: 0.95)")
    parser.add_argument("--jacoco-xml", default="backend/core/target/site/jacoco/jacoco.xml")
    parser.add_argument("--lcov-info", default="frontend/coverage/lcov.info")
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()

    threshold = args.threshold
    print(f"\nCoverage gate — threshold: {threshold:.0%}")
    print(f"Diff base: {args.diff_base}\n")

    changed = get_changed_files(args.diff_base, args.repo_root)
    if not changed:
        print("No changed files found. Skipping coverage check.")
        sys.exit(0)

    print(f"Changed files ({len(changed)}):")
    for f in changed:
        print(f"  {f}")
    print()

    all_failures = []

    # --- Java ---
    jacoco = parse_jacoco(args.jacoco_xml)
    if jacoco:
        java_failures = check_java_coverage(changed, jacoco, threshold, args.repo_root)
        all_failures.extend(java_failures)
    else:
        print("No JaCoCo report found — skipping Java coverage check.")

    # --- Flutter ---
    lcov = parse_lcov(args.lcov_info)
    if lcov:
        flutter_failures = check_flutter_coverage(changed, lcov, threshold)
        all_failures.extend(flutter_failures)
    else:
        print("No lcov report found — skipping Flutter coverage check.")

    # --- Report ---
    if not all_failures:
        print(f"✅ All changed files meet the {threshold:.0%} coverage threshold.")
        sys.exit(0)

    print(f"❌ {len(all_failures)} file(s) below the {threshold:.0%} coverage threshold:\n")
    for file_path, ratio in sorted(all_failures):
        if ratio == 0.0:
            coverage_str = "0% (no tests ran for this file)"
        else:
            coverage_str = f"{ratio:.1%}"
        print(f"  {file_path}: {coverage_str}")

    print(f"\nAdd or update tests for the files above to reach {threshold:.0%} line coverage.")
    sys.exit(1)


if __name__ == "__main__":
    main()
