"""Build the RoadResQ project report in strict Anna University format.

Differences from build_report.py (the earlier draft):
  * general text is Times New Roman 14 pt, 1.5 line spacing (para 4 of the format)
  * separate cover page, followed by the title page (Appendix 1)
  * abstract restricted to one page (para 3.3)
  * table of contents lists the front matter, as para 3.4 requires, and is
    generated with real page numbers
  * list of symbols, abbreviations and nomenclature replaces the abbreviation list
  * appendix numbered "Appendix 1" with listings A.1 ... A.4
  * references numbered in the specimen style, single spaced, alphabetically
  * all tables / figures / tab stops fit inside the 5.75 in text column
"""
import json
import os
import re

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.style import WD_STYLE_TYPE
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import (WD_ALIGN_PARAGRAPH, WD_LINE_SPACING,
                            WD_TAB_ALIGNMENT, WD_TAB_LEADER)
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt, RGBColor

import content_ch1 as C1
import content_ch2 as C2
import content_ch3 as C3
import content_ch4 as C4
import content_ch5 as C5
import content_ch6 as C6
import content_ch7 as C7
import front_au as FA

OUT = "RoadResQ_Final_Project_Report.docx"
FIG_DIR = "figs"
PAGE_MAP = "page_map3.json"

BODY = 14           # general text (para 4)
TEXT_W = 5.75       # usable width in inches: 8.27 - 1.5 - 1.02
TABLE_PT = 10.0
CAP_PT = 11.0

MODULES = (C1, C2, C3, C4, C5, C6, C7)

# ---- length reduction for the submission copy -------------------------------
# 1) the seven end-of-chapter summaries restate what the chapter has just said
DROP_H2 = {"1.6", "2.4", "3.6", "4.2", "5.4", "6.5", "7.4", "3.5"}
DROP_H3 = {"2.2.5", "6.3.9", "5.2.4"}
# 2) the four pseudocode listings repeat the prose and equations of 4.1.3-4.1.8
CUT_FROM_H3 = {"4.1.10"}
# 3) the appendix reproduces source code already described in Chapters 3 and 4
INCLUDE_APPENDIX = False
# 4) the data figures do not need the full text column
SHRINK_FIGS = {"6.4", "6.5", "6.6", "6.7", "6.8", "6.9", "6.10", "6.11"}
SHRINK_TO = 3.6


LEVEL = {"chapter": 0, "h2": 1, "h3": 2, "h4": 3}


def blocks_for(mod):
    """Return the blocks of a chapter with the dropped sections removed whole."""
    out, cut, skip_level = [], False, None
    for b in mod.BLOCKS:
        kind = b[0]
        lvl = LEVEL.get(kind)
        if cut:
            continue
        if lvl is not None:
            if skip_level is not None and lvl <= skip_level:
                skip_level = None
            if skip_level is None:
                if kind == "h3" and b[1] in CUT_FROM_H3:
                    cut = True
                    continue
                if kind == "h2" and b[1] in DROP_H2:
                    skip_level = lvl
                    continue
                if kind == "h3" and b[1] in DROP_H3:
                    skip_level = lvl
                    continue
        if skip_level is not None:
            continue
        out.append(b)
    return out


# --------------------------------------------------------------------- helpers
def _field(paragraph, instr, placeholder="1", size=11):
    run = paragraph.add_run()
    b = OxmlElement("w:fldChar"); b.set(qn("w:fldCharType"), "begin")
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = instr
    s = OxmlElement("w:fldChar"); s.set(qn("w:fldCharType"), "separate")
    t = OxmlElement("w:t"); t.text = placeholder
    e = OxmlElement("w:fldChar"); e.set(qn("w:fldCharType"), "end")
    for el in (b, it, s, t, e):
        run._r.append(el)
    run.font.name = "Times New Roman"
    run.font.size = Pt(size)
    return run


def _set_pgnum(section, fmt, start=None):
    sectPr = section._sectPr
    for old in sectPr.findall(qn("w:pgNumType")):
        sectPr.remove(old)
    pg = OxmlElement("w:pgNumType")
    pg.set(qn("w:fmt"), fmt)
    if start is not None:
        pg.set(qn("w:start"), str(start))
    sectPr.append(pg)


