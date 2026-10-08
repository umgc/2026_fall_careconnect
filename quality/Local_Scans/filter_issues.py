"""
Parse gate tool outputs and filter to feature file inventory.
Usage: python filter_issues.py
"""

import xml.etree.ElementTree as ET
import re
import os
from pathlib import Path
from datetime import datetime

REPO_ROOT = Path(__file__).resolve().parents[2]
WORK_DIR = Path("C:/Users/kmsyl/AppData/Local/Temp/tmpbjh96z84")
OUT_FILE = Path("D:/670_docs/feature_issues_report_v4.txt")

# -----------------------------------------------------------------------
# Inventory — all 93 feature files (relative to repo root, forward slash)
# -----------------------------------------------------------------------
INVENTORY = {
    # Video Calling — frontend source
    "frontend/lib/services/video_call_service.dart",
    "frontend/lib/services/video_call_service_base.dart",
    "frontend/lib/services/video_call_service_web.dart",
    "frontend/lib/services/web_video_call_service.dart",
    "frontend/lib/services/hybrid_video_call_service.dart",
    "frontend/lib/services/mobile_video_call_service_web.dart",
    "frontend/lib/services/video_call_integration.dart",
    "frontend/lib/services/generic_webrtc_service.dart",
    "frontend/lib/utils/call_integration_helper.dart",
    "frontend/lib/widgets/video_call_widget.dart",
    "frontend/lib/widgets/video_widget.dart",
    "frontend/lib/widgets/hybrid_video_call_widget.dart",
    # Video Calling — frontend tests
    "frontend/test/services/video_call_service_web_test.dart",
    "frontend/test/services/hybrid_video_call_service_test.dart",
    "frontend/test/services/video_call_service_test.dart",
    "frontend/test/widgets/hybrid_video_call_widget_test.dart",
    "frontend/test/pages/video_call_test_page_test.dart",
    "frontend/integration_test/video_call_e2e_test.dart",
    # Conference Calls — frontend source
    "frontend/lib/widgets/chime_meeting_embed.dart",
    "frontend/lib/widgets/chime_meeting_embed_web.dart",
    "frontend/lib/widgets/chime_meeting_embed_mobile.dart",
    "frontend/lib/widgets/chime_meeting_embed_stub.dart",
    "frontend/lib/widgets/incoming_call_popup.dart",
    "frontend/lib/widgets/communication_widget.dart",
    "frontend/lib/services/call_notification_service.dart",
    "frontend/lib/services/communication_service.dart",
    "frontend/lib/features/communication/presentation/pages/communication_test_page.dart",
    "frontend/lib/features/health/caregiver-patient-list/widgets/patient_header_card.dart",
    "frontend/lib/features/health/caregiver-patient-list/widgets/mood_history_card.dart",
    # Conference Calls — frontend tests
    "frontend/test/features/calls/jitsi_meeting_screen_test.dart",
    "frontend/test/features/calls/telehealth_bridge_screen_test.dart",
    "frontend/test/widgets/incoming_call_popup_test.dart",
    "frontend/test/widgets/call_notification_status_indicator_test.dart",
    # Sentiment Analysis — frontend source
    "frontend/lib/widgets/sentiment_dashboard_widget.dart",
    "frontend/lib/config/theme/sentiment_colors.dart",
    # Sentiment Analysis — frontend tests
    "frontend/test/widgets/sentiment_dashboard_widget_test.dart",
    # Telemetry — frontend source
    "frontend/lib/widgets/post_call_telemetry_summary_screen.dart",
    "frontend/lib/features/telemetry/telemetry.dart",
    "frontend/lib/features/telemetry/telemetry_settings.dart",
    "frontend/lib/features/telemetry/telemetry_guardrails.dart",
    # Telemetry — frontend tests
    "frontend/test/features/telemetry/telemetry_settings_test.dart",
    "frontend/test/features/telemetry/telemetry_guardrails_test.dart",
    "frontend/test/widgets/post_call_telemetry_summary_screen_test.dart",
    # Conference Calls — backend
    "backend/core/src/main/java/com/careconnect/controller/CallController.java",
    "backend/core/src/main/java/com/careconnect/websocket/CallNotificationHandler.java",
    "backend/core/src/main/java/com/careconnect/service/ChimeService.java",
    "backend/core/src/test/java/com/careconnect/service/ChimeServiceTest.java",
    "backend/core/src/test/java/com/careconnect/controller/CallControllerTest.java",
    "backend/core/src/test/java/com/careconnect/controller/CallControllerExtendedTest.java",
    "backend/core/src/test/java/com/careconnect/websocket/CallNotificationHandlerTest.java",
    "backend/core/src/test/java/com/careconnect/integration/CallFlowIntegrationTest.java",
    # Sentiment Analysis — backend
    "backend/core/src/main/java/com/careconnect/service/BedrockSentimentService.java",
    "backend/core/src/test/java/com/careconnect/service/BedrockSentimentServiceTest.java",
    # Telemetry — backend source
    "backend/core/src/main/java/com/careconnect/controller/dev/DevTelemetryController.java",
    "backend/core/src/main/java/com/careconnect/service/CallTelemetryService.java",
    "backend/core/src/main/java/com/careconnect/service/TelemetryService.java",
    "backend/core/src/main/java/com/careconnect/service/TelemetryToggleService.java",
    "backend/core/src/main/java/com/careconnect/service/CallRecordingService.java",
    "backend/core/src/main/java/com/careconnect/service/CallSummaryService.java",
    "backend/core/src/main/java/com/careconnect/service/CallTranscriptService.java",
    "backend/core/src/main/java/com/careconnect/service/CallTranscriptArchiveService.java",
    "backend/core/src/main/java/com/careconnect/model/CallTelemetryEvent.java",
    "backend/core/src/main/java/com/careconnect/model/TelemetryEvent.java",
    "backend/core/src/main/java/com/careconnect/model/CallRecording.java",
    "backend/core/src/main/java/com/careconnect/model/CallSummary.java",
    "backend/core/src/main/java/com/careconnect/model/CallTranscriptSegment.java",
    "backend/core/src/main/java/com/careconnect/model/CallTranscriptArchive.java",
    "backend/core/src/main/java/com/careconnect/repository/CallTelemetryEventRepository.java",
    "backend/core/src/main/java/com/careconnect/repository/TelemetryEventRepository.java",
    "backend/core/src/main/java/com/careconnect/repository/CallRecordingRepository.java",
    "backend/core/src/main/java/com/careconnect/repository/CallSummaryRepository.java",
    "backend/core/src/main/java/com/careconnect/repository/CallTranscriptSegmentRepository.java",
    "backend/core/src/main/java/com/careconnect/repository/CallTranscriptArchiveRepository.java",
    # Telemetry — backend tests
    "backend/core/src/test/java/com/careconnect/service/CallTelemetryServiceTest.java",
    "backend/core/src/test/java/com/careconnect/service/CallTelemetryServiceExtendedTest.java",
    "backend/core/src/test/java/com/careconnect/service/CallRecordingServiceTest.java",
    "backend/core/src/test/java/com/careconnect/service/CallSummaryServiceTest.java",
    "backend/core/src/test/java/com/careconnect/service/CallTranscriptServiceTest.java",
    "backend/core/src/test/java/com/careconnect/service/CallTranscriptArchiveServiceTest.java",
    "backend/core/src/test/java/com/careconnect/controller/dev/DevTelemetryControllerTest.java",
    "backend/core/src/test/java/com/careconnect/model/CallTranscriptArchiveTest.java",
    # DB Migrations
    "backend/core/src/main/resources/db/migration/V34__create_telemetry_events.sql",
    "backend/core/src/main/resources/db/migration/V34.2__create_telemetry_events.sql",
    "backend/core/src/main/resources/db/migration/V36__drop_legacy_feature_telemetry_table.sql",
    "backend/core/src/main/resources/db/migration/V36.2__drop_legacy_feature_telemetry_table.sql",
    "backend/core/src/main/resources/db/migration/V37__create_call_recordings_table.sql",
    "backend/core/src/main/resources/db/migration/V37.1__create_call_recordings_table.sql",
    "backend/core/src/main/resources/db/migration/V38__add_call_recording_concatenation_fields.sql",
    "backend/core/src/main/resources/db/migration/V47__add_call_recording_concatenation_fields.sql",
    "backend/core/src/main/resources/db/migration/V51__create_call_telemetry_events.sql",
    "backend/core/src/main/resources/db/migration/V52__create_call_transcript_and_summary_tables.sql",
    "backend/core/src/main/resources/db/migration/V53__create_call_transcript_archive_table.sql",
    "backend/core/src/main/resources/db/migration/V54__create_call_recordings_table.sql",
    "backend/core/src/main/resources/db/migration/V59__create_call_telemetry_events.sql",
    "backend/core/src/main/resources/db/migration/V60__add_trace_id_index_to_telemetry_events.sql",
    "backend/core/src/main/resources/db/migration/V61__create_call_transcript_and_summary_tables.sql",
    "backend/core/src/main/resources/db/migration/V63__create_call_transcript_archive_table.sql",
}

