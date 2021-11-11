import os
import sys

tbss_dir = sys.argv[1]
ses = sys.argv[2]
space = sys.argv[3]
mod = sys.argv[4]
histfig = sys.argv[5]
boxfig = sys.argv[6]
report = sys.argv[7]

html = ""

html += f"<title>Report for {tbss_dir} / ses-{ses} / {space} space</title>"

html += f"<img src='{histfig}'/><br>"
html += f"<img src='{boxfig}'/><br>"

for sub in glob.glob("{tbss_dir}/sub-*"):
	
    html += f"<b>{mod} skeleton of {sub} for ses-{ses} in {space} space</b>"
    html += f"<img src='{tbss_dir}/{sub}/{ses}/dwi/{sub}_ses-{ses}_space-{space}_desc-skeleton_{mod}_overlay.png'/><br>"


with open(f"{report}", "w") as outputfile:
	outputfile.write(html)