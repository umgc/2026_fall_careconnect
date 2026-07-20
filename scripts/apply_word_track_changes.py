"""Merge original + revised docx with Word track-changes markup (w:ins / w:del)."""

from __future__ import annotations

import copy
import difflib
import sys
from datetime import datetime, timezone
from pathlib import Path

from docx import Document
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
SCRIPTS = ROOT / "scripts"
AUTHOR = "CareConnect Doc Refresh"
DATE = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

DOC_PAIRS: list[tuple[str, str, str]] = [
    (
        "Call_Transcript_Retrieval_Review.docx",
        "Call_Transcript_Retrieval_Review_refresh.docx",
        "Call_Transcript_Retrieval_Review.docx",
    ),
    (
        "Hybrid_Retrieval_Scope_PostgreSQL_FullText_pgvector.docx",
        "Hybrid_Retrieval_Scope_PostgreSQL_FullText_pgvector_refresh.docx",
        "Hybrid_Retrieval_Scope_PostgreSQL_FullText_pgvector.docx",
    ),
    (
        "Ask_AI_Upstream_Pipeline_Call_Visit_Summaries_baseline.docx",
        "Ask_AI_Upstream_Pipeline_Call_Visit_Summaries.docx",
        "Ask_AI_Upstream_Pipeline_Call_Visit_Summaries.docx",
    ),
    (
        "RBAC_Scoped_Retrieval_Source_Types.docx",
        "RBAC_Scoped_Retrieval_Source_Types_refresh.docx",
        "RBAC_Scoped_Retrieval_Source_Types.docx",
    ),
    (
        "Voice_Query_Path_and_STT_Framework_Dependencies.docx",
        "Voice_Query_Path_and_STT_Framework_Dependencies_refresh.docx",
        "Voice_Query_Path_and_STT_Framework_Dependencies.docx",
    ),
    (
        "Medication_Timeline_Retrieval_FR-AI-11.docx",
        "Medication_Timeline_Retrieval_FR-AI-11_refresh.docx",
        "Medication_Timeline_Retrieval_FR-AI-11.docx",
    ),
]


def enable_track_revisions(doc: Document) -> None:
    settings = doc.settings.element
    if settings.find(qn("w:trackRevisions")) is None:
        track = OxmlElement("w:trackRevisions")
        track.set(qn("w:val"), "true")
        settings.append(track)


def paragraph_text(element) -> str:
    texts = []
    for node in element.iter(qn("w:t")):
        if node.text:
            texts.append(node.text)
    return "".join(texts)


def table_text(element) -> str:
    rows = []
    for tr in element.findall(qn("w:tr")):
        cells = []
        for tc in tr.findall(qn("w:tc")):
            cell_parts = []
            for p in tc.findall(qn("w:p")):
                t = paragraph_text(p).strip()
                if t:
                    cell_parts.append(t)
            cells.append(" | ".join(cell_parts))
        rows.append(" || ".join(cells))
    return "\n".join(rows)


def block_text(element) -> str:
    if element.tag == qn("w:p"):
        return paragraph_text(element)
    if element.tag == qn("w:tbl"):
        return table_text(element)
    return ""


def body_blocks(path: Path) -> list[tuple[str, object]]:
    doc = Document(path)
    blocks: list[tuple[str, object]] = []
    for child in doc.element.body:
        if child.tag in (qn("w:p"), qn("w:tbl")):
            blocks.append((block_text(child), child))
    return blocks


def _next_id(counter: list[int]) -> str:
    counter[0] += 1
    return str(counter[0])


def _make_del_paragraph(text: str, rev_id: str) -> OxmlElement:
    p = OxmlElement("w:p")
    del_el = OxmlElement("w:del")
    del_el.set(qn("w:id"), rev_id)
    del_el.set(qn("w:author"), AUTHOR)
    del_el.set(qn("w:date"), DATE)
    r = OxmlElement("w:r")
    dt = OxmlElement("w:delText")
    dt.set(qn("xml:space"), "preserve")
    dt.text = text
    r.append(dt)
    del_el.append(r)
    p.append(del_el)
    return p


