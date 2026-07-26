#!/usr/bin/env bash
# coverage-gate.sh
# Team B CI — per-module coverage enforcement with a no-regression ratchet.
#
# Parses frontend/coverage/lcov.info (Flutter) and
# backend/core/target/site/jacoco/jacoco.xml (Maven/JaCoCo), then enforces:
#
#   1. NO-REGRESSION (hard, blocking): a "hard" module may never drop below
#      its committed baseline in scripts/coverage-baseline.json. A drop is a
#      "dip" and fails the build (exit 1). This is what stops other teams'
#      merges from dragging Team B coverage down.
#   2. ASPIRATIONAL TARGET (warn, non-blocking): if a module is at/above its
#      baseline but still below its target (e.g. 100%/95%), it emits a warning
#      comment but does NOT block. Close the gap by ratcheting the baseline up.
#   3. Visual/UI modules (lib/widgets, lib/components) are always warn-only.
#
# The baseline only moves UP: run in baseline mode (GATE_MODE=baseline) after
# coverage improves to lock in the gain, e.g. on a green build of a protected
# branch. Regenerating never lowers a recorded baseline.
#
# Usage:
#   scripts/coverage-gate.sh <repo_root> [pr_number] [github_token]      # check (default)
#   GATE_MODE=baseline scripts/coverage-gate.sh <repo_root>             # emit/ratchet baseline
#
# Environment:
#   GITHUB_REPOSITORY — owner/repo (set automatically in GitHub Actions)
#   GATE_MODE         — "check" (default) or "baseline"
#   BASELINE_FILE     — override baseline path (default <repo_root>/scripts/coverage-baseline.json)
#   REGRESSION_TOLERANCE — allowed float slack in pp before a drop counts (default 0.3)

set -euo pipefail

REPO_ROOT="${1:-.}"
PR_NUMBER="${2:-}"
GITHUB_TOKEN="${3:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"
GATE_MODE="${GATE_MODE:-check}"
BASELINE_FILE="${BASELINE_FILE:-${REPO_ROOT}/scripts/coverage-baseline.json}"
REGRESSION_TOLERANCE="${REGRESSION_TOLERANCE:-0.3}"

LCOV_FILE="${REPO_ROOT}/frontend/coverage/lcov.info"
JACOCO_FILE="${REPO_ROOT}/backend/core/target/site/jacoco/jacoco.xml"

# ------------------------------------------------------------------
# Delegate all parsing and threshold logic to embedded Python.
# Python 3.6+ is available on ubuntu-latest; no extra packages needed.
# ------------------------------------------------------------------
python3 - \
    "$LCOV_FILE" \
    "$JACOCO_FILE" \
    "$PR_NUMBER" \
    "$GITHUB_TOKEN" \
    "$GITHUB_REPOSITORY" \
    "$GATE_MODE" \
    "$BASELINE_FILE" \
    "$REGRESSION_TOLERANCE" \
    <<'PYEOF'
import sys
import os
import json
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from collections import defaultdict

lcov_path      = sys.argv[1]
jacoco_path    = sys.argv[2]
pr_number      = sys.argv[3]
github_token   = sys.argv[4]
github_repo    = sys.argv[5]
gate_mode      = sys.argv[6]
baseline_file  = sys.argv[7]
tolerance      = float(sys.argv[8])

# ------------------------------------------------------------------
# Threshold definitions
# Each entry: (path_prefix, req_line_pct, req_branch_pct, severity)
#   severity "hard" = subject to the no-regression ratchet (can block)
#   severity "warn" = comment only, never blocks
#   req_line/req_branch = ASPIRATIONAL target (warn when unmet but no dip)
#   req_branch_pct = None means branch threshold not enforced
#
# Frontend entries match against the SF: path from lcov.
# Backend entries match against JaCoCo package paths (/ separators).
# ------------------------------------------------------------------
FRONTEND_THRESHOLDS = [
    ("lib/features/shift_scheduling", 100.0, 100.0, "hard"),
    ("lib/features/evv",              100.0, 100.0, "hard"),
    ("lib/features/auth",              95.0,  95.0, "hard"),
    ("lib/features/authentication",    95.0,  95.0, "hard"),
    ("lib/features/messaging",         95.0,  95.0, "hard"),
    ("lib/features/chime",             95.0,  95.0, "hard"),
    ("lib/features/billing",           95.0,  90.0, "hard"),
    ("lib/features/communication",     95.0,  90.0, "hard"),
    ("lib/features/wearable",          95.0,  90.0, "hard"),
    ("lib/features/ai",                95.0,  90.0, "hard"),
    ("lib/features/database",          95.0,  90.0, "hard"),
    ("lib/widgets",                    90.0,  None, "warn"),
    ("lib/components",                 90.0,  None, "warn"),
]