# Normalise inventory to lowercase forward-slash for matching
INVENTORY_NORM = {p.lower().replace("\\", "/") for p in INVENTORY}


def in_inventory(abs_path: str) -> str | None:
    """Return the inventory-relative key if this path is in the inventory."""
    p = abs_path.replace("\\", "/")
    repo = str(REPO_ROOT).replace("\\", "/")
    # make relative to repo root
    if p.lower().startswith(repo.lower()):
        rel = p[len(repo):].lstrip("/")
    else:
        rel = p
    if rel.lower() in INVENTORY_NORM:
        return rel
    return None


# -----------------------------------------------------------------------
# Parsers
# -----------------------------------------------------------------------

def parse_flutter(path: Path) -> list[dict]:
    issues = []
    pattern = re.compile(
        r"^\s*(error|warning|info)\s*[-•]\s*(.+?)\s*[-•]\s*(.+?):(\d+):(\d+)\s*[-•]\s*(\S+)"
    )
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            m = pattern.match(line)
            if not m:
                continue
            severity, message, rel_file, lineno, col, rule = m.groups()
            # flutter analyze outputs paths relative to frontend/
            abs_path = str(REPO_ROOT / "frontend" / rel_file.replace("\\", "/"))
            key = in_inventory(abs_path)
            if key:
                issues.append({
                    "file": key,
                    "line": lineno,
                    "col": col,
                    "severity": severity,
                    "rule": rule,
                    "message": message.strip(),
                })
    return issues


