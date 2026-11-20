"""Build the internship report for Mithun Harishwar (RoadResQ @ Intelizign)
in the college's internship report template."""
import json
import os

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_TAB_ALIGNMENT, WD_TAB_LEADER
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt

DOCX = "Internship_Report_Mithun_RoadResQ.docx"
MAP = "intern_pages.json"

STUDENT = "MITHUN HARISHWAR P R"
ROLL = "310623205087"
TITLE_LINES = [
    "RoadResQ: A Capability-Constrained On-Demand Roadside",
    "Rescue Platform with Region-Aware Partner Allocation",
    "and Multi-Channel Incident Triggering",
]
SHORT_TITLE = ("RoadResQ: A Capability-Constrained On-Demand Roadside Rescue "
               "Platform with Region-Aware Partner Allocation")
COMPANY = "Intelizign Lifecycle Services Pvt Ltd"
PERIOD = "04/03/2026 - 31/03/2026"
MONTH = "MARCH 2026"

pages = json.load(open(MAP, encoding="utf-8")) if os.path.exists(MAP) else {}


# ------------------------------------------------------------------ utilities
def set_cell_borders(cell, sz=6):
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement("w:tcBorders")
    for edge in ("top", "left", "bottom", "right"):
        el = OxmlElement("w:" + edge)
        el.set(qn("w:val"), "single")
        el.set(qn("w:sz"), str(sz))
        el.set(qn("w:color"), "000000")
        borders.append(el)
    tcPr.append(borders)


def no_borders(table):
    tbl = table._tbl
    tblPr = tbl.tblPr
    borders = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        el = OxmlElement("w:" + edge)
        el.set(qn("w:val"), "none")
        borders.append(el)
    tblPr.append(borders)


def cell_text(cell, text, bold=False, size=12, align="left", italic=False,
              after=2):
    cell.text = ""
    p = cell.paragraphs[0]
    p.alignment = {"left": WD_ALIGN_PARAGRAPH.LEFT,
                   "center": WD_ALIGN_PARAGRAPH.CENTER,
                   "right": WD_ALIGN_PARAGRAPH.RIGHT}[align]
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.space_before = Pt(0)
    p.paragraph_format.line_spacing = 1.0
    r = p.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.size = Pt(size)
    r.font.name = "Times New Roman"
    return p


def para(doc, text="", size=12, bold=False, italic=False, align="justify",
         after=6, before=0, spacing=1.5, indent=0, first=0):
    p = doc.add_paragraph()
    p.alignment = {"left": WD_ALIGN_PARAGRAPH.LEFT,
                   "center": WD_ALIGN_PARAGRAPH.CENTER,
                   "justify": WD_ALIGN_PARAGRAPH.JUSTIFY,
                   "right": WD_ALIGN_PARAGRAPH.RIGHT}[align]
    pf = p.paragraph_format
    pf.space_after = Pt(after)
    pf.space_before = Pt(before)
    pf.line_spacing = spacing
    if indent:
        pf.left_indent = Inches(indent)
    if first:
        pf.first_line_indent = Inches(first)
    if text:
        r = p.add_run(text)
        r.bold = bold
        r.italic = italic
        r.font.size = Pt(size)
        r.font.name = "Times New Roman"
    return p


def bullets(doc, items, size=12, spacing=1.4):
    for lead, rest in items:
        p = doc.add_paragraph()
        pf = p.paragraph_format
        pf.left_indent = Inches(0.55)
        pf.first_line_indent = Inches(-0.25)
        pf.space_after = Pt(4)
        pf.space_before = Pt(0)
        pf.line_spacing = spacing
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        r0 = p.add_run("\u2022  ")
        r0.font.size = Pt(size)
        r0.font.name = "Times New Roman"
        r1 = p.add_run(lead)
        r1.bold = True
        r1.font.size = Pt(size)
        r1.font.name = "Times New Roman"
        r2 = p.add_run(rest)
        r2.font.size = Pt(size)
        r2.font.name = "Times New Roman"


