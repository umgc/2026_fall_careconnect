"""
Markdown Report Builder

Builds the markdown report string consumed by:

- GitHub Actions job summary
- Pull request comment

Functions
---------
build_markdown_report(evaluated_doc, env) -> str
    Build the complete markdown quality gate report.

Language Contract (per professor's guidance, 2026-08-22)
---------------------------------------------------------
- REPORT ONLY : gate.mode = report_only, findings detected.
                The PR is NOT blocked regardless of finding counts.
- PASSED      : No violations detected (any gate mode).
- BLOCKED     : gate.mode = enforce AND blocking violations exist.
                GitHub branch protection actually prevents the merge.

Role column contract:
- Advisory / Report Only : gate.mode = report_only (no merge is blocked).
- Enforced               : gate.mode = enforce AND tool is blocking=True.
- Advisory               : tool is blocking=False (any gate mode).

Secrets (TruffleHog / Gitleaks) are called out separately because they
should be investigated even when the gate is in report_only mode.
"""

from datetime import datetime, timezone

from quality.ci.gate.report.report_constants import (
    CATEGORY_MAP,
    _MD_TABLE_HEADER,
    _MD_TABLE_SEPARATOR,
)


PR_COMMENT_MARKER = "## CareConnect — Security & Quality Analysis Report"

_SECRETS_TOOLS = {"trufflehog", "gitleaks"}


def _role_label(blocking: bool, gate_mode: str) -> str:
    """
    Return the Role column value for a tool row.

    Parameters
    ----------
    blocking : bool
        Whether the tool is configured as blocking in policy.yaml.
    gate_mode : str
        Current gate mode: "report_only" or "enforce".

    Returns
    -------
    str
        Human-readable role label.
    """
    if not blocking:
        return "Advisory"
    if gate_mode == "report_only":
        return "Advisory / Report Only"
    return "Enforced"


def _summary_row(result: dict, gate_mode: str) -> str:
    """Build one markdown summary row for a tool result."""
    tool = result.get("tool", "unknown")
    category = CATEGORY_MAP.get(tool, "Analysis")
    violation = result.get("policy_violation", False)
    blocking = result.get("blocking", False)
    reason = result.get("reason", "")
    normalized = result.get("normalized", {})
    finding_count = normalized.get("violation_count", 0)
    findings_label = f"{finding_count} finding(s)" if finding_count else "—"

    if reason == "disabled":
        status = "DISABLED"
    elif violation:
        status = "FAILURE"
    else:
        status = "SUCCESS"

    role = _role_label(blocking, gate_mode)
    return f"| {tool} | {category} | {status} | {role} | {findings_label} |"


def _build_top_level_banner(overall_block: bool, gate_mode: str) -> str:
    """
    Build the top-level status banner.

    Parameters
    ----------
    overall_block : bool
        Whether the policy engine detected any blocking violations.
    gate_mode : str
        Current gate mode.

    Returns
    -------
    str
        A blockquote line suitable for the top of the report.
    """
    if not overall_block:
        return (
            "> ✅ **PASSED** — All required checks passed. No violations detected."
        )

    if gate_mode == "report_only":
        return (
            "> ℹ️ **REPORT ONLY** — Security and quality findings detected. "
            "This report does not currently block the PR. "
            "Findings are advisory only while the gate is in report-only mode."
        )

    # gate_mode == "enforce" and there are blocking violations
    return (
        "> 🚫 **BLOCKED** — One or more required checks failed. "
        "Fix the issues below before merging."
    )


def _secrets_callout(all_results: list[dict]) -> list[str]:
    """
    Build a callout section when secrets tools have findings.

    TruffleHog and Gitleaks findings should be investigated regardless
    of whether the gate is in report_only mode. A credential, token,
    or private key found in the repository should be rotated even if
    the rest of the SAST/style debt is advisory.

    Parameters
    ----------
    all_results : list[dict]
        All evaluated tool results.

    Returns
    -------
    list[str]
        Lines to insert into the report, or an empty list if no secrets
        findings were detected.
    """
    secrets_with_findings = [
        r for r in all_results
        if r.get("tool") in _SECRETS_TOOLS
        and r.get("policy_violation", False)
    ]

    if not secrets_with_findings:
        return []

    lines = [
        "### ⚠️ Secrets Scan Alert",
        "",
        "> **TruffleHog and/or Gitleaks detected potential secrets in this repository.**",
        ">",
        "> Unlike ordinary SAST or style debt, secrets findings should **not** be",
        "> dismissed simply because the gate is in report-only mode.",
        "> If any finding represents an actual credential, API token, private key,",
        "> or other active secret, it must be **investigated, removed, and rotated**",
        "> regardless of the overall gate status.",
        "",
    ]

    for r in secrets_with_findings:
        tool = r.get("tool", "unknown")
        count = r.get("normalized", {}).get("violation_count", 0)
        lines.append(f"- **{tool}**: {count} potential secret(s) detected")

    lines.append("")
    return lines


