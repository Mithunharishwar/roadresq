# -*- coding: utf-8 -*-
"""Front matter content and renderers for the RoadResQ report.

Layout metrics are taken from the approved reference report (proj_116report.docx):
Times New Roman 12 pt body, 1.5 line spacing, justified; 14 pt bold centred
chapter headings; 12.5 pt bold section headings; A4 with 3.7 / 2.4 / 2.4 / 2.3 cm
margins; lower-roman page numbers in the front matter and arabic numbers in the
body.
"""
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt

BODY = 12
TEXT_W = 14.9          # cm

TITLE = ("ROADRESQ: A CAPABILITY-CONSTRAINED ON-DEMAND ROADSIDE RESCUE "
         "PLATFORM WITH REGION-AWARE WEIGHTED PARTNER ALLOCATION AND "
         "MULTI-CHANNEL INCIDENT TRIGGERING")
STUDENTS = [("MITHUN HARISHWAR P R", "310623205087"),
            ("LOKESHWARAN K", "310623205302")]
COLLEGE = "EASWARI ENGINEERING COLLEGE, CHENNAI"
COLLEGE_SUB = "(AN AUTONOMOUS INSTITUTION)"
COLLEGE_ADDR = "EASWARI ENGINEERING COLLEGE, CHENNAI 600 089"
UNIVERSITY = "ANNA UNIVERSITY : CHENNAI 600 025"
MONTH_YEAR = "OCTOBER 2026"
DEGREE = "BACHELOR OF TECHNOLOGY"
BRANCH = "INFORMATION TECHNOLOGY"
DEPT = "Department of Information Technology, Easwari Engineering College, Ramapuram, Chennai \u2013 600089."

ACK_PARAS = [
    "We express our sincere thanks and deep sense of gratitude to our Founder Chairman, "
    "Dr. T. R. Parivendhar, and our beloved Chairman, Dr. R. Shivakumar, M.D., Ph.D., for "
    "their constant support, encouragement and inspiration, which motivated us to complete "
    "this project successfully.",

    "We record our respectful thanks to our Principal, Dr. P. Deiva Sundari, M.E., Ph.D., and "
    "to our Head of the Department, Dr. N. Ananthi, M.E., Ph.D., for their guidance, "
    "encouragement and continuous support throughout the course of this work.",

    "We owe our profound gratitude to our project supervisor, Mrs. K. Sudha, M.E., Assistant "
    "Professor, Department of Information Technology, Easwari Engineering College, for her "
    "valuable suggestions, patient review of every iteration of this work, and keen interest "
    "in its progress. Her insistence that every claim in the evaluation chapter be traceable "
    "to a recorded observation shaped both the design and the way we report it.",

    "We sincerely thank our project coordinator, Mr. K. Ravindran, M.E., for his continuous "
    "assistance and for keeping the review schedule on track.",

    "We are grateful to the faculty and staff of the Department of Information Technology for "
    "their cooperation, and to our classmates who tested early builds of the application on "
    "their own devices and reported failures that we would not otherwise have found.",

    "Finally, we thank our families for their patience and encouragement, which made the long "
    "working weeks of this project possible.",
]

