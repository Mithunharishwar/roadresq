"""Front matter for the RoadResQ report."""
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

TITLE_LINES = [
    "ROADRESQ: A CAPABILITY-CONSTRAINED ON-DEMAND ROADSIDE",
    "RESCUE PLATFORM WITH REGION-AWARE WEIGHTED PARTNER",
    "ALLOCATION AND MULTI-CHANNEL INCIDENT TRIGGERING",
]

STUDENTS = [
    ("MITHUN HARISHWAR P R", "310623205087"),
    ("LOKESHWARAN K", "310623205302"),
]


def _center(doc, text, size=12, bold=False, italic=False, before=0, after=0, spacing=1.15):
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(before)
    p.paragraph_format.space_after = Pt(after)
    p.paragraph_format.line_spacing = spacing
    r = p.add_run(text)
    r.bold = bold
    r.italic = italic
    r.font.size = Pt(size)
    r.font.name = "Times New Roman"
    return p


def title_page(doc, para, rich):
    _center(doc, "A PROJECT REPORT", size=12, bold=True, before=6, after=18)
    _center(doc, "on", size=12, after=18)
    for line in TITLE_LINES:
        _center(doc, line, size=15, bold=True, after=3, spacing=1.25)
    _center(doc, "", size=12, after=14)
    _center(doc, "Submitted by", size=12, italic=True, after=10)
    for name, roll in STUDENTS:
        _center(doc, f"{name}   ({roll})", size=13, bold=True, after=4)
    _center(doc, "", size=12, after=10)
    _center(doc, "in partial fulfillment for the award of the degree", size=12, after=6)
    _center(doc, "of", size=12, after=6)
    _center(doc, "BACHELOR OF TECHNOLOGY", size=14, bold=True, after=4)
    _center(doc, "in", size=12, after=4)
    _center(doc, "INFORMATION TECHNOLOGY", size=14, bold=True, after=18)
    _center(doc, "EASWARI ENGINEERING COLLEGE, CHENNAI", size=14, bold=True, after=2)
    _center(doc, "(AN AUTONOMOUS INSTITUTION)", size=11, after=4)
    _center(doc, "ANNA UNIVERSITY : CHENNAI 600 025", size=12, after=18)
    _center(doc, "OCTOBER 2026", size=13, bold=True, after=0)


def bonafide(doc, para, rich):
    _center(doc, "EASWARI ENGINEERING COLLEGE", size=15, bold=True, after=2)
    _center(doc, "(AN AUTONOMOUS INSTITUTION)", size=10, after=2)
    _center(doc, "AFFILIATED TO ANNA UNIVERSITY, CHENNAI 600025", size=10, after=16)
    _center(doc, "BONAFIDE CERTIFICATE", size=14, bold=True, after=16)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(10)
    r = p.add_run("Certified that this project report titled ")
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"
    r2 = p.add_run("\u201cROADRESQ: A CAPABILITY-CONSTRAINED ON-DEMAND ROADSIDE RESCUE PLATFORM "
                   "WITH REGION-AWARE WEIGHTED PARTNER ALLOCATION AND MULTI-CHANNEL INCIDENT TRIGGERING\u201d ")
    r2.bold = True
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"
    r3 = p.add_run("is the bonafide work of ")
    r3.font.size = Pt(12)
    r3.font.name = "Times New Roman"
    r4 = p.add_run("MITHUN HARISHWAR P R (310623205087)")
    r4.bold = True
    r4.font.size = Pt(12)
    r4.font.name = "Times New Roman"
    r5 = p.add_run(" and ")
    r5.font.size = Pt(12)
    r5.font.name = "Times New Roman"
    r6 = p.add_run("LOKESHWARAN K (310623205302)")
    r6.bold = True
    r6.font.size = Pt(12)
    r6.font.name = "Times New Roman"
    r7 = p.add_run(" who carried out the project work under my supervision during the academic year 2025\u20132026.")
    r7.font.size = Pt(12)
    r7.font.name = "Times New Roman"

    t = doc.add_table(rows=1, cols=2)
    t.autofit = False
    left, right = t.rows[0].cells
    left.width = Inches(3.0)
    right.width = Inches(3.0)
    for cell, lines in (
        (left, ["SIGNATURE", "", "Dr. N. ANANTHI, M.E., Ph.D.,", "HEAD OF THE DEPARTMENT",
                "Department of Information Technology,", "Easwari Engineering College,",
                "Ramapuram, Chennai \u2013 600089."]),
        (right, ["SIGNATURE", "", "Mrs. K. SUDHA, M.E.,", "SUPERVISOR",
                 "Assistant Professor,", "Department of Information Technology,",
                 "Easwari Engineering College, Ramapuram, Chennai \u2013 600089."]),
    ):
        cell.text = ""
        for i, line in enumerate(lines):
            cp = cell.paragraphs[0] if i == 0 else cell.add_paragraph()
            cp.paragraph_format.space_after = Pt(2)
            cp.paragraph_format.line_spacing = 1.15
            r = cp.add_run(line)
            r.font.size = Pt(11)
            r.font.name = "Times New Roman"
            r.bold = i in (0, 2, 3)

    _center(doc, "", size=11, after=24)
    _center(doc, "The Project Viva-Voce Examination was conducted on ______________________", size=11, after=18)
    t2 = doc.add_table(rows=1, cols=2)
    t2.autofit = False
    a, b = t2.rows[0].cells
    a.width = Inches(3.0)
    b.width = Inches(3.0)
    for cell, text in ((a, "Project Coordinator"), (b, "Panel Member Signature")):
        cell.text = ""
        cp = cell.paragraphs[0]
        cp.paragraph_format.space_after = Pt(2)
        r = cp.add_run(text)
        r.bold = True
        r.font.size = Pt(11)
        r.font.name = "Times New Roman"