def chapter_head(doc, num, name):
    p = para(doc, "", align="center", after=0, before=0, spacing=1.0)
    r = p.add_run("CHAPTER %s" % num)
    r.bold = True
    r.font.size = Pt(16)
    r.font.name = "Times New Roman"
    p2 = para(doc, "", align="center", after=14, before=2, spacing=1.0)
    r2 = p2.add_run(name)
    r2.bold = True
    r2.font.size = Pt(15)
    r2.font.name = "Times New Roman"


def section_head(doc, label, new_page=False):
    p = para(doc, "", align="left", after=6, before=10, spacing=1.15)
    p.paragraph_format.page_break_before = new_page
    r = p.add_run(label)
    r.bold = True
    r.font.size = Pt(13)
    r.font.name = "Times New Roman"


def _field(paragraph, instr):
    run = paragraph.add_run()
    b = OxmlElement("w:fldChar"); b.set(qn("w:fldCharType"), "begin")
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = instr
    s = OxmlElement("w:fldChar"); s.set(qn("w:fldCharType"), "separate")
    t = OxmlElement("w:t"); t.text = "1"
    e = OxmlElement("w:fldChar"); e.set(qn("w:fldCharType"), "end")
    run._r.append(b); run._r.append(it); run._r.append(s); run._r.append(t); run._r.append(e)
    run.font.size = Pt(11)
    run.font.name = "Times New Roman"


def clear_pgnum(section):
    """Remove an inherited page-number restart so numbering continues."""
    sectPr = section._sectPr
    for el in sectPr.findall(qn("w:pgNumType")):
        sectPr.remove(el)


def setup_sections(doc):
    sec = doc.sections[0]
    sec.page_width = Cm(21)
    sec.page_height = Cm(29.7)
    sec.left_margin = Inches(1.25)
    sec.right_margin = Inches(1.0)
    sec.top_margin = Inches(1.0)
    sec.bottom_margin = Inches(1.0)


def add_footer(section, show=True):
    f = section.footer
    f.is_linked_to_previous = False
    p = f.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for r in list(p.runs):
        r._r.getparent().remove(r._r)
    if show:
        _field(p, " PAGE ")


def pg_start(section, start):
    sectPr = section._sectPr
    for el in sectPr.findall(qn("w:pgNumType")):
        sectPr.remove(el)
    pg = OxmlElement("w:pgNumType")
    pg.set(qn("w:fmt"), "decimal")
    pg.set(qn("w:start"), str(start))
    sectPr.append(pg)


# ------------------------------------------------------------------ document
doc = Document()
style = doc.styles["Normal"]
style.font.name = "Times New Roman"
style.font.size = Pt(12)
setup_sections(doc)

# ============================================== page 1: title
t = doc.add_table(rows=1, cols=2)
t.autofit = False
no_borders(t)
t.columns[0].width = Inches(1.1)
t.columns[1].width = Inches(4.6)
c0, c1 = t.rows[0].cells
c0.width = Inches(1.1)
c1.width = Inches(4.6)
pl = c0.paragraphs[0]
pl.paragraph_format.space_after = Pt(0)
pl.add_run().add_picture("_logo1.png", width=Inches(0.95))
pr = c1.paragraphs[0]
pr.alignment = WD_ALIGN_PARAGRAPH.RIGHT
pr.paragraph_format.space_after = Pt(0)
pr.add_run().add_picture("_logo0.png", width=Inches(2.55))

para(doc, "", after=10, spacing=1.0)
for line in TITLE_LINES:
    para(doc, line, size=16, bold=True, align="center", after=2, spacing=1.15)
para(doc, "", after=12, spacing=1.0)
para(doc, "AN INTERNSHIP REPORT", size=14, bold=True, align="center", after=6, spacing=1.0)
para(doc, "Submitted by", size=12, italic=True, align="center", after=18, spacing=1.0)
para(doc, "%s (%s)" % (STUDENT, ROLL), size=14, bold=True, align="center", after=18, spacing=1.0)
para(doc, "in partial fulfilment for the award of the degree", size=12, italic=True,
     align="center", after=4, spacing=1.0)