BACKEND_THRESHOLDS = [
    ("com/careconnect/service/schedule",    100.0, 100.0, "hard"),
    ("com/careconnect/model/schedule",      100.0, 100.0, "hard"),
    ("com/careconnect/repository/schedule", 100.0, 100.0, "hard"),
    ("com/careconnect/dto/schedule",        100.0, 100.0, "hard"),
    ("com/careconnect/service/evv",         100.0, 100.0, "hard"),
    ("com/careconnect/model/evv",           100.0, 100.0, "hard"),
    ("com/careconnect/repository/evv",      100.0, 100.0, "hard"),
    ("com/careconnect/dto/evv",             100.0, 100.0, "hard"),
    ("com/careconnect/security",             95.0,  95.0, "hard"),
    ("com/careconnect/service/security",     95.0,  95.0, "hard"),
    ("com/careconnect/service/chat",         95.0,  95.0, "hard"),
    ("com/careconnect/notifications",        95.0,  90.0, "hard"),
    ("com/careconnect/service",              95.0,  90.0, "hard"),
    ("com/careconnect/controller",           95.0,  90.0, "hard"),
]


# ------------------------------------------------------------------
# lcov parser — returns per-file (lh, lf, brh, brf) and per-module
# aggregates grouped by the first 3 path segments.
# ------------------------------------------------------------------
def parse_lcov(path):
    try:
        with open(path) as f:
            raw = f.readlines()
    except FileNotFoundError:
        return {}, {}

    file_totals = {}
    current_sf = None
    cur = [0, 0, 0, 0]

    for line in raw:
        line = line.strip()
        if line.startswith("SF:"):
            current_sf = line[3:]
            cur = [0, 0, 0, 0]
        elif line.startswith("DA:") and current_sf:
            parts = line[3:].split(",")
            cur[1] += 1
            if int(parts[1]) > 0:
                cur[0] += 1
        elif line.startswith("BRH:") and current_sf:
            cur[2] += int(line[4:])
        elif line.startswith("BRF:") and current_sf:
            cur[3] += int(line[4:])
        elif line == "end_of_record" and current_sf:
            file_totals[current_sf] = cur[:]
            current_sf = None
            cur = [0, 0, 0, 0]

    file_data = {}
    for sf, (lh, lf, brh, brf) in file_totals.items():
        file_data[sf] = round(lh / lf * 100, 1) if lf > 0 else 100.0

    module_data = defaultdict(lambda: [0, 0, 0, 0])
    for sf, (lh, lf, brh, brf) in file_totals.items():
        parts = sf.split("/")
        prefix = "/".join(parts[:3]) if len(parts) >= 3 else "/".join(parts[:2])
        module_data[prefix][0] += lh
        module_data[prefix][1] += lf
        module_data[prefix][2] += brh
        module_data[prefix][3] += brf

    return dict(module_data), file_data


# ------------------------------------------------------------------
# JaCoCo XML parser — returns per-package (lh, lf, brh, brf).
# ------------------------------------------------------------------
def parse_jacoco(path):
    try:
        tree = ET.parse(path)
    except (FileNotFoundError, ET.ParseError):
        return {}

    root = tree.getroot()
    packages = {}

    for pkg in root.findall(".//package"):
        pkg_name = pkg.get("name", "")
        lh = lf = brh = brf = 0
        for counter in pkg.findall("counter"):
            ctype   = counter.get("type", "")
            covered = int(counter.get("covered", 0))
            missed  = int(counter.get("missed", 0))
            if ctype == "LINE":
                lh = covered
                lf = covered + missed
            elif ctype == "BRANCH":
                brh = covered
                brf = covered + missed
        packages[pkg_name] = (lh, lf, brh, brf)

    return packages


def pct(hit, total):
    if total == 0:
        return 100.0
    return round(hit / total * 100, 1)