def viva(doc, para, rich):
    _center(doc, "EASWARI ENGINEERING COLLEGE", size=15, bold=True, after=2)
    _center(doc, "(AN AUTONOMOUS INSTITUTION)", size=10, after=16)
    _center(doc, "CERTIFICATE OF VIVA-VOCE EXAMINATION", size=14, bold=True, after=16)

    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    p.paragraph_format.line_spacing = 1.5
    p.paragraph_format.space_after = Pt(16)
    r = p.add_run("This is to certify that the Viva-Voce Examination of the project work entitled ")
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"
    r2 = p.add_run("\u201cROADRESQ: A CAPABILITY-CONSTRAINED ON-DEMAND ROADSIDE RESCUE PLATFORM "
                   "WITH REGION-AWARE WEIGHTED PARTNER ALLOCATION AND MULTI-CHANNEL INCIDENT TRIGGERING\u201d ")
    r2.bold = True
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"
    r3 = p.add_run("submitted by ")
    r3.font.size = Pt(12)
    r3.font.name = "Times New Roman"
    r4 = p.add_run("MITHUN HARISHWAR P R (310623205087)")
    r4.bold = True
    r4.font.size = Pt(12)
    r4.font.name = "Times New Roman"
    r5 = p.add_run(" and ")
    r5.font.size = Pt(12)
    r5.font.name = "Times New Roman"
    r6 = p.add_run("LOKESHWARAN K (310623205302)")
    r6.bold = True
    r6.font.size = Pt(12)
    r6.font.name = "Times New Roman"
    r7 = p.add_run(" in partial fulfillment of the requirements for the award of the degree of Bachelor of "
                   "Technology was conducted on ______________ in the Department of Information Technology, "
                   "Easwari Engineering College, Ramapuram, Chennai.")
    r7.font.size = Pt(12)
    r7.font.name = "Times New Roman"

    t = doc.add_table(rows=1, cols=2)
    t.autofit = False
    for cell, head in zip(t.rows[0].cells, ("INTERNAL EXAMINER", "EXTERNAL EXAMINER")):
        cell.width = Inches(3.0)
        cell.text = ""
        for i, line in enumerate([head, "", "Name:", "Designation:", "Date:"]):
            cp = cell.paragraphs[0] if i == 0 else cell.add_paragraph()
            cp.paragraph_format.space_after = Pt(6)
            cp.paragraph_format.line_spacing = 1.2
            r = cp.add_run(line)
            r.font.size = Pt(11)
            r.font.name = "Times New Roman"
            r.bold = i == 0


