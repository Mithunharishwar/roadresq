"""Build the RoadResQ final project report (DOCX) in Anna University format."""
import os
from docx import Document
from docx.shared import Pt, Inches, RGBColor, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING, WD_BREAK
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.enum.text import WD_TAB_ALIGNMENT

import content_front as CF
import content_ch1 as C1
import content_ch2 as C2
import content_ch3 as C3
import content_ch4 as C4
import content_ch5 as C5
import content_ch6 as C6
import content_ch7 as C7

OUT = "RoadResQ_Final_Project_Report.docx"
FIG_DIR = "figs"


# ------------------------------------------------------------------ helpers
def _field(paragraph, instr, placeholder="1"):
    run = paragraph.add_run()
    fld_begin = OxmlElement("w:fldChar")
    fld_begin.set(qn("w:fldCharType"), "begin")
    instr_el = OxmlElement("w:instrText")
    instr_el.set(qn("xml:space"), "preserve")
    instr_el.text = instr
    fld_sep = OxmlElement("w:fldChar")
    fld_sep.set(qn("w:fldCharType"), "separate")
    txt = OxmlElement("w:t")
    txt.text = placeholder
    fld_end = OxmlElement("w:fldChar")
    fld_end.set(qn("w:fldCharType"), "end")
    run._r.append(fld_begin)
    run._r.append(instr_el)
    run._r.append(fld_sep)
    run._r.append(txt)
    run._r.append(fld_end)
    return run


def shade(paragraph, hexcolor="F2F2F2"):
    pPr = paragraph._p.get_or_add_pPr()
    shd = OxmlElement("w:shd")
    shd.set(qn("w:val"), "clear")
    shd.set(qn("w:color"), "auto")
    shd.set(qn("w:fill"), hexcolor)
    pPr.append(shd)


def border(paragraph):
    pPr = paragraph._p.get_or_add_pPr()
    borders = OxmlElement("w:pBdr")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), "4")
        el.set(qn("w:space"), "4")
        el.set(qn("w:color"), "BFBFBF")
        borders.append(el)
    pPr.append(borders)


def keep_with_next(paragraph):
    pPr = paragraph._p.get_or_add_pPr()
    el = OxmlElement("w:keepNext")
    pPr.append(el)


def page_number_footer(section, fmt="decimal", start=None, suppress_first=False):
    footer = section.footer
    footer.is_linked_to_previous = False
    p = footer.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    _field(p, " PAGE ", "1")
    for r in p.runs:
        r.font.name = "Times New Roman"
        r.font.size = Pt(11)
    sectPr = section._sectPr
    pg = sectPr.find(qn("w:pgNumType"))
    if pg is None:
        pg = OxmlElement("w:pgNumType")
        sectPr.append(pg)
    pg.set(qn("w:fmt"), fmt)
    if start is not None:
        pg.set(qn("w:start"), str(start))
    if suppress_first:
        section.different_first_page_header_footer = True


def setup(doc):
    st = doc.styles["Normal"]
    st.font.name = "Times New Roman"
    st.font.size = Pt(12)
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
        ("Heading 1", 14, True, False, 0, 18, WD_ALIGN_PARAGRAPH.CENTER),
        ("Heading 2", 12, True, False, 14, 6, WD_ALIGN_PARAGRAPH.LEFT),
        ("Heading 3", 12, True, True, 10, 4, WD_ALIGN_PARAGRAPH.LEFT),
        ("Heading 4", 12, True, True, 8, 4, WD_ALIGN_PARAGRAPH.LEFT),
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

    # tighten the generated table-of-contents styles so the TOC fits its pages
    from docx.enum.style import WD_STYLE_TYPE
    for lvl, size in ((1, 12), (2, 11.5), (3, 11)):
        name = f"TOC {lvl}"
        try:
            s = doc.styles[name]
        except KeyError:
            s = doc.styles.add_style(name, WD_STYLE_TYPE.PARAGRAPH)
        s.font.name = "Times New Roman"
        s.font.size = Pt(size)
        s.font.color.rgb = RGBColor(0, 0, 0)
        s.paragraph_format.space_before = Pt(0)
        s.paragraph_format.space_after = Pt(3)
        s.paragraph_format.line_spacing = 1.0

    sec = doc.sections[0]
    sec.page_width = Cm(21.0)
    sec.page_height = Cm(29.7)
    sec.top_margin = Inches(1.0)
    sec.bottom_margin = Inches(1.0)
    sec.left_margin = Inches(1.5)
    sec.right_margin = Inches(1.0)


