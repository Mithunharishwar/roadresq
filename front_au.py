"""Front matter for the RoadResQ report, laid out to the Anna University format
(Appendix 1, 2 and 3 of 'Format for Preparation of Project Report')."""
from docx.shared import Pt, Inches, Cm
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import OxmlElement
from docx.oxml.ns import qn

BODY = 14          # general text size required by the format
TITLE_LINES = [
    "ROADRESQ: A CAPABILITY-CONSTRAINED",
    "ON-DEMAND ROADSIDE RESCUE PLATFORM",
    "WITH REGION-AWARE WEIGHTED PARTNER",
    "ALLOCATION AND MULTI-CHANNEL",
    "INCIDENT TRIGGERING",
]
STUDENTS = [
    ("MITHUN HARISHWAR P R", "310623205087"),
    ("LOKESHWARAN K", "310623205302"),
]
COLLEGE = "EASWARI ENGINEERING COLLEGE, CHENNAI"
COLLEGE_SUB = "(AN AUTONOMOUS INSTITUTION)"
UNIVERSITY = "ANNA UNIVERSITY : CHENNAI 600 025"
MONTH_YEAR = "OCTOBER 2026"
DEGREE = "BACHELOR OF TECHNOLOGY"
BRANCH = "INFORMATION TECHNOLOGY"


def _c(doc, text="", size=BODY, bold=False, italic=False, before=0, after=0,
       spacing=1.0, keep=False, new_page=False):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    pf = p.paragraph_format
    pf.page_break_before = new_page
    pf.space_before = Pt(before)
    pf.space_after = Pt(after)
    pf.line_spacing = spacing
    if keep:
        pf.keep_with_next = True
    r = p.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.size = Pt(size)
    r.font.name = "Times New Roman"
    return p


def _heading(doc, text, size=16, after=18, new_page=False):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.page_break_before = new_page
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = 1.0
    p.paragraph_format.keep_with_next = True
    r = p.add_run(text)
    r.bold = True
    r.font.size = Pt(size)
    r.font.name = "Times New Roman"
    return p


def _body(doc, text, spacing=1.5, after=10, size=BODY, align="justify", first=0):
    p = doc.add_paragraph()
    p.alignment = (WD_ALIGN_PARAGRAPH.JUSTIFY if align == "justify"
                   else WD_ALIGN_PARAGRAPH.LEFT)
    pf = p.paragraph_format
    pf.line_spacing = spacing
    pf.space_after = Pt(after)
    pf.space_before = Pt(0)
    if first:
        pf.first_line_indent = Inches(first)
    r = p.add_run(text)
    r.font.size = Pt(size)
    r.font.name = "Times New Roman"
    return p


def _no_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement(f"w:{edge}")
        el.set(qn("w:val"), "none")
        el.set(qn("w:sz"), "0")
        borders.append(el)
    tblPr.append(borders)


# ----------------------------------------------------------------- cover / title
def cover_page(doc, roll_numbers=True):
    """Specimen cover page of Appendix 1 (also used, verbatim, as the title page)."""
    _c(doc, "", size=10, after=20)
    for i, line in enumerate(TITLE_LINES):
        _c(doc, line, size=18, bold=True, spacing=1.5,
           after=0 if i < len(TITLE_LINES) - 1 else 16)
    _c(doc, "A PROJECT REPORT", size=14, after=24)
    _c(doc, "Submitted by", size=14, italic=True, after=10)
    for name, roll in STUDENTS:
        _c(doc, f"{name}{'   (' + roll + ')' if roll_numbers else ''}",
           size=16, bold=True, after=2)
    _c(doc, "", size=10, after=34)
    _c(doc, "in partial fulfillment for the award of the degree", size=14,
       italic=True, spacing=1.5, after=6)
    _c(doc, "of", size=14, italic=True, spacing=1.5, after=6)
    _c(doc, DEGREE, size=16, bold=True, after=8)
    _c(doc, "IN", size=14, after=8)
    _c(doc, BRANCH, size=14, bold=True, after=56)
    _c(doc, COLLEGE, size=14, bold=True, after=0)
    _c(doc, COLLEGE_SUB, size=12, after=30)
    _c(doc, UNIVERSITY, size=16, bold=True, spacing=1.5, after=26)
    _c(doc, MONTH_YEAR, size=14, bold=True, after=0)