para(doc, "of", size=12, italic=True, align="center", after=8, spacing=1.0)
para(doc, "BACHELOR OF TECHNOLOGY", size=14, bold=True, align="center", after=4, spacing=1.0)
para(doc, "in", size=12, italic=True, align="center", after=8, spacing=1.0)
para(doc, "INFORMATION TECHNOLOGY", size=14, bold=True, align="center", after=24, spacing=1.0)
para(doc, "EASWARI ENGINEERING COLLEGE, RAMAPURAM", size=14, bold=True,
     align="center", after=2, spacing=1.0)
para(doc, "(AUTONOMOUS)", size=12, bold=True, align="center", after=10, spacing=1.0)
para(doc, "ANNA UNIVERSITY: CHENNAI 600 025", size=14, bold=True, align="center",
     after=10, spacing=1.0)
para(doc, MONTH, size=13, align="center", after=0, spacing=1.0)

# ============================================== page 2: certificate
sec2 = doc.add_section(WD_SECTION.NEW_PAGE)
add_footer(doc.sections[0], show=False)
add_footer(sec2, show=True)
pg_start(sec2, 2)

para(doc, "", after=6, spacing=1.0)
para(doc, "CERTIFICATE OF EVALUATION", size=14, bold=True, align="center", after=22, spacing=1.0)

rows = (
    ("College Name", "Easwari Engineering College"),
    ("Branch & Semester", "Information Technology & VIII"),
    ("Internship Period", PERIOD),
    ("Company Name", COMPANY),
)
ct = doc.add_table(rows=len(rows), cols=3)
ct.autofit = False
no_borders(ct)
widths = (1.65, 0.25, 4.2)
for row, (label, value), in zip(ct.rows, rows):
    for cell, w in zip(row.cells, widths):
        cell.width = Inches(w)
    cell_text(row.cells[0], label, bold=True, size=12, after=10)
    cell_text(row.cells[1], ":", bold=True, size=12, after=10)
    cell_text(row.cells[2], value, size=12, after=10)

para(doc, "", after=16, spacing=1.0)

grid = doc.add_table(rows=2, cols=4)
grid.alignment = WD_TABLE_ALIGNMENT.CENTER
grid.autofit = False
heads = ("Reg. No.", "Student Name", "Title",
         "Name of Industry\nSupervisor &\nDesignation")
gw = (1.05, 1.55, 1.7, 1.8)
for cell, w in zip(grid.rows[0].cells, gw):
    cell.width = Inches(w)
for cell, h in zip(grid.rows[0].cells, heads):
    cell_text(cell, h, bold=True, size=11, align="center", after=0)
grid.rows[0].height = Inches(0.95)
for cell, w in zip(grid.rows[1].cells, gw):
    cell.width = Inches(w)
vals = (ROLL, STUDENT, SHORT_TITLE,
        COMPANY + "\nNarmadha Senthilkumar,\nSenior HR Manager")
for cell, v in zip(grid.rows[1].cells, vals):
    cell_text(cell, v, size=10, align="left", after=0)
grid.rows[1].height = Inches(1.9)
for row in grid.rows:
    for cell in row.cells:
        set_cell_borders(cell)

para(doc, "", after=18, spacing=1.0)
para(doc, "The report of the internship work submitted by the above student in partial "
          "fulfilment for the award of Bachelor of Technology Degree in Information "
          "Technology of Anna University were evaluated and confirmed to be are part of "
          "the work done by the above student.", spacing=1.5, after=34)
para(doc, "The internship evaluation was held on ______________________", spacing=1.5, after=48)
para(doc, "INTERNAL EXAMINER", size=12, bold=True, align="left", after=0, spacing=1.0)

