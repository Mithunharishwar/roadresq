# -*- coding: utf-8 -*-
"""Walk a docx body in order and dump a structured view.  Usage: dumpsrc.py SRC OUT_TXT OUT_JSON"""
import json
import sys

from docx import Document
from docx.oxml.ns import qn

SRC, OUT_TXT, OUT_JSON = sys.argv[1], sys.argv[2], sys.argv[3]
d = Document(SRC)
body = d.element.body
paras = {p._p: p for p in d.paragraphs}
tables = {t._tbl: t for t in d.tables}

items = []
pidx = tidx = 0
for child in body.iterchildren():
    tag = child.tag.split("}")[-1]
    if tag == "p":
        p = paras.get(child)
        if p is None:
            continue
        has_img = bool(child.findall(".//" + qn("a:blip")))
        kind = "image" if has_img else "para"
        items.append({"i": pidx, "kind": kind, "style": p.style.name,
                      "text": p.text})
        pidx += 1
    elif tag == "tbl":
        t = tables.get(child)
        if t is None:
            continue
        rows = [[c.text.replace("\n", " / ") for c in r.cells] for r in t.rows]
        items.append({"i": tidx, "kind": "table", "rows": len(t.rows),
                      "cols": len(t.columns), "data": rows,
                      "style": t.style.name if t.style else None})
        tidx += 1

json.dump(items, open(OUT_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
L = []
for it in items:
    if it["kind"] == "table":
        L.append("[[TABLE %d r%dc%d style=%s]]" % (it["i"], it["rows"], it["cols"], it["style"]))
        for row in it["data"]:
            L.append("   | " + " || ".join(row))
    else:
        L.append("[%03d %s %s] %s" % (it["i"], it["kind"], it["style"],
                                      it["text"].replace("\n", "\\n")))
open(OUT_TXT, "w", encoding="utf-8").write("\n".join(L))
print("items", len(items), "paras", pidx, "tables", tidx)