def footer_number(section, fmt, start=None, suppress_first=False, show=True):
    section.footer.is_linked_to_previous = False
    p = section.footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for r in list(p.runs):
        r._r.getparent().remove(r._r)
    if show:
        _field(p, " PAGE ", "1")
    _set_pgnum(section, fmt, start)
    section.different_first_page_header_footer = bool(suppress_first)
    if suppress_first:
        fp = section.first_page_footer
        fp.is_linked_to_previous = False
        for r in list(fp.paragraphs[0].runs):
            r._r.getparent().remove(r._r)


def shade(paragraph, hexcolor="F7F7F7"):
    pPr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hexcolor)
    pPr.append(shd)


def no_borders(table):
    tblPr = table._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "none")
        el.set(qn("w:sz"), "0")
        borders.append(el)
    tblPr.append(borders)


def setup(doc):
    st = doc.styles["Normal"]
    st.font.name = "Times New Roman"
    st.font.size = Pt(BODY)
    rpr = st.element.get_or_add_rPr()
    rfonts = rpr.find(qn("w:rFonts"))
    if rfonts is None:
        rfonts = OxmlElement("w:rFonts")
        rpr.append(rfonts)
    for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        rfonts.set(qn(a), "Times New Roman")
    pf = st.paragraph_format
    pf.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    pf.space_after = Pt(6)
    pf.space_before = Pt(0)
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY

    for name, size, bold, italic, before, after, align in [
        ("Heading 1", 16, True, False, 0, 20, WD_ALIGN_PARAGRAPH.CENTER),
        ("Heading 2", BODY, True, False, 10, 4, WD_ALIGN_PARAGRAPH.LEFT),
        ("Heading 3", BODY, True, True, 8, 4, WD_ALIGN_PARAGRAPH.LEFT),
        ("Heading 4", BODY, True, True, 6, 3, WD_ALIGN_PARAGRAPH.LEFT),
    ]:
        s = doc.styles[name]
        s.font.name = "Times New Roman"
        s.font.size = Pt(size)
        s.font.bold = bold
        s.font.italic = italic
        s.font.color.rgb = RGBColor(0, 0, 0)
        s.paragraph_format.space_before = Pt(before)
        s.paragraph_format.space_after = Pt(after)
        s.paragraph_format.alignment = align
        s.paragraph_format.line_spacing = 1.5
        s.paragraph_format.keep_with_next = True

    sec = doc.sections[0]
    sec.page_width = Cm(21.0)
    sec.page_height = Cm(29.7)
    sec.top_margin = Inches(1.0)
    sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.5)
    sec.right_margin = Inches(1.02)


def para(doc, text="", size=BODY, bold=False, italic=False, align="justify",
         space_after=3, space_before=0, spacing=1.5, indent=0):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.alignment = {"justify": WD_ALIGN_PARAGRAPH.JUSTIFY,
                    "center": WD_ALIGN_PARAGRAPH.CENTER,
                    "left": WD_ALIGN_PARAGRAPH.LEFT,
                    "right": WD_ALIGN_PARAGRAPH.RIGHT}[align]
    pf.space_after = Pt(space_after)
    pf.space_before = Pt(space_before)
    pf.line_spacing = spacing
    if indent:
        pf.first_line_indent = Inches(indent)
    if text:
        r = p.add_run(text)
        r.font.size = Pt(size)
        r.bold = bold
        r.italic = italic
        r.font.name = "Times New Roman"
    return p


def bullet(doc, text, marker="\u2022"):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.left_indent = Inches(0.45)
    pf.first_line_indent = Inches(-0.25)
    pf.space_after = Pt(2)
    pf.space_before = Pt(0)
    pf.line_spacing = 1.5
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    r0 = p.add_run(marker + "  ")
    r0.font.size = Pt(BODY)
    r0.font.name = "Times New Roman"
    r1 = p.add_run(text)
    r1.font.size = Pt(BODY)
    r1.font.name = "Times New Roman"
    return p


