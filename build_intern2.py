"""Internship report for Mithun Harishwar (RoadResQ at Intelizign),
laid out to match INTERN_REPORT_POOJAA_K_FINAL.docx."""
import json
import os

from docx import Document
from docx.enum.section import WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Inches, Pt

DOCX = "Internship_Report_Mithun_RoadResQ.docx"
MAP = "intern_pages.json"

STUDENT = "MITHUN HARISHWAR P R"
ROLL = "310623205087"
TITLE = ("RoadResQ: A Capability-Constrained On-Demand Roadside Rescue "
         "Platform with Region-Aware Partner Allocation and Multi-Channel "
         "Incident Triggering")
COMPANY = "Intelizign Lifecycle Services Pvt Ltd"
PERIOD = "04/03/2026 - 31/03/2026"
MONTH = "MARCH 2026"
SUPERVISOR = "Narmadha Senthilkumar,\nSenior HR Manager"

pages = json.load(open(MAP, encoding="utf-8")) if os.path.exists(MAP) else {}

TOC = [
    ("1", "", "INTRODUCTION"),
    ("", "1.1", "Objective"),
    ("", "1.2", "Scope of the Internship"),
    ("2", "", "INTERNSHIP ACTIVITIES"),
    ("", "2.1", "Description of Tasks and Responsibilities"),
    ("", "2.2", "Tools, Technologies and Software Used"),
    ("", "2.3", "Skills Applied and Developed"),
    ("", "2.4", "Challenges Faced and Solutions Implemented"),
    ("3", "", "CONCLUSION"),
    ("", "3.1", "Summary of Internship Experience"),
    ("", "3.2", "Personal and Professional Development"),
    ("", "", "ANNEXURE"),
    ("", "A.1", "Internship Completion Certificate"),
    ("", "A.2", "Student Feedback Form"),
    ("", "A.3", "Outcome of Internship"),
    ("", "A.4", "Proof for Paid Internship (if any)"),
]


# ------------------------------------------------------------------ helpers
def borders(table, sz=6, inside=True):
    tblPr = table._tbl.tblPr
    el = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        if edge.startswith("inside") and not inside:
            continue
        e = OxmlElement("w:" + edge)
        e.set(qn("w:val"), "single")
        e.set(qn("w:sz"), str(sz))
        e.set(qn("w:color"), "000000")
        el.append(e)
    tblPr.append(el)


def no_borders(table):
    tblPr = table._tbl.tblPr
    el = OxmlElement("w:tblBorders")
    for edge in ("top", "left", "bottom", "right", "insideH", "insideV"):
        e = OxmlElement("w:" + edge)
        e.set(qn("w:val"), "none")
        el.append(e)
    tblPr.append(el)


def cell(c, text, bold=False, size=12, align="left", spacing=1.0, after=2):
    c.text = ""
    p = c.paragraphs[0]
    p.alignment = {"left": WD_ALIGN_PARAGRAPH.LEFT,
                   "center": WD_ALIGN_PARAGRAPH.CENTER,
                   "right": WD_ALIGN_PARAGRAPH.RIGHT}[align]
    pf = p.paragraph_format
    pf.space_after = Pt(after)
    pf.space_before = Pt(0)
    pf.line_spacing = spacing
    for i, chunk in enumerate(str(text).split("\n")):
        if i:
            p.add_run().add_break()
        r = p.add_run(chunk)
        r.bold = bold
        r.font.size = Pt(size)
        r.font.name = "Times New Roman"
    return p


def para(doc, text="", size=12, bold=False, align="justify", after=8, before=0,
         spacing=1.5):
    p = doc.add_paragraph()
    p.alignment = {"left": WD_ALIGN_PARAGRAPH.LEFT,
                   "center": WD_ALIGN_PARAGRAPH.CENTER,
                   "justify": WD_ALIGN_PARAGRAPH.JUSTIFY}[align]
    pf = p.paragraph_format
    pf.space_after = Pt(after)
    pf.space_before = Pt(before)
    pf.line_spacing = spacing
    if text:
        r = p.add_run(text)
        r.bold = bold
        r.font.size = Pt(size)
        r.font.name = "Times New Roman"
    return p