# ============================================== page 3: table of contents
sec3 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(sec3)
add_footer(sec3, show=True)
para(doc, "TABLE OF CONTENTS", size=14, bold=True, align="center", after=18, spacing=1.0)

toc_rows = [
    (0, "1", "INTRODUCTION"),
    (1, "1.1", "Objective"),
    (1, "1.2", "Scope of the Internship"),
    (0, "2", "INTERNSHIP ACTIVITIES"),
    (1, "2.1", "Description of Tasks and Responsibilities"),
    (1, "2.2", "Tools, Technologies and Software Used"),
    (1, "2.3", "Skills Applied and Developed"),
    (1, "2.4", "Challenges Faced and Solutions Implemented"),
    (0, "3", "CONCLUSION"),
    (1, "3.1", "Summary of Internship Experience"),
    (1, "3.2", "Personal and Professional Development"),
    (0, "", "ANNEXURE"),
    (1, "A.1", "Request Letter"),
    (1, "A.2", "Offer Letter"),
    (1, "A.3", "Internship Completion Certificate"),
    (1, "A.4", "Supervisor Feedback Form"),
    (1, "A.5", "Student Feedback Form"),
    (1, "A.6", "Outcome of Internship"),
    (1, "A.7", "Proof for Paid Internship (if any)"),
]

tt = doc.add_table(rows=1 + len(toc_rows), cols=3)
tt.autofit = False
tw = (1.15, 4.35, 1.0)
hdr = ("CHAPTER NO.", "TITLE", "PAGE NO.")
for cell, w, h in zip(tt.rows[0].cells, tw, hdr):
    cell.width = Inches(w)
    cell_text(cell, h, bold=True, size=11, align="center", after=4)
for cell in tt.rows[0].cells:
    tcPr = cell._tc.get_or_add_tcPr()
    borders = OxmlElement("w:tcBorders")
    el = OxmlElement("w:bottom")
    el.set(qn("w:val"), "single"); el.set(qn("w:sz"), "8"); el.set(qn("w:color"), "000000")
    borders.append(el)
    tcPr.append(borders)

for row, (lvl, num, title) in zip(tt.rows[1:], toc_rows):
    for cell, w in zip(row.cells, tw):
        cell.width = Inches(w)
    key = ("%s %s" % (num, title)).strip()
    page = pages.get(key, "")
    cell_text(row.cells[0], num, bold=(lvl == 0), size=11,
              align="left" if lvl else "left", after=4)
    cell_text(row.cells[1], title, bold=(lvl == 0), size=11,
              align="left", after=4)
    row.cells[1].paragraphs[0].paragraph_format.left_indent = Inches(0.0 if lvl == 0 else 0.3)
    cell_text(row.cells[2], str(page), size=11, align="right", after=4)

# ============================================== chapter 1
sec4 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(sec4)
add_footer(sec4, show=True)
chapter_head(doc, "1", "INTRODUCTION")

section_head(doc, "1.1  OBJECTIVE")
para(doc, "The internship was carried out at Intelizign Lifecycle Services Pvt. Ltd. from "
          "4 March 2026 to 31 March 2026 in the application development stream. Its "
          "objective was to design, build and evaluate a working software product under "
          "the conditions of a delivery team: a defined requirement, a review cycle, and "
          "a result that someone other than the author has to be able to operate and "
          "maintain.")
para(doc, "The product chosen was RoadResQ, an on-demand roadside rescue platform. A "
          "vehicle that stops working leaves its owner stranded, uncertain of the cost and "
          "unable to judge which nearby workshop can actually repair the fault. The two "
          "commercial forms that answer this need observe nothing about the service they "
          "arrange: a subscription product places the decision with a call-centre "
          "operator, and a directory application publishes a list of workshops and leaves "
          "the coordination to the owner. Neither selects a workshop against the fault "
          "that has actually occurred, and neither can explain afterwards why a particular "
          "crew was sent.")
