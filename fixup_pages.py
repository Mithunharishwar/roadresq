"""Read the rendered PDF and write the real page number of every TOC entry,
table and figure into page_map3.json."""
import io
import json
import re
import sys

import pymupdf

PDF = "RoadResQ_Final_Project_Report.pdf"
OUT = "page_map3.json"

ROMAN = re.compile(r"^[ivxlcdm]+$", re.I)
NUM = re.compile(r"^\d{1,3}$")
CAP = re.compile(r"^(Table|Figure)\s+(\d+\.\d+)")

doc = pymupdf.open(PDF)
n = doc.page_count

head_text = []      # normalized heading text per page (bold, >= 13.4 pt)
cap_labels = []     # list of (normalized label, page index) per page
printed = []        # printed page number per page

def norm(s):
    return re.sub(r"\s+", "", s)

for i, page in enumerate(doc):
    spans = []
    for b in page.get_text("dict")["blocks"]:
        if b["type"] != 0:
            continue
        for l in b["lines"]:
            for s in l["spans"]:
                spans.append(s)
    heads = "".join(norm(s["text"]) for s in spans
                    if "Bold" in s["font"] and 13.4 <= s["size"] <= 16.8)
    head_text.append(heads)

    labels = []
    for s in spans:
        t = s["text"].strip()
        m = CAP.match(t)
        if m and 10.0 <= s["size"] <= 11.8 and "Bold" in s["font"]:
            labels.append(norm(m.group(1) + " " + m.group(2)))
    cap_labels.append(labels)

    num = None
    for s in spans:
        if s["bbox"][1] > 750:
            t = s["text"].strip()
            if NUM.match(t) or ROMAN.match(t):
                num = t
                break
    if num is None:
        first = [l.strip() for l in page.get_text().split("\n")[:3]]
        for t in first:
            if NUM.match(t) or (ROMAN.match(t) and len(t) > 0):
                num = t
                break
    printed.append(num)

missing = []

def find(key, start=0, end=None):
    end = end if end is not None else n
    for i in range(start, end):
        if key in head_text[i]:
            return i
    return None

# ---- front matter, in document order, before the body starts
body_start = find("CHAPTER1INTRODUCTION")
if body_start is None:
    print("FATAL: chapter 1 heading not found")
    sys.exit(1)

pm = {}
cursor = 0
for label in ("ACKNOWLEDGEMENT", "ABSTRACT", "LIST OF TABLES", "LIST OF FIGURES",
              "LIST OF SYMBOLS, ABBREVIATIONS AND NOMENCLATURE"):
    key = norm(label)
    i = find(key, cursor)
    if i is None:
        missing.append(label)
        continue
    pm[key] = printed[i]
    cursor = i

toc = json.load(open("_toc_entries.json", encoding="utf-8"))

cursor = body_start
for kind, key, display, level in toc["entries"]:
    i = find(key, cursor)
    if i is None:
        # headings that wrap or hyphenate: retry with the first three tokens
        short = key[:22]
        i = find(short, cursor)
    if i is None:
        missing.append(key)
        continue
    pm[key] = printed[i]
    cursor = i

for label in toc["tail"]:
    i = find(label, cursor)
    if i is None:
        missing.append(label)
        continue
    pm[label] = printed[i]
    cursor = i

# ---- tables and figures
for prefix, keyname in (("Table", "tables"), ("Figure", "figures")):
    cursor = body_start
    for num, cap in toc[keyname]:
        lab = norm(f"{prefix} {num}")
        page = None
        for i in range(cursor, n):
            if lab in cap_labels[i]:
                page = i
                break
        if page is None:
            missing.append(f"{prefix} {num}")
            continue
        pm[norm(f"{prefix} {num} {cap}")] = printed[page]
        cursor = page

json.dump(pm, open(OUT, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("pages:", n, " entries:", len(pm), " missing:", len(missing))
for m in missing:
    print("  MISSING:", m)
