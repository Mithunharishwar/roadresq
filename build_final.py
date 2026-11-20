# -*- coding: utf-8 -*-
"""Build the RoadResQ project report in the approved reference layout.

The layout metrics (A4, 3.7 / 2.4 / 2.4 / 2.3 cm margins, Times New Roman 12 pt
justified body at 1.5 line spacing, 14 pt bold centred chapter headings,
12.5 pt bold section headings, 10.5 pt captions, 9 pt table text, numbered
references at 11 pt) are copied from proj_116report.docx, which is the approved
reference report.

Usage:  python build_final.py .        (page numbers left as en dashes)
        python build_final.py mapped   (page numbers from page_map4.json)
"""
import json
import os
import re
import sys

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

import content_ch1 as C1
import content_ch2 as C2
import content_ch3 as C3
import content_ch4 as C4
import content_ch5 as C5
import content_ch6 as C6
import content_ch7 as C7
import front_final as FF
from front_final import TEXT_W, _run

OUT = r"C:\Users\Admin\OneDrive\Desktop\gopal\roadresq\RoadResQ_Report_Final.docx"
PDF = r"C:\Users\Admin\OneDrive\Desktop\gopal\roadresq\RoadResQ_Report_Final.pdf"
FIG_DIR = r"C:\Users\Admin\OneDrive\Desktop\gopal\roadresq\figs"
PAGE_MAP = r"C:\Users\Admin\OneDrive\Desktop\gopal\roadresq\page_map4.json"

BODY = 12
H1 = 14
H2 = 12.5
H3 = 12
CAP = 10.5
TBL = 9
EQ = 11.5
REF = 11
MAX_FIG_H = 16.6        # cm

MODULES = (C1, C2, C3, C4, C5, C6, C7)
LEVEL = {"chapter": 0, "h2": 1, "h3": 2, "h4": 3}
FRONT_KEYS = ["ACKNOWLEDGEMENT", "ABSTRACT", "LIST OF TABLES", "LIST OF FIGURES",
              "LIST OF SYMBOLS AND ABBREVIATIONS"]


# ------------------------------------------------------------------ utilities
def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


ROMAN = ["", "i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x", "xi",
         "xii", "xiii", "xiv", "xv", "xvi", "xvii", "xviii", "xix", "xx"]


def roman(n):
    if n < len(ROMAN):
        return ROMAN[n]
    vals = [(1000, "m"), (900, "cm"), (500, "d"), (400, "cd"), (100, "c"),
            (90, "xc"), (50, "l"), (40, "xl"), (10, "x"), (9, "ix"),
            (5, "v"), (4, "iv"), (1, "i")]
    out = ""
    for v, s in vals:
        while n >= v:
            out += s
            n -= v
    return out


def lower_roman(n):
    return "(%s)" % roman(n)


def _field(paragraph, instr):
    run = paragraph.add_run()
    b = OxmlElement("w:fldChar"); b.set(qn("w:fldCharType"), "begin")
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = instr
    s = OxmlElement("w:fldChar"); s.set(qn("w:fldCharType"), "separate")
    t = OxmlElement("w:t"); t.text = "1"
    e = OxmlElement("w:fldChar"); e.set(qn("w:fldCharType"), "end")
    for el in (b, it, s, t, e):
        run._r.append(el)
    run.font.size = Pt(11)
    run.font.name = "Times New Roman"
    return run


def set_pgnum(section, fmt, start=None):
    sectPr = section._sectPr
    for old in sectPr.findall(qn("w:pgNumType")):
        sectPr.remove(old)
    pg = OxmlElement("w:pgNumType")
    pg.set(qn("w:fmt"), fmt)
    if start is not None:
        pg.set(qn("w:start"), str(start))
    sectPr.append(pg)