para(doc, "The specific objectives set for the internship were therefore:")
bullets(doc, [
    ("To build a complete application ", "across three tiers \u2013 a Flutter client, a "
     "Flask service layer and a MongoDB store \u2013 rather than an isolated module."),
    ("To implement allocation as a decision, ", "not a lookup: candidates are filtered on "
     "capability, availability and position freshness before they are ranked, and every "
     "ranking decision is recorded so that it can be explained."),
    ("To work to delivery standards ", "in version control, API documentation, automated "
     "testing and written reporting, so that the result could be handed over rather than "
     "demonstrated once."),
    ("To evaluate the result honestly, ", "against a baseline, on a reproducible corpus, "
     "and to report the cases in which the approach does not help."),
])

section_head(doc, "1.2  SCOPE OF THE INTERNSHIP")
para(doc, "The internship ran for four weeks, from 4 March 2026 to 31 March 2026, and was "
          "structured as a single product assignment rather than a rotation through "
          "departments. The scope was agreed at the start and is stated below so that what "
          "was and was not attempted is unambiguous.")
para(doc, "In scope:", after=4)
bullets(doc, [
    ("Request intake. ", "Three trigger channels \u2013 an explicit SOS control, a "
     "hands-free voice keyword evaluated on the device, and a sensor-detected impact that "
     "always requires confirmation \u2013 and the context captured with each request."),
    ("Allocation. ", "Region resolution, geospatial candidate retrieval, eligibility "
     "filtering, and a six-term weighted score with recorded term contributions."),
    ("Lifecycle. ", "A twelve-state request lifecycle held in one server-side transition "
     "table, with guards against duplicate requests, double acceptance and arrival from a "
     "position the crew is not at."),
    ("Service resolution and settlement. ", "Fault classification to a service class, a "
     "fixed tariff quoted before any offer, arrival estimation, settlement and payout."),
    ("Verification. ", "An automated test suite for the service layer, system-level test "
     "cases against the running platform, and a simulated evaluation on a paired corpus of "
     "4,000 requests."),
])
para(doc, "Out of scope:", after=4, before=6)
bullets(doc, [
    ("Payments integration with a live gateway. ", "Settlement was implemented and tested "
     "against a stub, not against a production payment provider."),
    ("Regulatory and insurance handling, ", "and any commercial agreement with real "
     "workshops; the platform was evaluated with a simulated supply side."),
    ("Production deployment at scale. ", "Load behaviour was measured on a single host to "
     "establish the shape of the curve, not to certify a capacity figure."),
])
para(doc, "The work was carried out against a version-controlled repository, with weekly "
          "review of the code and the design notes. The report below describes the tasks "
          "undertaken, the tools used, the skills applied and developed, and the "
          "difficulties that had to be resolved before the system behaved correctly.")

# ============================================== chapter 2
sec5 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(sec5)
add_footer(sec5, show=True)
chapter_head(doc, "2", "INTERNSHIP ACTIVITIES")

section_head(doc, "2.1  DESCRIPTION OF TASKS AND RESPONSIBILITIES")
para(doc, "The assignment decomposed into six tasks. They are described in the order in "
          "which they were carried out, because each depends on the state left by the one "
          "before it.")

para(doc, "Task 1 \u2013 Requirement analysis and domain study", bold=True, before=8, after=3, spacing=1.2)
para(doc, "The first days were spent on the problem rather than the code: how a breakdown "
          "is actually reported, who decides which workshop attends, what the owner is told "
          "about cost, and what happens when the first workshop declines. Two observations "
          "shaped the design. First, the decision that matters is not \u201cwhich workshop "
          "is nearest\u201d but \u201cwhich workshop can repair this fault and is free to "
          "attend now\u201d. Second, every party to the exchange needs a different view of "
          "the same event: the owner needs a cost and an arrival time, the crew needs the "
          "fault and the position, and the operator needs to know why a crew was chosen. "
          "The requirements were written down as use cases and reviewed before any code was "
          "written.")