def lead_para(doc, lead, rest):
    """Body paragraph in the sample's style: bold topic lead-in, then prose."""
    p = para(doc, after=8)
    r1 = p.add_run(lead)
    r1.bold = True
    r1.font.size = Pt(12)
    r1.font.name = "Times New Roman"
    r2 = p.add_run(rest)
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"
    return p


def chapter_head(doc, num, name):
    p = para(doc, align="center", after=8, spacing=1.15)
    r = p.add_run("CHAPTER %s" % num)
    r.bold = True
    r.font.size = Pt(14)
    r.font.name = "Times New Roman"
    p2 = para(doc, align="center", after=14, spacing=1.15)
    r2 = p2.add_run(name)
    r2.bold = True
    r2.font.size = Pt(14)
    r2.font.name = "Times New Roman"


def section_head(doc, label, new_page=False):
    p = para(doc, align="left", after=6, before=10, spacing=1.15)
    p.paragraph_format.page_break_before = new_page
    r = p.add_run(label)
    r.bold = True
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"


def _field(paragraph, instr):
    run = paragraph.add_run()
    b = OxmlElement("w:fldChar"); b.set(qn("w:fldCharType"), "begin")
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = instr
    s = OxmlElement("w:fldChar"); s.set(qn("w:fldCharType"), "separate")
    t = OxmlElement("w:t"); t.text = "1"
    e = OxmlElement("w:fldChar"); e.set(qn("w:fldCharType"), "end")
    for x in (b, it, s, t, e):
        run._r.append(x)
    run.font.size = Pt(11)
    run.font.name = "Times New Roman"


def add_footer(section, show=True):
    f = section.footer
    f.is_linked_to_previous = False
    p = f.paragraphs[0]
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for r in list(p.runs):
        r._r.getparent().remove(r._r)
    if show:
        _field(p, " PAGE ")


def clear_pgnum(section):
    for el in section._sectPr.findall(qn("w:pgNumType")):
        section._sectPr.remove(el)


def pg_start(section, start):
    clear_pgnum(section)
    pg = OxmlElement("w:pgNumType")
    pg.set(qn("w:fmt"), "decimal")
    pg.set(qn("w:start"), str(start))
    section._sectPr.append(pg)


# ------------------------------------------------------------------ document
doc = Document()
st = doc.styles["Normal"]
st.font.name = "Times New Roman"
st.font.size = Pt(12)

s0 = doc.sections[0]
s0.page_width = Cm(21); s0.page_height = Cm(29.7)
s0.left_margin = Inches(1.1); s0.right_margin = Inches(1.0)
s0.top_margin = Inches(1.0); s0.bottom_margin = Inches(1.0)

# ---------------------------------------------------------------- title page
lg = doc.add_table(rows=1, cols=2)
lg.autofit = False
no_borders(lg)
lg.columns[0].width = Inches(1.15)
lg.columns[1].width = Inches(4.7)
lg.rows[0].cells[0].width = Inches(1.15)
lg.rows[0].cells[1].width = Inches(4.7)
p0 = lg.rows[0].cells[0].paragraphs[0]
p0.paragraph_format.space_after = Pt(0)
p0.add_run().add_picture("_logo1.png", width=Inches(1.0))
p1 = lg.rows[0].cells[1].paragraphs[0]
p1.alignment = WD_ALIGN_PARAGRAPH.RIGHT
p1.paragraph_format.space_after = Pt(0)
p1.add_run().add_picture("_logo0.png", width=Inches(2.7))

para(doc, after=8, spacing=1.0)
para(doc, TITLE, size=18, bold=True, align="center", after=10, spacing=1.15)
para(doc, "AN INTERNSHIP REPORT", size=14, bold=True, align="center", after=10, spacing=1.15)
para(doc, "Submitted by", size=14, bold=True, align="center", after=14, spacing=1.15)
para(doc, "%s (%s)" % (STUDENT, ROLL), size=16, bold=True, align="center", after=14, spacing=1.15)
para(doc, "in partial fulfilment for the award of the degree", size=14, bold=True,
     align="center", after=6, spacing=1.15)
