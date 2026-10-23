#!/usr/bin/env python3
"""
scripts/coverage_gate.py
------------------------
Diff coverage gate: of the executable lines a PR adds or modifies in source
files, at least --threshold must be covered by tests.

Usage:
    python scripts/coverage_gate.py \
        --diff-base <git-sha> \
        --threshold 0.80 \
        --jacoco-xml backend/core/target/site/jacoco/jacoco.xml \
        --lcov-info frontend/coverage/lcov.info \
        --repo-root .

Only changed lines are scored, so a small edit to a large, poorly covered
file is judged on the edit, and a file whose diff only deletes lines is not
scored at all. Lines the coverage tool does not instrument (comments, blank
lines, declarations) are ignored.

Files listed in scripts/test-exemptions.txt, and files with no executable
code, are skipped. A changed source file missing from its coverage report
(no test ran it) fails, unless its diff only deletes lines.

Exit codes:
    0  Every changed source file meets the threshold on its changed lines
    1  One or more changed source files are below the threshold
"""

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

from test_mapping import get_added_lines, get_changed_files, load_exemptions, needs_test


THRESHOLD_DEFAULT = 0.80

# {repo-relative source path -> {line number -> covered?}} for instrumented lines
LineCoverage = dict[str, dict[int, bool]]


# ---------------------------------------------------------------------------
# Report parsing
# ---------------------------------------------------------------------------

def parse_jacoco(jacoco_xml: str) -> LineCoverage:
    """
    Per-line coverage from JaCoCo XML, keyed by repo path
    (backend/core/src/main/java/com/example/Foo.java). Inner classes share
    their outer class's source file, so they are included automatically.
    Returns an empty dict if the report doesn't exist.
    """
    path = Path(jacoco_xml)
    if not path.exists():
        return {}

    coverage: LineCoverage = {}
    root = ET.parse(path).getroot()
    for package in root.findall("package"):
        pkg = package.attrib.get("name", "")
        for source in package.findall("sourcefile"):
            key = f"backend/core/src/main/java/{pkg}/{source.attrib['name']}"
            lines = coverage.setdefault(key, {})
            for line in source.findall("line"):
                nr = int(line.attrib["nr"])
                lines[nr] = int(line.attrib.get("ci", 0)) > 0
    return coverage


def parse_lcov(lcov_info: str) -> LineCoverage:
    """
    Per-line coverage from lcov.info (DA:<line>,<hits>), keyed by repo path
    (frontend/lib/foo/bar.dart). Returns an empty dict if the file doesn't exist.
    """
    path = Path(lcov_info)
    if not path.exists():
        return {}

    coverage: LineCoverage = {}
    current = None
    with open(path, encoding="utf-8") as f:
        for raw in f:
            line = raw.strip()
            if line.startswith("SF:"):
                # lcov paths are relative to frontend/; normalize separators and "./"
                rel = line[3:].replace("\\", "/").removeprefix("./")
                current = coverage.setdefault(f"frontend/{rel}", {})
            elif line.startswith("DA:") and current is not None:
                nr, hits = line[3:].split(",")[:2]
                current[int(nr)] = int(hits) > 0
            elif line == "end_of_record":
                current = None
    return coverage


# ---------------------------------------------------------------------------
# Gate
# ---------------------------------------------------------------------------

def check_diff_coverage(
    changed_files: list[str],
    added_lines: dict[str, set[int]],
    coverage: LineCoverage,
    threshold: float,
    repo_root: str,
    exemptions: list[str],
) -> list[tuple[str, float, int, int]]:
    """
    Returns (file, ratio, covered, executable) for each changed source file
    whose changed executable lines are below the threshold.
    """
    failures = []
    for f in changed_files:
        if not needs_test(f, exemptions, repo_root):
            continue
        changed = added_lines.get(f, set())
        if not changed:
            continue  # deletion-only diff: no new code to cover

        if f not in coverage:
            # No test executed this file at all.
            failures.append((f, 0.0, 0, len(changed)))
            continue

        file_lines = coverage[f]
        executable = [n for n in changed if n in file_lines]
        if not executable:
            continue  # only comments, blank lines or declarations changed
        covered = sum(1 for n in executable if file_lines[n])
        ratio = covered / len(executable)
        if ratio < threshold:
            failures.append((f, ratio, covered, len(executable)))
    return failures


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def main():
    parser = argparse.ArgumentParser(description="Diff coverage gate for changed lines")
    parser.add_argument("--diff-base", required=True, help="Git SHA to diff against")
    parser.add_argument("--threshold", type=float, default=THRESHOLD_DEFAULT,
                        help="Minimum coverage ratio of changed lines (default: 0.80)")
    parser.add_argument("--jacoco-xml", default="backend/core/target/site/jacoco/jacoco.xml")
    parser.add_argument("--lcov-info", default="frontend/coverage/lcov.info")
    parser.add_argument("--repo-root", default=".")
    args = parser.parse_args()

    threshold = args.threshold
    print(f"\nDiff coverage gate — threshold: {threshold:.0%} of changed executable lines")
    print(f"Diff base: {args.diff_base}\n")

    changed = get_changed_files(args.diff_base, args.repo_root)
    if not changed:
        print("No changed files found. Skipping coverage check.")
        sys.exit(0)

    print(f"Changed files ({len(changed)}):")
    for f in changed:
        print(f"  {f}")
    print()

    exemptions = load_exemptions(args.repo_root)
    added = get_added_lines(args.diff_base, args.repo_root)

    # A missing report is not a pass: changed sources absent from it fail below.
    jacoco = parse_jacoco(args.jacoco_xml)
    if not jacoco:
        print("No JaCoCo report found — changed backend lines count as uncovered.")
    lcov = parse_lcov(args.lcov_info)
    if not lcov:
        print("No lcov report found — changed frontend lines count as uncovered.")

    failures = check_diff_coverage(
        changed, added, {**jacoco, **lcov}, threshold, args.repo_root, exemptions
    )

    if not failures:
        print(f"✅ Changed lines in every changed source file meet the {threshold:.0%} threshold.")
        sys.exit(0)

    print(f"❌ {len(failures)} file(s) below {threshold:.0%} coverage on their changed lines:\n")
    for file_path, ratio, covered, executable in sorted(failures):
        if covered == 0 and ratio == 0.0 and file_path not in {**jacoco, **lcov}:
            detail = "no test ran this file"
        else:
            detail = f"{covered}/{executable} changed lines covered"
        print(f"  {file_path}: {ratio:.1%} ({detail})")

    print(f"\nAdd or update tests that exercise the changed lines to reach {threshold:.0%}.")
    sys.exit(1)


if __name__ == "__main__":
    main()