def equation(doc, body, number):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(6)
    pf.space_after = Pt(8)
    pf.line_spacing = 1.2
    pf.tab_stops.add_tab_stop(Inches(TEXT_W / 2), WD_TAB_ALIGNMENT.CENTER)
    pf.tab_stops.add_tab_stop(Inches(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    r = p.add_run("\t" + body)
    r.font.size = Pt(BODY)
    r.font.name = "Times New Roman"
    r2 = p.add_run("\t" + number)
    r2.font.size = Pt(BODY)
    r2.font.name = "Times New Roman"
    return p


def figure(doc, path, number, caption, width=TEXT_W):
    width = min(width, TEXT_W - 0.1)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(3)
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(os.path.join(FIG_DIR, path), width=Inches(width))
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.paragraph_format.space_after = Pt(8)
    cap.paragraph_format.line_spacing = 1.0
    r = cap.add_run(f"Figure {number}  ")
    r.bold = True
    r.font.size = Pt(CAP_PT)
    r.font.name = "Times New Roman"
    r2 = cap.add_run(caption)
    r2.font.size = Pt(CAP_PT)
    r2.font.name = "Times New Roman"
    return cap


def table(doc, number, caption, header, rows, widths=None, font=TABLE_PT):
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.paragraph_format.space_before = Pt(6)
    cap.paragraph_format.space_after = Pt(3)
    cap.paragraph_format.keep_with_next = True
    cap.paragraph_format.line_spacing = 1.0
    r = cap.add_run(f"Table {number}  ")
    r.bold = True
    r.font.size = Pt(CAP_PT)
    r.font.name = "Times New Roman"
    r2 = cap.add_run(caption)
    r2.font.size = Pt(CAP_PT)
    r2.font.name = "Times New Roman"

    # scale the requested column widths into the text column
    if widths:
        total = sum(widths)
        widths = [w * TEXT_W / total for w in widths]

    t = doc.add_table(rows=1, cols=len(header))
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    tblPr = t._tbl.tblPr
    lay = OxmlElement("w:tblLayout")
    lay.set(qn("w:type"), "fixed")
    tblPr.append(lay)
    mar = OxmlElement("w:tblCellMar")
    for side in ("left", "right"):
        el = OxmlElement(f"w:{side}")
        el.set(qn("w:w"), "72")
        el.set(qn("w:type"), "dxa")
        mar.append(el)
    tblPr.append(mar)
    trPr = t.rows[0]._tr.get_or_add_trPr()
    trPr.append(OxmlElement("w:tblHeader"))

    def fill(cell, text, bold, align, fill_hex=None):
        cell.text = ""
        p = cell.paragraphs[0]
        p.alignment = align
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.line_spacing = 1.0
        run = p.add_run(text)
        run.bold = bold
        run.font.size = Pt(font)
        run.font.name = "Times New Roman"
        if fill_hex:
            tcPr = cell._tc.get_or_add_tcPr()
            shd = OxmlElement("w:shd")
            shd.set(qn("w:val"), "clear")
            shd.set(qn("w:fill"), fill_hex)
            tcPr.append(shd)

    for i, h in enumerate(header):
        fill(t.rows[0].cells[i], h, True, WD_ALIGN_PARAGRAPH.CENTER, "EDEFF3")
    for row in rows:
        nr = t.add_row()
        nr._tr.get_or_add_trPr().append(OxmlElement("w:cantSplit"))
        for i, val in enumerate(row):
            fill(nr.cells[i], str(val), False,
                 WD_ALIGN_PARAGRAPH.LEFT if i == 0 else WD_ALIGN_PARAGRAPH.CENTER)
    if widths:
        for row in t.rows:
            for i, w in enumerate(widths):
                row.cells[i].width = Inches(w)
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def code(doc, filename, text, number, caption):
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    p.paragraph_format.line_spacing = 1.0
    r = p.add_run(f"Listing {number}: ")
    r.bold = True
    r.font.size = Pt(10.5)
    r.font.name = "Times New Roman"
    r2 = p.add_run(f"{caption} ({filename})")
    r2.font.size = Pt(10.5)
    r2.font.name = "Times New Roman"
    for line in text.split("\n"):
        cp = doc.add_paragraph()
        cp.paragraph_format.space_after = Pt(0)
        cp.paragraph_format.space_before = Pt(0)
        cp.paragraph_format.line_spacing = 1.0
        cp.paragraph_format.left_indent = Inches(0.12)
        cr = cp.add_run(line if line else " ")
        cr.font.name = "Consolas"
        cr.font.size = Pt(8.5)
        shade(cp)
    doc.add_paragraph().paragraph_format.space_after = Pt(4)


# --------------------------------------------------------------- toc collection
def norm(text):
    return re.sub(r"\s+", "", text)


def collect_entries():
    """Ordered list of (kind, key, display, level) for the table of contents."""
    out = []
    for mod in MODULES:
        for b in blocks_for(mod):
            if b[0] == "chapter":
                out.append(("h1", norm(f"CHAPTER {b[1]} {b[2]}"),
                            f"{b[1]}.   {b[2]}", 0))
            elif b[0] == "h2":
                out.append(("h2", norm(f"{b[1]} {b[2]}"), f"{b[1]}   {b[2]}", 1))
            elif b[0] == "h3":
                out.append(("h3", norm(f"{b[1]} {b[2]}"), f"{b[1]}   {b[2]}", 2))
            elif b[0] == "h4":
                out.append(("h4", norm(b[1]), b[1], 3))
    return out


def collect_tables_figures():
    tabs, figs = [], []
    for mod in MODULES:
        for b in blocks_for(mod):
            if b[0] == "tab":
                tabs.append((b[1], b[2]))
            elif b[0] == "fig":
                figs.append((b[2], b[3]))
    return tabs, figs


def load_pages():
    if os.path.exists(PAGE_MAP):
        with open(PAGE_MAP, encoding="utf-8") as f:
            return json.load(f)
    return {}


# ------------------------------------------------------------------ toc writing
INDENT = {0: 0.0, 1: 0.45, 2: 0.95, 3: 1.45}


def entry_line(doc, text, page, level, bold=False, size=12, after=0):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_after = Pt(after)
    pf.space_before = Pt(0)
    pf.line_spacing = 1.4
    pf.left_indent = Inches(INDENT[level] + (0.3 if level else 0.0))
    if level:
        pf.first_line_indent = Inches(-0.3)
    pf.tab_stops.add_tab_stop(Inches(TEXT_W), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS)
    r = p.add_run(text)
    r.bold = bold
    r.font.size = Pt(size)
    r.font.name = "Times New Roman"
    r2 = p.add_run("\t" + str(page))
    r2.bold = bold
    r2.font.size = Pt(size)
    r2.font.name = "Times New Roman"
    return p


def build_toc(doc, pages):
    from docx.enum.text import WD_BREAK
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.page_break_before = True
    p.paragraph_format.space_after = Pt(10)
    r = p.add_run("TABLE OF CONTENTS")
    r.bold = True
    r.font.size = Pt(16)
    r.font.name = "Times New Roman"

    hdr = doc.add_paragraph()
    hdr.paragraph_format.space_after = Pt(10)
    hdr.paragraph_format.line_spacing = 1.0
    hdr.paragraph_format.tab_stops.add_tab_stop(Inches(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    rr = hdr.add_run("CHAPTER / TITLE\tPAGE NO.")
    rr.bold = True
    rr.font.size = Pt(11)
    rr.font.name = "Times New Roman"

    for label in ("ACKNOWLEDGEMENT", "ABSTRACT", "LIST OF TABLES",
                  "LIST OF FIGURES",
                  "LIST OF SYMBOLS, ABBREVIATIONS AND NOMENCLATURE"):
        entry_line(doc, label, pages.get(norm(label), "\u2013"), 1)

    for kind, key, display, level in collect_entries():
        entry_line(doc, display, pages.get(key, "\u2013"), level,
                   bold=(level == 0))

    if INCLUDE_APPENDIX:
        entry_line(doc, "APPENDIX 1   SAMPLE CODE",
                   pages.get("APPENDIX1SAMPLECODE", "\u2013"), 0, bold=True)
    entry_line(doc, "REFERENCES", pages.get("REFERENCES", "\u2013"), 0, bold=True)


def build_lists(doc, pages):
    tabs, figs = collect_tables_figures()
    for title, entries, prefix in (("LIST OF TABLES", tabs, "Table"),
                                   ("LIST OF FIGURES", figs, "Figure")):
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.page_break_before = True
        p.paragraph_format.space_after = Pt(14)
        r = p.add_run(title)
        r.bold = True
        r.font.size = Pt(16)
        r.font.name = "Times New Roman"

        for num, cap in entries:
            q = doc.add_paragraph()
            pf = q.paragraph_format
            pf.space_after = Pt(2)
            pf.space_before = Pt(0)
            pf.line_spacing = 1.5
            pf.left_indent = Inches(0.55)
            pf.first_line_indent = Inches(-0.55)
            pf.right_indent = Inches(0.55)
            pf.tab_stops.add_tab_stop(Inches(TEXT_W), WD_TAB_ALIGNMENT.RIGHT,
                                      WD_TAB_LEADER.DOTS)
            r1 = q.add_run(f"{prefix} {num}  ")
            r1.bold = True
            r1.font.size = Pt(11)
            r1.font.name = "Times New Roman"
            r2 = q.add_run(cap)
            r2.font.size = Pt(11)
            r2.font.name = "Times New Roman"
            r3 = q.add_run("\t" + str(pages.get(norm(f"{prefix} {num} {cap}"), "\u2013")))
            r3.font.size = Pt(11)
            r3.font.name = "Times New Roman"


# ----------------------------------------------------------------------- render
def render(doc, blocks):
    for b in blocks:
        kind = b[0]
        if kind == "chapter":
            p = doc.add_paragraph(style="Heading 1")
            r = p.add_run(f"CHAPTER {b[1]}")
            r.add_break()
            p.add_run(b[2])
            p.paragraph_format.page_break_before = True
        elif kind == "h2":
            p = doc.add_paragraph(style="Heading 2")
            p.add_run(f"{b[1]}   {b[2]}")
        elif kind == "h3":
            p = doc.add_paragraph(style="Heading 3")
            p.add_run(f"{b[1]}   {b[2]}")
        elif kind == "h4":
            p = doc.add_paragraph(style="Heading 4")
            p.add_run(b[1])
        elif kind == "p":
            para(doc, b[1])
        elif kind == "pc":
            para(doc, b[1], align="center")
        elif kind == "bul":
            for item in b[1]:
                bullet(doc, item)
            doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
        elif kind == "num":
            for i, item in enumerate(b[1], start=1):
                p = doc.add_paragraph()
                pf = p.paragraph_format
                pf.left_indent = Inches(0.5)
                pf.first_line_indent = Inches(-0.35)
                pf.space_after = Pt(5)
                pf.line_spacing = 1.5
                pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
                r = p.add_run(f"({chr(96 + i)})  ")
                r.font.size = Pt(BODY)
                r.font.name = "Times New Roman"
                r2 = p.add_run(item)
                r2.font.size = Pt(BODY)
                r2.font.name = "Times New Roman"
            doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
        elif kind == "bul2":
            for lead, rest in b[1]:
                p = bullet(doc, "", marker="\u2022")
                r1 = p.add_run(lead)
                r1.bold = True
                r1.font.size = Pt(BODY)
                r1.font.name = "Times New Roman"
                r2 = p.add_run(rest)
                r2.font.size = Pt(BODY)
                r2.font.name = "Times New Roman"
            doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
        elif kind == "eq":
            equation(doc, b[1], b[2])
        elif kind == "fig":
            w = b[4] if len(b) > 4 else TEXT_W
            if b[2] in SHRINK_FIGS:
                w = min(w, SHRINK_TO)
            elif 1.8 < w < 2.8:
                w = w * 0.80
            figure(doc, b[1], b[2], b[3], w)
        elif kind == "tab":
            table(doc, b[1], b[2], b[3], b[4], b[5] if len(b) > 5 else None)
        elif kind == "code":
            code(doc, b[1], b[2], b[3], b[4])
        elif kind == "pagebreak":
            doc.add_page_break()
        elif kind == "space":
            para(doc, "", space_after=b[1])
        else:
            raise ValueError(kind)


def new_section(doc, fmt, start, suppress_first=False, show=True):
    sec = doc.add_section(WD_SECTION.NEW_PAGE)
    sec.page_width = Cm(21.0)
    sec.page_height = Cm(29.7)
    sec.top_margin = Inches(1.0)
    sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.5)
    sec.right_margin = Inches(1.02)
    footer_number(sec, fmt, start, suppress_first=suppress_first, show=show)
    return sec


def main():
    pages = load_pages()
    doc = Document()
    setup(doc)

    # section 1: cover page, no page number
    footer_number(doc.sections[0], "lowerRoman", 1, show=False)
    FA.cover_page(doc)

    # section 2: title page (page i, number suppressed)
    new_section(doc, "lowerRoman", 1, suppress_first=True)
    FA.cover_page(doc)

    # section 3: remaining front matter, roman numbering continues
    new_section(doc, "lowerRoman", None)
    FA.bonafide(doc)
    FA.viva(doc)
    FA.acknowledgement(doc)
    FA.abstract(doc)

    build_toc(doc, pages)
    build_lists(doc, pages)
    FA.symbols_and_abbreviations(doc)

    # section 4: chapters, arabic numbering from 1
    new_section(doc, "decimal", 1)
    for mod in MODULES:
        render(doc, blocks_for(mod))

    # appendix 1 (omitted from the shortened submission copy)
    if not INCLUDE_APPENDIX:
        p = None
    p = doc.add_paragraph(style="Heading 1") if INCLUDE_APPENDIX else None
    if INCLUDE_APPENDIX:
        p.paragraph_format.page_break_before = True
        r = p.add_run("APPENDIX 1")
        r.add_break()
        p.add_run("SAMPLE CODE")

    def appx_para(doc_, text="", **kw):
        if text.startswith("7.5"):
            return None
        return para(doc_, text, **kw)

    APPX_CAPTIONS = {
        "1": "Weighted scoring with per-term explanation",
        "2": "Ranked allocation with a bounded offer chain",
        "3": "Lifecycle transition table",
        "4": "Client-side impact detection with window validation",
    }

    def appx_code(doc_, filename, text, number, caption):
        n = number.split(".")[-1]
        return code(doc_, filename, text, "A." + n, APPX_CAPTIONS.get(n, caption))

    if INCLUDE_APPENDIX:
        C7.appendix(doc, appx_para, appx_code, table)

    # references
    p = doc.add_paragraph(style="Heading 1")
    p.paragraph_format.page_break_before = True
    p.add_run("REFERENCES")
    for i, ref in enumerate(C7.REFERENCES, start=1):
        body = re.sub(r"^\[\d+\]\s*", "", ref)
        rp = doc.add_paragraph()
        pf = rp.paragraph_format
        pf.left_indent = Inches(0.45)
        pf.first_line_indent = Inches(-0.45)
        pf.space_after = Pt(6)
        pf.line_spacing = 1.0
        pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        r1 = rp.add_run(f"{i}.\t")
        r1.font.size = Pt(12)
        r1.font.name = "Times New Roman"
        r2 = rp.add_run(body)
        r2.font.size = Pt(12)
        r2.font.name = "Times New Roman"

    settings = doc.settings.element
    uf = OxmlElement("w:updateFields")
    uf.set(qn("w:val"), "false")
    settings.append(uf)

    doc.save(OUT)
    with open("_toc_entries.json", "w", encoding="utf-8") as f:
        json.dump({
            "front": ["ACKNOWLEDGEMENT", "ABSTRACT", "LIST OF TABLES",
                      "LIST OF FIGURES",
                      "LIST OF SYMBOLS, ABBREVIATIONS AND NOMENCLATURE"],
            "entries": [[k, key, d, l] for k, key, d, l in collect_entries()],
            "tables": [[n, c] for n, c in collect_tables_figures()[0]],
            "figures": [[n, c] for n, c in collect_tables_figures()[1]],
            "tail": ["APPENDIX1SAMPLECODE", "REFERENCES"],
        }, f, ensure_ascii=False, indent=1)
    print("saved", OUT)


if __name__ == "__main__":
    main()