para(doc, "of", size=14, bold=True, align="center", after=6, spacing=1.15)
para(doc, "BACHELOR OF TECHNOLOGY", size=14, bold=True, align="center", after=6, spacing=1.15)
para(doc, "in", size=14, bold=True, align="center", after=6, spacing=1.15)
para(doc, "INFORMATION TECHNOLOGY", size=14, bold=True, align="center", after=22, spacing=1.15)
para(doc, "EASWARI ENGINEERING COLLEGE, RAMAPURAM", size=14, bold=True, align="center",
     after=6, spacing=1.15)
para(doc, "(AUTONOMOUS)", size=14, bold=True, align="center", after=12, spacing=1.15)
para(doc, "ANNA UNIVERSITY: CHENNAI 600 025", size=16, bold=True, align="center",
     after=10, spacing=1.15)
para(doc, MONTH, size=14, align="center", after=0, spacing=1.15)

# ---------------------------------------------------------- certificate page
s2 = doc.add_section(WD_SECTION.NEW_PAGE)
add_footer(doc.sections[0], show=False)
add_footer(s2, show=True)
pg_start(s2, 2)

para(doc, "CERTIFICATE OF EVALUATION", size=12, bold=True, align="center", after=20)
for label, value in (("College Name", "Easwari Engineering College"),
                     ("Branch & Semester", "Information Technology & VIII"),
                     ("Internship Period", PERIOD),
                     ("Company Name", COMPANY)):
    p = para(doc, after=2)
    r = p.add_run("%-22s: %s" % (label, value))
    r.bold = True
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"

para(doc, after=12)
grid = doc.add_table(rows=2, cols=4)
grid.alignment = WD_TABLE_ALIGNMENT.CENTER
grid.autofit = False
widths = (Inches(1.0), Inches(1.5), Inches(1.7), Inches(1.9))
heads = ("Reg. No.", "Student Name", "Title", "Name of Industry\nSupervisor &\nDesignation")
for c, w, h in zip(grid.rows[0].cells, widths, heads):
    c.width = w
    cell(c, h, bold=True, size=11, align="center", after=0)
grid.rows[0].height = Inches(1.0)
vals = (ROLL, STUDENT, TITLE, COMPANY + "\n" + SUPERVISOR)
for c, w, v in zip(grid.rows[1].cells, widths, vals):
    c.width = w
    cell(c, v, size=9.5, align="left", after=0)
grid.rows[1].height = Inches(2.4)
borders(grid)

para(doc, after=14)
para(doc, "The report of the internship work submitted by the above student in partial "
          "fulfilment for the award of Bachelor of Technology Degree in Information "
          "Technology of Anna University were evaluated and confirmed to be are part of "
          "the work done by the above student.", after=26)
para(doc, "The internship evaluation was held on ______________", after=36)
para(doc, "INTERNAL EXAMINER", size=12, bold=True, align="left", after=0)

# --------------------------------------------------------------- contents
s3 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(s3)
add_footer(s3, show=True)

toc = doc.add_table(rows=2 + len(TOC), cols=4)
toc.autofit = False
colw = (Inches(1.0), Inches(0.75), Inches(3.55), Inches(0.95))
for row in toc.rows:
    for c, w in zip(row.cells, colw):
        c.width = w
borders(toc, sz=6)

title_row = toc.rows[0]
merged = title_row.cells[0].merge(title_row.cells[3])
cell(merged, "TABLE OF CONTENTS", bold=True, size=12, align="center", after=0)
hdr = toc.rows[1]
cell(hdr.cells[0], "CHAPTER NO.", bold=True, size=11, align="center", after=0)
mid = hdr.cells[1].merge(hdr.cells[2])
cell(mid, "TITLE", bold=True, size=11, align="center", after=0)
cell(hdr.cells[3], "PAGE NO.", bold=True, size=11, align="center", after=0)