def acknowledgement(doc, para, rich):
    _center(doc, "ACKNOWLEDGEMENT", size=14, bold=True, after=18)

    paragraphs = [
        "We express our sincere thanks and deep sense of gratitude to our Founder Chairman, Dr. T. R. Parivendhar, "
        "and our beloved Chairman, Dr. R. Shivakumar, M.D., Ph.D., for their constant support, encouragement and "
        "inspiration, which motivated us to complete this project successfully.",

        "We record our respectful thanks to our Principal, Dr. P. Deiva Sundari, M.E., Ph.D., and to our Head of the "
        "Department, Dr. N. Ananthi, M.E., Ph.D., for their guidance, encouragement and continuous support throughout "
        "the course of this work.",

        "We owe our profound gratitude to our project supervisor, Mrs. K. Sudha, M.E., Assistant Professor, Department "
        "of Information Technology, Easwari Engineering College, for her valuable suggestions, patient review of every "
        "iteration of this work, and keen interest in its progress. Her insistence that every claim in the evaluation "
        "chapter be traceable to a recorded observation shaped both the design and the way we report it.",

        "We sincerely thank our project coordinator, Mr. K. Ravindran, M.E., for his continuous assistance and for "
        "keeping the review schedule on track.",

        "We are grateful to the faculty and staff of the Department of Information Technology for their cooperation, "
        "and to our classmates who tested early builds of the application on their own devices and reported failures "
        "that we would not otherwise have found.",

        "Finally, we thank our families for their patience and encouragement, which made the long working weeks of this "
        "project possible.",
    ]
    for text in paragraphs:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.line_spacing = 1.5
        p.paragraph_format.space_after = Pt(12)
        r = p.add_run(text)
        r.font.size = Pt(12)
        r.font.name = "Times New Roman"


def abstract(doc, para, rich):
    _center(doc, "ABSTRACT", size=14, bold=True, after=16)

    paragraphs = [
        "A vehicle breakdown is an unplanned event that leaves the owner stranded, uncertain of the cost, and unable "
        "to judge which of the nearby workshops can actually repair the fault. The roadside assistance market answers "
        "this need in two forms. A subscription product places the coordination with a call-centre operator and prices "
        "the service as an annual entitlement; a directory application publishes a list of workshops and leaves the "
        "coordination to the owner. Neither form observes the outcome of the service it arranges, and neither selects "
        "a workshop against the fault that has actually occurred.",

        "This project designs, implements and evaluates RoadResQ, a roadside rescue platform that treats the "
        "assignment of a rescue crew as a decision problem rather than as a directory lookup. The platform is built "
        "around an explicit request lifecycle, a region-aware retrieval of candidate crews, and a transparent, "
        "weighted allocation score. Six terms enter the score: proximity, service compatibility, current availability, "
        "verification state, workload and rating. Each term is normalised into the unit interval, and the weights are "
        "exposed as configuration rather than fixed in code, so that every dispatch decision can be explained from the "
        "factors that produced it. Eligibility is filtered before ranking, which prevents a crew that is offline, "
        "unverified, outside its declared radius or already at capacity from appearing as a candidate at all.",

        "A request may be raised in three ways: an explicit SOS control, a hands-free voice keyword, and an impact "
        "event detected from the device accelerometer and gyroscope. The sensor path never dispatches on its own; it "
        "opens a confirmation prompt, because the cost of a false dispatch is much higher than the cost of a missed "
        "prompt. Requests advance through a twelve-state lifecycle whose legal transitions are held in one table, so that "
        "an illegal transition is unrepresentable rather than merely unlikely. Fault descriptions are mapped to a "
        "service class and a fixed tariff before any offer is made, and settlement is recorded as an append-only "
        "ledger entry.",

        "The implementation comprises a Flutter client for owners, a Flutter client for crews, a Python service tier "
        "built with Flask and Flask-SocketIO, a MongoDB store and an in-memory geo index. The allocation engine is "
        "written as a pure module that takes records and returns a ranked decision with its factor contributions, which "
        "makes each decision independently testable.",

        "Evaluation is carried out on a paired simulated corpus of 4,000 requests over three supply densities. Against "
        "a proximity-only dispatch policy, the proposed score raises the job allocation rate from 84.1% to 96.5% and "
        "end-to-end thirty-minute compliance from 57.3% to 66.4%, while the median time to resolution rises by only "
        "0.3 minutes. The advantage is concentrated in thin supply: at a rural density of 2.2 crews per ten square "
        "kilometres, the allocation rate is 87.0% against 55.1%. The multi-feature incident detector raises the "
        "detection rate at a fixed false-alarm budget from 65.0% to 90.5%, and the fault classifier attains a pooled "
        "F1-score of 0.91 against 0.77 for a lexical baseline. These results are reported as differences on a common "
        "corpus rather than as field measurements, and the parameters that generate them are published with the "
        "simulator.",

        "The contribution of the work is therefore not a faster tow. It is a demonstration that a capability-"
        "constrained, explainable assignment rule changes who is dispatched, and that this change matters most exactly "
        "where the existing commercial forms fail, which is in thin and semi-urban supply.",
    ]
    for text in paragraphs:
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.line_spacing = 1.5
        p.paragraph_format.space_after = Pt(10)
        r = p.add_run(text)
        r.font.size = Pt(12)
        r.font.name = "Times New Roman"

    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(8)
    p.paragraph_format.line_spacing = 1.4
    r = p.add_run("KEYWORDS: ")
    r.bold = True
    r.font.size = Pt(12)
    r.font.name = "Times New Roman"
    r2 = p.add_run("roadside assistance, geospatial retrieval, weighted allocation, capability matching, "
                   "request lifecycle, mobile platform, incident detection, Flutter, Flask, MongoDB.")
    r2.font.size = Pt(12)
    r2.font.name = "Times New Roman"


