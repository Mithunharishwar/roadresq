"""Build the internship review deck for Mithun Harishwar on the sample's template."""
import copy

from pptx import Presentation
from pptx.util import Pt

SRC = "_sample.pptx"
OUT = "Internship_Review_Mithun_RoadResQ.pptx"

prs = Presentation(SRC)


def shape_by_name(slide, name, idx=0):
    hits = [s for s in slide.shapes if s.name == name]
    return hits[idx] if len(hits) > idx else None


def set_two_line(tf, first, second, first_size=None, second_size=None):
    """Replace the two paragraphs of a label/value text frame."""
    paras = tf.paragraphs
    while len(tf.paragraphs) > 2:
        tf._txBody.remove(tf.paragraphs[-1]._p)
    p0, p1 = tf.paragraphs[0], tf.paragraphs[1]
    for p, txt, size in ((p0, first, first_size), (p1, second, second_size)):
        for r in list(p.runs)[1:]:
            p._p.remove(r._r)
        p.runs[0].text = txt
        if size:
            p.runs[0].font.size = Pt(size)


def rebuild_bullets(shape, items):
    """Replace the body text with bullet paragraphs made of (bold, rest) pairs."""
    tf = shape.text_frame
    template_p = copy.deepcopy(tf.paragraphs[0]._p)
    for p in list(tf.paragraphs)[1:]:
        p._p.getparent().remove(p._p)

    bold_src = None
    for r in tf.paragraphs[0].runs:
        if r.font.bold:
            bold_src = copy.deepcopy(r._r)
    for p in [template_p]:
        pass

    body = tf._txBody
    for p in list(body.findall("{http://schemas.openxmlformats.org/drawingml/2006/main}p")):
        body.remove(p)

    for lead, rest in items:
        p_el = copy.deepcopy(template_p)
        body.append(p_el)
        para = tf.paragraphs[-1]
        for r in list(para.runs):
            r._r.getparent().remove(r._r)
        r1 = para.add_run()
        r1.text = lead
        r1.font.bold = True
        r1.font.size = Pt(19)
        r1.font.name = "Times New Roman"
        r2 = para.add_run()
        r2.text = rest
        r2.font.bold = False
        r2.font.size = Pt(19)
        r2.font.name = "Times New Roman"


# ------------------------------------------------------------------ slide 1
s1 = prs.slides[0]
shape_by_name(s1, "Google Shape;89;p1").text_frame.paragraphs[0].runs[0].text = \
    "Software Development Intern"

set_two_line(shape_by_name(s1, "Google Shape;92;p1").text_frame,
             "Project Domain", "Mobile App Development", None, 22)
set_two_line(shape_by_name(s1, "Google Shape;96;p1").text_frame,
             "Company Name", " Intelizign Lifecycle Services Pvt Ltd", None, 18)
set_two_line(shape_by_name(s1, "Google Shape;93;p1").text_frame,
             "Duration", "04/03/26 - 31/03/26", None, 22)

presented = shape_by_name(s1, "Google Shape;91;p1").text_frame
for para in presented.paragraphs:
    if any("Poojapriya" in r.text for r in para.runs):
        runs = para.runs
        runs[0].text = "Mithun Harishwar P R"
        runs[1].text = ""
        runs[2].text = " \u2013 310623205087"
        for r in runs:
            r.font.size = Pt(22)

for slide in prs.slides:
    for sh in slide.shapes:
        if sh.has_text_frame and "Academic Year" in sh.text_frame.text:
            for para in sh.text_frame.paragraphs:
                for r in para.runs:
                    if "Academic Year" in r.text:
                        r.text = "Academic Year : 2025 \u2013 2026 (Even)"