def para(doc, text="", size=12, bold=False, italic=False, align="justify",
         space_after=6, space_before=0, spacing=1.5, indent=0, style=None):
    p = doc.add_paragraph(style=style)
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


def rich(doc, parts, align="justify", space_after=6, spacing=1.5, size=12):
    """parts: list of (text, bold, italic) tuples."""
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.alignment = {"justify": WD_ALIGN_PARAGRAPH.JUSTIFY,
                    "center": WD_ALIGN_PARAGRAPH.CENTER,
                    "left": WD_ALIGN_PARAGRAPH.LEFT}[align]
    pf.space_after = Pt(space_after)
    pf.line_spacing = spacing
    for text, bold, italic in parts:
        r = p.add_run(text)
        r.bold = bold
        r.italic = italic
        r.font.size = Pt(size)
        r.font.name = "Times New Roman"
    return p


def bullet(doc, text, level=0, marker="\u2022"):
    style = "List Bullet" if level == 0 else "List Bullet 2"
    p = doc.add_paragraph(style=style)
    pf = p.paragraph_format
    pf.left_indent = Inches(0.42 + 0.30 * level)
    pf.first_line_indent = Inches(-0.22)
    pf.space_after = Pt(4)
    pf.space_before = Pt(0)
    pf.line_spacing = 1.35
    pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    r2 = p.add_run(text)
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"
    return p


def equation(doc, body, number):
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.space_before = Pt(6)
    pf.space_after = Pt(8)
    pf.line_spacing = 1.2
    usable = 6.0
    pf.tab_stops.add_tab_stop(Inches(usable / 2), WD_TAB_ALIGNMENT.CENTER)
    pf.tab_stops.add_tab_stop(Inches(usable), WD_TAB_ALIGNMENT.RIGHT)
    r = p.add_run("\t" + body)
    r.italic = False
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"
    r2 = p.add_run("\t" + number)
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"
    return p


def figure(doc, path, number, caption, width=5.9):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.keep_with_next = True
    p.add_run().add_picture(os.path.join(FIG_DIR, path), width=Inches(width))
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.paragraph_format.space_after = Pt(12)
    cap.paragraph_format.line_spacing = 1.0
    r = cap.add_run(f"Figure {number}  ")
    r.bold = True
    r.font.size = Pt(10)
    r.font.name = "Times New Roman"
    r2 = cap.add_run(caption)
    r2.font.size = Pt(10)
    r2.font.name = "Times New Roman"
    return cap