ABBREVIATIONS = [
    ("API", "Application Programming Interface"),
    ("ASGI", "Asynchronous Server Gateway Interface"),
    ("CI/CD", "Continuous Integration and Continuous Delivery"),
    ("CRUD", "Create, Read, Update, Delete"),
    ("CSV", "Comma-Separated Values"),
    ("ETA", "Estimated Time of Arrival"),
    ("FCM", "Firebase Cloud Messaging"),
    ("GPS", "Global Positioning System"),
    ("HTTP", "Hypertext Transfer Protocol"),
    ("HTTPS", "Hypertext Transfer Protocol Secure"),
    ("JSON", "JavaScript Object Notation"),
    ("JWT", "JSON Web Token"),
    ("MAE", "Mean Absolute Error"),
    ("MVC", "Model\u2013View\u2013Controller"),
    ("OSM", "OpenStreetMap"),
    ("RBAC", "Role-Based Access Control"),
    ("REST", "Representational State Transfer"),
    ("SDK", "Software Development Kit"),
    ("SLA", "Service-Level Agreement"),
    ("SMS", "Short Message Service"),
    ("SOS", "Save Our Souls (emergency trigger)"),
    ("SQL", "Structured Query Language"),
    ("TLS", "Transport Layer Security"),
    ("TTL", "Time To Live"),
    ("UI", "User Interface"),
    ("UPI", "Unified Payments Interface"),
    ("URL", "Uniform Resource Locator"),
    ("UX", "User Experience"),
    ("V2X", "Vehicle-to-Everything"),
    ("WS", "WebSocket"),
]


def abbreviations(doc, para):
    from docx.shared import Pt
    from docx.enum.text import WD_ALIGN_PARAGRAPH
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_after = Pt(18)
    r = p.add_run("LIST OF ABBREVIATIONS")
    r.bold = True
    r.font.size = Pt(14)
    r.font.name = "Times New Roman"

    t = doc.add_table(rows=0, cols=2)
    t.autofit = False
    for abbr, full in ABBREVIATIONS:
        cells = t.add_row().cells
        cells[0].width = Inches(1.2)
        cells[1].width = Inches(4.6)
        for i, text in enumerate((abbr, full)):
            cp = cells[i].paragraphs[0]
            cp.paragraph_format.space_after = Pt(3)
            cp.paragraph_format.line_spacing = 1.15
            r = cp.add_run(text)
            r.font.size = Pt(12)
            r.font.name = "Times New Roman"
            r.bold = i == 0