ABSTRACT_PARAS = [
    "A vehicle breakdown leaves the owner stranded, uncertain of the cost, and unable to judge "
    "which nearby workshop can repair the fault. The two commercial forms that answer this need "
    "both fail to observe the outcome of the service they arrange: a subscription product places "
    "the decision with a call-centre operator and prices an intermittent need as an annual "
    "entitlement, while a directory application publishes a list of workshops and leaves the "
    "coordination to the owner; neither selects a workshop against the fault that has actually "
    "occurred.",

    "This project designs, implements and evaluates RoadResQ, a platform that treats the "
    "assignment of a rescue crew as a decision problem rather than a directory lookup. "
    "Candidates are filtered on capability, availability and position freshness before ranking, "
    "and the survivors are scored on six normalised terms with published weights and recorded "
    "contributions, so that every dispatch can be explained. Requests are raised by an SOS "
    "control, a voice keyword or a confirmed sensor-detected impact, and advance through a "
    "twelve-state lifecycle held in one transition table; the fault is mapped to a service class "
    "and a fixed tariff before any offer is made.",

    "On a paired simulated corpus of 4,000 requests, the score raises the allocation rate from "
    "84.1% to 96.5% and end-to-end thirty-minute compliance from 57.3% to 66.4% against a "
    "proximity-only policy, at 0.3 minutes of median cost; in thin supply the allocation rate is "
    "87.0% against 55.1%. The multi-feature detector raises the detection rate at a fixed "
    "false-alarm budget from 65.0% to 90.5%, and the classifier attains a pooled F1-score of "
    "0.91 against 0.77 for a lexical baseline.",
]

KEYWORDS = ("roadside assistance, weighted allocation, capability matching, request lifecycle, "
            "incident detection, Flutter, Flask, MongoDB.")

SYMBOLS = [
    ("R", "Search radius around the request position (default 10 km); also the mean earth "
          "radius in Equation 4.1"),
    ("d(m, r), d_route", "Great-circle distance between crew m and request r; and the remaining "
                         "network distance on the published route"),
    ("M, E(r)", "Crews inside the search radius, and the subset that satisfies the eligibility "
                "predicates for request r"),
    ("k_r, \u03c1_m", "Service class of the request, and the service radius declared by crew m"),
    ("P\u0302(m, r), S(m, r)", "Normalised proximity term, and the total weighted allocation "
                               "score of crew m for request r"),
    ("w_p, w_s, w_a, w_v, w_l, w_r", "Weights of the proximity, service, availability, "
                                     "verification, workload and rating terms"),
    ("fit(m, k)", "Capability-fit value: 1 verified, 0.5 declared only, 0 otherwise"),
    ("Rep(m), Acc(m)", "Shrunk reputation and acceptance-rate estimates of crew m"),
    ("n_m, o_m, \u03b1, \u03b2, s\u2080, a\u2080", "Completed jobs, dispatched offers, prior "
                                                    "strengths, prior mean rating and prior "
                                                    "acceptance rate of the estimators"),
    ("\u03c6, \u03bb", "Latitude and longitude"),
    ("P(k | x), k*", "Posterior probability of service class k, and the class selected by the "
                     "minimum-expected-cost rule"),
    ("|a|, j[n], \u0394t_meas", "Resultant magnitude of proper acceleration, jerk at sample n, "
                                "and the measured sampling interval"),
    ("T\u0302, v_eff(t), \u03c4_prep", "Estimated time of arrival, effective speed for the region "
                                      "and hour, and the preparation allowance"),
    ("C, c, F", "Captured amount, commission rate and fixed platform fee"),
    ("N, B", "Number of indexed crews (corpus size in Equation 4.8), and the maximum number of "
             "offers dispatched per request"),
]

