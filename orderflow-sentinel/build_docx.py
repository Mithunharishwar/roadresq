# -*- coding: utf-8 -*-
"""Build a styled DOCX from the solution markdown (subset parser)."""
import re
import sys
from pathlib import Path

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_BREAK
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor

SRC = Path(__file__).with_name("OrderFlow_Sentinel_Solution.md")
OUT = Path(__file__).with_name("OrderFlow_Sentinel_Solution.docx")

ACCENT = RGBColor(0x0E, 0x4F, 0x5C)
ACCENT2 = RGBColor(0xC2, 0x5B, 0x28)
GREY = RGBColor(0x55, 0x5F, 0x66)


def shade(cell, hex_fill):
    tcPr = cell._tc.get_or_add_tcPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hex_fill)
    tcPr.append(shd)


def bottom_border(paragraph, color="0E4F5C", size="8"):
    pPr = paragraph._p.get_or_add_pPr()
    pbdr = OxmlElement("w:pBdr")
    bottom = OxmlElement("w:bottom")
    bottom.set(qn("w:val"), "single")
    bottom.set(qn("w:sz"), size)
    bottom.set(qn("w:space"), "2")
    bottom.set(qn("w:color"), color)
    pbdr.append(bottom)
    pPr.append(pbdr)


def add_runs(paragraph, text, size=None, color=None, base_bold=False):
    """Split on **bold**, `code`, *italic* and add runs."""
    tokens = re.split(r"(\*\*[^*]+\*\*|`[^`]+`|\*[^*]+\*)", text)
    for tok in tokens:
        if not tok:
            continue
        bold = base_bold
        mono = False
        italic = False
        body = tok
        if tok.startswith("**") and tok.endswith("**") and len(tok) > 4:
            body, bold = tok[2:-2], True
        elif tok.startswith("`") and tok.endswith("`") and len(tok) > 2:
            body, mono = tok[1:-1], True
        elif tok.startswith("*") and tok.endswith("*") and len(tok) > 2:
            body, italic = tok[1:-1], True
        run = paragraph.add_run(body)
        run.bold = bold
        run.italic = italic
        if mono:
            run.font.name = "Consolas"
            run._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
            run.font.size = Pt(9)
            run.font.color.rgb = ACCENT2
        else:
            if size:
                run.font.size = size
            if color is not None:
                run.font.color.rgb = color
    return paragraph


def setup_styles(doc):
    normal = doc.styles["Normal"]
    normal.font.name = "Calibri"
    normal.font.size = Pt(10.5)
    normal.paragraph_format.space_after = Pt(5)
    normal.paragraph_format.line_spacing = 1.15

    for name, size, color, before, after in (
        ("Heading 1", 20, ACCENT, 16, 6),
        ("Heading 2", 15, ACCENT, 14, 4),
        ("Heading 3", 12, ACCENT2, 10, 3),
    ):
        st = doc.styles[name]
        st.font.name = "Calibri"
        st.font.size = Pt(size)
        st.font.bold = True
        st.font.color.rgb = color
        st.paragraph_format.space_before = Pt(before)
        st.paragraph_format.space_after = Pt(after)
        st.paragraph_format.keep_with_next = True


def cover(doc):
    for _ in range(3):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("ORDERFLOW SENTINEL")
    r.font.size = Pt(34)
    r.font.bold = True
    r.font.color.rgb = ACCENT

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("Self-Healing AI for Order & API Failure Resolution")
    r.font.size = Pt(15)
    r.font.color.rgb = GREY

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    bottom_border(p, "C25B28", "12")

    for _ in range(2):
        doc.add_paragraph()

    meta = [
        ("Hackathon", "Use Case 1 — OrderFlow Sentinel"),
        ("Industry anchor", "Telecom broadband / device order fulfilment · Retail omnichannel OMS"),
        ("Failure modes", "API Response Errors · Order Delays · Order Rejections"),
        ("Stage target", "Stage II — Proof of Concept"),
        ("Core claim", "Detects, diagnoses and — where provably safe — resolves order failures end to end"),
    ]
    t = doc.add_table(rows=0, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    for k, v in meta:
        row = t.add_row().cells
        row[0].width = Inches(1.5)
        row[1].width = Inches(4.6)
        pk = row[0].paragraphs[0]
        rk = pk.add_run(k)
        rk.bold = True
        rk.font.size = Pt(9.5)
        rk.font.color.rgb = ACCENT
        add_runs(row[1].paragraphs[0], v, size=Pt(9.5))

    for _ in range(3):
        doc.add_paragraph()
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("One engine · two verticals · any multi-system order journey")
    r.font.size = Pt(10)
    r.italic = True
    r.font.color.rgb = GREY

    doc.add_page_break()


def code_block(doc, lines):
    t = doc.add_table(rows=1, cols=1)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    cell = t.rows[0].cells[0]
    shade(cell, "F4F6F7")
    cell.paragraphs[0].text = ""
    first = True
    for ln in lines:
        p = cell.paragraphs[0] if first else cell.add_paragraph()
        first = False
        p.paragraph_format.space_after = Pt(0)
        p.paragraph_format.space_before = Pt(0)
        p.paragraph_format.line_spacing = 1.0
        r = p.add_run(ln if ln else " ")
        r.font.name = "Consolas"
        r._element.rPr.rFonts.set(qn("w:eastAsia"), "Consolas")
        r.font.size = Pt(8)
        r.font.color.rgb = RGBColor(0x27, 0x2E, 0x33)
    doc.add_paragraph().paragraph_format.space_after = Pt(4)


def parse_table(rows):
    """rows: list of raw '| a | b |' lines."""
    data = []
    for ln in rows:
        cells = [c.strip() for c in ln.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c) for c in cells if c):
            continue
        data.append(cells)
    return data


