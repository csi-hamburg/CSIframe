import os
import sys
import glob
import pdfkit

tbss_dir = sys.argv[1]
ses = sys.argv[2]
space = sys.argv[3]
mod = sys.argv[4]
histfig = sys.argv[5]
boxfig = sys.argv[6]
report = sys.argv[7]

# Create HTML
#############

html = ""
html += '<p style="font-size:30px">'
html += f"Report for {tbss_dir} / ses-{ses} / {space} space"
html += "</p><br>"

html += f"<img src='{histfig}'/>"
html += f"<img src='{boxfig}'/><br>"

overlay_paths=glob.glob(f'{tbss_dir}/*/ses-{ses}/dwi/*_ses-{ses}_space-{space}_desc-skeleton_{mod}_overlay.png')

for overlay in overlay_paths:
    
    sub = overlay.split("/")[-1].split("_")[0]

    html += f"<b>{mod} skeleton of {sub} for ses-{ses} in {space} space</b>"
    html += f"<img src='{overlay}'/><br>\n"

with open(f"{report}", "w") as outputfile:
	outputfile.write(html)

# Convert to PDF
################

report_pdf = report.split(".")[0]

print(report_pdf)

pdfkit.from_file(f'{report}', f'{report_pdf}.pdf')