def table(doc, number, caption, header, rows, widths=None, font=9.5):
    cap = doc.add_paragraph()
    cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
    cap.paragraph_format.space_before = Pt(10)
    cap.paragraph_format.space_after = Pt(4)
    cap.paragraph_format.keep_with_next = True
    cap.paragraph_format.line_spacing = 1.0
    r = cap.add_run(f"Table {number}  ")
    r.bold = True
    r.font.size = Pt(10)
    r.font.name = "Times New Roman"
    r2 = cap.add_run(caption)
    r2.font.size = Pt(10)
    r2.font.name = "Times New Roman"

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
    # repeat the header row on every page a long table occupies
    trPr = t.rows[0]._tr.get_or_add_trPr()
    th = OxmlElement("w:tblHeader")
    trPr.append(th)

    hdr = t.rows[0].cells
    for i, h in enumerate(header):
        hdr[i].text = ""
        p = hdr[i].paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p.paragraph_format.space_after = Pt(2)
        p.paragraph_format.space_before = Pt(2)
        p.paragraph_format.line_spacing = 1.0
        run = p.add_run(h)
        run.bold = True
        run.font.size = Pt(font)
        run.font.name = "Times New Roman"
        tcPr = hdr[i]._tc.get_or_add_tcPr()
        shd = OxmlElement("w:shd")
        shd.set(qn("w:val"), "clear")
        shd.set(qn("w:fill"), "EDEFF3")
        tcPr.append(shd)

    for row in rows:
        new_row = t.add_row()
        trPr2 = new_row._tr.get_or_add_trPr()
        cs = OxmlElement("w:cantSplit")
        trPr2.append(cs)
        cells = new_row.cells
        for i, val in enumerate(row):
            cells[i].text = ""
            p = cells[i].paragraphs[0]
            p.paragraph_format.space_after = Pt(2)
            p.paragraph_format.space_before = Pt(2)
            p.paragraph_format.line_spacing = 1.0
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT if i == 0 else WD_ALIGN_PARAGRAPH.CENTER
            run = p.add_run(str(val))
            run.font.size = Pt(font)
            run.font.name = "Times New Roman"

    if widths:
        for r_ in t.rows:
            for i, w in enumerate(widths):
                r_.cells[i].width = Inches(w)

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
    r.font.size = Pt(10)
    r.font.name = "Times New Roman"
    r2 = p.add_run(f"{caption} ({filename})")
    r2.font.size = Pt(10)
    r2.font.name = "Times New Roman"

    for line in text.split("\n"):
        cp = doc.add_paragraph()
        cp.paragraph_format.space_after = Pt(0)
        cp.paragraph_format.space_before = Pt(0)
        cp.paragraph_format.line_spacing = 1.0
        cp.paragraph_format.left_indent = Inches(0.12)
        cr = cp.add_run(line if line else " ")
        cr.font.name = "Consolas"
        cr.font.size = Pt(8.2)
        shade(cp, "F7F7F7")
    doc.add_paragraph().paragraph_format.space_after = Pt(4)


# ------------------------------------------------------------------ content rendering
def render(doc, blocks):
    for b in blocks:
        kind = b[0]
        if kind == "chapter":
            p = doc.add_paragraph(style="Heading 1")
            r = p.add_run(f"CHAPTER {b[1]}")
            r.add_break()
            r2 = p.add_run(b[2])
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.space_after = Pt(20)
            p.paragraph_format.page_break_before = True
        elif kind == "h2":
            p = doc.add_paragraph(style="Heading 2")
            p.add_run(f"{b[1]}  {b[2]}")
        elif kind == "h3":
            p = doc.add_paragraph(style="Heading 3")
            p.add_run(f"{b[1]}  {b[2]}")
        elif kind == "h4":
            p = doc.add_paragraph(style="Heading 4")
            p.add_run(b[1])
        elif kind == "p":
            para(doc, b[1])
        elif kind == "pc":  # paragraph, centred
            para(doc, b[1], align="center")
        elif kind == "bul":
            for item in b[1]:
                bullet(doc, item)
            doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
        elif kind == "num":
            for i, item in enumerate(b[1], start=1):
                p = doc.add_paragraph()
                pf = p.paragraph_format
                pf.left_indent = Inches(0.42)
                pf.first_line_indent = Inches(-0.32)
                pf.space_after = Pt(5)
                pf.line_spacing = 1.35
                pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
                r = p.add_run(f"({chr(96 + i)})  " if i <= 26 else f"{i}.  ")
                r.font.size = Pt(12)
                r.font.name = "Times New Roman"
                r2 = p.add_run(item)
                r2.font.size = Pt(12)
                r2.font.name = "Times New Roman"
            doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
        elif kind == "bul2":
            for lead, rest in b[1]:
                p = doc.add_paragraph(style="List Bullet")
                pf = p.paragraph_format
                pf.left_indent = Inches(0.42)
                pf.first_line_indent = Inches(-0.22)
                pf.space_after = Pt(4)
                pf.space_before = Pt(0)
                pf.line_spacing = 1.35
                pf.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
                r1 = p.add_run(lead)
                r1.bold = True
                r1.font.size = Pt(12)
                r1.font.name = "Times New Roman"
                r2 = p.add_run(rest)
                r2.font.size = Pt(12)
                r2.font.name = "Times New Roman"
            doc.paragraphs[-1].paragraph_format.space_after = Pt(8)
        elif kind == "eq":
            equation(doc, b[1], b[2])
        elif kind == "fig":
            figure(doc, b[1], b[2], b[3], b[4] if len(b) > 4 else 5.9)
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


