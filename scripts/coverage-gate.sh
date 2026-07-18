#!/usr/bin/env bash
# coverage-gate.sh
# Team B CI — per-module coverage threshold enforcement.
#
# Parses frontend/coverage/lcov.info (Flutter) and
# backend/core/target/site/jacoco/jacoco.xml (Maven/JaCoCo),
# then enforces the thresholds defined in the THRESHOLDS section below.
#
# Hard failures exit 1 and block the PR.
# Visual/UI modules emit a warning comment but do not block.
#
# Usage:
#   scripts/coverage-gate.sh <repo_root> [pr_number] [github_token]
#
# Environment:
#   GITHUB_REPOSITORY — owner/repo (set automatically in GitHub Actions)

set -euo pipefail

REPO_ROOT="${1:-.}"
PR_NUMBER="${2:-}"
GITHUB_TOKEN="${3:-}"
GITHUB_REPOSITORY="${GITHUB_REPOSITORY:-}"

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
    <<'PYEOF'
import sys
import os
import json
import urllib.request
import urllib.error
import xml.etree.ElementTree as ET
from collections import defaultdict

lcov_path    = sys.argv[1]
jacoco_path  = sys.argv[2]
pr_number    = sys.argv[3]
github_token = sys.argv[4]
github_repo  = sys.argv[5]

# ------------------------------------------------------------------
# Threshold definitions
# Each entry: (path_prefix, req_line_pct, req_branch_pct, severity)
#   severity "hard" = blocks PR; "warn" = comment only
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
    """
    Returns (module_data, file_data).
    module_data: {module_prefix: {"lh": int, "lf": int, "brh": int, "brf": int}}
    file_data:   {filepath: line_pct_float}
    """
    try:
        with open(path) as f:
            raw = f.readlines()
    except FileNotFoundError:
        return {}, {}

    file_totals = {}   # filepath -> [lh, lf, brh, brf]
    current_sf = None
    cur = [0, 0, 0, 0]

    for line in raw:
        line = line.strip()
        if line.startswith("SF:"):
            current_sf = line[3:]
            cur = [0, 0, 0, 0]
        elif line.startswith("DA:") and current_sf:
            parts = line[3:].split(",")
            cur[1] += 1  # lf
            if int(parts[1]) > 0:
                cur[0] += 1  # lh
        elif line.startswith("BRH:") and current_sf:
            cur[2] += int(line[4:])
        elif line.startswith("BRF:") and current_sf:
            cur[3] += int(line[4:])
        elif line == "end_of_record" and current_sf:
            file_totals[current_sf] = cur[:]
            current_sf = None
            cur = [0, 0, 0, 0]

    # Per-file line coverage percentage
    file_data = {}
    for sf, (lh, lf, brh, brf) in file_totals.items():
        file_data[sf] = round(lh / lf * 100, 1) if lf > 0 else 100.0

    # Aggregate by module prefix (first 3 path segments)
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
    """Returns {package_path: {"lh": int, "lf": int, "brh": int, "brf": int}}"""
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
            ctype    = counter.get("type", "")
            covered  = int(counter.get("covered", 0))
            missed   = int(counter.get("missed", 0))
            if ctype == "LINE":
                lh = covered
                lf = covered + missed
            elif ctype == "BRANCH":
                brh = covered
                brf = covered + missed
        packages[pkg_name] = (lh, lf, brh, brf)

    return packages


# ------------------------------------------------------------------
# Compute actual percentage (0-100).
# ------------------------------------------------------------------
def pct(hit, total):
    if total == 0:
        return 100.0
    return round(hit / total * 100, 1)


# ------------------------------------------------------------------
# Check a single module against its threshold.
# Returns (passed: bool, message: str, severity: str).
# ------------------------------------------------------------------
def check_module(label, lh, lf, brh, brf, req_line, req_branch, severity, file_data):
    actual_line = pct(lh, lf)

    line_fail   = req_line is not None and actual_line < req_line
    branch_fail = False
    actual_branch = None

    if req_branch is not None and brf > 0:
        actual_branch = pct(brh, brf)
        branch_fail = actual_branch < req_branch

    if not line_fail and not branch_fail:
        branch_str = f"{actual_branch}%" if actual_branch is not None else "N/A"
        return True, f"  [PASS] {label}: line={actual_line}% branch={branch_str}", severity

    # Build the exact failure message format specified in the CI requirements.
    lines = [f"COVERAGE GATE FAILED: {label}"]
    if line_fail:
        lines.append(f"  Line coverage: {actual_line}% (required: {req_line}%)")
    if branch_fail:
        lines.append(f"  Branch coverage: {actual_branch}% (required: {req_branch}%)")

    # Find files in this module that are below the line threshold
    below = []
    for filepath, file_pct in sorted(file_data.items()):
        if not filepath.startswith(label):
            continue
        if req_line is not None and file_pct < req_line:
            filename = os.path.basename(filepath)
            below.append(f"    - {filename}: {file_pct}%")

    if below:
        lines.append("  Files below threshold:")
        lines.extend(below)

    lines.append("  Add unit tests before merging.")
    message = "\n".join(lines)
    return False, message, severity