# ------------------------------------------------------------------
# Aggregate a threshold prefix across all matching parsed modules.
# Returns (matched, lh, lf, brh, brf).
# ------------------------------------------------------------------
def aggregate(prefix, parsed, backend=False):
    # Match on path-segment boundaries so a prefix never swallows a sibling
    # module: "lib/features/ai" must NOT absorb "lib/features/ai_hitl", and
    # "lib/features/auth" must NOT absorb "lib/features/authentication".
    total = [0, 0, 0, 0]
    matched = False
    for key, (lh, lf, brh, brf) in parsed.items():
        hit = key == prefix or key.startswith(prefix + "/")
        if hit:
            matched = True
            total[0] += lh
            total[1] += lf
            total[2] += brh
            total[3] += brf
    return matched, total[0], total[1], total[2], total[3]


# ------------------------------------------------------------------
# Baseline load/save. Shape:
#   {"frontend": {prefix: {"line": x, "branch": y|null}}, "backend": {...}}
# ------------------------------------------------------------------
def load_baseline():
    try:
        with open(baseline_file) as f:
            data = json.load(f)
    except (FileNotFoundError, ValueError):
        return {"frontend": {}, "backend": {}}
    data.setdefault("frontend", {})
    data.setdefault("backend", {})
    return data


# ------------------------------------------------------------------
# CHECK MODE — enforce ratchet + aspirational target.
# Returns (passed, message, is_regression).
# ------------------------------------------------------------------
def check_module(label, lh, lf, brh, brf, req_line, req_branch, severity,
                 base_line, base_branch, file_data):
    actual_line = pct(lh, lf)
    actual_branch = pct(brh, brf) if brf > 0 else None
    branch_str = f"{actual_branch}%" if actual_branch is not None else "N/A"

    # --- Regression check (hard modules only) ---
    regressions = []
    if severity == "hard":
        if base_line is not None and actual_line < base_line - tolerance:
            regressions.append(
                f"  Line coverage: {actual_line}% dropped below baseline {base_line}% "
                f"(target {req_line}%)")
        if (base_branch is not None and req_branch is not None and brf > 0
                and actual_branch < base_branch - tolerance):
            regressions.append(
                f"  Branch coverage: {actual_branch}% dropped below baseline {base_branch}% "
                f"(target {req_branch}%)")

    if regressions:
        lines = [f"COVERAGE REGRESSION (dip): {label}"] + regressions
        below = []
        for filepath, file_pct in sorted(file_data.items()):
            if filepath.startswith(label) and file_pct < actual_line:
                below.append(f"    - {os.path.basename(filepath)}: {file_pct}%")
        if below:
            lines.append("  Lowest-covered files in this module:")
            lines.extend(below[:8])
        lines.append("  Restore coverage to at least the baseline before merging.")
        return False, "\n".join(lines), True

    # --- Aspirational target (warn only) ---
    line_below   = req_line is not None and actual_line < req_line
    branch_below = (req_branch is not None and actual_branch is not None
                    and actual_branch < req_branch)
    if line_below or branch_below:
        base_str = f"{base_line}%" if base_line is not None else "none"
        msg = (f"{label}: line={actual_line}% branch={branch_str} "
               f"below target (line {req_line}% / branch {req_branch}%), "
               f"baseline={base_str} — no regression, ratchet up when ready")
        return False, msg, False

    return True, f"  [PASS] {label}: line={actual_line}% branch={branch_str}", False


def post_pr_comment(body):
    if not pr_number or not github_token or not github_repo:
        return
    url  = f"https://api.github.com/repos/{github_repo}/issues/{pr_number}/comments"
    data = json.dumps({"body": body}).encode("utf-8")
    req  = urllib.request.Request(
        url, data=data,
        headers={
            "Authorization": f"token {github_token}",
            "Content-Type": "application/json",
            "Accept": "application/vnd.github.v3+json",
        },
        method="POST",
    )
    try:
        urllib.request.urlopen(req, timeout=10)
    except urllib.error.URLError:
        pass


