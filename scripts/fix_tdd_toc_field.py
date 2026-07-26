"""
Rebuild a live Word TOC field (matching the reference document's format) inside
the CareConnect TDD docx that currently has a plain-text, non-updating
Table of Contents.

Usage:
    python fix_tdd_toc_field.py

Reads:  C:\\Users\\ravic\\Downloads\\01_Technical_Design_Document (1).docx
Writes: C:\\Users\\ravic\\Downloads\\01_Technical_Design_Document (1).docx  (in place)
Backup: C:\\Users\\ravic\\Downloads\\01_Technical_Design_Document (1) - backup.docx
"""
import difflib
import re
import shutil
import zipfile
from xml.etree import ElementTree as ET

import sys

SRC = sys.argv[1] if len(sys.argv) > 1 else r"C:\Users\ravic\Downloads\01_Technical_Design_Document (1).docx"
BACKUP = SRC.replace(".docx", " - backup.docx")

W = "{http://schemas.openxmlformats.org/wordprocessingml/2006/main}"
WNS = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"

LEVEL1_PPR = (
    '<w:pPr><w:widowControl w:val="0"/><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="12000"/></w:tabs>'
    '<w:spacing w:before="60" w:line="240" w:lineRule="auto"/>'
    '<w:rPr><w:rFonts w:ascii="Arial" w:cs="Arial" w:eastAsia="Arial" w:hAnsi="Arial"/><w:b w:val="1"/><w:bCs w:val="1"/>'
    '<w:i w:val="0"/><w:iCs w:val="0"/><w:smallCaps w:val="0"/><w:strike w:val="0"/><w:color w:val="000000"/>'
    '<w:sz w:val="22"/><w:szCs w:val="22"/><w:u w:val="none"/><w:shd w:fill="auto" w:val="clear"/>'
    '<w:vertAlign w:val="baseline"/></w:rPr></w:pPr>'
)
LEVEL2_PPR = (
    '<w:pPr><w:widowControl w:val="0"/><w:tabs><w:tab w:val="right" w:leader="dot" w:pos="12000"/></w:tabs>'
    '<w:spacing w:before="60" w:line="240" w:lineRule="auto"/><w:ind w:left="360" w:firstLine="0"/>'
    '<w:rPr><w:rFonts w:ascii="Arial" w:cs="Arial" w:eastAsia="Arial" w:hAnsi="Arial"/><w:b w:val="0"/><w:bCs w:val="0"/>'
    '<w:i w:val="0"/><w:iCs w:val="0"/><w:smallCaps w:val="0"/><w:strike w:val="0"/><w:color w:val="000000"/>'
    '<w:sz w:val="22"/><w:szCs w:val="22"/><w:u w:val="none"/><w:shd w:fill="auto" w:val="clear"/>'
    '<w:vertAlign w:val="baseline"/></w:rPr></w:pPr>'
)


def run_rpr(bold):
    b = "1" if bold else "0"
    return (
        f'<w:rPr><w:rFonts w:ascii="Arial" w:cs="Arial" w:eastAsia="Arial" w:hAnsi="Arial"/>'
        f'<w:b w:val="{b}"/><w:bCs w:val="{b}"/><w:i w:val="0"/><w:iCs w:val="0"/><w:smallCaps w:val="0"/>'
        f'<w:strike w:val="0"/><w:color w:val="000000"/><w:sz w:val="24"/><w:szCs w:val="24"/><w:u w:val="none"/>'
        f'<w:shd w:fill="auto" w:val="clear"/><w:vertAlign w:val="baseline"/><w:rtl w:val="0"/></w:rPr>'
    )


def xml_escape(text):
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
    )


def build_entry_paragraph(level, title, anchor, page, extra_run_before="", extra_run_after=""):
    ppr = LEVEL1_PPR if level == 1 else LEVEL2_PPR
    bold = level == 1
    rpr = run_rpr(bold)
    title_esc = xml_escape(title)
    return (
        f"<w:p>{ppr}"
        f"{extra_run_before}"
        f'<w:hyperlink w:anchor="{anchor}">'
        f'<w:r>{rpr}<w:t xml:space="preserve">{title_esc}</w:t><w:tab/><w:t xml:space="preserve">{page}</w:t></w:r>'
        f"</w:hyperlink>"
        f'<w:r><w:rPr><w:rtl w:val="0"/></w:rPr></w:r>'
        f"{extra_run_after}"
        f"</w:p>"
    )


def normalize_title(text):
    text = re.sub(r"\[\d+\]", "", text)
    text = re.sub(r"\s+", " ", text).strip()
    text = text.rstrip(". ")
    return text.lower()


