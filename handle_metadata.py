from bids import BIDSLayout
import os
import glob
import json
import sys

subject=sys.argv[1]
if not subject.startswith('sub-'): subject = 'sub-' + subject
bidsdir=os.getcwd()

# Defince problematic metadata fields
problematic_metadata=['InstitutionName', 'InstitutionalDepartmentName','InstitutionAddress','InstitutionAddress','ProcedureStepDescription']

# Make list of the json files to edit
json_paths=glob.glob(f'{subject}/ses-1/*/*.json')
print('Amending json metadata of:', json_paths)

# For each json substitute contents of problematic metadata fields with 'deleted'
for json_path in json_paths:
	with open(json_path, 'r') as data_file:
		json_file = json.load(data_file)
		for item in problematic_metadata:
			if item in json_file: json_file[item]='deleted'
	with open(json_path, 'w') as data_file:
		json_file = json.dump(json_file, data_file)