para(doc, "Task 2 \u2013 Data model and service skeleton", bold=True, before=8, after=3, spacing=1.2)
para(doc, "The persistence layer was modelled first: users, vehicles, crews, service "
          "capabilities, requests, offers and settlements, with the request as the "
          "aggregate that everything else hangs from. A Flask application was then stood up "
          "with a modular layout \u2013 allocation, state machine, pricing, settlement and "
          "detection as separate modules \u2013 so that the decision logic could be tested "
          "without an HTTP request. Authentication used signed tokens, with role separation "
          "between owner, crew and administrator.")

para(doc, "Task 3 \u2013 The allocation engine", bold=True, before=8, after=3, spacing=1.2)
para(doc, "This was the central piece of work. Allocation runs in two stages. The first "
          "stage is a filter: crews must hold a capability that matches the fault, must be "
          "available, must be within their declared service radius, and must have reported "
          "their position recently enough to be trusted. The second stage scores the "
          "survivors on six normalised terms \u2013 proximity, service compatibility, "
          "availability, verification status, current workload and rating \u2013 with "
          "weights held in configuration. The design decision that cost the most time was "
          "to return the contribution of each term alongside the total score, so that a "
          "dispatch can be justified to an owner who asks why a particular crew was sent.")

para(doc, "Task 4 \u2013 Request lifecycle and its guards", bold=True, before=8, after=3, spacing=1.2)
para(doc, "A rescue request passes through twelve states, from creation to settlement or "
          "cancellation. Rather than scattering the rules across handlers, every legal "
          "transition was collected into one table on the server, and each transition was "
          "given its own permission and guard. Three defects that appeared during testing "
          "were closed this way: a duplicate request created by a retried tap, an offer "
          "accepted twice by a crew on a weak connection, and an arrival recorded from a "
          "position the crew was not at. Making the endpoints idempotent removed the first "
          "two at the source.")

para(doc, "Task 5 \u2013 Client application and trigger channels", bold=True, before=8, after=3, spacing=1.2)
para(doc, "The Flutter client was built against the service layer, with state handled "
          "through a provider-based structure so that a request in progress survives "
          "navigation. Three trigger channels were implemented: an explicit SOS control, a "
          "voice keyword evaluated on the device so that it works without a round trip, and "
          "impact detection from the accelerometer and gyroscope. Impact detection never "
          "raises a request by itself; it presents a countdown that the owner must confirm, "
          "because a false alarm at speed is worse than a missed one.")

para(doc, "Task 6 \u2013 Testing, evaluation and documentation", bold=True, before=8, after=3, spacing=1.2)
para(doc, "The service layer was covered by an automated suite covering the score, the "
          "transition table, tariff resolution and settlement. System-level cases were then "
          "executed against the running platform, and the allocation policy was compared "
          "with a proximity-only baseline on a paired corpus of 4,000 simulated requests. "
          "The final task was documentation: an API reference, a data dictionary, the "
          "deployment steps and the evaluation report.")

section_head(doc, "2.2  TOOLS, TECHNOLOGIES AND SOFTWARE USED")
para(doc, "The stack was chosen so that each tier could be exercised independently and so "
          "that nothing in it required a commercial licence. The table below lists what was "
          "used and the purpose it served.", after=8)

tools = [
    ("Flutter / Dart", "Client application for owner and crew roles; single code base for "
                       "Android and iOS."),
    ("Flask (Python)", "Service layer; allocation, lifecycle, pricing, settlement and "
                       "detection exposed as REST endpoints."),
    ("MongoDB", "Document store for requests, crews, offers and settlements; geospatial "
                "index for candidate retrieval."),
    ("JWT authentication", "Signed tokens with role claims for owner, crew and "
                           "administrator."),
    ("Google Maps / OpenStreetMap", "Position capture, route distance and map display."),
    ("Firebase Cloud Messaging", "Offer and status notifications to the client."),
    ("Git and GitHub", "Version control, branching and pull-request review."),
    ("Postman", "Endpoint testing and the collection used for system-level cases."),
    ("pytest", "Automated suite for the service layer."),
    ("VS Code", "Development environment for both tiers."),
]
tt2 = doc.add_table(rows=1 + len(tools), cols=2)
tt2.autofit = False
for row in tt2.rows:
    row.cells[0].width = Inches(1.85)
    row.cells[1].width = Inches(4.15)