for row, (chap, sub, ttl) in zip(toc.rows[2:], TOC):
    key = ("%s %s" % (chap or sub, ttl)).strip()
    cell(row.cells[0], chap, bold=True, size=11, align="center", after=0)
    cell(row.cells[1], sub, size=11, align="center", after=0)
    cell(row.cells[2], ttl, bold=(not sub), size=11, align="left", after=0)
    cell(row.cells[3], str(pages.get(key, "")), size=11, align="center", after=0)

# ---------------------------------------------------------------- chapter 1
s4 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(s4)
add_footer(s4, show=True)
chapter_head(doc, "1", "INTRODUCTION")

section_head(doc, "1.1  OBJECTIVE")
para(doc, "The primary objective of the internship was to build a complete software "
          "product under delivery conditions \u2013 a stated requirement, a review cycle, "
          "and a result that someone other than its author has to be able to operate \u2013 "
          "rather than to complete an exercise. The internship was carried out at "
          "Intelizign Lifecycle Services Pvt. Ltd. from 4 March 2026 to "
          "31 March 2026, in the application development stream.")
para(doc, "The product developed was RoadResQ, an on-demand roadside rescue platform. A "
          "vehicle that stops working leaves its owner stranded, uncertain of the cost and "
          "unable to judge which nearby workshop can actually repair the fault. The two "
          "commercial forms that answer this need observe nothing about the service they "
          "arrange: a subscription product places the decision with a call-centre operator "
          "and prices an intermittent need as an annual entitlement, while a directory "
          "application publishes a list of workshops and leaves the coordination to the "
          "owner. Neither selects a workshop against the fault that has actually occurred, "
          "and neither can explain afterwards why a particular crew was sent.")
para(doc, "Within that product, the objectives set for the internship period were to "
          "implement allocation as a decision rather than a lookup, to hold the request "
          "lifecycle in one auditable place, to build the client for three different "
          "trigger channels, and to evaluate the result against a baseline on a "
          "reproducible corpus. A further objective was professional: to work to the review, "
          "documentation and testing standards of a delivery team, so that the system could "
          "be handed over rather than demonstrated once.")

section_head(doc, "1.2  SCOPE OF THE INTERNSHIP")
para(doc, "The internship covered the full build of the platform across three tiers: a "
          "Flutter client for the owner and crew roles, a Flask service layer, and a "
          "MongoDB document store. Within that boundary the scope included request intake "
          "from an SOS control, an on-device voice keyword and a sensor-detected impact "
          "that always requires confirmation; region resolution and geospatial candidate "
          "retrieval; eligibility filtering on capability, availability and position "
          "freshness; a six-term weighted allocation score that records the contribution of "
          "each term; a twelve-state request lifecycle with guards; fault classification to "
          "a service class with a fixed tariff quoted before any offer; arrival estimation; "
          "settlement and payout; and an automated test suite with a simulated evaluation "
          "over 4,000 paired requests.")
para(doc, "Three areas were deliberately left outside the scope. Payment settlement was "
          "implemented and tested against a stub rather than a live payment gateway. The "
          "supply side \u2013 workshops and crews \u2013 was simulated rather than contracted, "
          "so no commercial agreement with real workshops was undertaken. Production "
          "deployment at scale was not attempted: load behaviour was measured on a single "
          "host to establish the shape of the curve, not to certify a capacity figure. "
          "Regulatory, insurance and dispute-handling requirements were also out of scope, "
          "and are recorded as future work in the evaluation.")

# ---------------------------------------------------------------- chapter 2
s5 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(s5)
add_footer(s5, show=True)
chapter_head(doc, "2", "INTERNSHIP ACTIVITIES")

section_head(doc, "2.1  DESCRIPTION OF TASKS AND RESPONSIBILITIES")
para(doc, "During the internship I worked across the client application, the service layer "
          "and the evaluation of the finished system. The work decomposed into six tasks, "
          "carried out in the order below because each depends on the state left by the "
          "previous one.")
lead_para(doc, "Requirement analysis and domain study. ",
          "The first days were spent on the problem rather than the code: how a breakdown "
          "is reported, who decides which workshop attends, what the owner is told about "
          "cost, and what happens when the first workshop declines. Two observations shaped "
          "the design. The decision that matters is not which workshop is nearest but which "
          "workshop can repair this fault and is free to attend now; and every party needs "
          "a different view of the same event, so the owner needs a cost and an arrival "
          "time, the crew needs the fault and the position, and the operator needs to know "
          "why a crew was chosen. The requirements were written as use cases and reviewed "
          "before implementation began.")
