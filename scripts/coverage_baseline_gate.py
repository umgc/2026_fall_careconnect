#!/usr/bin/env python3
"""
scripts/coverage_baseline_gate.py
----------------------------------
Whole-repo coverage regression gate for the team-*-develop -> develop
merge stage.

Unlike scripts/coverage_gate.py (which checks only files changed in a
diff against a 95% threshold at the feature/* -> team-*-develop stage),
this checks the AGGREGATE, whole-project line coverage against a fixed
baseline, so a team-level merge can't quietly erode overall coverage.

Usage:
    python scripts/coverage_baseline_gate.py \
        --jacoco-xml backend/core/target/site/jacoco/jacoco.xml \
        --threshold 0.80

    python scripts/coverage_baseline_gate.py \
        --lcov-info frontend/coverage/lcov.info \
        --threshold 0.70

If --threshold is omitted or empty, the gate is report-only: it prints
the current aggregate coverage and always exits 0.

Exit codes:
    0  Coverage >= threshold, OR threshold not set (report-only),
       OR no report file found (nothing to check yet)
    1  Coverage below threshold
"""

import argparse
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def aggregate_jacoco_line_coverage(jacoco_xml: str) -> tuple[int, int] | None:
    """Return (covered, missed) whole-report LINE counts, or None if no report."""
    path = Path(jacoco_xml)
    if not path.exists():
        return None

    root = ET.parse(path).getroot()

    # The report-level <counter> elements are direct children of <report>,
    # appearing after every <package>, and represent the whole-repo
    # aggregate — not a per-class or per-package total.
    for counter in root.findall("counter"):
        if counter.attrib.get("type") == "LINE":
            missed = int(counter.attrib.get("missed", 0))
            covered = int(counter.attrib.get("covered", 0))
            return covered, missed

    return None


def aggregate_lcov_line_coverage(lcov_info: str) -> tuple[int, int] | None:
    """Return (lines_hit, lines_found) totals across every SF block, or None."""
    path = Path(lcov_info)
    if not path.exists():
        return None

    total_lf = 0
    total_lh = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("LF:"):
                total_lf += int(line[3:])
            elif line.startswith("LH:"):
                total_lh += int(line[3:])

    if total_lf == 0:
        return None
    return total_lh, total_lf


def main():
    parser = argparse.ArgumentParser(description="Whole-repo coverage regression gate")
    parser.add_argument("--jacoco-xml", help="Path to JaCoCo XML report")
    parser.add_argument("--lcov-info", help="Path to lcov.info report")
    parser.add_argument(
        "--threshold",
        default="",
        help="Minimum aggregate coverage ratio (e.g. 0.80). "
             "Empty = report-only, always passes.",
    )
    args = parser.parse_args()

    if not args.jacoco_xml and not args.lcov_info:
        print("ERROR: pass --jacoco-xml and/or --lcov-info", file=sys.stderr)
        sys.exit(1)

    threshold = None
    if args.threshold.strip():
        try:
            threshold = float(args.threshold)
        except ValueError:
            print(f"ERROR: --threshold '{args.threshold}' is not a number", file=sys.stderr)
            sys.exit(1)

    failures = []

    if args.jacoco_xml:
        result = aggregate_jacoco_line_coverage(args.jacoco_xml)
        if result is None:
            print(f"No JaCoCo report found at {args.jacoco_xml} — skipping.")
        else:
            covered, missed = result
            total = covered + missed
            ratio = covered / total if total else 1.0
            label = f"Backend (JaCoCo): {ratio:.1%} line coverage ({covered}/{total} lines)"
            if threshold is None:
                print(f"{label} — report-only, no baseline set yet.")
            elif ratio < threshold:
                failures.append((label, ratio, threshold))
            else:
                print(f"{label} — meets {threshold:.0%} baseline.")

    if args.lcov_info:
        result = aggregate_lcov_line_coverage(args.lcov_info)
        if result is None:
            print(f"No lcov report found at {args.lcov_info} — skipping.")
        else:
            hit, found = result
            ratio = hit / found if found else 1.0
            label = f"Frontend (lcov): {ratio:.1%} line coverage ({hit}/{found} lines)"
            if threshold is None:
                print(f"{label} — report-only, no baseline set yet.")
            elif ratio < threshold:
                failures.append((label, ratio, threshold))
            else:
                print(f"{label} — meets {threshold:.0%} baseline.")

    if failures:
        print("\n❌ Coverage regression detected:")
        for label, ratio, thr in failures:
            print(f"  {label} is below the {thr:.0%} baseline.")
        sys.exit(1)

    sys.exit(0)


if __name__ == "__main__":
    main()