cell_text(tt2.rows[0].cells[0], "Tool / Technology", bold=True, size=11, align="left")
cell_text(tt2.rows[0].cells[1], "Purpose in the project", bold=True, size=11, align="left")
for row, (name, purpose) in zip(tt2.rows[1:], tools):
    cell_text(row.cells[0], name, bold=True, size=10.5, align="left")
    cell_text(row.cells[1], purpose, size=10.5, align="left")
for row in tt2.rows:
    for cell in row.cells:
        set_cell_borders(cell)
para(doc, "", after=6, spacing=1.0)

section_head(doc, "2.3  SKILLS APPLIED AND DEVELOPED")
para(doc, "The internship drew on the coursework in databases, software engineering and "
          "computer networks, and extended each of them in a direction that only appears "
          "when software has to run for someone else.", after=6)
para(doc, "Technical skills applied", bold=True, after=3, spacing=1.2)
bullets(doc, [
    ("Data modelling and indexing. ", "Designing documents around the aggregate that is "
     "actually queried, and adding a geospatial index where retrieval demanded it."),
    ("Service design. ", "Separating decision logic from transport so that the allocation "
     "engine and the lifecycle table could be tested as pure functions."),
    ("State management in a mobile client, ", "including keeping an in-flight request "
     "consistent across navigation and reconnection."),
    ("Testing. ", "Writing cases that assert refusal as well as success, which is where "
     "most of the defects were found."),
])
para(doc, "Skills developed", bold=True, after=3, before=8, spacing=1.2)
bullets(doc, [
    ("Reading a requirement for what it leaves out. ", "Much of the design came from "
     "questions the brief did not answer, such as what happens when a crew accepts and "
     "then does not move."),
    ("Explaining a decision. ", "Building the case for a design in review, in writing, and "
     "in the interface itself."),
    ("Working to a review cycle. ", "Submitting work for comment, taking the comment, and "
     "separating a genuine defect from a matter of preference."),
    ("Documenting for a successor. ", "Writing the API reference and data dictionary so "
     "that the system could be picked up without the author present."),
])

section_head(doc, "2.4  CHALLENGES FACED AND SOLUTIONS IMPLEMENTED")
para(doc, "Four problems took disproportionate time. Each is recorded with the symptom, the "
          "cause and the change that resolved it.", after=6)

challenges = [
    ("A dispatch could not be defended. ",
     "The first scoring implementation returned a single number, so when an owner asked why "
     "a distant crew had been sent there was no answer. The score was rebuilt to carry the "
     "contribution of each of its six terms, and the response was extended to return them. "
     "The change also exposed a weighting error that the total had concealed."),
    ("Sensor detection fired on potholes and speed breakers. ",
     "A magnitude threshold alone cannot distinguish a crash from road roughness. Detection "
     "was rebuilt around a validation window with jerk analysis and a mandatory user "
     "confirmation. At a fixed false-alarm budget the detection rate rose from 65.0% to "
     "90.5%."),
    ("State drifted when requests were retried. ",
     "Mobile clients on weak connections retried taps, producing duplicate requests, and a "
     "replayed acceptance produced two assigned crews. Consolidating every legal transition "
     "into one server-side table with idempotent endpoints removed both classes of defect."),
    ("Stale crew positions distorted the ranking. ",
     "A crew that had not reported for twenty minutes could still win a dispatch on the "
     "strength of an old position. Freshness is now a filter applied before scoring, not a "
     "penalty applied after it, so an unreachable crew cannot win at all."),
]
for i, (title, body) in enumerate(challenges, start=1):
    para(doc, "Challenge %d \u2013 %s" % (i, title.rstrip(". ")), bold=True,
         before=8, after=3, spacing=1.2)
    para(doc, body)

