import os
import sys
import win32com.client as win32

src = os.path.abspath(sys.argv[1])
dst = os.path.abspath(sys.argv[2])

word = win32.Dispatch("Word.Application")
word.Visible = False
word.DisplayAlerts = 0
doc = word.Documents.Open(src)
try:
    doc.Fields.Update()
    for i in range(1, doc.TablesOfContents.Count + 1):
        doc.TablesOfContents(i).Update()
    doc.Repaginate()
    doc.Save()
    doc.SaveAs2(dst, FileFormat=17)
    pages = doc.ComputeStatistics(2)  # wdStatisticPages
    print("PDF pages:", pages)
finally:
    doc.Close(False)
    word.Quit()
print("wrote", dst)