def _wrap_block_as_ins(element: object, rev_id: str) -> OxmlElement:
    """Wrap a block (paragraph or table) as a tracked insertion."""
    ins = OxmlElement("w:ins")
    ins.set(qn("w:id"), rev_id)
    ins.set(qn("w:author"), AUTHOR)
    ins.set(qn("w:date"), DATE)
    ins.append(copy.deepcopy(element))
    return ins


def _save_doc(doc: Document, output: Path) -> Path:
    output.parent.mkdir(parents=True, exist_ok=True)
    try:
        doc.save(output)
        print(f"Tracked: {output}")
        return output
    except PermissionError:
        alt = output.with_name(f"{output.stem}_tracked{output.suffix}")
        doc.save(alt)
        print(f"Tracked (target locked): {alt}")
        return alt


def build_tracked_document(original: Path, revised: Path, output: Path) -> Path | None:
    orig_blocks = body_blocks(original)
    rev_blocks = body_blocks(revised)
    if not rev_blocks:
        print(f"Skip (empty revised): {revised}")
        return None

    orig_texts = [t for t, _ in orig_blocks]
    rev_texts = [t for t, _ in rev_blocks]

    doc = Document()
    enable_track_revisions(doc)
    body = doc.element.body
    for child in list(body):
        body.remove(child)

    counter = [0]
    sm = difflib.SequenceMatcher(None, orig_texts, rev_texts, autojunk=False)

    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for _, element in rev_blocks[j1:j2]:
                body.append(copy.deepcopy(element))
        elif tag == "delete":
            for text, _ in orig_blocks[i1:i2]:
                if text.strip():
                    body.append(_make_del_paragraph(text, _next_id(counter)))
        elif tag == "insert":
            for _, element in rev_blocks[j1:j2]:
                body.append(_wrap_block_as_ins(element, _next_id(counter)))
        elif tag == "replace":
            for text, _ in orig_blocks[i1:i2]:
                if text.strip():
                    body.append(_make_del_paragraph(text, _next_id(counter)))
            for _, element in rev_blocks[j1:j2]:
                body.append(_wrap_block_as_ins(element, _next_id(counter)))

    note_p = OxmlElement("w:p")
    ins = OxmlElement("w:ins")
    ins.set(qn("w:id"), _next_id(counter))
    ins.set(qn("w:author"), AUTHOR)
    ins.set(qn("w:date"), DATE)
    r = OxmlElement("w:r")
    rPr = OxmlElement("w:rPr")
    i_el = OxmlElement("w:i")
    rPr.append(i_el)
    r.append(rPr)
    t = OxmlElement("w:t")
    t.set(qn("xml:space"), "preserve")
    t.text = (
        f"[Track Changes] Revisions by {AUTHOR} on {DATE[:10]}. "
        f"Open Review tab → All Markup to see insertions/deletions."
    )
    r.append(t)
    ins.append(r)
    note_p.append(ins)
    body.insert(0, note_p)

    return _save_doc(doc, output)


def ensure_ask_ai_baseline() -> None:
    baseline = DOCS / "Ask_AI_Upstream_Pipeline_Call_Visit_Summaries_baseline.docx"
    if baseline.exists():
        return
    sys.path.insert(0, str(SCRIPTS))
    import generate_ask_ai_upstream_pipeline_docx as gen

    old_output = gen.OUTPUT
    try:
        gen.OUTPUT = baseline
        gen.build(include_revision=False)
        print(f"Baseline: {baseline}")
    finally:
        gen.OUTPUT = old_output


def main() -> int:
    ensure_ask_ai_baseline()
    ok = 0
    for original_name, revised_name, output_name in DOC_PAIRS:
        original = DOCS / original_name
        revised = DOCS / revised_name
        output = DOCS / output_name
        if not original.exists():
            print(f"Skip (missing original): {original}")
            continue
        if not revised.exists():
            print(f"Skip (missing revised): {revised}")
            continue
        if build_tracked_document(original, revised, output):
            ok += 1
    print(f"Done — {ok} document(s) with Word track changes.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