def build_markdown_report(evaluated_doc: dict, env: dict) -> str:
    """
    Build the markdown quality gate report.

    Parameters
    ----------
    evaluated_doc : dict
        Evaluated quality gate document.
    env : dict
        Environment metadata used for report rendering.
        Must include ``gate_mode`` key (added by report.py).

    Returns
    -------
    str
        Complete markdown report body.
    """
    gate_mode: str = env.get("gate_mode", "enforce")

    report_data = {
        "overall_block": bool(evaluated_doc.get("overall_block", True)),
        "blocking_results": evaluated_doc.get("blocking_results", []),
        "non_blocking_results": evaluated_doc.get("non_blocking_results", []),
    }
    report_data["all_results"] = (
        report_data["blocking_results"] + report_data["non_blocking_results"]
    )

    render_data = {
        "sha_short": env["sha"][:7] if env["sha"] else "unknown",
        "run_url": (
            f"{env['server_url']}/{env['repository']}/actions/runs/{env['run_id']}"
        ),
        "commit_url": (
            f"{env['server_url']}/{env['repository']}/commit/{env['sha']}"
        ),
        "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S UTC"),
        "approval_line": _build_top_level_banner(
            report_data["overall_block"], gate_mode
        ),
    }

    lines: list[str] = [
        "# CareConnect Quality Gate Report",
        "",
        render_data["approval_line"],
        "",
        PR_COMMENT_MARKER,
        "",
        "### Report Header",
        "",
        _MD_TABLE_HEADER,
        _MD_TABLE_SEPARATOR,
        f"| **Generated (UTC)** | {render_data['generated_at']} |",
        f"| **Pipeline Run** | [#{env['run_number']}]({render_data['run_url']}) |",
        f"| **Trigger** | `{env['event_name']}` |",
        f"| **Scan Root** | `{env['scan_root']}` |",
        f"| **Gate Mode** | `{gate_mode}` |",
        "",
        "_All timestamps are reported in Coordinated Universal Time (UTC)._",
        "",
    ]

    if env["event_name"] == "pull_request" and env["pr_number"]:
        lines += [
            "### Pull Request",
            "",
            _MD_TABLE_HEADER,
            _MD_TABLE_SEPARATOR,
            f"| **PR Number** | #{env['pr_number']} |",
            f"| **PR Author** | @{env['actor']} |",
            f"| **Source Branch** | `{env['head_ref']}` |",
            f"| **Target Branch** | `{env['base_ref']}` |",
            "",
        ]

    lines += [
        "### Commit Details",
        "",
        _MD_TABLE_HEADER,
        _MD_TABLE_SEPARATOR,
        (
            f"| **Commit SHA** | `{render_data['sha_short']}` "
            f"([full]({render_data['commit_url']})) |"
        ),
        "",
    ]

    # Secrets callout (only when findings exist)
    lines.extend(_secrets_callout(report_data["all_results"]))

    # Legend — language depends on gate mode
    if gate_mode == "report_only":
        role_enforced_row = (
            "| Advisory / Report Only | Tool is configured as blocking in policy.yaml, "
            "but the gate is in **report-only mode** — no PR is blocked |"
        )
        report_only_note = (
            "\n> **Note — Report-Only Mode:** The gate is currently running in "
            "`report_only` mode. Findings from all tools are **advisory only** "
            "and will **not** prevent merging. BLOCKED status is reserved for "
            "when `gate.mode: enforce` is active and GitHub branch protection "
            "actually prevents the merge. Use this report to understand the "
            "security and quality state of the repository."
        )
    else:
        role_enforced_row = (
            "| Enforced | Violations from this tool will block the merge |"
        )
        report_only_note = ""

    lines += [
        "### Legend",
        "",
        "| Status | Meaning |",
        "|--------|---------|",
        "| PASSED | All checks ran; no violations detected |",
        "| REPORT ONLY | Findings detected; gate is in report-only mode — PR is not blocked |",
        "| BLOCKED | Findings detected; gate is enforced — GitHub check fails and blocks merge |",
        "| SUCCESS | This tool ran and found no violations |",
        "| FAILURE | This tool found one or more violations |",
        "| DISABLED | Tool is not yet configured |",
        "",
        "| Role | Meaning |",
        "|------|---------|",
        role_enforced_row,
        "| Advisory | Violations are reported but will not block the merge |",
    ]

    if report_only_note:
        lines.append("")
        lines.append(report_only_note)

    lines += [
        "",
        "### Tool Results Summary",
        "",
        "| Tool | Category | Status | Role | Findings |",
        "|------|----------|--------|------|----------|",
    ]

    lines.extend(
        _summary_row(result, gate_mode)
        for result in report_data["all_results"]
    )

    lines += [
        "",
        "---",
        "_Full artifact bundle available in the workflow run artifacts._",
        "",
    ]

    return "\n".join(lines)