def add_table(doc, data):
    if not data:
        return
    ncol = max(len(r) for r in data)
    t = doc.add_table(rows=0, cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    for i, row in enumerate(data):
        cells = t.add_row().cells
        for j in range(ncol):
            text = row[j] if j < len(row) else ""
            p = cells[j].paragraphs[0]
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.space_before = Pt(2)
            if i == 0:
                shade(cells[j], "0E4F5C")
                add_runs(p, text, size=Pt(8.5), color=RGBColor(0xFF, 0xFF, 0xFF), base_bold=True)
            else:
                if i % 2 == 0:
                    shade(cells[j], "F7F9FA")
                add_runs(p, text, size=Pt(8.5))
    doc.add_paragraph().paragraph_format.space_after = Pt(2)


def add_footer(doc):
    section = doc.sections[0]
    p = section.footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    r = p.add_run("OrderFlow Sentinel  ·  Hackathon Solution Submission  ·  ")
    r.font.size = Pt(8)
    r.font.color.rgb = GREY


def build():
    text = SRC.read_text(encoding="utf-8")
    lines = text.split("\n")

    doc = Document()
    setup_styles(doc)
    sec = doc.sections[0]
    sec.top_margin = Inches(0.75)
    sec.bottom_margin = Inches(0.7)
    sec.left_margin = Inches(0.8)
    sec.right_margin = Inches(0.8)

    cover(doc)
    add_footer(doc)

    i = 0
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()

        # code fence
        if stripped.startswith("```"):
            i += 1
            buf = []
            while i < len(lines) and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            code_block(doc, buf)
            continue

        # table
        if stripped.startswith("|") and stripped.endswith("|"):
            buf = []
            while i < len(lines) and lines[i].strip().startswith("|"):
                buf.append(lines[i])
                i += 1
            add_table(doc, parse_table(buf))
            continue

        if not stripped:
            i += 1
            continue

        if stripped == "---":
            p = doc.add_paragraph()
            bottom_border(p, "D5DBDF", "6")
            i += 1
            continue

        m = re.match(r"^(#{1,4})\s+(.*)$", stripped)
        if m:
            level = len(m.group(1))
            content = m.group(2).strip()
            if level == 1:
                p = doc.add_paragraph(style="Heading 1")
                add_runs(p, content, size=Pt(20), color=ACCENT, base_bold=True)
                bottom_border(p)
            elif level == 2:
                doc.add_paragraph(style="Heading 2").add_run(content)
                doc.paragraphs[-1].runs[0].bold = True
            else:
                doc.add_paragraph(style="Heading 3").add_run(content)
                doc.paragraphs[-1].runs[0].bold = True
            i += 1
            continue

        # bullets
        m = re.match(r"^[-*]\s+(.*)$", stripped)
        if m:
            p = doc.add_paragraph(style="List Bullet")
            add_runs(p, m.group(1))
            p.paragraph_format.space_after = Pt(2)
            i += 1
            continue

        m = re.match(r"^(\d+)\.\s+(.*)$", stripped)
        if m:
            p = doc.add_paragraph(style="List Number")
            add_runs(p, m.group(2))
            p.paragraph_format.space_after = Pt(2)
            i += 1
            continue

        if stripped.startswith(">"):
            p = doc.add_paragraph()
            p.paragraph_format.left_indent = Inches(0.25)
            add_runs(p, stripped.lstrip("> ").strip())
            for r in p.runs:
                r.italic = True
                r.font.color.rgb = GREY
            i += 1
            continue

        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        add_runs(p, stripped)
        i += 1

    doc.save(OUT)
    print("WROTE", OUT, OUT.stat().st_size)


if __name__ == "__main__":
    build()