# ------------------------------------------------------------------
# Post a comment to the GitHub PR.
# ------------------------------------------------------------------
def post_pr_comment(body):
    if not pr_number or not github_token or not github_repo:
        return
    url  = f"https://api.github.com/repos/{github_repo}/issues/{pr_number}/comments"
    data = json.dumps({"body": body}).encode("utf-8")
    req  = urllib.request.Request(
        url,
        data=data,
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
        pass  # Best-effort; do not fail the gate on comment errors


# ------------------------------------------------------------------
# Main
# ------------------------------------------------------------------
hard_failures = []
warnings      = []

print("=== Coverage Gate ===")
print()

# ---- Frontend (lcov) ----
print("--- Frontend (Flutter / lcov) ---")
module_data, file_data = parse_lcov(lcov_path)

if not module_data:
    print(f"  WARNING: {lcov_path} not found or empty — skipping frontend check.")
else:
    for (prefix, req_line, req_branch, severity) in FRONTEND_THRESHOLDS:
        # Aggregate across all lcov modules that start with this prefix
        total_lh = total_lf = total_brh = total_brf = 0
        matched = False
        for mod_prefix, (lh, lf, brh, brf) in module_data.items():
            if mod_prefix.startswith(prefix) or mod_prefix == prefix:
                matched = True
                total_lh  += lh
                total_lf  += lf
                total_brh += brh
                total_brf += brf

        if not matched:
            continue

        passed, msg, sev = check_module(
            prefix, total_lh, total_lf, total_brh, total_brf,
            req_line, req_branch, severity, file_data
        )
        print(msg if passed else f"  [{'FAIL' if sev == 'hard' else 'WARN'}] {msg}")
        if not passed:
            if sev == "hard":
                hard_failures.append(msg)
            else:
                warnings.append(msg)

print()

# ---- Backend (JaCoCo) ----
print("--- Backend (Maven / JaCoCo) ---")
jacoco_data = parse_jacoco(jacoco_path)

if not jacoco_data:
    print(f"  WARNING: {jacoco_path} not found or empty — skipping backend check.")
else:
    for (prefix, req_line, req_branch, severity) in BACKEND_THRESHOLDS:
        total_lh = total_lf = total_brh = total_brf = 0
        matched = False
        for pkg, (lh, lf, brh, brf) in jacoco_data.items():
            if pkg == prefix or pkg.startswith(prefix + "/"):
                matched = True
                total_lh  += lh
                total_lf  += lf
                total_brh += brh
                total_brf += brf

        if not matched:
            continue

        passed, msg, sev = check_module(
            prefix, total_lh, total_lf, total_brh, total_brf,
            req_line, req_branch, severity, {}
        )
        print(msg if passed else f"  [{'FAIL' if sev == 'hard' else 'WARN'}] {msg}")
        if not passed:
            if sev == "hard":
                hard_failures.append(msg)
            else:
                warnings.append(msg)

print()

# ---- PR comment ----
if hard_failures or warnings:
    comment_lines = []
    if hard_failures:
        comment_lines.append("## Coverage Gate — FAILED\n")
        comment_lines.extend(f"```\n{m}\n```" for m in hard_failures)
    if warnings:
        comment_lines.append("## Coverage Gate — Warnings (non-blocking)\n")
        comment_lines.extend(f"```\n{m}\n```" for m in warnings)
    post_pr_comment("\n\n".join(comment_lines))

# ---- Final result ----
if hard_failures:
    print("=== COVERAGE GATE: FAILED ===")
    print()
    for m in hard_failures:
        print(m)
        print()
    sys.exit(1)
else:
    print("=== COVERAGE GATE: PASSED ===")
    if warnings:
        print()
        print("Warnings (non-blocking):")
        for m in warnings:
            print(m)
            print()
    sys.exit(0)
PYEOF