lead_para(doc, "Data model and service skeleton. ",
          "The persistence layer was modelled first \u2013 users, vehicles, crews, service "
          "capabilities, requests, offers and settlements, with the request as the aggregate "
          "that everything else hangs from. A Flask application was then stood up with the "
          "decision logic in separate modules so that allocation, the transition table, "
          "pricing and settlement could be tested without an HTTP request. Authentication "
          "used signed tokens with role separation between owner, crew and administrator.")
lead_para(doc, "The allocation engine. ",
          "This was the central piece of work and ran in two stages. The first stage is a "
          "filter: a crew must hold a capability that matches the fault, must be available, "
          "must lie within its declared service radius, and must have reported its position "
          "recently enough to be trusted. The second stage scores the survivors on six "
          "normalised terms \u2013 proximity, service compatibility, availability, "
          "verification status, current workload and rating \u2013 with the weights held in "
          "configuration. The design decision that cost the most time was to return the "
          "contribution of each term alongside the total, so that a dispatch can be "
          "justified to an owner who asks why a particular crew was sent.")
lead_para(doc, "Request lifecycle and its guards. ",
          "A request passes through twelve states from creation to settlement or "
          "cancellation. Instead of scattering the rules across handlers, every legal "
          "transition was collected into one table on the server, and each transition was "
          "given its own permission and guard. Three defects found in testing were closed "
          "this way: a duplicate request created by a retried tap, an offer accepted twice "
          "by a crew on a weak connection, and an arrival recorded from a position the crew "
          "was not at. Making the endpoints idempotent removed the first two at the source.")
lead_para(doc, "Client application and trigger channels. ",
          "The Flutter client was built against the service layer, with state held so that "
          "a request in progress survives navigation. Three trigger channels were "
          "implemented: an explicit SOS control, a voice keyword evaluated on the device so "
          "that it works without a round trip, and impact detection from the accelerometer "
          "and gyroscope. Impact detection never raises a request by itself; it presents a "
          "countdown that the owner must confirm, because a false alarm at speed is worse "
          "than a missed one.")
lead_para(doc, "Testing, evaluation and documentation. ",
          "The service layer was covered by an automated suite exercising the score, the "
          "transition table, tariff resolution and settlement. System-level cases were then "
          "executed against the running platform, and the allocation policy was compared "
          "with a proximity-only baseline on 4,000 paired simulated requests. The final task "
          "was documentation: the API reference, the data dictionary, the deployment steps "
          "and the evaluation report.")

section_head(doc, "2.2  TOOLS, TECHNOLOGIES AND SOFTWARE USED")
para(doc, "The stack was chosen so that each tier could be exercised independently and so "
          "that nothing in it required a commercial licence.")
lead_para(doc, "Flutter and Dart. ",
          "The client application was written once in Flutter and run on both Android and "
          "iOS, with the owner and crew experiences separated by role rather than by "
          "application. Dart's asynchronous model was used for the network calls that drive "
          "the request lifecycle.")
lead_para(doc, "Flask. ",
          "The service layer was built in Python with Flask, exposing the allocation engine, "
          "lifecycle transitions, tariff resolution, settlement and detection as REST "
          "endpoints. Keeping the decision logic in importable modules meant it could be "
          "tested without a running server.")
lead_para(doc, "MongoDB. ",
          "Requests, crews, offers and settlements were stored as documents shaped around "
          "the queries that read them, with a geospatial index on crew positions for "
          "candidate retrieval and a compound index supporting offer lookups by request.")
lead_para(doc, "Authentication, messaging and mapping. ",
          "Signed JSON Web Tokens carried role claims for the three user types. Firebase "
          "Cloud Messaging delivered offers and status changes to the client, and Google "
          "Maps together with OpenStreetMap data supplied position capture, route distance "
          "and the map view.")