def footer_page_number(section, fmt, start=None, suppress_first=False):
    section.footer.is_linked_to_previous = False
    p = section.footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(0)
    for r in list(p.runs):
        r._r.getparent().remove(r._r)
    _field(p, " PAGE ")
    set_pgnum(section, fmt, start)
    section.different_first_page_header_footer = bool(suppress_first)
    if suppress_first:
        fp = section.first_page_footer
        fp.is_linked_to_previous = False
        for pp in fp.paragraphs:
            for r in list(pp.runs):
                r._r.getparent().remove(r._r)


def page_setup(section):
    section.page_width = Cm(21.0)
    section.page_height = Cm(29.7)
    section.left_margin = Cm(3.7)
    section.right_margin = Cm(2.4)
    section.top_margin = Cm(2.4)
    section.bottom_margin = Cm(2.3)
    section.header_distance = Cm(1.2)
    section.footer_distance = Cm(1.1)


def setup_styles(doc):
    st = doc.styles["Normal"]
    st.font.name = "Times New Roman"
    st.font.size = Pt(BODY)
    st.font.color.rgb = None
    rpr = st.element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = OxmlElement("w:rFonts")
        rpr.append(rf)
    for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        rf.set(qn(a), "Times New Roman")
    pf = st.paragraph_format
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    pf.line_spacing = 1.5
    pf.space_before = Pt(0)
    pf.space_after = Pt(6)

    for name, size, bold, italic, align, before, after, ls in [
        ("Heading 1", H1, True, False, WD_ALIGN_PARAGRAPH.CENTER, 6, 14, 1.5),
        ("Heading 2", H2, True, False, WD_ALIGN_PARAGRAPH.LEFT, 14, 2, 1.3),
        ("Heading 3", H3, True, False, WD_ALIGN_PARAGRAPH.LEFT, 10, 4, 1.3),
        ("Heading 4", H3, True, True, WD_ALIGN_PARAGRAPH.LEFT, 8, 4, 1.3),
    ]:
        s = doc.styles[name]
        s.font.name = "Times New Roman"
        s.font.size = Pt(size)
        s.font.bold = bold
        s.font.italic = italic
        s.font.color.rgb = None
        s.paragraph_format.alignment = align
        s.paragraph_format.space_before = Pt(before)
        s.paragraph_format.space_after = Pt(after)
        s.paragraph_format.line_spacing = ls
        s.paragraph_format.keep_with_next = True
        rpr = s.element.get_or_add_rPr()
        rf = rpr.find(qn("w:rFonts"))
        if rf is None:
            rf = OxmlElement("w:rFonts")
            rpr.append(rf)
        for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
            rf.set(qn(a), "Times New Roman")


# ------------------------------------------------------------- block helpers
def body_para(doc, text):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(6)
    _run(p, text, BODY)
    return p


def bullet(doc, marker, item):
    """One list item; item is a string or a (bold lead-in, remainder) tuple."""
    lead, rest = item if isinstance(item, tuple) else (None, item)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    pf = p.paragraph_format
    pf.left_indent = Cm(1.0)
    pf.first_line_indent = Cm(-0.55)
    pf.line_spacing = 1.5
    pf.space_after = Pt(3)
    pf.tab_stops.add_tab_stop(Cm(1.0), WD_TAB_ALIGNMENT.LEFT)
    _run(p, marker + "\t", BODY)
    if lead:
        _run(p, lead, BODY, True)
    _run(p, rest, BODY)
    return p