def main():
    shutil.copyfile(SRC, BACKUP)
    print(f"Backup written to {BACKUP}")

    with zipfile.ZipFile(SRC) as z:
        names = z.namelist()
        contents = {n: z.read(n) for n in names}

    doc_xml = contents["word/document.xml"].decode("utf-8")

    # 1. Clean stray "[1]"/"[2]" literal bracket text baked into heading titles.
    doc_xml = doc_xml.replace(
        '<w:t xml:space="preserve">List of Tables[1] </w:t>',
        '<w:t xml:space="preserve">List of Tables</w:t>',
    )
    doc_xml = doc_xml.replace(
        '<w:t xml:space="preserve">List of Figures[2] </w:t>',
        '<w:t xml:space="preserve">List of Figures</w:t>',
    )

    # 1b. Strip stray literal "\u25cf" bullet-character + spacer runs baked
    # directly into six Team E heading paragraphs (12.9, 12.9.1-12.9.5).
    # Target document does not have this artifact (0 bullet-char headings).
    bullet_run_pattern = re.compile(
        r'<w:r w:rsidDel="00000000" w:rsidR="00000000" w:rsidRPr="00000000">'
        r'<w:rPr><w:b w:val="0"/><w:bCs w:val="0"/><w:sz w:val="(?:26|34)"/><w:szCs w:val="(?:26|34)"/>'
        r'<w:rtl w:val="0"/></w:rPr><w:t xml:space="preserve">\u25cf</w:t></w:r>'
        r'<w:r w:rsidDel="00000000" w:rsidR="00000000" w:rsidRPr="00000000">'
        r'<w:rPr><w:rFonts w:ascii="Times New Roman" w:cs="Times New Roman" w:eastAsia="Times New Roman" '
        r'w:hAnsi="Times New Roman"/><w:b w:val="0"/><w:bCs w:val="0"/><w:sz w:val="14"/><w:szCs w:val="14"/>'
        r'<w:rtl w:val="0"/></w:rPr><w:t xml:space="preserve">\s*</w:t></w:r>'
    )
    doc_xml, bullet_fix_count = bullet_run_pattern.subn("", doc_xml)
    print(f"Stripped bullet-char run pairs: {bullet_fix_count}")

    # 1c. Content contradiction fixes (auth mechanism, API path convention,
    # proposed-schema labeling) requested alongside the format fix.
    content_fixes = [
        # Auth: reconcile every non-Spring-JWT mention with the codebase's
        # actual mechanism (Spring Security JWT + BCrypt), verified against
        # JwtTokenProvider / AuthService / BCryptPasswordEncoder usage.
        (
            '<w:t xml:space="preserve">(Argon2id), </w:t>',
            '<w:t xml:space="preserve">(BCrypt), </w:t>',
        ),
        (
            '<w:t xml:space="preserve">Cognito-issued bearer token.</w:t>',
            '<w:t xml:space="preserve">Spring-issued JWT bearer token (see Section 5.3).</w:t>',
        ),
        (
            '<w:t xml:space="preserve">Cognito/JWT, feature services</w:t>',
            '<w:t xml:space="preserve">JWT (Spring Security), feature services</w:t>',
        ),
        (
            "Cognito/JWT enforcement of USE_AI_FEATURES",
            "JWT (Spring Security) enforcement of USE_AI_FEATURES",
        ),
        # Redis: not part of the approved stack in Section 3; reframe as a
        # proposed optimization rather than an implemented fact.
        (
            "tamper detection. The role/permission join table is cached in Redis on application startup and invalidated via a Postgres ",
            "tamper detection. As a future optimization, the role/permission join table could be cached in Redis on application startup and invalidated via a Postgres ",
        ),
        (
            "channel, so authorization checks remain sub-millisecond even at peak load.",
            "channel, so authorization checks would remain sub-millisecond even at peak load; this Redis caching layer is proposed and is not part of the currently approved technology stack (Section 3).",
        ),
        # API path convention: make the inherited-prefix exceptions an
        # explicit, stated policy instead of an unexplained inconsistency.
        (
            "API versioning is path-based (/v1/api/). Breaking changes require a new version prefix. Non-breaking additions (new optional fields, new endpoints) may be introduced within the existing version. Deprecations will be noted in OpenAPI documentation before removal.",
            "API versioning is path-based (/v1/api/). Breaking changes require a new version prefix. Non-breaking additions (new optional fields, new endpoints) may be introduced within the existing version. Deprecations will be noted in OpenAPI documentation before removal. Endpoints inherited or extended from pre-existing subsystems keep their original path prefixes rather than migrating onto /v1/api/: the video-call pipeline uses /api/v3/calls/..., summary confirmation uses /api/summaries/..., and the Ask AI retrieval endpoint uses /api/ai/ask. New Team A endpoints follow /v1/api/ going forward; Sections 5.2, 6.2, and 6.12 document the specific inherited exceptions.",
        ),
        # Schema entities: label Section 4.6-4.8 as proposed/target schema so
        # they are not read as already-implemented fact alongside Section 4.3.
        (
            '<w:t xml:space="preserve">The EVV domain implements the 21st Century Cures Act',
            '<w:t xml:space="preserve">Status: proposed target schema for Team D\u2019s EVV WBS scope; the entities below are not yet present in the Flyway migrations and extend rather than replace the inherited evv_participant, evv_record, evv_audit_event, and evv_outbox tables (V28__create_evv_tables.sql, V55.1__create_evv_outbox_table.sql). The EVV domain implements the 21st Century Cures Act',
        ),
        (
            '<w:t xml:space="preserve">This domain models the day-to-day caregiver workflow',
            '<w:t xml:space="preserve">Status: proposed target schema for Team D\u2019s In-Home Residential Support WBS scope; the entities below are not yet present in the Flyway migrations. This domain models the day-to-day caregiver workflow',
        ),
        (
            '<w:t xml:space="preserve">The Admin &amp; Audit domain provides identity, authorization, and the immutable evidentiary trail required for HIPAA</w:t>',
            '<w:t xml:space="preserve">Status: proposed target schema; the role, permission, audit_event, and compliance_report entities below are not yet present in the Flyway migrations (the inherited schema has users and an EVV-scoped evv_audit_event only). The Admin &amp; Audit domain provides identity, authorization, and the immutable evidentiary trail required for HIPAA</w:t>',
        ),
    ]
    for old, new in content_fixes:
        count = doc_xml.count(old)
        assert count == 1, f"Expected exactly 1 occurrence, found {count}: {old[:80]!r}"
        doc_xml = doc_xml.replace(old, new)
    print(f"Applied {len(content_fixes)} content-contradiction text fixes")

    root = ET.fromstring(doc_xml.encode("utf-8"))
    body = root.find(W + "body")
    paras = list(body.iter(W + "p"))

    def style_of(p):
        pPr = p.find(W + "pPr")
        if pPr is not None:
            pStyle = pPr.find(W + "pStyle")
            if pStyle is not None:
                return pStyle.get(W + "val")
        return None

    def text_of(p):
        return "".join(t.text or "" for t in p.iter(W + "t"))

    def bookmark_of(p):
        bm = p.find(W + "bookmarkStart")
        return bm.get(W + "name") if bm is not None else None

    headings = []  # (level, text, anchor)
    toc_idx = None
    lot_idx = None
    for i, p in enumerate(paras):
        st = style_of(p)
        txt = text_of(p).strip()
        if st == "Heading1" and txt == "Table of Contents" and toc_idx is None:
            toc_idx = i
        if st == "Heading1" and txt.startswith("List of Tables") and toc_idx is not None and lot_idx is None:
            lot_idx = i
        if st in ("Heading1", "Heading2") and txt:
            # Real Word TOC fields silently omit headings with no text (the
            # target document has 10 blank Heading2 paragraphs that never
            # produce a cached TOC line); replicate that behavior instead of
            # emitting a title-less dot-leader/page-number row.
            anchor = bookmark_of(p)
            headings.append((1 if st == "Heading1" else 2, txt, anchor))

    assert toc_idx is not None and lot_idx is not None, "Could not locate TOC/List of Tables headings"
    print(f"toc_idx={toc_idx} lot_idx={lot_idx} total H1/H2 headings={len(headings)}")

    # 2. Parse old (stale) flat TOC entries for approximate page numbers.
    old_entries = []
    for i in range(toc_idx + 1, lot_idx):
        txt = text_of(paras[i]).strip()
        if not txt:
            continue
        m = re.match(r"^(.*?)[\.\s]+(\d+)\s*$", txt)
        if m:
            old_entries.append((m.group(1).strip(), int(m.group(2))))
        else:
            old_entries.append((txt, None))

    old_titles_norm = [normalize_title(t) for t, _ in old_entries]
    new_titles_norm = [normalize_title(t) for _, t, _ in headings]

    sm = difflib.SequenceMatcher(None, old_titles_norm, new_titles_norm, autojunk=False)
    page_for_new = [None] * len(headings)
    for tag, i1, i2, j1, j2 in sm.get_opcodes():
        if tag == "equal":
            for k in range(i2 - i1):
                page_for_new[j1 + k] = old_entries[i1 + k][1]

    # Fill gaps (headings with no matched old entry) by interpolating from
    # the nearest known preceding page number.
    last_known = 1
    for idx in range(len(page_for_new)):
        if page_for_new[idx] is None:
            page_for_new[idx] = last_known
        else:
            last_known = page_for_new[idx]

    # 3. Build the new field-based TOC XML.
    field_instr = (
        ' TOC \\h \\u \\z \\t &quot;Heading 1,1,Heading 2,2,Heading 5,5,Heading 6,6,&quot; '
    )
    entry_xmls = []
    for idx, (level, title, anchor) in enumerate(headings):
        page = page_for_new[idx]
        if idx == 0:
            begin_run = (
                "<w:r><w:fldChar w:fldCharType=\"begin\"/>"
                f'<w:instrText xml:space="preserve">{field_instr}</w:instrText>'
                '<w:fldChar w:fldCharType="separate"/></w:r>'
            )
            entry_xmls.append(
                build_entry_paragraph(level, title, anchor, page, extra_run_before=begin_run)
            )
        elif idx == len(headings) - 1:
            end_run = '<w:r><w:fldChar w:fldCharType="end"/></w:r>'
            entry_xmls.append(
                build_entry_paragraph(level, title, anchor, page, extra_run_after=end_run)
            )
        else:
            entry_xmls.append(build_entry_paragraph(level, title, anchor, page))

    sdt_id = "1227102603"
    new_toc_xml = (
        "<w:sdt>"
        f'<w:sdtPr><w:id w:val="{sdt_id}"/>'
        '<w:docPartObj><w:docPartGallery w:val="Table of Contents"/><w:docPartUnique w:val="1"/></w:docPartObj>'
        "</w:sdtPr>"
        "<w:sdtContent>" + "".join(entry_xmls) + "</w:sdtContent>"
        "</w:sdt>"
    )

    # 4. Splice into the raw document.xml string between the two heading paragraphs.
    # Re-serialize is avoided; we locate byte offsets in the *original* string
    # (post [1]/[2] cleanup) using unique paragraph markers.
    toc_heading_marker = '<w:t xml:space="preserve">Table of Contents</w:t>'
    lot_heading_marker = '<w:t xml:space="preserve">List of Tables</w:t>'

    toc_marker_pos = doc_xml.find(toc_heading_marker)
    assert toc_marker_pos != -1, "Table of Contents heading text not found"
    # end of that paragraph
    toc_para_end = doc_xml.find("</w:p>", toc_marker_pos) + len("</w:p>")

    lot_marker_pos = doc_xml.find(lot_heading_marker, toc_para_end)
    assert lot_marker_pos != -1, "List of Tables heading text not found after TOC heading"
    lot_para_start = doc_xml.rfind("<w:p ", toc_para_end, lot_marker_pos)
    if lot_para_start == -1:
        lot_para_start = doc_xml.rfind("<w:p>", toc_para_end, lot_marker_pos)
    assert lot_para_start != -1, "Could not find start of List of Tables heading paragraph"

    new_doc_xml = doc_xml[:toc_para_end] + new_toc_xml + doc_xml[lot_para_start:]

    contents["word/document.xml"] = new_doc_xml.encode("utf-8")

    # 5. Force Word to recompute all fields (including this TOC) on next open.
    settings_xml = contents["word/settings.xml"].decode("utf-8")
    if "<w:updateFields" not in settings_xml:
        settings_xml = settings_xml.replace(
            "<w:settings ",
            "<w:settings ",
            1,
        )
        # Insert updateFields as the first child element of w:settings.
        insert_at = settings_xml.find(">", settings_xml.find("<w:settings")) + 1
        settings_xml = (
            settings_xml[:insert_at]
            + '<w:updateFields w:val="true"/>'
            + settings_xml[insert_at:]
        )
    contents["word/settings.xml"] = settings_xml.encode("utf-8")

    # 6. Re-zip.
    with zipfile.ZipFile(SRC, "w", zipfile.ZIP_DEFLATED) as z:
        for name in names:
            z.writestr(name, contents[name])

    print("Done. New TOC entries written:", len(entry_xmls))
    print("Sample page assignments (first 8):")
    for (level, title, anchor), page in list(zip(headings, page_for_new))[:8]:
        print(f"  L{level} {title[:50]!r} -> anchor={anchor} page={page}")


if __name__ == "__main__":
    main()
