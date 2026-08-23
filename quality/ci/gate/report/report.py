"""
Report Generation Entry Point (Layer 4)

Reads evaluated.json and normalized.json and produces:

- quality/analysis/report.md
    Markdown report used for pull request comments and job summaries
- quality/analysis/report.html
    Rich HTML report suitable for download or artifact viewing

Delegates to
------------
- report_md.py
    Markdown report builder
- report_html.py
    HTML report builder
- report_github.py
    Pull request comment poster

Execution
---------
python -m quality.ci.gate.report.report
"""

import json
import os
import sys
from pathlib import Path

import yaml

from quality.ci.gate.report.report_github import post_or_update_pr_comment
from quality.ci.gate.report.report_html import build_html_report
from quality.ci.gate.report.report_md import build_markdown_report


ANALYSIS_DIR = Path("quality/analysis")
EVALUATED_FILE = ANALYSIS_DIR / "evaluated" / "evaluated.json"
NORMALIZED_FILE = ANALYSIS_DIR / "normalized" / "normalized.json"
REPORT_MD_FILE = ANALYSIS_DIR / "report.md"
REPORT_HTML_FILE = ANALYSIS_DIR / "report.html"
POLICY_FILE = Path("quality/ci/gate/policy.yaml")


def _load_gate_mode() -> str:
    """
    Read gate.mode from policy.yaml.

    Returns "enforce" as a fail-safe default so the report never
    silently under-reports enforcement status.

    Returns
    -------
    str
        "report_only" or "enforce"
    """
    try:
        with open(POLICY_FILE, "r", encoding="utf-8") as fh:
            data = yaml.safe_load(fh) or {}
        mode = str((data.get("gate", {}) or {}).get("mode", "enforce")).strip().lower()
        return mode if mode in {"enforce", "report_only"} else "enforce"
    except (OSError, TypeError, ValueError, yaml.YAMLError):
        return "enforce"


def _get_env() -> dict:
    """
    Collect GitHub Actions environment metadata used for report generation.

    Returns
    -------
    dict
        Environment values used by markdown, HTML, and pull request
        comment generation.
    """
    return {
        "event_name": os.environ.get("GITHUB_EVENT_NAME", "unknown"),
        "run_number": os.environ.get("GITHUB_RUN_NUMBER", "?"),
        "run_id": os.environ.get("GITHUB_RUN_ID", ""),
        "sha": os.environ.get("GITHUB_SHA", ""),
        "server_url": os.environ.get("GITHUB_SERVER_URL", "https://github.com"),
        "repository": os.environ.get("GITHUB_REPOSITORY", ""),
        "actor": os.environ.get("GITHUB_ACTOR", "unknown"),
        "head_ref": os.environ.get("GITHUB_HEAD_REF", ""),
        "base_ref": os.environ.get("GITHUB_BASE_REF", ""),
        "pr_number": os.environ.get("PR_NUMBER", ""),
        "scan_root": os.environ.get("SCAN_ROOT", "."),
        "token": os.environ.get("GITHUB_TOKEN", ""),
        "gate_mode": _load_gate_mode(),
    }


def generate_report() -> None:
    """
    Generate markdown and HTML quality gate reports.

    This function loads evaluated.json, renders both report formats,
    writes them to the analysis directory, and posts or updates the
    pull request comment when running in a pull request context.

    Raises
    ------
    SystemExit
        Exits with status code 1 if evaluated.json is missing or invalid.
    """
    env = _get_env()

    if not EVALUATED_FILE.exists():
        print(f"[report] evaluated.json not found at {EVALUATED_FILE}.")
        sys.exit(1)

    try:
        with open(EVALUATED_FILE, "r", encoding="utf-8") as file_handle:
            evaluated_doc = json.load(file_handle)
    except (OSError, json.JSONDecodeError) as e:
        print(f"[report] Failed to parse evaluated.json: {e}")
        sys.exit(1)

    REPORT_MD_FILE.parent.mkdir(parents=True, exist_ok=True)

    md_body = build_markdown_report(evaluated_doc, env)
    REPORT_MD_FILE.write_text(md_body, encoding="utf-8")
    print(f"[report] report.md written to: {REPORT_MD_FILE}")

    html_body = build_html_report(evaluated_doc, env)
    REPORT_HTML_FILE.write_text(html_body, encoding="utf-8")
    print(f"[report] report.html written to: {REPORT_HTML_FILE}")

    if env["event_name"] == "pull_request" and env["pr_number"]:
        post_or_update_pr_comment(md_body, env)
    else:
        print("[report] Not a PR event. Skipping PR comment.")


if __name__ == "__main__":
    generate_report()
    