ABBREVIATIONS = [
    ("ACM", "Association for Computing Machinery"),
    ("API", "Application Programming Interface"),
    ("ASGI", "Asynchronous Server Gateway Interface"),
    ("CI/CD", "Continuous Integration and Continuous Delivery"),
    ("CRUD", "Create, Read, Update, Delete"),
    ("CSV", "Comma-Separated Values"),
    ("ETA", "Estimated Time of Arrival"),
    ("F1", "F1-score, the harmonic mean of precision and recall"),
    ("FCM", "Firebase Cloud Messaging"),
    ("GPS", "Global Positioning System"),
    ("HTTP", "Hypertext Transfer Protocol"),
    ("HTTPS", "Hypertext Transfer Protocol Secure"),
    ("IEEE", "Institute of Electrical and Electronics Engineers"),
    ("INR", "Indian Rupee"),
    ("ISO/IEC", "International Organization for Standardization / International Electrotechnical "
                "Commission"),
    ("JSON", "JavaScript Object Notation"),
    ("JWT", "JSON Web Token"),
    ("LTS", "Long-Term Support"),
    ("MAE", "Mean Absolute Error"),
    ("MVC", "Model\u2013View\u2013Controller"),
    ("OSM", "OpenStreetMap"),
    ("OWASP", "Open Worldwide Application Security Project"),
    ("RBAC", "Role-Based Access Control"),
    ("REST", "Representational State Transfer"),
    ("SDK", "Software Development Kit"),
    ("SLA", "Service-Level Agreement"),
    ("SMS", "Short Message Service"),
    ("SOS", "Save Our Souls (emergency trigger)"),
    ("SQL", "Structured Query Language"),
    ("TF-IDF", "Term Frequency \u2013 Inverse Document Frequency"),
    ("TLS", "Transport Layer Security"),
    ("TTL", "Time To Live"),
    ("UI", "User Interface"),
    ("UPI", "Unified Payment Interface"),
    ("URL", "Uniform Resource Locator"),
    ("UX", "User Experience"),
    ("V2X", "Vehicle-to-Everything"),
    ("WS", "WebSocket"),
]

# --------------------------------------------------------------- small helpers


def _run(p, text, size=BODY, bold=False, italic=False, font="Times New Roman"):
    r = p.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.size = Pt(size)
    r.font.name = font
    rpr = r._element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = OxmlElement("w:rFonts")
        rpr.append(rf)
    for a in ("w:ascii", "w:hAnsi", "w:cs", "w:eastAsia"):
        rf.set(qn(a), font)
    return r


def line(doc, text="", size=BODY, bold=False, italic=False, align="center",
         before=0, after=0, spacing=1.0, keep=False, page_break=False):
    p = doc.add_paragraph()
    p.alignment = {"center": WD_ALIGN_PARAGRAPH.CENTER,
                   "left": WD_ALIGN_PARAGRAPH.LEFT,
                   "justify": WD_ALIGN_PARAGRAPH.JUSTIFY}[align]
    pf = p.paragraph_format
    pf.page_break_before = page_break
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = spacing
    pf.keep_with_next = keep
    if text:
        _run(p, text, size, bold, italic)
    return p


def heading(doc, text, after=14, before=0, page_break=False, keep=True):
    return line(doc, text, size=14, bold=True, align="center", before=before,
                after=after, keep=keep, page_break=page_break)


def _no_borders(table):
    tblPr = table._tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement("w:%s" % edge)
        el.set(qn("w:val"), "none")
        el.set(qn("w:sz"), "0")
        el.set(qn("w:space"), "0")
        borders.append(el)
    tblPr.append(borders)


def _fixed(table, widths_cm):
    tblPr = table._tbl.tblPr
    lay = OxmlElement("w:tblLayout")
    lay.set(qn("w:type"), "fixed")
    tblPr.append(lay)
    table.autofit = False
    for row in table.rows:
        for i, w in enumerate(widths_cm):
            row.cells[i].width = Cm(w)


# ----------------------------------------------------------------- title page
def title_page(doc):
    line(doc, TITLE, size=18, bold=True, before=0, after=18, spacing=1.15)
    line(doc, "A PROJECT REPORT", size=14, bold=True, after=14)
    line(doc, "Submitted by", size=14, bold=True, italic=True, after=8)
    for name, roll in STUDENTS:
        line(doc, "%s (%s)" % (name, roll), size=16, bold=True, after=2)
    line(doc, "", size=12, after=10)
    line(doc, "in partial fulfillment for the award of the degree", size=14,
         italic=True, after=2)
    line(doc, "of", size=14, italic=True, after=2)
    line(doc, DEGREE, size=16, bold=True, after=2)
    line(doc, "IN", size=12, after=2)
    line(doc, BRANCH, size=14, bold=True, after=10)
    logo(doc, Cm(2.2), before=4, after=14)
    line(doc, COLLEGE, size=14, bold=True, after=2)
    line(doc, COLLEGE_SUB, size=12, after=2)
    line(doc, UNIVERSITY, size=16, bold=True, after=14)
    line(doc, MONTH_YEAR, size=14, bold=True, after=0)