# ==================================================================
# BASELINE MODE — compute current coverage and ratchet the file UP.
# ==================================================================
def run_baseline_mode():
    baseline = load_baseline()
    module_fe, _ = parse_lcov(lcov_path)
    jacoco       = parse_jacoco(jacoco_path)

    def ratchet(section, thresholds, parsed, backend):
        if not parsed:
            print(f"  {section}: no coverage data found — preserving existing "
                  f"baseline ({len(baseline[section])} module(s)).")
            return
        for (prefix, _rl, req_branch, severity) in thresholds:
            matched, lh, lf, brh, brf = aggregate(prefix, parsed, backend)
            if not matched:
                continue
            cur_line   = pct(lh, lf)
            cur_branch = pct(brh, brf) if brf > 0 else None
            prev = baseline[section].get(prefix, {})
            new_line = max(cur_line, prev.get("line", 0.0))
            if cur_branch is None:
                new_branch = prev.get("branch")
            else:
                pb = prev.get("branch")
                new_branch = cur_branch if pb is None else max(cur_branch, pb)
            baseline[section][prefix] = {"line": round(new_line, 1),
                                         "branch": new_branch}
            arrow = "↑" if new_line > prev.get("line", 0.0) else "="
            print(f"  {section}: {prefix} line {new_line}% {arrow} branch {new_branch}")

    print("=== Coverage Baseline (ratchet up) ===\n")
    ratchet("frontend", FRONTEND_THRESHOLDS, module_fe, backend=False)
    ratchet("backend",  BACKEND_THRESHOLDS,  jacoco,    backend=True)

    baseline["_comment"] = ("Auto-generated no-regression baseline for coverage-gate.sh. "
                            "Values only ratchet UP. Regenerate with "
                            "GATE_MODE=baseline scripts/coverage-gate.sh .")
    os.makedirs(os.path.dirname(baseline_file), exist_ok=True)
    with open(baseline_file, "w") as f:
        json.dump(baseline, f, indent=2, sort_keys=True)
        f.write("\n")
    print(f"\nWrote baseline -> {baseline_file}")
    sys.exit(0)


# ==================================================================
# CHECK MODE
# ==================================================================
def run_check_mode():
    baseline = load_baseline()
    have_baseline = bool(baseline["frontend"] or baseline["backend"])

    hard_failures = []   # regressions (block)
    warnings      = []   # below-target, no regression

    print("=== Coverage Gate (no-regression ratchet) ===")
    if not have_baseline:
        print("NOTE: no baseline recorded yet — running in warn-only mode until "
              "scripts/coverage-baseline.json is seeded (GATE_MODE=baseline).")
    print()

    def run_section(title, thresholds, parsed, section, backend, file_data):
        print(f"--- {title} ---")
        if not parsed:
            print(f"  WARNING: coverage data not found or empty — skipping {title}.")
            print()
            return
        for (prefix, req_line, req_branch, severity) in thresholds:
            matched, lh, lf, brh, brf = aggregate(prefix, parsed, backend)
            if not matched:
                continue
            base = baseline[section].get(prefix, {})
            passed, msg, is_reg = check_module(
                prefix, lh, lf, brh, brf, req_line, req_branch, severity,
                base.get("line"), base.get("branch"), file_data)
            if passed:
                print(msg)
            elif is_reg:
                print(f"  [FAIL] {msg}")
                hard_failures.append(msg)
            else:
                print(f"  [WARN] {msg}")
                warnings.append(msg)
        print()

    module_fe, file_data = parse_lcov(lcov_path)
    run_section("Frontend (Flutter / lcov)", FRONTEND_THRESHOLDS, module_fe,
                "frontend", False, file_data)

    jacoco = parse_jacoco(jacoco_path)
    run_section("Backend (Maven / JaCoCo)", BACKEND_THRESHOLDS, jacoco,
                "backend", True, {})

    # ---- PR comment ----
    if hard_failures or warnings:
        parts = []
        if hard_failures:
            parts.append("## ❌ Coverage Gate — REGRESSION (blocking)\n")
            parts.append("Coverage dropped below the committed baseline. "
                         "Restore it before merging.\n")
            parts.extend(f"```\n{m}\n```" for m in hard_failures)
        if warnings:
            parts.append("## ⚠️ Coverage Gate — below target (non-blocking)\n")
            parts.extend(f"```\n{m}\n```" for m in warnings)
        post_pr_comment("\n\n".join(parts))

    # ---- Final result ----
    if hard_failures:
        print("=== COVERAGE GATE: FAILED (regression / dip) ===\n")
        for m in hard_failures:
            print(m)
            print()
        sys.exit(1)

    print("=== COVERAGE GATE: PASSED (no regression) ===")
    if warnings:
        print("\nBelow-target warnings (non-blocking):")
        for m in warnings:
            print(f"  {m}")
    sys.exit(0)


if gate_mode == "baseline":
    run_baseline_mode()
else:
    run_check_mode()
PYEOF