lead_para(doc, "Development and testing tools. ",
          "Git and GitHub were used for version control and pull-request review, Postman for "
          "endpoint testing and for the collection that became the system-level cases, "
          "pytest for the automated suite, and Visual Studio Code as the editor for both "
          "tiers. The evaluation harness was written as a script so that every reported "
          "figure can be regenerated.")

section_head(doc, "2.3  SKILLS APPLIED AND DEVELOPED")
para(doc, "The internship drew directly on coursework in database systems, software "
          "engineering and computer networks, and extended each of them in a direction that "
          "only appears when software has to run for someone else.")
lead_para(doc, "Data modelling and indexing. ",
          "Designing documents around the aggregate actually queried, and adding a "
          "geospatial index where retrieval performance demanded it, connected the "
          "normalisation theory of the classroom to a concrete cost.")
lead_para(doc, "Service and interface design. ",
          "Separating decision logic from transport made the allocation engine and the "
          "lifecycle table testable as pure functions, and clarified how an API should be "
          "shaped for the clients that consume it.")
lead_para(doc, "State management in a mobile client. ",
          "Keeping an in-flight request consistent across navigation, reconnection and "
          "application restart required an explicit model of what the client knows and when "
          "it knows it.")
lead_para(doc, "Testing as design. ",
          "Writing cases that assert refusal as well as success turned out to be where most "
          "defects surfaced, and changed how the endpoints were designed rather than only "
          "how they were verified.")
lead_para(doc, "Explaining a decision. ",
          "Presenting a design in review and writing the API reference improved my ability "
          "to state a case in writing and to separate a genuine defect from a matter of "
          "preference.")
lead_para(doc, "Working to a review cycle. ",
          "Submitting work for comment, taking the comment, and revising without losing the "
          "intent of the original design was the professional skill practised most "
          "consistently during the four weeks.")

section_head(doc, "2.4  CHALLENGES FACED AND SOLUTIONS IMPLEMENTED")
para(doc, "Four problems took disproportionate time. Each is recorded with the symptom, "
          "the cause and the change that resolved it.")
lead_para(doc, "A dispatch could not be defended. ",
          "The first scoring implementation returned a single number, so when an owner asked "
          "why a distant crew had been sent there was no answer. The score was rebuilt to "
          "carry the contribution of each of its six terms and the response extended to "
          "return them; the change also exposed a weighting error that the total had "
          "concealed.")
lead_para(doc, "Sensor detection fired on potholes and speed breakers. ",
          "A magnitude threshold alone cannot distinguish a crash from road roughness. "
          "Detection was rebuilt around a validation window with jerk analysis and a "
          "mandatory user confirmation. At a fixed false-alarm budget the detection rate "
          "rose from 65.0% to 90.5%.")
lead_para(doc, "State drifted when requests were retried. ",
          "Mobile clients on weak connections retried taps, producing duplicate requests, "
          "and a replayed acceptance produced two assigned crews. Consolidating every legal "
          "transition into one server-side table with idempotent endpoints removed both "
          "classes of defect rather than the individual symptoms.")
lead_para(doc, "Stale crew positions distorted the ranking. ",
          "A crew that had not reported for twenty minutes could still win a dispatch on the "
          "strength of an old position. Freshness is now a filter applied before scoring "
          "rather than a penalty applied after it, so an unreachable crew cannot win at all.")

# ---------------------------------------------------------------- chapter 3
s6 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(s6)
add_footer(s6, show=True)
chapter_head(doc, "3", "CONCLUSION")

section_head(doc, "3.1  SUMMARY OF INTERNSHIP EXPERIENCE")
para(doc, "The internship produced a working platform rather than a prototype: a client "
          "application, a service layer with allocation, lifecycle, pricing and settlement, "
          "a documented API and an automated suite. On a paired corpus of 4,000 simulated "
          "requests the weighted allocation policy raised the allocation rate from 84.1% to "
          "96.5% and thirty-minute compliance from 57.3% to 66.4% against a proximity-only "
          "baseline, at a cost of 0.3 minutes in the median time to resolution. The gain was "
          "concentrated where supply was thin, which is the condition the platform exists to "
          "serve.")
