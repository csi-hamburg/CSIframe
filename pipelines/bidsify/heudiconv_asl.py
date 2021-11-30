#!/usr/bin/env python3
import os
# the OS module in Python allows to interface with the underlying operating system that Python is running on - Windows, Mac or Linux

# create a function called create_key
def create_key(template, outtype=('nii.gz',), annotation_classes=None):
    if template is None or not template:
        raise ValueError('Template must be a valid format string')
    return template, outtype, annotation_classes

def infotodict(seqinfo):
    ###################################################################################################################################################################
    # STEP 1: KEY DEFINITIONS
    ###################################################################################################################################################################
    # For each sequence, define a variable using the create_key function: variable = create_key(output_directory_path_and_name). "data" creates sequential numbers which can be for naming sequences.
    #data = create_key('run-{item:03d}')
    
    control_asl = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-1_asl')
    label_asl = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_run-2_asl')
    m0scan = create_key('sub-{subject}/{session}/perf/sub-{subject}_{session}_m0scan')

    # The data dictionary below uses the variables defined above as keys
    info = {label_asl: [], control_asl: [], m0scan: []}
    last_run = len(seqinfo)

    ###################################################################################################################################################################
    # STEP 2: DEFINING TEST CRITERIA
    ###################################################################################################################################################################
    # Define test criteria to check that each dicom sequence is correct. seqinfo (s) refers to information in dicominfo.tsv.

    for idx, s in enumerate(seqinfo):
        if ('ss_TE00_TI1700' == s.series_description) and (s.series_files > 24):
            info[control_asl].append(s.series_id)
        if ('ns_TE00_TI1700' == s.series_description):
            info[label_asl].append(s.series_id)
        if ('M0' in s.protocol_name):
            info[m0scan].append(s.series_id)
    return info