def parse_checkstyle(path: Path) -> list[dict]:
    issues = []
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return issues
    for file_el in tree.findall(".//file"):
        fname = file_el.get("name", "")
        key = in_inventory(fname)
        if not key:
            continue
        for err in file_el.findall("error"):
            issues.append({
                "file": key,
                "line": err.get("line", "?"),
                "col": err.get("column", "?"),
                "severity": err.get("severity", "?"),
                "rule": err.get("source", "?").split(".")[-1],
                "message": err.get("message", "").strip(),
            })
    return issues


def parse_pmd(path: Path) -> list[dict]:
    issues = []
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return issues
    ns = {"pmd": "http://pmd.sourceforge.net/report/2.0.0"}
    # try with namespace first, fall back without
    files = tree.findall(".//file") or tree.findall("pmd:file", ns)
    for file_el in files:
        fname = file_el.get("name", "")
        key = in_inventory(fname)
        if not key:
            continue
        for v in file_el.findall("violation") or file_el.findall("pmd:violation", ns):
            issues.append({
                "file": key,
                "line": v.get("beginline", "?"),
                "col": v.get("begincolumn", "?"),
                "severity": f"P{v.get('priority', '?')}",
                "rule": v.get("rule", "?"),
                "message": (v.text or "").strip(),
            })
    return issues