# ----------------------------------------------------------------- bonafide
def bonafide(doc, new_page=True):
    _c(doc, "ANNA UNIVERSITY : CHENNAI 600 025", size=18, bold=True, after=6,
       new_page=new_page, spacing=1.5)
    _c(doc, "BONAFIDE CERTIFICATE", size=16, bold=True, after=4)
    _c(doc, "EASWARI ENGINEERING COLLEGE, CHENNAI 600 089", size=12,
       bold=True, after=2)
    _c(doc, "(AN AUTONOMOUS INSTITUTION)", size=10, after=14)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.LEFT
    p.paragraph_format.line_spacing = 2.0          # double line spacing (para 3.2)
    p.paragraph_format.space_after = Pt(6)
    parts = [
        ("Certified that this project report \u201c", False),
        ("ROADRESQ: A CAPABILITY-CONSTRAINED ON-DEMAND ROADSIDE RESCUE "
         "PLATFORM WITH REGION-AWARE WEIGHTED PARTNER ALLOCATION AND "
         "MULTI-CHANNEL INCIDENT TRIGGERING", True),
        ("\u201d is the bonafide work of \u201c", False),
        ("MITHUN HARISHWAR P R (310623205087)", True),
        ("\u201d and \u201c", False),
        ("LOKESHWARAN K (310623205302)", True),
        ("\u201d who carried out the project work under my supervision "
         "during the academic year 2025\u20132026.", False),
    ]
    for text, bold in parts:
        r = p.add_run(text)
        r.bold = bold
        r.font.size = Pt(BODY)
        r.font.name = "Times New Roman"

    t = doc.add_table(rows=1, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    _no_borders(t)
    lay = OxmlElement("w:tblLayout")
    lay.set(qn("w:type"), "fixed")
    t._tbl.tblPr.append(lay)
    for col in t.columns:
        col.width = Inches(2.85)
    left, right = t.rows[0].cells
    left.width = Inches(2.85)
    right.width = Inches(2.85)
    for cell, lines in (
        (left, ["SIGNATURE", "", "Dr. N. ANANTHI, M.E., Ph.D.,",
                "HEAD OF THE DEPARTMENT",
                "Department of Information Technology,",
                "Easwari Engineering College,",
                "Ramapuram, Chennai \u2013 600089."]),
        (right, ["SIGNATURE", "", "Mrs. K. SUDHA, M.E.,",
                 "SUPERVISOR",
                 "Assistant Professor,",
                  "Department of Information Technology,",
                  "Easwari Engineering College,",
                  "Ramapuram, Chennai \u2013 600089."]),
    ):
        cell.text = ""
        for i, line in enumerate(lines):
            cp = cell.paragraphs[0] if i == 0 else cell.add_paragraph()
            cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
            cp.paragraph_format.space_after = Pt(2)
            cp.paragraph_format.line_spacing = 1.2
            r = cp.add_run(line)
            r.font.size = Pt(12)
            r.font.name = "Times New Roman"
            r.bold = i in (0, 2, 3)

    _c(doc, "", size=10, after=16)
    _c(doc, "The Project Viva-Voce Examination was conducted on ____________",
       size=11.5, after=16)
    t2 = doc.add_table(rows=1, cols=2)
    t2.alignment = WD_TABLE_ALIGNMENT.CENTER
    t2.autofit = False
    _no_borders(t2)
    a, b = t2.rows[0].cells
    a.width = Inches(2.9)
    b.width = Inches(2.9)
    for cell, text in ((a, "Project Coordinator"), (b, "Panel Member Signature")):
        cell.text = ""
        cp = cell.paragraphs[0]
        cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
        cp.paragraph_format.space_after = Pt(2)
        r = cp.add_run(text)
        r.bold = True
        r.font.size = Pt(12)
        r.font.name = "Times New Roman"


# ----------------------------------------------------------------- viva certificate
def viva(doc, new_page=True):
    _c(doc, "EASWARI ENGINEERING COLLEGE", size=16, bold=True, after=2,
       new_page=new_page)
    _c(doc, COLLEGE_SUB, size=12, after=12)
    _heading(doc, "CERTIFICATE OF VIVA-VOCE EXAMINATION", size=16, after=14)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 2.0
    p.paragraph_format.space_after = Pt(8)
    for text, bold in [
        ("This is to certify that the Viva-Voce Examination of the project work entitled \u201c", False),
        ("ROADRESQ: A CAPABILITY-CONSTRAINED ON-DEMAND ROADSIDE RESCUE "
         "PLATFORM WITH REGION-AWARE WEIGHTED PARTNER ALLOCATION AND "
         "MULTI-CHANNEL INCIDENT TRIGGERING", True),
        ("\u201d submitted by \u201c", False),
        ("MITHUN HARISHWAR P R (310623205087)", True),
        ("\u201d and \u201c", False),
        ("LOKESHWARAN K (310623205302)", True),
        ("\u201d in partial fulfillment of the requirements for the award of "
         "the degree of Bachelor of Technology was conducted on ______________ "
         "in the Department of Information Technology, Easwari Engineering "
         "College, Ramapuram, Chennai.", False),
    ]:
        r = p.add_run(text)
        r.bold = bold
        r.font.size = Pt(BODY)
        r.font.name = "Times New Roman"

    t = doc.add_table(rows=1, cols=2)
    t.alignment = WD_TABLE_ALIGNMENT.CENTER
    t.autofit = False
    _no_borders(t)
    for cell, head in zip(t.rows[0].cells, ("INTERNAL EXAMINER", "EXTERNAL EXAMINER")):
        cell.width = Inches(2.9)
        cell.text = ""
        for i, line in enumerate([head, "", "Name:", "Designation:", "Date:"]):
            cp = cell.paragraphs[0] if i == 0 else cell.add_paragraph()
            cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
            cp.paragraph_format.space_after = Pt(6)
            cp.paragraph_format.line_spacing = 1.5
            r = cp.add_run(line)
            r.font.size = Pt(12)
            r.font.name = "Times New Roman"
            r.bold = i == 0


# ----------------------------------------------------------------- acknowledgement
def acknowledgement(doc, new_page=False):
    _heading(doc, "ACKNOWLEDGEMENT", new_page=True)
    paragraphs = [
        "We express our sincere thanks and deep sense of gratitude to our Founder "
        "Chairman, Dr. T. R. Parivendhar, and our beloved Chairman, "
        "Dr. R. Shivakumar, M.D., Ph.D., for their constant support, encouragement "
        "and inspiration, which motivated us to complete this project successfully.",

        "We record our respectful thanks to our Principal, Dr. P. Deiva Sundari, "
        "M.E., Ph.D., and to our Head of the Department, Dr. N. Ananthi, M.E., "
        "Ph.D., for their guidance, encouragement and continuous support throughout "
        "the course of this work.",

        "We owe our profound gratitude to our project supervisor, Mrs. K. Sudha, "
        "M.E., Assistant Professor, Department of Information Technology, Easwari "
        "Engineering College, for her valuable suggestions, patient review of every "
        "iteration of this work, and keen interest in its progress. Her insistence "
        "that every claim in the evaluation chapter be traceable to a recorded "
        "observation shaped both the design and the way we report it.",

        "We sincerely thank our project coordinator, Mr. K. Ravindran, M.E., for "
        "his continuous assistance and for keeping the review schedule on track.",

        "We are grateful to the faculty and staff of the Department of Information "
        "Technology for their cooperation, and to our classmates who tested early "
        "builds of the application on their own devices and reported failures that "
        "we would not otherwise have found.",

        "Finally, we thank our families for their patience and encouragement, which "
        "made the long working weeks of this project possible.",
    ]
    for text in paragraphs:
        _body(doc, text, spacing=1.5, after=10)


# ----------------------------------------------------------------- abstract
def abstract(doc, new_page=False):
    """One page synopsis, as required by paragraph 3.3 of the format."""
    _heading(doc, "ABSTRACT", after=14, new_page=True)

    paragraphs = [
        "A vehicle breakdown leaves the owner stranded, uncertain of the cost, and "
        "unable to judge which nearby workshop can repair the fault. The two "
        "commercial forms that answer this need both fail to observe the outcome of "
        "the service they arrange: a subscription product places the decision with "
        "a call-centre operator and prices an intermittent need as an annual "
        "entitlement, while a directory application publishes a list of workshops "
        "and leaves the coordination to the owner; neither selects a workshop "
        "against the fault that has actually occurred.",

        "This project designs, implements and evaluates RoadResQ, a platform that "
        "treats the assignment of a rescue crew as a decision problem rather than a "
        "directory lookup. Candidates are filtered on capability, availability and "
        "position freshness before ranking, and the survivors are scored on six "
        "normalised terms with published weights and recorded contributions, so "
        "that every dispatch can be explained. Requests are raised "
        "by an SOS control, a voice keyword or a confirmed sensor-detected impact, "
        "and advance through a twelve-state lifecycle held in one transition table; "
        "the fault is mapped to a service class and a fixed tariff before any offer "
        "is made.",

        "On a paired simulated corpus of 4,000 requests, the score raises the "
        "allocation rate from 84.1% to 96.5% and end-to-end thirty-minute "
        "compliance from 57.3% to 66.4% against a proximity-only policy, at 0.3 "
        "minutes of median cost; in thin supply the allocation rate is 87.0% "
        "against 55.1%. The multi-feature detector raises the detection rate at a "
        "fixed false-alarm budget from 65.0% to 90.5%, and the classifier attains "
        "a pooled F1-score of 0.91 against 0.77 for a lexical baseline.",
    ]
    for text in paragraphs:
        _body(doc, text, spacing=1.5, after=6)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_before = Pt(4)
    r = p.add_run("KEYWORDS: ")
    r.bold = True
    r.font.size = Pt(BODY)
    r.font.name = "Times New Roman"
    r2 = p.add_run("roadside assistance, weighted allocation, capability matching, "
                   "request lifecycle, incident detection, Flutter, Flask, MongoDB.")
    r2.font.size = Pt(BODY)
    r2.font.name = "Times New Roman"


# ----------------------------------------------------------------- symbols + abbreviations
SYMBOLS = [
    ("R", "Search radius around the request position (default 10 km); also the mean "
          "earth radius in Equation 4.1"),
    ("d(m, r), d_route", "Great-circle distance between crew m and request r; and the "
                         "remaining network distance on the published route"),
    ("M, E(r)", "Crews inside the search radius, and the subset that satisfies the "
                "eligibility predicates for request r"),
    ("k_r, \u03c1_m", "Service class of the request, and the service radius declared "
                      "by crew m"),
    ("P\u0302(m, r), S(m, r)", "Normalised proximity term, and the total weighted "
                               "allocation score of crew m for request r"),
    ("w_p, w_s, w_a, w_v, w_l, w_r",
     "Weights of the proximity, service, availability, verification, workload and "
     "rating terms"),
    ("fit(m, k)", "Capability-fit value: 1 verified, 0.5 declared only, 0 otherwise"),
    ("Rep(m), Acc(m)", "Shrunk reputation and acceptance-rate estimates of crew m"),
    ("n_m, o_m, \u03b1, \u03b2, s\u2080, a\u2080",
     "Completed jobs, dispatched offers, prior strengths, prior mean rating and prior "
     "acceptance rate of the estimators"),
    ("\u03c6, \u03bb", "Latitude and longitude"),
    ("P(k | x), k*", "Posterior probability of service class k, and the class selected "
                     "by the minimum-expected-cost rule"),
    ("|a|, j[n], \u0394t_meas", "Resultant magnitude of proper acceleration, jerk at "
                                "sample n, and the measured sampling interval"),
    ("T\u0302, v_eff(t), \u03c4_prep", "Estimated time of arrival, effective speed for "
                                       "the region and hour, and the preparation "
                                       "allowance"),
    ("C, c, F", "Captured amount, commission rate and fixed platform fee"),
    ("N, B", "Number of indexed crews (corpus size in Equation 4.8), and the maximum "
             "number of offers dispatched per request"),
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
    ("ISO/IEC", "International Organization for Standardization / "
                "International Electrotechnical Commission"),
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
    ("UPI", "Unified Payments Interface"),
    ("URL", "Uniform Resource Locator"),
    ("UX", "User Experience"),
    ("V2X", "Vehicle-to-Everything"),
    ("WS", "WebSocket"),
]


def symbols_and_abbreviations(doc, new_page=True):
    _heading(doc, "LIST OF SYMBOLS, ABBREVIATIONS AND NOMENCLATURE", size=14, after=14,
             new_page=new_page)

    _c(doc, "A.  SYMBOLS", size=12, bold=True, after=8)
    t = doc.add_table(rows=0, cols=2)
    t.autofit = False
    _no_borders(t)
    for sym, meaning in SYMBOLS:
        cells = t.add_row().cells
        cells[0].width = Inches(1.85)
        cells[1].width = Inches(3.85)
        for i, text in enumerate((sym, meaning)):
            cp = cells[i].paragraphs[0]
            cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
            cp.paragraph_format.space_after = Pt(1)
            cp.paragraph_format.line_spacing = 1.2
            r = cp.add_run(text)
            r.font.size = Pt(12)
            r.font.name = "Times New Roman"
            r.bold = i == 0

    _c(doc, "", size=10, after=6)
    _c(doc, "B.  ABBREVIATIONS", size=12, bold=True, after=8)
    t2 = doc.add_table(rows=0, cols=2)
    t2.autofit = False
    _no_borders(t2)
    for abbr, full in ABBREVIATIONS:
        cells = t2.add_row().cells
        cells[0].width = Inches(1.35)
        cells[1].width = Inches(4.35)
        for i, text in enumerate((abbr, full)):
            cp = cells[i].paragraphs[0]
            cp.alignment = WD_ALIGN_PARAGRAPH.LEFT
            cp.paragraph_format.space_after = Pt(1)
            cp.paragraph_format.line_spacing = 1.2
            r = cp.add_run(text)
            r.font.size = Pt(12)
            r.font.name = "Times New Roman"
            r.bold = i == 0