# ------------------------------------------------------------------ front matter
def entries_from_blocks():
    figs, tabs = [], []
    for mod in (C1, C2, C3, C4, C5, C6, C7):
        for b in mod.BLOCKS:
            if b[0] == "fig":
                figs.append((b[2], b[3]))
            elif b[0] == "tab":
                tabs.append((b[1], b[2]))
    return figs, tabs


def page_map():
    import json
    if os.path.exists("page_map.json"):
        with open("page_map.json", encoding="utf-8") as f:
            return json.load(f)
    return {}


def listing(doc, entries, prefix, pm):
    from docx.enum.text import WD_TAB_LEADER
    for num, cap in entries:
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.space_after = Pt(7)
        pf.space_before = Pt(0)
        pf.line_spacing = 1.0
        pf.alignment = WD_ALIGN_PARAGRAPH.LEFT
        pf.tab_stops.add_tab_stop(Inches(6.0), WD_TAB_ALIGNMENT.RIGHT, WD_TAB_LEADER.DOTS)
        r = p.add_run(f"{prefix} {num}  ")
        r.bold = True
        r.font.size = Pt(11)
        r.font.name = "Times New Roman"
        r2 = p.add_run(cap)
        r2.font.size = Pt(11)
        r2.font.name = "Times New Roman"
        r3 = p.add_run("\t" + str(pm.get(f"{prefix} {num}", "\u2013")))
        r3.font.size = Pt(11)
        r3.font.name = "Times New Roman"


def build_front(doc):
    CF.title_page(doc, para, rich)
    doc.add_page_break()
    CF.bonafide(doc, para, rich)
    doc.add_page_break()
    CF.viva(doc, para, rich)
    doc.add_page_break()
    CF.acknowledgement(doc, para, rich)
    doc.add_page_break()
    CF.abstract(doc, para, rich)
    doc.add_page_break()

    # TOC
    p = para(doc, "TABLE OF CONTENTS", bold=True, align="center", size=13, space_after=14)
    toc_p = doc.add_paragraph()
    _field(toc_p, ' TOC \\o "1-3" \\h \\z \\u ', "Right-click and choose Update Field to build the contents.")
    doc.add_page_break()

    figs, tabs = entries_from_blocks()
    pm = page_map()

    p = para(doc, "LIST OF TABLES", bold=True, align="center", size=13, space_after=14)
    listing(doc, tabs, "Table", pm)
    doc.add_page_break()

    p = para(doc, "LIST OF FIGURES", bold=True, align="center", size=13, space_after=14)
    listing(doc, figs, "Figure", pm)
    doc.add_page_break()

    CF.abbreviations(doc, para)


def main():
    doc = Document()
    setup(doc)
    sec0 = doc.sections[0]
    page_number_footer(sec0, "lowerRoman", 1, suppress_first=True)

    build_front(doc)

    # body section with arabic numbering restarting at 1
    new_sec = doc.add_section(WD_SECTION.NEW_PAGE)
    new_sec.top_margin = Inches(1.0)
    new_sec.bottom_margin = Inches(1.0)
    new_sec.left_margin = Inches(1.5)
    new_sec.right_margin = Inches(1.0)
    page_number_footer(new_sec, "decimal", 1)

    for mod in (C1, C2, C3, C4, C5, C6, C7):
        render(doc, mod.BLOCKS)

    # appendix
    p = doc.add_paragraph(style="Heading 1")
    p.paragraph_format.page_break_before = True
    p.add_run("APPENDIX")
    C7.appendix(doc, para, code, table)

    # references
    p = doc.add_paragraph(style="Heading 1")
    p.paragraph_format.page_break_before = True
    p.add_run("REFERENCES")
    for ref in C7.REFERENCES:
        rp = doc.add_paragraph()
        rp.paragraph_format.left_indent = Inches(0.42)
        rp.paragraph_format.first_line_indent = Inches(-0.42)
        rp.paragraph_format.space_after = Pt(6)
        rp.paragraph_format.line_spacing = 1.3
        rp.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        r = rp.add_run(ref)
        r.font.size = Pt(11)
        r.font.name = "Times New Roman"

    # update fields on open
    settings = doc.settings.element
    uf = OxmlElement("w:updateFields")
    uf.set(qn("w:val"), "true")
    settings.append(uf)

    doc.save(OUT)
    print("saved", OUT)


if __name__ == "__main__":
    main()