# ------------------------------------------------------------------ slide 2
s2 = prs.slides[1]
shape_by_name(s2, "Title 1").text_frame.paragraphs[0].runs[0].text = "Brief about the Company"
rebuild_bullets(shape_by_name(s2, "Text Placeholder 2"), [
    ("Intelizign Lifecycle Services Pvt. Ltd. ",
     "is an engineering services company whose identity is built around product lifecycle "
     "management, summarised in its own tagline \u201cPLM & beyond\u201d."),
    ("The company operates as part of Quest Global ",
     "and supports manufacturing clients in managing product data, engineering change and "
     "digital lifecycle processes from design through production."),
    ("Delivery is organised from four Indian offices ",
     "\u2013 Bengaluru, Chennai, Hyderabad and Pune \u2013 which lets teams work alongside "
     "clients across time zones."),
    ("The work culture is documentation-led: ",
     "tasks are specified, reviewed and recorded, and interns are expected to work to the "
     "same review discipline as the delivery teams."),
    ("Interns work with application development teams ",
     "on internal and client-facing tooling, using frameworks such as Flutter and Flask, as "
     "recorded in the completion certificate."),
    ("Learning is continuous and practical, ",
     "with progress measured by the work delivered rather than by time spent."),
])

# ------------------------------------------------------------------ slide 3
s3 = prs.slides[2]
shape_by_name(s3, "Title 1").text_frame.paragraphs[0].runs[0].text = "Objective"
rebuild_bullets(shape_by_name(s3, "Rectangle 1"), [
    ("To gain industrial experience ",
     "in application development using Flutter for the client, Flask for the service layer "
     "and MongoDB for persistence."),
    ("To apply academic knowledge ",
     "of software engineering, databases and networking to a working product rather than to "
     "a laboratory exercise."),
    ("To build one feature end to end ",
     "\u2013 data model, service logic, interface and tests \u2013 and to see it reviewed, "
     "corrected and shipped."),
    ("To strengthen problem solving and debugging skills ",
     "on faults that only appear under real conditions, such as stale positions, duplicate "
     "requests and weak network coverage."),
    ("To learn professional practice ",
     "in version control, API documentation, test discipline and written reporting."),
    ("To develop readiness ",
     "for a software development role through direct exposure to a delivery team."),
])

# ------------------------------------------------------------------ slide 4
s4 = prs.slides[3]
shape_by_name(s4, "Title 1").text_frame.paragraphs[0].runs[0].text = "Contributions & Outcomes"
rebuild_bullets(shape_by_name(s4, "Rectangle 1"), [
    ("Designed and built RoadResQ, ",
     "an on-demand roadside rescue platform: a Flutter client, a Flask service layer and a "
     "MongoDB store."),
    ("Implemented a capability-constrained allocation engine ",
     "that filters crews on service fit, availability and position freshness before ranking "
     "them."),
    ("Built a transparent six-term score ",
     "(proximity, service, availability, verification, workload, rating) that records the "
     "contribution of every term, so each dispatch can be explained."),
    ("Implemented the request lifecycle ",
     "as a twelve-state transition table held on the server, with guards against duplicate "
     "requests and double acceptance."),
    ("Added multi-channel triggering and triage: ",
     "SOS control, on-device voice keyword, sensor-detected impact with confirmation, and "
     "fault classification to a fixed tariff."),
    ("Evaluated the system on 4,000 paired simulated requests: ",
     "allocation rose from 84.1% to 96.5% and thirty-minute compliance from 57.3% to 66.4% "
     "against a proximity-only policy."),
])

# ------------------------------------------------------------------ slide 5
s5 = prs.slides[4]
shape_by_name(s5, "Title 1").text_frame.paragraphs[0].runs[0].text = "Challenges & Achievements"
rebuild_bullets(shape_by_name(s5, "Rectangle 1"), [
    ("A single dispatch score was not defensible: ",
     "when a crew was chosen there was no way to say why. The score was rebuilt so that every "
     "term exposes its own contribution in the API response."),
    ("Sensor detection misfired on potholes and speed breakers. ",
     "Window validation, jerk analysis and a mandatory confirmation step raised the detection "
     "rate at a fixed false-alarm budget from 65.0% to 90.5%."),
    ("State drifted when requests were retried. ",
     "Consolidating every legal transition into one server-side table, with idempotent "
     "endpoints, removed duplicate requests and double acceptance."),
    ("Stale crew positions distorted ranking. ",
     "Freshness filtering now runs before scoring, so a crew that has not reported recently "
     "cannot win a dispatch."),
    ("First production-style Flask and MongoDB work ",
     "meant learning testing, API documentation and review conventions in parallel with the "
     "feature work."),
    ("Outcome: ",
     "a complete working system with a measured evaluation, and a completion certificate that "
     "records dedication and eagerness to learn."),
])

prs.save(OUT)
print("saved", OUT, "slides:", len(prs.slides))
