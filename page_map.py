"""Build page_map.json by locating captions in the exported PDF (body pages only)."""
import json
import re
import sys
from pypdf import PdfReader

pdf = sys.argv[1] if len(sys.argv) > 1 else "RoadResQ_Final_Project_Report.pdf"
r = PdfReader(pdf)

pages = []
for p in r.pages:
    txt = (p.extract_text() or "")
    pages.append(re.sub(r"\s+", " ", txt))

# the body begins on the page after the last front-matter page
abbr_pages = [i for i, txt in enumerate(pages) if "LIST OF ABBREVIATIONS" in txt]
if not abbr_pages:
    raise SystemExit("could not locate front matter")
body_start = abbr_pages[-1] + 1

targets = {}
for i in range(body_start, len(pages)):
    txt = pages[i]
    body_page = i - body_start + 1
    for m in re.finditer(r"(Figure|Table)\s+(\d+\.\d+)\s", txt):
        key = f"{m.group(1)} {m.group(2)}"
        targets.setdefault(key, body_page)

with open("page_map.json", "w", encoding="utf-8") as f:
    json.dump(targets, f, indent=2, ensure_ascii=False)
print("body_start pdf page:", body_start + 1)
print(json.dumps(targets, indent=2))