# ------------------------------------------------------------------- emblem
LOGO = r"C:\Users\Admin\OneDrive\Desktop\gopal\roadresq\figs\logo_image1.jpeg"


def logo(doc, width, before=0, after=0, align="center"):
    p = doc.add_paragraph()
    p.alignment = {"center": WD_ALIGN_PARAGRAPH.CENTER,
                   "left": WD_ALIGN_PARAGRAPH.LEFT}[align]
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.0
    p.add_run().add_picture(LOGO, width=width)
    return p


def page_break(doc):
    """A one-point paragraph that starts a new page (used before a table)."""
    p = doc.add_paragraph()
    pf = p.paragraph_format
    pf.page_break_before = True
    pf.space_before = Pt(0)
    pf.space_after = Pt(0)
    pf.line_spacing = Pt(1)
    pPr = p._p.get_or_add_pPr()
    rPr = OxmlElement("w:rPr")
    sz = OxmlElement("w:sz")
    sz.set(qn("w:val"), "2")
    rPr.append(sz)
    pPr.append(rPr)
    return p


def college_header(doc):
    """Emblem on the left, college name beside it, as in the reference report."""
    t = doc.add_table(rows=1, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    _no_borders(t)
    _fixed(t, [3.4, 11.5])
    c0, c1 = t.rows[0].cells
    c0.text = ""
    p0 = c0.paragraphs[0]
    p0.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p0.paragraph_format.space_after = Pt(0)
    p0.add_run().add_picture(LOGO, width=Cm(1.9))
    c1.text = ""
    p = c1.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(10)
    p.paragraph_format.space_after = Pt(0)
    _run(p, "EASWARI ENGINEERING COLLEGE", 16, True)
    p2 = c1.add_paragraph()
    p2.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p2.paragraph_format.space_after = Pt(0)
    _run(p2, COLLEGE_SUB, 12)
    return t


# ------------------------------------------------------------------ bonafide
def _signature_table(doc, blocks, widths=(7.45, 7.45), align="center"):
    t = doc.add_table(rows=1, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    _no_borders(t)
    _fixed(t, list(widths))
    body_align = (WD_ALIGN_PARAGRAPH.LEFT if align == "left"
                  else WD_ALIGN_PARAGRAPH.CENTER)
    for cell, lines in zip(t.rows[0].cells, blocks):
        cell.text = ""
        for i, (txt, bold) in enumerate(lines):
            cp = cell.paragraphs[0] if i == 0 else cell.add_paragraph()
            cp.alignment = WD_ALIGN_PARAGRAPH.CENTER if i == 0 else body_align
            cp.paragraph_format.space_after = Pt(0)
            cp.paragraph_format.space_before = Pt(0)
            cp.paragraph_format.line_spacing = 1.15
            _run(cp, txt, 12, bold)
    return t


def bonafide(doc):
    page_break(doc)
    college_header(doc)
    line(doc, "BONAFIDE CERTIFICATE", size=14, bold=True, before=10, after=18)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 2.0
    p.paragraph_format.space_after = Pt(24)
    parts = [
        ("Certified that this project report \u201c", False),
        (TITLE, True),
        ("\u201d is the bonafide work of \u201c", False),
        ("%s (%s)" % STUDENTS[0], True),
        ("\u201d and \u201c", False),
        ("%s (%s)" % STUDENTS[1], True),
        ("\u201d who carried out the project work under my supervision during the "
         "academic year 2025\u20132026.", False),
    ]
    for text, bold in parts:
        _run(p, text, BODY, bold)

    _signature_table(doc, [
        [("SIGNATURE", True), ("", False), ("Dr. N. ANANTHI, M.E., Ph.D.,", True),
         ("HEAD OF THE DEPARTMENT", True), ("", False), (DEPT, False)],
        [("SIGNATURE", True), ("", False), ("K. SUDHA, M.E.,", True),
         ("SUPERVISOR", True), ("Assistant Professor,", False), (DEPT, False)],
    ])

    line(doc, "", size=12, after=18)
    line(doc, "The Project Viva-Voce Examination was conducted on ______________",
         size=12, align="left", after=18)
    _signature_table(doc, [
        [("Project Coordinator", True)],
        [("Panel Member Signature", True)],
    ])


# --------------------------------------------------------------------- viva
def viva(doc):
    page_break(doc)
    college_header(doc)
    line(doc, "CERTIFICATE OF VIVA-VOCE EXAMINATION", size=14, bold=True,
         before=12, after=16)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 2.0
    p.paragraph_format.space_after = Pt(30)
    for text, bold in [
        ("This is to certify that the Viva-Voce Examination of the project work entitled \u201c", False),
        (TITLE, True),
        ("\u201d submitted by \u201c", False),
        ("%s (%s)" % STUDENTS[0], True),
        ("\u201d and \u201c", False),
        ("%s (%s)" % STUDENTS[1], True),
        ("\u201d in partial fulfillment of the requirements for the award of the degree of "
         "Bachelor of Technology was conducted on ______________ in the Department of "
         "Information Technology, Easwari Engineering College, Ramapuram, Chennai.", False),
    ]:
        _run(p, text, BODY, bold)

    filler = "_" * 26
    _signature_table(doc, [
        [("INTERNAL EXAMINER", True), ("", False), ("", False), ("", False),
         ("Name:  " + filler, False), ("Designation:  " + "_" * 20, False),
         ("Date:  " + filler, False)],
        [("EXTERNAL EXAMINER", True), ("", False), ("", False), ("", False),
         ("Name:  " + filler, False), ("Designation:  " + "_" * 20, False),
         ("Date:  " + filler, False)],
    ], align="left")


# ---------------------------------------------------------- acknowledgement
def acknowledgement(doc):
    heading(doc, "ACKNOWLEDGEMENT", after=16, page_break=True)
    for text in ACK_PARAS:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.line_spacing = 1.5
        p.paragraph_format.space_after = Pt(10)
        _run(p, text, BODY)


# ------------------------------------------------------------------ abstract
def abstract(doc):
    heading(doc, "ABSTRACT", after=14, page_break=True)
    for text in ABSTRACT_PARAS:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.line_spacing = 1.5
        p.paragraph_format.space_after = Pt(8)
        _run(p, text, BODY)
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_before = Pt(4)
    _run(p, "KEYWORDS: ", BODY, True)
    _run(p, KEYWORDS, BODY)


# -------------------------------------------------------------- abbreviations
def _two_col(doc, rows, w0, w1, gap=False):
    t = doc.add_table(rows=0, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    _no_borders(t)
    table_like = t
    table_like.autofit = False
    for a, b in rows:
        cells = t.add_row().cells
        cells[0].width = Cm(w0)
        cells[1].width = Cm(w1)
        for i, txt in enumerate((a, b)):
            cp = cells[i].paragraphs[0]
            cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
            cp.paragraph_format.space_after = Pt(0)
            cp.paragraph_format.space_before = Pt(0)
            cp.paragraph_format.line_spacing = 1.15
            _run(cp, txt, BODY, i == 0)
    return t


def symbols_and_abbreviations(doc):
    heading(doc, "LIST OF SYMBOLS AND ABBREVIATIONS", after=12, page_break=True)
    line(doc, "SYMBOLS", size=12, bold=True, align="left", after=6, keep=True)
    _two_col(doc, SYMBOLS, 5.0, 9.9)
    line(doc, "", size=10, after=6)
    line(doc, "ABBREVIATIONS", size=12, bold=True, align="left", after=6, keep=True)
    _two_col(doc, ABBREVIATIONS, 2.8, 12.1)