def parse_spotbugs(path: Path) -> list[dict]:
    issues = []
    try:
        tree = ET.parse(path)
    except ET.ParseError:
        return issues
    repo_str = str(REPO_ROOT).replace("\\", "/")
    for bug in tree.findall(".//BugInstance"):
        bug_type = bug.get("type", "?")
        priority = bug.get("priority", "?")
        category = bug.get("category", "?")
        # SpotBugs stores source path relative to source root
        src = bug.find("SourceLine")
        if src is None:
            continue
        sourcepath = src.get("sourcepath", "")  # e.g. com/careconnect/service/Foo.java
        start = src.get("start", "?")
        # reconstruct likely absolute paths for main and test
        candidates = [
            f"{repo_str}/backend/core/src/main/java/{sourcepath}",
            f"{repo_str}/backend/core/src/test/java/{sourcepath}",
        ]
        key = None
        for c in candidates:
            key = in_inventory(c)
            if key:
                break
        if not key:
            continue
        msg_el = bug.find("LongMessage") or bug.find("ShortMessage")
        message = msg_el.text.strip() if msg_el is not None and msg_el.text else bug_type
        issues.append({
            "file": key,
            "line": start,
            "col": "-",
            "severity": f"P{priority}",
            "rule": f"{category}/{bug_type}",
            "message": message,
        })
    return issues


# -----------------------------------------------------------------------
# Report writer
# -----------------------------------------------------------------------

def write_report(flutter, checkstyle, pmd, spotbugs):
    # Group all issues by file
    all_issues: dict[str, list] = {}
    for tool, issues in [("Flutter", flutter), ("Checkstyle", checkstyle),
                          ("PMD", pmd), ("SpotBugs", spotbugs)]:
        for issue in issues:
            entry = {**issue, "tool": tool}
            all_issues.setdefault(issue["file"], []).append(entry)

    total = sum(len(v) for v in all_issues.values())
    now = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")

    lines = []
    lines.append("=" * 80)
    lines.append("CARECONNECT FEATURE FILE ISSUES REPORT")
    lines.append(f"Generated : {now}")
    lines.append(f"Gate run  : 2026-03-24  (commit b5237cf4)")
    lines.append(f"Files with issues : {len(all_issues)} / 93 in inventory")
    lines.append(f"Total issues      : {total}")
    lines.append(f"  Flutter Analyze : {len(flutter)}")
    lines.append(f"  Checkstyle      : {len(checkstyle)}")
    lines.append(f"  PMD             : {len(pmd)}")
    lines.append(f"  SpotBugs        : {len(spotbugs)}")
    lines.append("=" * 80)
    lines.append("")

    for filepath in sorted(all_issues.keys()):
        file_issues = all_issues[filepath]
        lines.append("-" * 80)
        lines.append(f"FILE: {filepath}  ({len(file_issues)} issue(s))")
        lines.append("-" * 80)
        # sort by tool then line
        file_issues.sort(key=lambda x: (x["tool"], int(x["line"]) if str(x["line"]).isdigit() else 0))
        for i in file_issues:
            loc = f"line {i['line']}" + (f":{i['col']}" if i["col"] not in ("-", "?") else "")
            lines.append(f"  [{i['tool']}] [{i['severity']}] {loc}")
            lines.append(f"    Rule   : {i['rule']}")
            lines.append(f"    Message: {i['message']}")
            lines.append("")

    lines.append("=" * 80)
    lines.append("END OF REPORT")
    lines.append("=" * 80)

    OUT_FILE.parent.mkdir(parents=True, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))

    print(f"Report written to: {OUT_FILE}")
    print(f"Files with issues: {len(all_issues)}")
    print(f"Total issues: {total}  (Flutter:{len(flutter)}  CS:{len(checkstyle)}  PMD:{len(pmd)}  SB:{len(spotbugs)})")


if __name__ == "__main__":
    print("Parsing Flutter Analyze...")
    flutter = parse_flutter(WORK_DIR / "flutter_analyze.txt")
    print(f"  -> {len(flutter)} issues in inventory files")

    print("Parsing Checkstyle...")
    checkstyle = parse_checkstyle(WORK_DIR / "checkstyle.xml")
    print(f"  -> {len(checkstyle)} issues in inventory files")

    print("Parsing PMD...")
    pmd = parse_pmd(WORK_DIR / "pmd.xml")
    print(f"  -> {len(pmd)} issues in inventory files")

    print("Parsing SpotBugs...")
    spotbugs = parse_spotbugs(WORK_DIR / "spotbugs.xml")
    print(f"  -> {len(spotbugs)} issues in inventory files")

    write_report(flutter, checkstyle, pmd, spotbugs)