# ============================================== chapter 3
sec6 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(sec6)
add_footer(sec6, show=True)
chapter_head(doc, "3", "CONCLUSION")

section_head(doc, "3.1  SUMMARY OF INTERNSHIP EXPERIENCE")
para(doc, "The internship produced a working platform rather than a prototype: a client "
          "application, a service layer with allocation, lifecycle, pricing and settlement, "
          "a documented API, and an automated suite. On a paired corpus of 4,000 simulated "
          "requests the weighted allocation policy raised the allocation rate from 84.1% to "
          "96.5% and thirty-minute compliance from 57.3% to 66.4% against a proximity-only "
          "baseline, at a cost of 0.3 minutes in the median time to resolution. The gain was "
          "concentrated where supply was thin, which is the condition the platform exists to "
          "serve.")
para(doc, "The more useful outcome was the change in working method. Requirements were "
          "written and reviewed before implementation; the decision logic was isolated so "
          "that it could be tested without a device; defects were traced to a cause rather "
          "than patched at the symptom; and every claim in the evaluation was produced by a "
          "script that could be run again. The four weeks also made clear where the system "
          "is still weak \u2013 the supply side is simulated, payment settlement is stubbed, "
          "and the detector has been tuned on a small corpus \u2013 which is recorded in the "
          "report rather than left implicit.")

section_head(doc, "3.2  PERSONAL AND PROFESSIONAL DEVELOPMENT")
para(doc, "Working to a delivery standard changed several habits. The first was to write "
          "down the decision before defending it: design notes that could be read in review "
          "proved more persuasive than explanation in the moment. The second was to treat "
          "testing as part of the feature rather than a phase after it, because the guards "
          "that made the lifecycle correct were themselves tests. The third was to keep the "
          "explanation of a result alongside the result, which is why the allocation score "
          "records its own reasoning.")
para(doc, "The internship also clarified the direction of further work. The natural "
          "extensions \u2013 a real payment provider, a live supply side, on-device model "
          "inference for fault classification, and offline-tolerant synchronisation \u2013 "
          "are the parts that would turn a defensible system into a deployable one. The "
          "completion certificate records dedication, enthusiasm and an ability to apply "
          "programming knowledge to business problems; the work described here is the "
          "evidence for that assessment, and the gaps listed above are the agenda for the "
          "next stage.")

# ============================================== annexure
sec7 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(sec7)
add_footer(sec7, show=True)
para(doc, "ANNEXURE", size=16, bold=True, align="center", after=18, spacing=1.0)

annex = [
    ("A.1  REQUEST LETTER", None),
    ("A.2  OFFER LETTER", None),
    ("A.3  INTERNSHIP COMPLETION CERTIFICATE", "_cert.png"),
    ("A.4  SUPERVISOR FEEDBACK FORM", None),
    ("A.5  STUDENT FEEDBACK FORM", None),
    ("A.6  OUTCOME OF INTERNSHIP", None),
    ("A.7  PROOF FOR PAID INTERNSHIP (IF ANY)", None),
]
for title, image in annex:
    p = para(doc, "", align="left", after=8, before=14, spacing=1.0)
    p.paragraph_format.page_break_before = True
    r = p.add_run(title)
    r.bold = True
    r.font.size = Pt(13)
    r.font.name = "Times New Roman"
    if image:
        pic = doc.add_paragraph()
        pic.alignment = WD_ALIGN_PARAGRAPH.CENTER
        pic.paragraph_format.space_before = Pt(6)
        pic.add_run().add_picture(image, width=Inches(5.9))
    else:
        para(doc, "", after=10, spacing=1.0)
        para(doc, "[ Insert the scanned copy of this document on this page. ]",
             italic=True, align="center", size=12, after=0, spacing=1.5)

doc.save(DOCX)
print("saved", DOCX)