para(doc, "The more useful outcome was the change in working method. Requirements were "
          "written and reviewed before implementation; the decision logic was isolated so "
          "that it could be tested without a device; defects were traced to a cause rather "
          "than patched at the symptom; and every claim in the evaluation is produced by a "
          "script that can be run again. The four weeks also made clear where the system "
          "remains weak \u2013 the supply side is simulated, payment settlement is stubbed "
          "and the detector is tuned on a small corpus \u2013 which is recorded in the report "
          "rather than left implicit.")

section_head(doc, "3.2  PERSONAL AND PROFESSIONAL DEVELOPMENT")
para(doc, "Working to a delivery standard changed several habits. The first was to write "
          "down a decision before defending it: design notes that could be read in review "
          "proved more persuasive than explanation in the moment. The second was to treat "
          "testing as part of the feature rather than a phase after it, because the guards "
          "that made the lifecycle correct were themselves tests. The third was to keep the "
          "explanation of a result alongside the result, which is why the allocation score "
          "records its own reasoning.")
para(doc, "The internship also clarified the direction of further work. A real payment "
          "provider, a live supply side, on-device model inference for fault classification "
          "and offline-tolerant synchronisation are the parts that would turn a defensible "
          "system into a deployable one. The completion certificate records dedication, "
          "enthusiasm and an ability to apply programming knowledge to business problems; "
          "the work described here is the evidence for that assessment, and the gaps listed "
          "above are the agenda for the next stage.")

# ---------------------------------------------------------------- annexure
s7 = doc.add_section(WD_SECTION.NEW_PAGE)
clear_pgnum(s7)
add_footer(s7, show=True)
para(doc, "ANNEXURE", size=14, bold=True, align="center", after=18, spacing=1.15)

def annex_head(label, title):
    p = para(doc, align="left", after=6, before=8, spacing=1.15)
    p.paragraph_format.page_break_before = True
    r = p.add_run(label)
    r.bold = True
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"
    r2 = p.add_run("   " + title)
    r2.bold = True
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"

annex_head("A.1", "INTERNSHIP COMPLETION CERTIFICATE")
pic = doc.add_paragraph()
pic.alignment = WD_ALIGN_PARAGRAPH.CENTER
pic.paragraph_format.space_before = Pt(8)
pic.add_run().add_picture("_cert.png", width=Inches(5.8))

annex_head("A.2", "STUDENT FEEDBACK FORM")
para(doc, "[ Paste the scanned copy of the signed Student Feedback Form on this page. ]",
     align="center", after=0)
para(doc, "", after=10)
para(doc, "The form is issued by the Department of Information Technology and is returned "
          "to the internship coordinator after the viva-voce examination. It records the "
          "student's assessment of the internship: the relevance of the assigned work to "
          "the curriculum, the quality of supervision and mentoring received, the adequacy "
          "of the facilities provided by the organisation, and the usefulness of the "
          "internship in preparing for a professional role.")

annex_head("A.3", "OUTCOME OF INTERNSHIP")
para(doc, "The internship produced a working software product and a set of transferable "
          "practices. The product is RoadResQ, an on-demand roadside rescue platform that "
          "assigns a rescue crew to a stranded vehicle on the basis of the fault reported, "
          "the capability of the crew, its availability and the freshness of its position, "
          "and that records the reasoning behind each assignment so that the decision can be "
          "explained to the owner.")
para(doc, "The measurable outcomes were an allocation rate of 96.5% against 84.1% for a "
          "proximity-only policy, thirty-minute compliance of 66.4% against 57.3%, median "
          "time to resolution within 0.3 minutes of the baseline, and a detection rate of "
          "90.5% against 65.0% at a fixed false-alarm budget. Beyond the figures, the "
          "outcome was a method: requirements written before code, decision logic isolated "
          "for testing, defects traced to their cause, and an evaluation that can be "
          "regenerated from a script.")

annex_head("A.4", "PROOF FOR PAID INTERNSHIP (IF ANY)")
para(doc, "N/A \u2013 the internship was an unpaid internship. No stipend or remuneration "
          "was received, and no payment proof is therefore enclosed.")

doc.save(DOCX)
print("saved", DOCX)