def equation(doc, text, number):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(8)
    pf.space_after = Pt(8)
    pf.line_spacing = 1.2
    pf.tab_stops.add_tab_stop(Cm(TEXT_W / 2), WD_TAB_ALIGNMENT.CENTER)
    pf.tab_stops.add_tab_stop(Cm(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    _run(p, "\t" + text, EQ)
    _run(p, "\t(%s)" % number, EQ)
    return p


def caption(doc, label, text, before=2, after=10, keep=False):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pf = p.paragraph_format
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = 1.0
    pf.keep_with_next = False
    _run(p, label + "  ", CAP, True)
    _run(p, text, CAP)
    return p


def figure(doc, path, number, text, width_in):
    from docx.shared import Inches
    from PIL import Image  # noqa: F401  (kept optional)

    full = os.path.join(FIG_DIR, path)
    w_cm = min(width_in * 2.54, TEXT_W - 0.3)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.keep_with_next = True
    run = p.add_run()
    run.add_picture(full, width=Cm(w_cm))
    # enforce a maximum height
    inline = run._r.findall(".//" + qn("wp:extent"))
    if inline:
        ext = inline[0]
        cx = int(ext.get("cx"))
        cy = int(ext.get("cy"))
        maxh = Cm(MAX_FIG_H)
        if cy > maxh:
            scale = maxh / cy
            for target in (ext,):
                target.set("cx", str(int(cx * scale)))
                target.set("cy", str(int(cy * scale)))
            for tag in ("a:ext",):
                for e in run._r.findall(".//" + qn(tag)):
                    if e.get("cx") is not None:
                        e.set("cx", str(int(int(e.get("cx")) * scale)))
                        e.set("cy", str(int(int(e.get("cy")) * scale)))
    caption(doc, "Figure %s" % number, text, before=2, after=10)
    return p


def _cell_text(cell, text, bold, align, size=TBL, shade=None):
    cell.text = ""
    p = cell.paragraphs[0]
    p.alignment = align
    pf = p.paragraph_format
    pf.space_before = Pt(2)
    pf.space_after = Pt(1.5)
    pf.line_spacing = 1.0
    _run(p, text, size, bold)
    if shade:
        tcPr = cell._tc.get_or_add_tcPr()
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:color"), "auto")
        shd.set(qn("w:fill"), shade)
        tcPr.append(shd)


def table(doc, number, text, header, rows, widths):
    caption(doc, "Table %s" % number, text, before=8, after=4)
    total = sum(widths)
    widths = [w * TEXT_W / total for w in widths]

    t = doc.add_table(rows=1, cols=len(header))
    t.style = doc.styles["Table Grid"]
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    tblPr = t._tbl.tblPr
    lay = OxmlElement("w:tblLayout")
    lay.set(qn("w:type"), "fixed")
    tblPr.append(lay)
    trPr = t.rows[0]._tr.get_or_add_trPr()
    trPr.append(OxmlElement("w:tblHeader"))
    trPr.append(OxmlElement("w:cantSplit"))

    numeric_first = all(re.match(r"^[\d,\.\u2013\u2212+\-]+$", str(r[0])) for r in rows)
    for i, h in enumerate(header):
        _cell_text(t.rows[0].cells[i], h, True, WD_ALIGN_PARAGRAPH.CENTER,
                   shade="DCE6F1")
    for row in rows:
        nr = t.add_row()
        nr._tr.get_or_add_trPr().append(OxmlElement("w:cantSplit"))
        for i, val in enumerate(row):
            if i == 0 and not numeric_first:
                align = WD_ALIGN_PARAGRAPH.LEFT
            else:
                align = WD_ALIGN_PARAGRAPH.CENTER
            _cell_text(nr.cells[i], str(val), False, align)
    for row in t.rows:
        for i, w in enumerate(widths):
            row.cells[i].width = Cm(w)
    FF.line(doc, "", size=6, after=4)
    return t


def code_block(doc, filename, text, number, cap):
    for ln in text.split("\n"):
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.space_before = Pt(0)
        pf.space_after = Pt(0)
        pf.line_spacing = 1.0
        pf.left_indent = Cm(0.2)
        _run(p, ln if ln else " ", 8.5, font="Consolas")
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:fill"), "F5F5F5")
        p._p.get_or_add_pPr().append(shd)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    p.paragraph_format.space_before = Pt(2)
    p.paragraph_format.space_after = Pt(8)
    p.paragraph_format.line_spacing = 1.0
    _run(p, "%s" % filename, 9, italic=True)


def reference(doc, text):
    m = re.match(r"^\[(\d+)\]\s*(.*)$", text, re.S)
    num, rest = (m.group(1), m.group(2)) if m else ("", text)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    pf = p.paragraph_format
    pf.left_indent = Cm(1.0)
    pf.first_line_indent = Cm(-1.0)
    pf.line_spacing = 1.3
    pf.space_after = Pt(8)
    pf.tab_stops.add_tab_stop(Cm(1.0), WD_TAB_ALIGNMENT.LEFT)
    _run(p, "[%s]\t" % num, REF)
    _run(p, rest.strip(), REF)
    return p


# ------------------------------------------------------------ heading blocks
def chapter_heading(doc, number, title):
    p = doc.add_paragraph(style="Heading 1")
    p.paragraph_format.page_break_before = True
    r = p.add_run("CHAPTER %s" % number)
    _run(p, "", H1)
    r.font.size = Pt(H1)
    r.font.name = "Times New Roman"
    r.bold = True
    r.add_break()
    r2 = p.add_run(title)
    r2.font.size = Pt(H1)
    r2.font.name = "Times New Roman"
    r2.bold = True
    return p


def section_heading(doc, num, title, level):
    label = num if re.match(r"^[\d.]+$", num) else ("%s:" % num if num else "")
    text = ("%s  %s" % (label, title)) if label else title
    p = doc.add_paragraph(style="Heading %d" % (level + 1))
    _run(p, text, H2 if level == 1 else H3, True)
    return p, text


def h4_heading(doc, text):
    p = doc.add_paragraph(style="Heading 4")
    _run(p, text, H3, True, True)
    return p


# ------------------------------------------------------------- entry collect
def collect_entries():
    """(level, num, title, key) for the table of contents."""
    out = []
    for mod in MODULES:
        for b in mod.BLOCKS:
            if b[0] == "chapter":
                out.append((0, b[1], b[2], "h:" + norm("CHAPTER %s %s" % (b[1], b[2]))))
            elif b[0] == "h2":
                out.append((1, b[1], b[2], "h:" + norm("%s %s" % (b[1], b[2]))))
            elif b[0] == "h3":
                label = b[1] if re.match(r"^[\d.]+$", b[1]) else ("%s:" % b[1])
                out.append((2, label, b[2], "h:" + norm("%s %s" % (label, b[2]))))
    out.append((0, "", "REFERENCES", "h:" + norm("REFERENCES")))
    return out


def collect_tables_figures():
    tabs, figs = [], []
    for mod in MODULES:
        for b in mod.BLOCKS:
            if b[0] == "tab":
                tabs.append((b[1], b[2]))
            elif b[0] == "fig":
                figs.append((b[2], b[3]))
    return tabs, figs


# ------------------------------------------------------------------- TOC etc
def tabbed(doc, num, title, page, num_cm, title_cm, bold=False, after=3, size=BODY):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    pf = p.paragraph_format
    pf.left_indent = Cm(title_cm)
    pf.first_line_indent = Cm(num_cm - title_cm)
    pf.line_spacing = 1.25
    pf.space_before = Pt(0)
    pf.space_after = Pt(after)
    pf.tab_stops.add_tab_stop(Cm(title_cm), WD_TAB_ALIGNMENT.LEFT)
    pf.tab_stops.add_tab_stop(Cm(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    _run(p, "%s\t%s\t%s" % (num, title, page), size, bold)
    return p


def build_toc(doc, pages):
    FF.heading(doc, "TABLE OF CONTENTS", after=12, page_break=True)
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = 1.0
    pf.space_after = Pt(8)
    pf.tab_stops.add_tab_stop(Cm(3.2), WD_TAB_ALIGNMENT.LEFT)
    pf.tab_stops.add_tab_stop(Cm(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    _run(p, "CHAPTER NO.\tTITLE\tPAGE NO.", BODY, True)

    for label in FRONT_KEYS:
        tabbed(doc, "", label, pages.get("fm:" + label, "\u2013"), 0.0, 3.2, after=3)
    for level, num, title, key in collect_entries():
        num_cm = (0.0, 1.3, 3.1)[level]
        title_cm = (1.3, 3.2, 4.9)[level]
        tabbed(doc, num, title, pages.get(key, "\u2013"), num_cm, title_cm,
               after=2 if level else 4)


def build_lists(doc, pages):
    tabs, figs = collect_tables_figures()

    FF.heading(doc, "LIST OF TABLES", after=12, page_break=True)
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = 1.0
    pf.space_after = Pt(8)
    pf.tab_stops.add_tab_stop(Cm(2.6), WD_TAB_ALIGNMENT.LEFT)
    pf.tab_stops.add_tab_stop(Cm(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    _run(p, "TABLE NO.\tTITLE\tPAGE NO.", BODY, True)
    for num, cap in tabs:
        tabbed(doc, num, cap, pages.get("t:" + num, "\u2013"), 0.0, 2.6, after=4)

    FF.heading(doc, "LIST OF FIGURES", after=12, page_break=True)
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.line_spacing = 1.0
    pf.space_after = Pt(8)
    pf.tab_stops.add_tab_stop(Cm(3.2), WD_TAB_ALIGNMENT.LEFT)
    pf.tab_stops.add_tab_stop(Cm(TEXT_W), WD_TAB_ALIGNMENT.RIGHT)
    _run(p, "FIGURE NO.\tTITLE\tPAGE NO.", BODY, True)
    for num, cap in figs:
        tabbed(doc, num, cap, pages.get("f:" + num, "\u2013"), 0.0, 3.2, after=4)


# --------------------------------------------------------------------- main
def build(pages):
    doc = Document()
    setup_styles(doc)
    sec0 = doc.sections[0]
    page_setup(sec0)
    footer_page_number(sec0, "lowerRoman", 1, suppress_first=True)

    FF.title_page(doc)
    FF.bonafide(doc)
    FF.viva(doc)
    FF.acknowledgement(doc)
    FF.abstract(doc)
    build_toc(doc, pages)
    build_lists(doc, pages)
    FF.symbols_and_abbreviations(doc)

    sec1 = doc.add_section(WD_SECTION.NEW_PAGE)
    page_setup(sec1)
    footer_page_number(sec1, "decimal", 1, suppress_first=False)

    for mod in MODULES:
        for b in mod.BLOCKS:
            kind = b[0]
            if kind == "chapter":
                chapter_heading(doc, b[1], b[2])
            elif kind in ("h2", "h3"):
                section_heading(doc, b[1], b[2], 1 if kind == "h2" else 2)
            elif kind == "h4":
                h4_heading(doc, b[1])
            elif kind == "p":
                body_para(doc, b[1])
            elif kind == "num":
                for i, item in enumerate(b[1], 1):
                    bullet(doc, lower_roman(i), item)
            elif kind in ("bul", "bul2"):
                for item in b[1]:
                    bullet(doc, "\u2022", item)
            elif kind == "eq":
                equation(doc, b[1], b[2])
            elif kind == "fig":
                figure(doc, b[1], b[2], b[3], b[4] if len(b) > 4 else 6.0)
            elif kind == "tab":
                table(doc, b[1], b[2], b[3], b[4], b[5])
            elif kind == "code":
                code_block(doc, b[1], b[2], b[3], b[4])

    # references
    p = doc.add_paragraph(style="Heading 1")
    p.paragraph_format.page_break_before = True
    _run(p, "REFERENCES", H1, True)
    for ref in C7.REFERENCES:
        reference(doc, ref)

    doc.save(OUT)
    return OUT


def main():
    pages = {}
    if len(sys.argv) > 1 and sys.argv[1] == "mapped":
        if os.path.exists(PAGE_MAP):
            pages = json.load(open(PAGE_MAP, encoding="utf-8"))
            print("loaded %d page entries" % len(pages))
    out = build(pages)
    print("saved", out, os.path.getsize(out))


if __name__ == "__main__":
    main()
